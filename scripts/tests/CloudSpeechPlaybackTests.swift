import Foundation
import CryptoKit

/// Exercises the real AVAudioEngine output thread, sequential beats, cache
/// replay and cancellation without contacting any AI or using private speech.
@MainActor enum CloudSpeechPlaybackTests {
    static func run() async throws -> String {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain:"SpeechPlaybackCheck",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
        }
        let soundscape = CompanionSoundscape()
        soundscape.setVolume(0); soundscape.setActive(true)
        let scope = "audio-regression:"+UUID().uuidString
        let api = CharacterAI(accountID:scope,characterID:"anime-kipfel")
        let speech = CloudSpeech(soundscape:soundscape,api:api,cacheScope:scope)
        let message = UUID()
        let script = AIScript(messageId:message.uuidString,characterId:"anime-kipfel",text:"Audio regression",
            beats:[AIBeat(beatId:"speech",dialogue:AIDialogue(text:"Audio regression"),narrations:[],visuals:[]),
                   AIBeat(beatId:"vocal",narrations:[],visuals:[],vocalEvents:[AIVocalEvent(event:"sigh")])])
        var staged=script
        staged.beats[0].parts=[AIReplyPart(kind:"dialogue",text:"先说一句。",at:0),AIReplyPart(kind:"thought",text:"我也有点期待。",at:0.5),AIReplyPart(kind:"dialogue",text:"接着说完。",at:0.5)]
        var reveal=ReplyReveal();reveal.begin(message,script:staged)
        try require(reveal.count(message,beat:"speech")==1,"Initial presentation must contain only its first stage")
        reveal.advance("speech",fraction:0.6);reveal.advance("speech",fraction:0.1)
        try require(reveal.count(message,beat:"speech")==3,"Corrected audio duration must not retract delivered text")
        reveal.finish()
        try require(reveal.count(message,beat:"speech")==nil,"Cancellation/history replay must expose the complete saved script")
        func oldVoiceKey(_ beat:String)->String {
            SHA256.hash(data:Data((scope+"|qwen-audio-3.1-designed-v2|1.0|"+script.messageId+"|"+beat).utf8))
                .map {String(format:"%02x",$0)}.joined()
        }
        var peak: Float = 0
        var played: [String] = []
        var previousTime = 0.0
        var regressions = 0
        var round = 0
        var frames: [[String:Any]] = []
        var progress:[String:[Double]]=[:]
        speech.onBeatProgress = {beat,fraction in progress[beat,default:[]].append(fraction)}
        speech.onState = { state in
            if state == "thinking" { previousTime = 0; round += 1 }
            frames.append(["kind":"state","state":state,"round":round])
        }
        speech.onFrame = { time,level in
            peak = max(peak,level)
            if time+0.0001 < previousTime { regressions += 1 }
            previousTime = time
            frames.append(["kind":"frame","time":time,"level":level,"round":round])
        }
        speech.onBeat = { played.append($0) }
        defer {
            speech.stop(); soundscape.setActive(false)
            if let trace = try? JSONSerialization.data(withJSONObject:["frames":frames,"regressions":regressions],options:[.prettyPrinted,.sortedKeys]),
               let root = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first {
                try? trace.write(to:root.appendingPathComponent("speech-playback-review.json"),options:.atomic)
            }
            for beat in script.beats {
                let key = SpeechClipCache.shared.key(scope:scope,text:script.messageId+"|"+beat.beatId,speed:1)
                try? FileManager.default.removeItem(at:CacheLocations.live.speech.appendingPathComponent(key+".wav"))
                try? FileManager.default.removeItem(at:CacheLocations.live.speech.appendingPathComponent(oldVoiceKey(beat.beatId)+".wav"))
            }
        }
        // A low-volume 0.6-second sine per beat. This is an audio fixture only,
        // never a fallback conversation or a synthesized provider response.
        var pcm = Data()
        for frame in 0..<14400 {
            var sample = Int16(sin(Double(frame)*2*Double.pi*440/24000)*2400).littleEndian
            withUnsafeBytes(of:&sample) { pcm.append(contentsOf:$0) }
        }
        for beat in script.beats {
            // Retired cache bytes must never reach the playback decoder.
            SpeechClipCache.shared.insert(Data("retired voice clip".utf8),key:oldVoiceKey(beat.beatId))
        }
        try require(try await !speech.cachedReplay(script,messageID:message),"Old voice clips survived the voice revision change")
        speech.prepare(message,script:script)
        let pump=ReplyAudioPump { event in
            if event.type=="audio.completed" {speech.finish()}
            else {try await speech.accept(event)}
        }
        defer {pump.cancel()}
        for beat in script.beats {
            try pump.send(AIEvent(type:"segment.audio.started",beatId:beat.beatId))
            for offset in stride(from:0,to:pcm.count,by:9600) {
                try pump.send(AIEvent(type:"segment.audio.chunk",data:Data(pcm.dropFirst(offset).prefix(9600)).base64EncodedString()))
            }
            try pump.send(AIEvent(type:"segment.audio.ready",beatId:beat.beatId))
        }
        try pump.send(AIEvent(type:"audio.completed"))
        // Simulate a visual arriving after the complete audio stream. Consuming
        // it must be possible while the first beat is still physically playing.
        for _ in 0..<100 {
            if peak>0 {break}
            try await Task.sleep(for:.milliseconds(10))
        }
        try require(speech.isSpeaking && played==["speech"],"The network consumer waited for PCM playback instead of accepting late visuals")
        try await pump.finish()
        try require(speech.playbackLevel==0,"Drained audio did not become silent")
        try require(peak > 0.02,"No actual mixer output was measured")
        try require(speech.audibleSegments == 2,"Expected both spoken and vocal-only output beats")
        try require(abs((speech.durations[message] ?? 0)-1.2)<0.01,"Playback did not drain both buffers")
        try require(played == ["speech","vocal"],"Beat order changed")
        try require(progress["speech"]?.last==1 && progress["speech"]?.contains(where:{$0>0 && $0<1})==true,"Reveal progress skipped real playback or never completed")
        try require(regressions == 0,"Speech timestamps moved backwards across streamed beats or finish; Unity rejects later lip-sync frames")
        try require(try await speech.cachedReplay(script,messageID:message),"Cached replay missed")
        try require(speech.audibleSegments == 4 && played == ["speech","vocal","speech","vocal"],"Replay skipped the vocal-only beat")
        try require(regressions == 0,"Cached speech timestamps moved backwards")
        // Hiding a tab while a beat drains must neither cancel the turn nor
        // discard its complete PCM. Later hidden beats cache without output.
        speech.prepare(message,script:script)
        try await speech.accept(AIEvent(type:"segment.audio.started",beatId:"speech"))
        try await speech.accept(AIEvent(type:"segment.audio.chunk",data:pcm.base64EncodedString()))
        let draining=Task {try await speech.accept(AIEvent(type:"segment.audio.ready",beatId:"speech"))}
        try await Task.sleep(for:.milliseconds(50))
        soundscape.setActive(false);speech.setPresentationActive(false)
        try await draining.value
        let beforeHidden=speech.audibleSegments
        try await speech.accept(AIEvent(type:"segment.audio.started",beatId:"vocal"))
        try await speech.accept(AIEvent(type:"segment.audio.chunk",data:pcm.base64EncodedString()))
        try await speech.accept(AIEvent(type:"segment.audio.ready",beatId:"vocal"))
        try require(!speech.isSpeaking && speech.audibleSegments==beforeHidden,"Hidden-page speech started an audible engine")
        try require(abs((speech.durations[message] ?? 0)-1.2)<0.01,"Hidden completion lost PCM or duration")
        speech.finish();soundscape.setActive(true);speech.setPresentationActive(true)
        try require(try await speech.cachedReplay(script,messageID:message),"A reply completed offscreen could not replay from cache")
        try require(speech.audibleSegments==beforeHidden+2,"Returning did not restore real output")
        speech.prepare(message,script:script)
        try await speech.accept(AIEvent(type:"segment.audio.started",beatId:"speech"))
        try await speech.accept(AIEvent(type:"segment.audio.chunk",data:pcm.base64EncodedString()))
        speech.stop()
        try await Task.sleep(for:.milliseconds(80))
        try require(!speech.isSpeaking && !speech.isBusy && speech.playbackLevel == 0 && soundscape.focus == .none,"Cancellation leaked playback state")
        var waiting=false;var cancelled=false;var nextBeatAccepted=false
        let cancelledPump=ReplyAudioPump { event in
            if event.type=="wait" {
                waiting=true
                do {try await Task.sleep(for:.seconds(10))}
                catch {cancelled=true;throw error}
            } else {nextBeatAccepted=true}
        }
        try cancelledPump.send(AIEvent(type:"wait"));try cancelledPump.send(AIEvent(type:"mustNotRun"))
        while !waiting {await Task.yield()}
        cancelledPump.cancel()
        do {try await cancelledPump.finish();try require(false,"Cancelled audio worker reported success")}
        catch is CancellationError {}
        try require(cancelled && !nextBeatAccepted,"Cancellation left audio from the old turn queued")
        return "PASS: real audio metering, cache replay, monotonic lip-sync, nonblocking queue, late visuals, hidden-tab drain and PCM cache, playback restoration, duration and worker cancellation; zero network calls."
    }
}
