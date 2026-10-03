import Foundation
import AVFoundation
import Observation
import UIKit

/// The audio callback only converts/enqueues PCM. Network writes run in order on
/// a separate asynchronous consumer; a bounded queue prevents unbounded recording.
// AVAudioConverter synchronously invokes its input block. This holder confines
// that non-Sendable AVAudioPCMBuffer to one conversion, never across tasks.
private final class ConversionInput: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var supplied = false
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
}
private final class MicrophonePCM: @unchecked Sendable {
    private let queue=DispatchQueue(label:"app.starry.microphone",qos:.userInitiated)
    private var engine:AVAudioEngine?
    private var converter: AVAudioConverter?
    private var tapped=false
    func start(_ receive: @escaping @Sendable (Data,Float) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
            queue.async { [self] in
                do {try startEngine(receive);continuation.resume()}
                catch {stopEngine();continuation.resume(throwing:error)}
            }
        }
    }
    private func startEngine(_ receive: @escaping @Sendable (Data,Float) -> Void) throws {
        // Audio hardware construction can block too, not only engine.start().
        // Create and destroy the entire engine on the same audio queue.
        let engine=AVAudioEngine();self.engine=engine
        let input = engine.inputNode
        let source = input.outputFormat(forBus:0)
        guard source.sampleRate > 0, let target = AVAudioFormat(commonFormat:.pcmFormatInt16,sampleRate:16000,channels:1,interleaved:true),
              let converter = AVAudioConverter(from:source,to:target) else { throw AIConnectionError.unavailable }
        self.converter = converter
        input.installTap(onBus:0,bufferSize:2048,format:source) { buffer,_ in
            let capacity = AVAudioFrameCount(Double(buffer.frameLength)*16000/source.sampleRate+32)
            guard let output = AVAudioPCMBuffer(pcmFormat:target,frameCapacity:capacity) else { return }
            let input = ConversionInput(buffer); var error: NSError?
            converter.convert(to:output,error:&error) { _,status in
                if input.supplied { status.pointee = .noDataNow; return nil }
                input.supplied = true; status.pointee = .haveData; return input.buffer
            }
            guard error == nil, output.frameLength > 0, let samples = output.int16ChannelData?[0] else { return }
            var square:Float=0
            for index in 0..<Int(output.frameLength) {let sample=Float(samples[index])/32768;square += sample*sample}
            receive(Data(bytes:samples,count:Int(output.frameLength)*2),min(1,sqrt(square/Float(output.frameLength))*5))
        }
        tapped=true
        engine.prepare(); try engine.start()
    }
    private func stopEngine() {
        if tapped {engine?.inputNode.removeTap(onBus:0);tapped=false}
        engine?.stop();engine=nil;converter=nil
    }
    func stop() { queue.async { [self] in stopEngine() } }
}

@MainActor @Observable final class CloudSpeech: NSObject {
    var ready = false
    var status = "正在连接声音"
    var error: String?
    var isRecording = false
    var isSpeaking = false
    var isBusy = false
    private(set) var recordingTranscript=""
    private(set) var inputLevel:Float=0
    @ObservationIgnored private var recordingEnded=false
    private(set) var activeMessageID: UUID?
    private(set) var playbackElapsed = 0.0
    private(set) var playbackLevel: Float = 0
    private(set) var durations: [UUID:Double] = [:]
    private(set) var durationSpeeds: [UUID:Double] = [:]
    private(set) var audibleSegments = 0
    @ObservationIgnored var onTranscript: ((String) -> Void)?
    @ObservationIgnored var onPartial: ((String) -> Void)?
    @ObservationIgnored var nickname: (() -> String)?
    @ObservationIgnored var onDuration: ((UUID,Double,Double) -> Void)?
    @ObservationIgnored var onState: ((String) -> Void)?
    @ObservationIgnored var onFrame: ((Double,Float) -> Void)?
    @ObservationIgnored var onBeat: ((String) -> Void)?
    @ObservationIgnored var onBeatProgress: ((String,Double) -> Void)?
    let soundscape: CompanionSoundscape
    let api: CharacterAI
    let cacheScope: String
    private let clipCache: SpeechClipCache
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var player: AVAudioPlayerNode?
    @ObservationIgnored private var microphone: MicrophonePCM?
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var recording: Task<Void,Never>?
    @ObservationIgnored private var upload: Task<Void,Never>?
    @ObservationIgnored private var recordingLimit: Task<Void,Never>?
    @ObservationIgnored private var recordingTimeout: Task<Void,Never>?
    @ObservationIgnored var onCaptureCancelled: (() -> Void)?
    @ObservationIgnored var onCaptureRecovery: ((String) -> Void)?
    @ObservationIgnored private var capture: AsyncThrowingStream<Data,Error>.Continuation?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var buffers = 0
    @ObservationIgnored private var beat = ""
    @ObservationIgnored private var beatPCM = Data()
    @ObservationIgnored private var beatSourcePCM = Data()
    @ObservationIgnored private var onset = SpeechOnset()
    @ObservationIgnored private var totalDuration = 0.0
    @ObservationIgnored private var beatStartTime = 0.0
    @ObservationIgnored private var beatFrames = 0
    @ObservationIgnored private var beatDuration: Double?
    @ObservationIgnored private var durationHints: [String:Double] = [:]
    @ObservationIgnored private var playbackSegment = UUID()
    @ObservationIgnored private var cacheGeneration = UUID()
    @ObservationIgnored private var cacheMessage = ""
    @ObservationIgnored private var repairBeats:Set<String> = []
    @ObservationIgnored private var measured = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var presentationActive=true
    @ObservationIgnored private var segmentAudible=true
    @ObservationIgnored private var voiceTrace:String?
    /// Drain hidden-page audio to the same cache without starting an engine.
    /// Keep the transport generation and PCM intact; returning may play the next
    /// complete beat, while the interrupted beat remains available for replay.
    func setPresentationActive(_ active:Bool) {
        presentationActive=active
        guard !active else {return}
        segmentAudible=false;playbackSegment=UUID();buffers=0
        timer?.invalidate();timer=nil;player?.stop();engine?.stop();player=nil;engine=nil
        isSpeaking=false;playbackLevel=0;onFrame?(playbackElapsed,0)
        soundscape.endVoice()
    }
    init(soundscape: CompanionSoundscape, api: CharacterAI, cacheScope: String, clipCache:SpeechClipCache = .shared) {
        self.soundscape = soundscape; self.api = api; self.cacheScope = cacheScope; self.clipCache=clipCache
        super.init()
        for name in [UIApplication.didEnterBackgroundNotification,AVAudioSession.interruptionNotification] {
            NotificationCenter.default.addObserver(self,selector:#selector(interrupted),name:name,object:nil)
        }
    }
    @objc nonisolated private func interrupted(_ note: Notification) {
        if note.name == AVAudioSession.interruptionNotification,
           (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) != AVAudioSession.InterruptionType.began.rawValue {return}
        Task { @MainActor [weak self] in self?.stop();self?.onCaptureCancelled?() }
    }
    func check() async { ready = await api.check(); status = ready ? "声音已连接" : "请检查 AI 服务连接" }
    func refreshVolume() { player?.volume = Float(soundscape.speechVolume) }
    func prepare(_ message: UUID, script: AIScript,traceID:String?=nil) {
        stop(); error = nil; activeMessageID = message; cacheMessage = script.messageId
        voiceTrace=traceID ?? VoiceTimeline.shared.begin(account:api.accountID,character:api.characterID,kind:"playback",message:script.messageId)
        VoiceTimeline.shared.mark(voiceTrace,"playback_prepare")
        VoiceTimeline.shared.flag(voiceTrace,"speech_volume",String(soundscape.speechVolume))
        cacheGeneration = clipCache.generation
        repairBeats=Set(script.beats.filter{ReplyDisplayText.needsSpeechRepair($0.dialogue?.text ?? "")}.map(\.beatId))
        durationHints=Dictionary(uniqueKeysWithValues:script.beats.map {($0.beatId,$0.readingDuration ?? max(1.8,Double($0.dialogue?.text.count ?? 0)/5.5))})
        isBusy = true; totalDuration = 0; beatStartTime = 0; beatFrames = 0; playbackElapsed = 0; onState?("thinking")
    }
    private func key(_ beat: String) -> String { clipCache.key(scope:cacheScope,text:cacheMessage+"|"+beat,speed:1,repair:repairBeats.contains(beat)) }
    private func cachedKey(_ script:AIScript,_ beat:String)->String {
        let repair=ReplyDisplayText.needsSpeechRepair(script.beats.first{$0.beatId==beat}?.dialogue?.text ?? "")
        return clipCache.key(scope:cacheScope,text:script.messageId+"|"+beat,speed:1,repair:repair)
    }
    func cachePrepared(_ clips:[AIPreparedClip]) {
        let generation=clipCache.generation
        for clip in clips {
            for audio in clip.audio {
                guard let data=Data(base64Encoded:audio.data),!data.isEmpty,data.count%2==0 else {continue}
                clipCache.insert(Self.wave(data),key:cachedKey(clip.script,audio.beatId),generation:generation)
            }
        }
    }
    func hasCached(_ script:AIScript)->Bool {
        let beats=script.beats.filter(\.hasAudio)
        return !beats.isEmpty && beats.allSatisfy {clipCache.data(cachedKey(script,$0.beatId)) != nil}
    }
    func accept(_ event: AIEvent) async throws {
        let timeline=VoiceTimeline.shared
        if let trace=event.traceId {voiceTrace=trace}
        if let id=voiceTrace,let received=event.receivedAt {
            timeline.add(id,VoiceSpan(name:"audio.queue_wait",startMs:max(0,timeline.now(id)-(ProcessInfo.processInfo.systemUptime-received)*1000),durationMs:max(0,(ProcessInfo.processInfo.systemUptime-received)*1000),beatId:event.beatId))
        }
        switch event.type {
        case "segment.audio.started":
            var stage=voiceTrace.map {timeline.now($0)} ?? 0
            try await drain()
            timeline.span(voiceTrace,"audio.previous_drain",start:stage,beat:event.beatId)
            timer?.invalidate(); timer = nil; playbackSegment = UUID()
            player?.stop(); engine?.stop(); engine = nil; player = nil
            beat = event.beatId ?? ""; beatPCM = Data(); beatSourcePCM = Data(); onset = SpeechOnset(); beatFrames = 0; measured = false; beatDuration=nil
            beatStartTime = totalDuration; playbackElapsed = beatStartTime; playbackLevel = 0
            onFrame?(playbackElapsed,0)
            segmentAudible=presentationActive
            timeline.flag(voiceTrace,"presentation_active",presentationActive ? "是" : "否；仅缓存不出声")
            guard segmentAudible else {return}
            stage=voiceTrace.map {timeline.now($0)} ?? 0
            do {try await soundscape.beginVoice(.speech)}
            catch {if !presentationActive {segmentAudible=false;return};throw error}
            timeline.span(voiceTrace,"audio.session",start:stage,beat:beat)
            guard presentationActive else {segmentAudible=false;return}
            stage=voiceTrace.map {timeline.now($0)} ?? 0
            let engine = AVAudioEngine(), player = AVAudioPlayerNode()
            engine.attach(player); engine.connect(player,to:engine.mainMixerNode,format:AVAudioFormat(standardFormatWithSampleRate:24000,channels:1))
            self.engine = engine; self.player = player; refreshVolume()
            let current = generation
            let segment = playbackSegment
            // Meter audio that actually reaches the output mixer. Network chunks
            // can arrive far ahead of playback, especially during cached replay.
            engine.mainMixerNode.installTap(onBus:0,bufferSize:1024,format:nil,block:Self.meteringTap { [weak self] level in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == current, self.playbackSegment == segment else { return }
                    self.playbackLevel = level
                    if !self.measured && level > 0.02 {
                        self.measured = true; self.audibleSegments += 1
                        VoiceTimeline.shared.mark(self.voiceTrace,"first_output")
                        VoiceTimeline.shared.mark(self.voiceTrace,"output."+self.beat)
                    }
                }
            })
            engine.prepare(); try engine.start(); player.play()
            timeline.span(voiceTrace,"audio.engine",start:stage,beat:beat)
        case "segment.audio.chunk":
            let decoding=voiceTrace.map {timeline.now($0)} ?? 0
            guard let data = event.data.flatMap({ Data(base64Encoded:$0) }) else { throw AIConnectionError.remote("INVALID_AUDIO") }
            timeline.span(voiceTrace,"audio.base64",start:decoding,beat:beat,bytes:data.count)
            append(data)
        case "segment.audio.ready":
            schedulePCM(onset.finish())
            timeline.flag(voiceTrace,"audio.onset_padding_removed_ms."+beat,String(Double(onset.removedFrames)/24))
            // The full byte count is known before draining, so reveal stages
            // while sound is actually playing, not when downloading finishes.
            beatDuration=Double(beatPCM.count)/48000
            // Save a complete network segment before waiting for the speaker.
            // Backgrounding/stopping playback must not discard downloaded audio.
            if !beatPCM.isEmpty {
                let start=voiceTrace.map {timeline.now($0)} ?? 0
                clipCache.insert(Self.wave(beatSourcePCM),key:key(beat),generation:cacheGeneration)
                timeline.span(voiceTrace,"audio.cache_write",start:start,beat:beat,bytes:beatSourcePCM.count)
            }
            let draining=voiceTrace.map {timeline.now($0)} ?? 0
            try await drain()
            timeline.span(voiceTrace,"audio.drain",start:draining,beat:beat)
            onBeatProgress?(beat,1)
            playbackSegment = UUID() // Retire late mixer/timer callbacks during the next beat's network wait.
            timer?.invalidate(); timer = nil; playbackLevel = 0
            playbackElapsed = beatStartTime+Double(beatFrames)/24000
            onFrame?(playbackElapsed,0)
            if !beatPCM.isEmpty {
                totalDuration += Double(beatPCM.count)/48000
                if let id = activeMessageID {
                    durations[id] = totalDuration; durationSpeeds[id] = 1; onDuration?(id,1,totalDuration)
                }
            }
        case "audio.error": error = event.message;VoiceTimeline.shared.finish(voiceTrace,status:"failed");finish()
        default: break
        }
    }
    // AVAudioNodeTapBlock is imported without @Sendable. Construct it outside
    // MainActor isolation: the audio thread must never inherit an actor check.
    nonisolated private static func meteringTap(_ receive: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        { buffer,_ in
            guard buffer.frameLength > 0, let samples = buffer.floatChannelData?[0] else { return }
            var square: Float = 0
            for index in 0..<Int(buffer.frameLength) { square += samples[index]*samples[index] }
            receive(min(1,sqrt(square/Float(buffer.frameLength))*4))
        }
    }
    private func append(_ data: Data) {
        guard data.count.isMultiple(of:2),data.count <= 24000*2*15 else {return}
        beatSourcePCM.append(data)
        schedulePCM(onset.accept(data))
    }
    private func schedulePCM(_ data:Data) {
        guard !data.isEmpty else {return}
        if !segmentAudible {
            beatPCM.append(data);beatFrames += data.count/2
            return
        }
        let timeline=VoiceTimeline.shared
        let converting=voiceTrace.map {timeline.now($0)} ?? 0
        guard let player,
              let format = AVAudioFormat(standardFormatWithSampleRate:24000,channels:1),
              let buffer = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(data.count/2)),
              let output = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = buffer.frameCapacity
        data.withUnsafeBytes { bytes in
            for index in 0..<Int(buffer.frameLength) {
                let sample = Float(Int16(littleEndian:bytes.loadUnaligned(fromByteOffset:index*2,as:Int16.self)))/32768
                output[index] = sample
            }
        }
        timeline.span(voiceTrace,"audio.pcm_convert",start:converting,beat:beat,bytes:data.count)
        let current = generation
        let segment = playbackSegment
        if beatPCM.isEmpty {
            onBeat?(beat); isSpeaking = true; isBusy = false; onState?("speaking")
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval:0.04,repeats:true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == current, self.playbackSegment == segment else { return }
                    // Unity orders frames for the whole utterance, not each beat.
                    // Keep this offset stable even when ready updates totalDuration.
                    self.onFrame?(self.beatStartTime+Double(self.beatFrames)/24000,self.playbackLevel)
                    let duration=max(0.1,self.beatDuration ?? self.durationHints[self.beat] ?? 4)
                    self.onBeatProgress?(self.beat,min(0.98,Double(self.beatFrames)/24000/duration))
                }
            }
        }
        beatPCM.append(data); buffers += 1
        let frames = Int(buffer.frameLength)
        let scheduling=voiceTrace.map {timeline.now($0)} ?? 0
        timeline.mark(voiceTrace,"first_buffer_scheduled")
        player.scheduleBuffer(buffer,completionCallbackType:.dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == current, self.playbackSegment == segment else { return }
                self.buffers = max(0,self.buffers-1); self.beatFrames += frames
                self.playbackElapsed = self.beatStartTime+Double(self.beatFrames)/24000
                VoiceTimeline.shared.mark(self.voiceTrace,"last_buffer_played",once:false)
                if self.buffers == 0 { self.playbackLevel = 0 }
            }
        }
        timeline.span(voiceTrace,"audio.schedule",start:scheduling,beat:beat,bytes:data.count)
    }
    private func drain() async throws {
        let current = generation
        while buffers > 0 {
            try await Task.sleep(for:.milliseconds(20)); try Task.checkCancellation()
            if current != generation { throw CancellationError() }
        }
    }
    func cachedReplay(_ script: AIScript, messageID: UUID,traceID:String?=nil) async throws -> Bool {
        let timeline=VoiceTimeline.shared
        let id=traceID ?? timeline.begin(account:api.accountID,character:api.characterID,kind:script.openingID==nil ? "local_replay" : "bundled_opening",message:script.messageId)
        let reading=timeline.now(id)
        if let openingID=script.openingID,let opening=CharacterOpenings.find(openingID) {
            let pcm=try await opening.pcm()
            try Task.checkCancellation()
            prepare(messageID,script:script,traceID:id)
            timeline.span(voiceTrace,"audio.cache_read",start:reading,bytes:pcm.count)
            timeline.flag(voiceTrace,"audio_source","内置首句")
            timeline.mark(id,"audio_ready")
            timeline.mark(id,"processing_complete")
            let duration=Double(pcm.count)/48000
            durations[messageID]=duration;durationSpeeds[messageID]=1;onDuration?(messageID,1,duration)
            try await accept(AIEvent(type:"segment.audio.started",beatId:"opening"))
            for offset in stride(from:0,to:pcm.count,by:12288) {
                try Task.checkCancellation()
                try await accept(AIEvent(type:"segment.audio.chunk",data:pcm.subdata(in:offset..<min(offset+12288,pcm.count)).base64EncodedString()))
            }
            try await accept(AIEvent(type:"segment.audio.ready",beatId:"opening"))
            finish();return true
        }
        let keys = script.beats.filter { $0.hasAudio }.map { $0.beatId }
        let cached = keys.map { clipCache.data(cachedKey(script,$0)) }
        timeline.span(id,"audio.cache_read",start:reading)
        guard !keys.isEmpty, cached.allSatisfy({ $0 != nil }) else {timeline.flag(id,"audio_source","本地缓存缺失");if traceID==nil {timeline.finish(id,status:"cache_miss")};return false }
        prepare(messageID,script:script,traceID:id)
        timeline.flag(id,"audio_source","持久语音缓存")
        timeline.mark(id,"audio_ready")
        timeline.mark(id,"processing_complete")
        for (id,wave) in zip(keys,cached) {
            try await accept(AIEvent(type:"segment.audio.started",beatId:id))
            let pcm = wave!.dropFirst(44)
            for offset in stride(from:0,to:pcm.count,by:12288) {
                let part = Data(pcm.dropFirst(offset).prefix(12288))
                try await accept(AIEvent(type:"segment.audio.chunk",data:part.base64EncodedString()))
            }
            try await accept(AIEvent(type:"segment.audio.ready",beatId:id))
        }
        finish(); return true
    }
    func finish() {
        VoiceTimeline.shared.mark(voiceTrace,"playback_finished")
        VoiceTimeline.shared.finish(voiceTrace,status:error==nil ? "completed" : "failed");voiceTrace=nil
        playbackSegment = UUID(); buffers = 0
        timer?.invalidate(); timer = nil; player?.stop(); engine?.stop(); player = nil; engine = nil
        isSpeaking = false; isBusy = false; activeMessageID = nil; playbackLevel = 0
        onFrame?(playbackElapsed,0); onState?("idle"); soundscape.endVoice()
    }
    func toggleRecording() {
        if isRecording { finishRecording(); return }
        startRecording()
    }
    func startRecording() {
        guard !isRecording else {return}
        stop(); error = nil; let current = generation
        voiceTrace=VoiceTimeline.shared.begin(account:api.accountID,character:api.characterID,kind:"asr")
        recordingTranscript="";inputLevel=0;recordingEnded=false
        isRecording=true;isBusy=true;status="正在打开麦克风";onState?("listening")
        #if DEBUG && targetEnvironment(simulator)
        // Deterministic gesture regression: the provider finishes while the
        // finger is still down. Never requests microphone/network/paid AI.
        let arguments=ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing"),arguments.contains("--voice-atmosphere-check"),!arguments.contains("--live-ai") {
            recording=Task { @MainActor [weak self] in
                do {try await Task.sleep(for:.milliseconds(120))} catch {return}
                guard let self,current==generation else {return}
                recordingTranscript="今天窗外";onPartial?(recordingTranscript);isBusy=false
                do {try await Task.sleep(for:.milliseconds(220))} catch {return}
                guard current==generation else {return}
                recordingTranscript="今天窗外下雨了";onPartial?(recordingTranscript)
                if arguments.contains("--voice-capture-error") {failRecording("测试连接中断，文字已保留。")}
                else {stop();onTranscript?("今天窗外下雨了")}
            }
            return
        }
        #endif
        recording = Task { @MainActor [weak self] in
            guard let self else { return }
            let permission=self.voiceTrace.map {VoiceTimeline.shared.now($0)} ?? 0
            let allowed=await AVAudioApplication.requestRecordPermission()
            VoiceTimeline.shared.span(self.voiceTrace,"microphone.permission",start:permission)
            guard current==generation else {return}
            guard allowed else {failRecording("请在系统设置中允许麦克风权限。");return}
            guard !recordingEnded else {stop();onCaptureCancelled?();return}
            do {
                let socket = try api.socket(nickname:nickname?() ?? "",traceID:voiceTrace); self.socket = socket; socket.resume()
                VoiceTimeline.shared.mark(voiceTrace,"asr_socket_sent")
                scheduleRecordingTimeout(seconds:12,current:current)
                let audioSession=voiceTrace.map {VoiceTimeline.shared.now($0)} ?? 0
                try await soundscape.beginVoice(.recording)
                VoiceTimeline.shared.span(voiceTrace,"audio.session",start:audioSession)
                guard current==generation else {return}
                // Start capture while ASR connects. Four seconds of bounded
                // pre-roll retain the first syllable without unbounded memory.
                let (stream,continuation)=AsyncThrowingStream<Data,Error>.makeStream(bufferingPolicy:.bufferingOldest(96))
                capture=continuation
                let microphone=MicrophonePCM();self.microphone=microphone
                let captureStart=voiceTrace.map {VoiceTimeline.shared.now($0)} ?? 0
                try await microphone.start { [weak self] data,level in
                    if case .dropped = continuation.yield(data) {continuation.finish(throwing:URLError(.networkConnectionLost))}
                    Task { @MainActor [weak self] in
                        guard let self,self.generation==current else {return};self.inputLevel=level
                    }
                }
                VoiceTimeline.shared.span(voiceTrace,"microphone.engine",start:captureStart)
                guard current==generation else {microphone.stop();return}
                isBusy=false;status="松开发送，上滑编辑"
                if recordingEnded {finishRecording()}
                recordingLimit = Task { @MainActor [weak self] in
                    try? await Task.sleep(for:.seconds(30));if !Task.isCancelled {self?.finishRecording()}
                }
                let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
                while !Task.isCancelled {
                    let packet = try await socket.receive()
                    let data: Data
                    switch packet { case .data(let value): data = value; case .string(let value): data = Data(value.utf8); @unknown default: continue }
                    let event = try decoder.decode(AIEvent.self,from:data)
                    if let id=voiceTrace {VoiceTimeline.shared.receive(id,event:event)}
                    guard current == generation else { return }
                    switch event.type {
                    case "asr.ready":
                        VoiceTimeline.shared.mark(voiceTrace,"asr_ready")
                        if let id=voiceTrace,let start=VoiceTimeline.shared.records.last(where:{$0.id==id})?.marks["asr_socket_sent"] {
                            VoiceTimeline.shared.span(id,"asr.socket_ready",start:start)
                        }
                        if !recordingEnded {recordingTimeout?.cancel();recordingTimeout=nil}
                        upload = Task { @MainActor [weak self] in
                            do {
                                for try await chunk in stream {
                                    try Task.checkCancellation();let start=self?.voiceTrace.map {VoiceTimeline.shared.now($0)} ?? 0
                                    try await socket.send(.data(chunk))
                                    VoiceTimeline.shared.span(self?.voiceTrace,"asr.upload",start:start,bytes:chunk.count)
                                }
                                try await socket.send(.string("{\"type\":\"finish\"}"))
                            } catch {
                                guard let self,current==generation,!Task.isCancelled else {return}
                                failRecording("上传语音中断，已保留识别文字。")
                            }
                        }
                    case "asr.partial", "asr.final":
                        VoiceTimeline.shared.mark(voiceTrace,"asr_first_text")
                        recordingTranscript=String((event.text ?? "").prefix(500));onPartial?(recordingTranscript)
                    case "asr.completed":
                        VoiceTimeline.shared.mark(voiceTrace,"asr_completed")
                        VoiceTimeline.shared.finish(voiceTrace)
                        let text = event.text ?? ""
                        if text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {failRecording("没有听清，可以重新说一次或输入文字。")}
                        else {stop();onTranscript?(String(text.prefix(500)))}
                        return
                    case "asr.error": throw AIConnectionError.remote("ASR_FAILED")
                    default: break
                    }
                }
            } catch {
                guard current == generation, !Task.isCancelled else { return }
                failRecording((error as? AIConnectionError)?.errorDescription ?? "语音识别连接中断，已保留识别文字。")
            }
        }
    }
    func finishRecording() {
        guard isRecording || recordingEnded else { return }
        recordingEnded=true
        VoiceTimeline.shared.mark(voiceTrace,"microphone_released")
        microphone?.stop(); microphone = nil; capture?.finish(); capture = nil
        isRecording = false; isBusy = true; inputLevel=0;status = "正在确认最后一句"; recordingLimit?.cancel(); recordingLimit = nil
        scheduleRecordingTimeout(seconds:10,current:generation)
    }
    private func scheduleRecordingTimeout(seconds:Double,current:UUID) {
        recordingTimeout?.cancel()
        recordingTimeout=Task { @MainActor [weak self] in
            do {try await Task.sleep(for:.seconds(seconds))} catch {return}
            guard let self,current==generation else {return}
            failRecording("语音连接超时，可以修改已识别的文字。")
        }
    }
    private func failRecording(_ message:String) {
        VoiceTimeline.shared.finish(voiceTrace,status:"failed")
        let partial=recordingTranscript
        stop();error=message;onCaptureRecovery?(partial)
    }
    func stop() {
        VoiceTimeline.shared.finish(voiceTrace,status:"cancelled")
        generation = UUID(); recording?.cancel(); recording = nil; upload?.cancel(); upload = nil
        recordingLimit?.cancel(); recordingLimit = nil; capture?.finish(); capture = nil
        recordingTimeout?.cancel();recordingTimeout=nil
        microphone?.stop(); microphone = nil; socket?.cancel(with:.goingAway,reason:nil); socket = nil
        buffers = 0; beatPCM = Data(); beatSourcePCM = Data(); onset = SpeechOnset(); isRecording = false; recordingEnded=false;inputLevel=0;finish()
    }
    private static func wave(_ pcm: Data) -> Data {
        var output = Data("RIFF".utf8)
        func number<T: FixedWidthInteger>(_ value: T) { var value = value.littleEndian; withUnsafeBytes(of:&value) { output.append(contentsOf:$0) } }
        number(UInt32(pcm.count+36)); output.append(Data("WAVEfmt ".utf8)); number(UInt32(16)); number(UInt16(1)); number(UInt16(1))
        number(UInt32(24000)); number(UInt32(48000)); number(UInt16(2)); number(UInt16(16)); output.append(Data("data".utf8)); number(UInt32(pcm.count)); output.append(pcm); return output
    }
}
