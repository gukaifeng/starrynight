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
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    func start(_ receive: @escaping @Sendable (Data) -> Void) throws {
        let input = engine.inputNode
        let source = input.outputFormat(forBus:0)
        guard source.sampleRate > 0, let target = AVAudioFormat(commonFormat:.pcmFormatInt16,sampleRate:16000,channels:1,interleaved:true),
              let converter = AVAudioConverter(from:source,to:target) else { throw AIConnectionError.unavailable }
        self.converter = converter
        input.installTap(onBus:0,bufferSize:2048,format:source) { [self] buffer,_ in
            let capacity = AVAudioFrameCount(Double(buffer.frameLength)*16000/source.sampleRate+32)
            guard let output = AVAudioPCMBuffer(pcmFormat:target,frameCapacity:capacity), let converter = self.converter else { return }
            let input = ConversionInput(buffer); var error: NSError?
            converter.convert(to:output,error:&error) { _,status in
                if input.supplied { status.pointee = .noDataNow; return nil }
                input.supplied = true; status.pointee = .haveData; return input.buffer
            }
            guard error == nil, output.frameLength > 0, let samples = output.int16ChannelData?[0] else { return }
            receive(Data(bytes:samples,count:Int(output.frameLength)*2))
        }
        engine.prepare(); try engine.start()
    }
    func stop() { engine.inputNode.removeTap(onBus:0); engine.stop(); converter = nil }
}

@MainActor @Observable final class CloudSpeech: NSObject {
    var ready = false
    var status = "正在连接声音"
    var error: String?
    var isRecording = false
    var isSpeaking = false
    var isBusy = false
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
    let soundscape: CompanionSoundscape
    let api: CharacterAI
    let cacheScope: String
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var player: AVAudioPlayerNode?
    @ObservationIgnored private var microphone: MicrophonePCM?
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var recording: Task<Void,Never>?
    @ObservationIgnored private var upload: Task<Void,Never>?
    @ObservationIgnored private var recordingLimit: Task<Void,Never>?
    @ObservationIgnored private var capture: AsyncThrowingStream<Data,Error>.Continuation?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var buffers = 0
    @ObservationIgnored private var beat = ""
    @ObservationIgnored private var beatPCM = Data()
    @ObservationIgnored private var totalDuration = 0.0
    @ObservationIgnored private var beatFrames = 0
    @ObservationIgnored private var cacheGeneration = UUID()
    @ObservationIgnored private var cacheMessage = ""
    @ObservationIgnored private var measured = false
    @ObservationIgnored private var timer: Timer?
    init(soundscape: CompanionSoundscape, api: CharacterAI, cacheScope: String) {
        self.soundscape = soundscape; self.api = api; self.cacheScope = cacheScope
        super.init()
        for name in [UIApplication.didEnterBackgroundNotification,AVAudioSession.interruptionNotification] {
            NotificationCenter.default.addObserver(self,selector:#selector(interrupted),name:name,object:nil)
        }
    }
    @objc nonisolated private func interrupted(_ note: Notification) { Task { @MainActor [weak self] in self?.stop() } }
    func check() async { ready = await api.check(); status = ready ? "声音已连接" : "请检查 AI 服务连接" }
    func refreshVolume() { player?.volume = Float(soundscape.speechVolume) }
    func prepare(_ message: UUID, script: AIScript) {
        stop(); error = nil; activeMessageID = message; cacheMessage = script.messageId
        cacheGeneration = SpeechClipCache.shared.generation
        isBusy = true; totalDuration = 0; onState?("thinking")
    }
    private func key(_ beat: String) -> String { SpeechClipCache.shared.key(scope:cacheScope,text:cacheMessage+"|"+beat,speed:1) }
    func accept(_ event: AIEvent) async throws {
        switch event.type {
        case "segment.audio.started":
            try await drain(); player?.stop(); engine?.stop(); engine = nil; player = nil
            beat = event.beatId ?? ""; beatPCM = Data(); beatFrames = 0; measured = false
            try soundscape.beginVoice(.speech)
            let engine = AVAudioEngine(), player = AVAudioPlayerNode()
            engine.attach(player); engine.connect(player,to:engine.mainMixerNode,format:AVAudioFormat(standardFormatWithSampleRate:24000,channels:1))
            self.engine = engine; self.player = player; refreshVolume()
            let current = generation
            // Meter audio that actually reaches the output mixer. Network chunks
            // can arrive far ahead of playback, especially during cached replay.
            engine.mainMixerNode.installTap(onBus:0,bufferSize:1024,format:nil,block:Self.meteringTap { [weak self] level in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == current else { return }
                    self.playbackLevel = level
                    if !self.measured && level > 0.02 { self.measured = true; self.audibleSegments += 1 }
                }
            })
            engine.prepare(); try engine.start(); player.play()
        case "segment.audio.chunk":
            guard let data = event.data.flatMap({ Data(base64Encoded:$0) }) else { throw AIConnectionError.remote("INVALID_AUDIO") }
            append(data)
        case "segment.audio.ready":
            try await drain()
            if !beatPCM.isEmpty {
                SpeechClipCache.shared.insert(Self.wave(beatPCM),key:key(beat),generation:cacheGeneration)
                totalDuration += Double(beatPCM.count)/48000
                if let id = activeMessageID {
                    durations[id] = totalDuration; durationSpeeds[id] = 1; onDuration?(id,1,totalDuration)
                }
            }
        case "audio.error": error = event.message; finish()
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
        guard let player, data.count.isMultiple(of:2), data.count <= 24000*2*15,
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
        let current = generation
        if beatPCM.isEmpty {
            onBeat?(beat); isSpeaking = true; isBusy = false; onState?("speaking")
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval:0.04,repeats:true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == current else { return }
                    self.onFrame?(Double(self.beatFrames)/24000,self.playbackLevel)
                }
            }
        }
        beatPCM.append(data); buffers += 1
        let frames = Int(buffer.frameLength)
        player.scheduleBuffer(buffer,completionCallbackType:.dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                self.buffers = max(0,self.buffers-1); self.beatFrames += frames
                self.playbackElapsed = self.totalDuration+Double(self.beatFrames)/24000
                if self.buffers == 0 { self.playbackLevel = 0 }
            }
        }
    }
    private func drain() async throws {
        let current = generation
        while buffers > 0 {
            try await Task.sleep(for:.milliseconds(20)); try Task.checkCancellation()
            if current != generation { throw CancellationError() }
        }
    }
    func cachedReplay(_ script: AIScript, messageID: UUID) async throws -> Bool {
        let keys = script.beats.filter { $0.hasAudio }.map { $0.beatId }
        let cached = keys.map { SpeechClipCache.shared.data(SpeechClipCache.shared.key(scope:cacheScope,text:script.messageId+"|"+$0,speed:1)) }
        guard !keys.isEmpty, cached.allSatisfy({ $0 != nil }) else { return false }
        prepare(messageID,script:script)
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
        timer?.invalidate(); timer = nil; player?.stop(); engine?.stop(); player = nil; engine = nil
        isSpeaking = false; isBusy = false; activeMessageID = nil; playbackLevel = 0
        onFrame?(0,0); onState?("idle"); soundscape.endVoice()
    }
    func toggleRecording() {
        if isRecording { finishRecording(); return }
        stop(); error = nil; let current = generation
        recording = Task { @MainActor [weak self] in
            guard let self else { return }
            guard await AVAudioApplication.requestRecordPermission(), current == generation else { error = "请在系统设置中允许麦克风权限。"; return }
            do {
                let socket = try api.socket(nickname:nickname?() ?? ""); self.socket = socket; socket.resume()
                isRecording = true; isBusy = true; status = "正在连接麦克风"; onState?("listening")
                let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
                while !Task.isCancelled {
                    let packet = try await socket.receive()
                    let data: Data
                    switch packet { case .data(let value): data = value; case .string(let value): data = Data(value.utf8); @unknown default: continue }
                    let event = try decoder.decode(AIEvent.self,from:data)
                    guard current == generation else { return }
                    switch event.type {
                    case "asr.ready":
                        try soundscape.beginVoice(.recording)
                        let (stream,continuation) = AsyncThrowingStream<Data,Error>.makeStream(bufferingPolicy:.bufferingOldest(120))
                        capture = continuation; let microphone = MicrophonePCM(); self.microphone = microphone
                        try microphone.start { data in
                            if case .dropped = continuation.yield(data) { continuation.finish(throwing:URLError(.networkConnectionLost)) }
                        }
                        isBusy = false; status = "正在聆听 · 再点结束"
                        upload = Task { @MainActor [weak self] in
                            do {
                                for try await chunk in stream { try Task.checkCancellation(); try await socket.send(.data(chunk)) }
                                try await socket.send(.string("{\"type\":\"finish\"}"))
                            } catch { if !Task.isCancelled { self?.stop(); self?.error = "上传语音失败，请重试。" } }
                        }
                        recordingLimit = Task { @MainActor [weak self] in
                            try? await Task.sleep(for:.seconds(30)); if !Task.isCancelled { self?.finishRecording() }
                        }
                    case "asr.partial", "asr.final": onPartial?(String((event.text ?? "").prefix(500)))
                    case "asr.completed":
                        let text = event.text ?? ""; stop()
                        if text.isEmpty { error = "没有听清，请再说一次。" } else { onTranscript?(String(text.prefix(500))) }
                        return
                    case "asr.error": throw AIConnectionError.remote("ASR_FAILED")
                    default: break
                    }
                }
            } catch {
                guard current == generation, !Task.isCancelled else { return }
                stop(); self.error = (error as? AIConnectionError)?.errorDescription ?? "语音识别连接中断，请重试。"
            }
        }
    }
    private func finishRecording() {
        guard isRecording else { return }
        microphone?.stop(); microphone = nil; capture?.finish(); capture = nil
        isRecording = false; isBusy = true; status = "正在确认最后一句"; recordingLimit?.cancel(); recordingLimit = nil
    }
    func stop() {
        generation = UUID(); recording?.cancel(); recording = nil; upload?.cancel(); upload = nil
        recordingLimit?.cancel(); recordingLimit = nil; capture?.finish(); capture = nil
        microphone?.stop(); microphone = nil; socket?.cancel(with:.goingAway,reason:nil); socket = nil
        buffers = 0; beatPCM = Data(); isRecording = false; finish()
    }
    private static func wave(_ pcm: Data) -> Data {
        var output = Data("RIFF".utf8)
        func number<T: FixedWidthInteger>(_ value: T) { var value = value.littleEndian; withUnsafeBytes(of:&value) { output.append(contentsOf:$0) } }
        number(UInt32(pcm.count+36)); output.append(Data("WAVEfmt ".utf8)); number(UInt32(16)); number(UInt16(1)); number(UInt16(1))
        number(UInt32(24000)); number(UInt32(48000)); number(UInt16(2)); number(UInt16(16)); output.append(Data("data".utf8)); number(UInt32(pcm.count)); output.append(pcm); return output
    }
}
