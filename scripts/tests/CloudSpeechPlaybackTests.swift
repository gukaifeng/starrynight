import Foundation
import CryptoKit
import AVFoundation

/// Exercises the real AVAudioEngine output thread, sequential beats, cache
/// replay and cancellation without contacting any AI or using private speech.
@MainActor enum CloudSpeechPlaybackTests {
    static func run() async throws -> String {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain:"SpeechPlaybackCheck",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
        }
        func pcmData(_ samples:[Int16])->Data {samples.withUnsafeBytes {Data($0)}}
        let quiet=pcmData(Array(repeating:7,count:7200))
        let voiced=pcmData([20,Int16.min,60,80]+Array(repeating:800,count:2400))
        var onset=SpeechOnset()
        try require(onset.accept(Data(quiet.prefix(4800))).isEmpty,"Short low-level prefix must wait for safe onset")
        let trimmed=onset.accept(Data(quiet.dropFirst(4800))+voiced)
        try require(onset.removedFrames==6000 && trimmed==Data(quiet.dropFirst(12000))+voiced,"Trim is bounded and preserves every voiced sample, including Int16.min")
        try require(onset.accept(voiced)==voiced && onset.finish().isEmpty,"Inner pauses must never be trimmed")
        var immediate=SpeechOnset()
        try require(immediate.accept(voiced)==voiced && immediate.removedFrames==0,"An immediate soft onset retains its first samples")
        var short=SpeechOnset();let whisper=pcmData(Array(repeating:20,count:800))
        _=short.accept(whisper)
        try require(short.finish()==whisper,"Short quiet vocalizations remain intact")
        var preRoll=SpeechOnset();let pad=pcmData(Array(repeating:7,count:2400))
        try require(preRoll.accept(pad+voiced)==Data(pad.dropFirst(1441*2))+voiced && preRoll.removedFrames==1441,"Forty milliseconds protects the soft onset")
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
        staged.beats[0].parts?.insert(AIReplyPart(kind:"thought",text:"我想仔细听你说。",at:0),at:0)
        staged.beats[0].parts?.append(AIReplyPart(kind:"thought",text:"我还留着一个小问题。",at:1))
        reveal.update(staged)
        try require(reveal.count(message,beat:"speech")==4,"Late annotations must retain the audio fraction without revealing future clauses")
        let visibleSpeech=reveal.visibleParts(message,beat:staged.beats[0]).filter {$0.kind=="dialogue"}.map(\.text).joined()
        try require(visibleSpeech=="先说一句。接着说完。","Optional asides must never gate received spoken text")
        var misplaced=staged
        misplaced.beats[0].parts=[AIReplyPart(kind:"thought",text:"我有点期待。",at:0),AIReplyPart(kind:"narration",text:"轻轻点头",at:1),AIReplyPart(kind:"dialogue",text:"收到的完整台词。",at:0)]
        reveal.begin(message,script:misplaced)
        try require(reveal.visibleParts(message,beat:misplaced.beats[0]).map(\.kind)==["thought","dialogue"],"A future optional annotation must not hide the speech after it")
        misplaced.beats[0].parts?.append(AIReplyPart(kind:"thought",text:"我还想多听一点。",at:0.2))
        reveal.update(misplaced);let earlierRevision=reveal.revision
        reveal.advance("speech",fraction:0.3)
        try require(reveal.revision>earlierRevision,"A non-prefix annotation must notify layout and auto-scroll when revealed")
        reveal.begin(message,script:staged);reveal.advance("speech",fraction:0.6)
        reveal.advance("speech",fraction:1)
        try require(reveal.count(message,beat:"speech")==5,"Final annotation must reveal at the completed spoken clause")
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
        // A server preparation download is playable before its candidate is
        // consumed, in a reconstructed disk cache; account scopes cannot read it.
        var prepared=script;prepared.messageId=UUID().uuidString;prepared.beats=Array(prepared.beats.prefix(1))
        let preparedID=UUID(uuidString:prepared.messageId)!
        let paddedPCM=quiet+pcm
        speech.cachePrepared([AIPreparedClip(id:UUID().uuidString,script:prepared,audio:[AIPreparedAudio(beatId:"speech",data:paddedPCM.base64EncodedString())])])
        let preparedDisk=SpeechClipCache(directory:CacheLocations.live.speech)
        let preparedPlayer=CloudSpeech(soundscape:soundscape,api:api,cacheScope:scope,clipCache:preparedDisk)
        try require(preparedPlayer.hasCached(prepared),"Prepared PCM was not durably downloaded")
        let other=CloudSpeech(soundscape:soundscape,api:api,cacheScope:scope+":other",clipCache:preparedDisk)
        try require(!other.hasCached(prepared),"Prepared voice leaked between account scopes")
        let preparedTrace=VoiceTimeline.shared.begin(account:scope,character:api.characterID,kind:"prefetched_cache_check")
        try require(try await preparedPlayer.cachedReplay(prepared,messageID:preparedID,traceID:preparedTrace),"Prepared offline playback failed")
        let prefetchedOutput=VoiceTimeline.shared.records.first(where:{$0.id==preparedTrace})?.marks["first_output"]
        try require(prefetchedOutput != nil,"Prepared playback had no actual mixer output")
        try require(abs((preparedPlayer.durations[preparedID] ?? 0)-Double(paddedPCM.count-12000)/48000)<0.001,"Playback duration must account for removed padding")
        let rawWave=preparedDisk.data(preparedDisk.key(scope:scope,text:prepared.messageId+"|speech",speed:1))!
        try require(Data(rawWave.dropFirst(44))==paddedPCM,"Onset filtering must preserve the original durable recording")
        try? FileManager.default.removeItem(at:CacheLocations.live.speech.appendingPathComponent(preparedDisk.key(scope:scope,text:prepared.messageId+"|speech",speed:1)+".wav"))
        // Relaunch equivalent: no shared memory cache and no reachable provider.
        let disk=SpeechClipCache(directory:CacheLocations.live.speech)
        let fresh=CloudSpeech(soundscape:soundscape,api:api,cacheScope:scope,clipCache:disk)
        let restored=try JSONDecoder().decode(AIScript.self,from:JSONEncoder().encode(script))
        try require(try await fresh.cachedReplay(restored,messageID:message),"Offline replay after reconstruction missed durable clips")
        try require(fresh.audibleSegments==2,"Durable replay did not produce real audio")
        // A completed download survives interruption before its speaker drains.
        fresh.prepare(message,script:restored)
        try await fresh.accept(AIEvent(type:"segment.audio.started",beatId:"speech"))
        try await fresh.accept(AIEvent(type:"segment.audio.chunk",data:pcm.base64EncodedString()))
        let readyTask=Task {try await fresh.accept(AIEvent(type:"segment.audio.ready",beatId:"speech"))}
        try await Task.sleep(for:.milliseconds(30));fresh.stop();readyTask.cancel()
        _ = try? await readyTask.value
        let afterStop=SpeechClipCache(directory:CacheLocations.live.speech)
        try require(afterStop.data(afterStop.key(scope:scope,text:script.messageId+"|speech",speed:1)) != nil,"Complete audio was lost when playback stopped")
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
        // Real system notifications, not a mocked availability getter. A
        // temporary output pause must preserve the complete downloadable reply.
        func interruption(_ type:AVAudioSession.InterruptionType,resume:Bool=true) async {
            NotificationCenter.default.post(name:AVAudioSession.interruptionNotification,object:AVAudioSession.sharedInstance(),userInfo:[
                AVAudioSessionInterruptionTypeKey:type.rawValue,
                AVAudioSessionInterruptionOptionKey:resume ? AVAudioSession.InterruptionOptions.shouldResume.rawValue : UInt(0)])
            try? await Task.sleep(for:.milliseconds(40))
        }
        var interruptedScript=script;interruptedScript.messageId=UUID().uuidString;interruptedScript.beats=Array(script.beats.prefix(1))
        let interruptedID=UUID(uuidString:interruptedScript.messageId)!
        let recovering=CloudSpeech(soundscape:soundscape,api:api,cacheScope:scope)
        let recoveryKey=SpeechClipCache.shared.key(scope:scope,text:interruptedScript.messageId+"|speech",speed:1)
        defer {recovering.stop();try? FileManager.default.removeItem(at:CacheLocations.live.speech.appendingPathComponent(recoveryKey+".wav"))}
        await interruption(.began)
        try require(soundscape.interrupted,"A began notification must block speaker activation")
        recovering.prepare(interruptedID,script:interruptedScript)
        try await recovering.accept(AIEvent(type:"segment.audio.started",beatId:"speech"))
        try await recovering.accept(AIEvent(type:"segment.audio.chunk",data:pcm.base64EncodedString()))
        try await recovering.accept(AIEvent(type:"segment.audio.ready",beatId:"speech"))
        try require(recovering.playbackDeferred && !recovering.isSpeaking && recovering.audibleSegments==0,"An interruption must drain and cache without starting output or failing the reply")
        recovering.finish()
        try require(recovering.hasCached(interruptedScript),"Interrupted output discarded a complete reply's durable audio")
        await interruption(.ended)
        try require(!soundscape.interrupted && !soundscape.playbackSuspended,"Ended/shouldResume must unlock the audio session")
        try require(try await recovering.cachedReplay(interruptedScript,messageID:interruptedID),"Audio could not replay after an ended interruption")
        try require(recovering.audibleSegments==1,"Recovery did not produce real audio output")
        // Interrupt between network chunks, before cache persistence. Verify
        // that both halves survive, not merely an older complete cached clip.
        recovering.prepare(interruptedID,script:interruptedScript)
        try await recovering.accept(AIEvent(type:"segment.audio.started",beatId:"speech"))
        try await recovering.accept(AIEvent(type:"segment.audio.chunk",data:Data(pcm.prefix(14400)).base64EncodedString()))
        await interruption(.began)
        try await recovering.accept(AIEvent(type:"segment.audio.chunk",data:Data(pcm.dropFirst(14400)).base64EncodedString()))
        try await recovering.accept(AIEvent(type:"segment.audio.ready",beatId:"speech"))
        recovering.finish()
        let interruptedDisk=SpeechClipCache(directory:CacheLocations.live.speech)
        let saved=interruptedDisk.data(recoveryKey)
        try require(saved.map {Data($0.dropFirst(44))==pcm}==true,"A mid-stream interruption lost PCM or cache identity")
        await interruption(.ended,resume:false)
        try require(!soundscape.interrupted && soundscape.playbackSuspended,"A should-not-resume recommendation must pause output without latching the interruption")
        soundscape.resumePlayback()
        try require(try await recovering.cachedReplay(interruptedScript,messageID:interruptedID),"Explicit replay must resume after a privacy pause")
        NotificationCenter.default.post(name:AVAudioSession.routeChangeNotification,object:AVAudioSession.sharedInstance(),userInfo:[AVAudioSessionRouteChangeReasonKey:AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        try await Task.sleep(for:.milliseconds(40))
        try require(soundscape.playbackSuspended && !soundscape.interrupted,"Headset removal was mistaken for a permanent system interruption")
        try require(try await recovering.cachedReplay(interruptedScript,messageID:interruptedID),"Suspended output must remain consumable without a transport error")
        try require(recovering.playbackDeferred,"Automatic speech must respect a removed headset")
        soundscape.resumePlayback()
        soundscape.setActive(false)
        try require(try await recovering.cachedReplay(interruptedScript,messageID:interruptedID),"Foreground/session activation race must not fail the reply")
        try require(recovering.playbackDeferred,"Inactive output started a speaker")
        soundscape.setActive(true)
        // Exercise actual auto-reaction sessions for different roles. There is
        // no user message, and no paid transport or preparation is permitted.
        if ConversationContinuityFixture.enabled {
            for role in ["anime-hikarun","anime-chiffon"] {
                guard let model=ModelDescriptor.all.first(where:{$0.id==role}) else {throw NSError(domain:"SpeechPlaybackCheck",code:2)}
                let folder=FileManager.default.temporaryDirectory.appendingPathComponent("automatic-audio-\(UUID())")
                let journal=CompanionStore(storageURL:folder.appendingPathComponent("journal.json"),arguments:[])
                let session=CompanionSession(store:journal,model:model,soundscape:soundscape)
                defer {session.stop()}
                await interruption(.began)
                session.reactToModelInteraction(kind:role=="anime-hikarun" ? "shake" : "pinch_out",intensity:0.7)
                for _ in 0..<400 {
                    if !session.generating,!session.speech.isBusy,journal.record(role).messages.contains(where:{$0.role=="assistant"}) {break}
                    try await Task.sleep(for:.milliseconds(10))
                }
                let messages=journal.record(role).messages
                try require(messages.count==1 && messages[0].role=="assistant" && session.notice==nil,"Automatic interrupted speech created a phantom outgoing message or resend notice for \(role)")
                try require(messages[0].aiScript.map(session.speech.hasCached)==true && session.speech.playbackDeferred,"Automatic reply audio was not retained for \(role)")
                await interruption(.ended)
                session.playMessage(messages[0])
                for _ in 0..<200 {if session.speech.audibleSegments>0 && !session.speech.isBusy && !session.speech.isSpeaking {break};try await Task.sleep(for:.milliseconds(10))}
                try require(session.speech.audibleSegments>0,"Automatic reply could not replay after recovery for \(role)")
                session.reactToShake(intensity:1)
                for _ in 0..<300 {if !session.generating {break};try await Task.sleep(for:.milliseconds(10))}
                try require(!session.generating && session.notice==nil && journal.record(role).messages.count==1,"Exhausted automatic network retries displayed a nonexistent resend action for \(role)")
                try require(!journal.record(role).messages.contains(where:{$0.deliveryState=="failed"}),"Automatic failure marked an unrelated outgoing message")
            }
        }
        let traces=VoiceTimeline.shared.records.filter {$0.account==scope}
        try require(traces.contains(where:{$0.marks["first_output"] != nil && $0.spans.contains(where:{$0.name=="audio.pcm_convert"})}),"Voice trace missed real output or PCM conversion")
        try require(traces.contains(where:{$0.spans.contains(where:{$0.name=="audio.cache_write"}) && $0.spans.contains(where:{$0.name=="audio.drain" && $0.durationMs>50})}),"Voice trace omitted cache I/O or real speaker drain")
        try require(traces.contains(where:{$0.flags["audio_source"]=="持久语音缓存"}),"Durable replay source was not recorded")
        let encoded=try JSONEncoder().encode(traces)
        try require(!String(decoding:encoded,as:UTF8.self).contains("Audio regression"),"Diagnostics stored dialogue content")
        return "PASS: real output/cache/lip-sync/queue/cancellation; interruptions before and during PCM, ended recovery, route privacy, inactive-session race, Hikarun/Chiffon automatic replies and exhausted automatic retries; prefetched output \(Int(prefetchedOutput ?? -1)) ms (simulator fixture), zero network calls."
    }
}
