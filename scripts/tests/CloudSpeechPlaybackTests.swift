import Foundation

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
        var peak: Float = 0
        var played: [String] = []
        var previousTime = 0.0
        var regressions = 0
        var round = 0
        var frames: [[String:Any]] = []
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
            }
        }
        // A low-volume 0.6-second sine per beat. This is an audio fixture only,
        // never a fallback conversation or a synthesized provider response.
        var pcm = Data()
        for frame in 0..<14400 {
            var sample = Int16(sin(Double(frame)*2*Double.pi*440/24000)*2400).littleEndian
            withUnsafeBytes(of:&sample) { pcm.append(contentsOf:$0) }
        }
        speech.prepare(message,script:script)
        for beat in script.beats {
            try await speech.accept(AIEvent(type:"segment.audio.started",beatId:beat.beatId))
            for offset in stride(from:0,to:pcm.count,by:9600) {
                try await speech.accept(AIEvent(type:"segment.audio.chunk",data:Data(pcm.dropFirst(offset).prefix(9600)).base64EncodedString()))
            }
            try await speech.accept(AIEvent(type:"segment.audio.ready",beatId:beat.beatId))
            try await Task.sleep(for:.milliseconds(100))
            try require(speech.playbackLevel == 0,"A drained segment must stay silent while waiting for the next beat")
        }
        speech.finish()
        try require(peak > 0.02,"No actual mixer output was measured")
        try require(speech.audibleSegments == 2,"Expected both spoken and vocal-only output beats")
        try require(abs((speech.durations[message] ?? 0)-1.2)<0.01,"Playback did not drain both buffers")
        try require(played == ["speech","vocal"],"Beat order changed")
        try require(regressions == 0,"Speech timestamps moved backwards across streamed beats or finish; Unity rejects later lip-sync frames")
        try require(try await speech.cachedReplay(script,messageID:message),"Cached replay missed")
        try require(speech.audibleSegments == 4 && played == ["speech","vocal","speech","vocal"],"Replay skipped the vocal-only beat")
        try require(regressions == 0,"Cached speech timestamps moved backwards")
        speech.prepare(message,script:script)
        try await speech.accept(AIEvent(type:"segment.audio.started",beatId:"speech"))
        try await speech.accept(AIEvent(type:"segment.audio.chunk",data:pcm.base64EncodedString()))
        speech.stop()
        try await Task.sleep(for:.milliseconds(80))
        try require(!speech.isSpeaking && !speech.isBusy && speech.playbackLevel == 0 && soundscape.focus == .none,"Cancellation leaked playback state")
        return "PASS: real audio-thread metering, monotonic lip-sync timestamps, two-beat playback, vocal-only cache replay, duration and cancellation; zero network calls."
    }
}
