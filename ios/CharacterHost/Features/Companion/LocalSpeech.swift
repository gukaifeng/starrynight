import Foundation
import AVFoundation
import Observation
import UIKit

@MainActor @Observable
final class LocalSpeech: NSObject, AVAudioPlayerDelegate {
    var ready = false
    var status = "正在准备声音"
    var error: String?
    var isRecording = false
    var isSpeaking = false
    var isBusy = false
    private(set) var activeMessageID: UUID?
    private(set) var playbackElapsed: TimeInterval = 0
    private(set) var playbackLevel: Float = 0
    private(set) var durations: [UUID:TimeInterval] = [:]
    private(set) var durationSpeeds: [UUID:Double] = [:]
    let cacheScope: String
    private(set) var audibleSegments = 0
    @ObservationIgnored var onTranscript: ((String) -> Void)?
    @ObservationIgnored var onDuration: ((UUID,Double,TimeInterval) -> Void)?
    @ObservationIgnored var onState: ((String) -> Void)?
    @ObservationIgnored var onLevel: ((Float) -> Void)?
    @ObservationIgnored var onFrame: ((Double,Float) -> Void)?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var segmentMeasured = false
    @ObservationIgnored private var task: Task<Void,Never>?
    @ObservationIgnored private var requestTask: Task<Data,Error>?
    @ObservationIgnored private var generation = UUID()
    private static let modelDirectory = Bundle.main.resourceURL!.appendingPathComponent("VoiceModels")
    private static let engine = OfflineSpeechEngine(modelDirectory:modelDirectory.path)
    private let recordingURL = FileManager.default.temporaryDirectory.appendingPathComponent("xiaoban-input.wav")
    let soundscape: CompanionSoundscape
    init(soundscape: CompanionSoundscape, cacheScope: String) {
        self.soundscape = soundscape
        self.cacheScope = cacheScope
        super.init()
        NotificationCenter.default.addObserver(self,selector:#selector(releaseInferenceModels),name:UIApplication.didReceiveMemoryWarningNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(releaseInferenceModels),name:UIApplication.didEnterBackgroundNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(audioInterrupted),name:AVAudioSession.interruptionNotification,object:nil)
    }
    @objc nonisolated private func releaseInferenceModels(_ notification: Notification) {
        Task { @MainActor [weak self] in self?.stop(); Self.engine.releaseModels() }
    }
    @objc nonisolated private func audioInterrupted(_ notification: Notification) {
        Task { @MainActor [weak self] in self?.stop() }
    }
    private func diagnostic(_ stage: String) {
#if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing"),
              let directory = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first else { return }
        let file = directory.appendingPathComponent("speech-events.jsonl")
        let json: [String:Any] = ["stage":stage,"time":Date().timeIntervalSince1970]
        guard let data = try? JSONSerialization.data(withJSONObject:json), var line = String(data:data,encoding:.utf8) else { return }
        line += "\n"
        if !FileManager.default.fileExists(atPath:file.path) { FileManager.default.createFile(atPath:file.path,contents:nil) }
        if let handle = try? FileHandle(forWritingTo:file) { defer { try? handle.close() }; _ = try? handle.seekToEnd(); try? handle.write(contentsOf:Data(line.utf8)) }
#endif
    }
    func check() async {
        // The build verifies hashes. At launch, validate packaged file presence/size
        // without reading 400 MB or loading inference sessions on the UI thread.
        do {
            let data = try Data(contentsOf:Self.modelDirectory.appendingPathComponent("manifest.json"))
            let manifest = try JSONDecoder().decode(SpeechAssetManifest.self,from:data)
            guard !manifest.files.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            for file in manifest.files {
                let attributes = try FileManager.default.attributesOfItem(atPath:Self.modelDirectory.appendingPathComponent(file.path).path)
                guard (attributes[.size] as? NSNumber)?.intValue == file.bytes else { throw CocoaError(.fileReadCorruptFile) }
            }
            ready = true; error = nil
            if !isBusy && !isSpeaking && !isRecording { status = "离线语音已就绪 · 可以轻声说" }
            diagnostic("offline-models-ready")
        } catch {
            ready = false; status = "语音资源不完整，先打字聊聊"
            self.error = "App 内的语音资源不完整，请重新安装完整版本。"
        }
    }
    private struct SpeechAssetManifest: Decodable {
        struct File: Decodable { let path: String; let bytes: Int }
        let files: [File]
    }
    private func synthesize(_ text: String, speed: Double) async throws -> Data {
        try Task.checkCancellation()
        let key = SpeechClipCache.shared.key(scope:cacheScope,text:text,speed:speed)
        if let cached = SpeechClipCache.shared.data(key) { diagnostic("tts-cache-hit"); return cached }
        let cacheGeneration = SpeechClipCache.shared.generation
        diagnostic("offline-tts-start")
        let started = Date()
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            Self.engine.synthesize(text,speed:speed) { data,error in
                if let error { continuation.resume(throwing:error) }
                else if let data { continuation.resume(returning:data) }
                else { continuation.resume(throwing:CocoaError(.coderInvalidValue)) }
            }
        }
        diagnostic("offline-tts-finished-ms-\(Int(Date().timeIntervalSince(started)*1000))-bytes-\(data.count)")
        try Task.checkCancellation()
        SpeechClipCache.shared.insert(data,key:key,generation:cacheGeneration)
        return data
    }
    func refreshVolume() { player?.setVolume(Float(soundscape.speechVolume),fadeDuration:0.12) }
    func speak(_ text: String, speed: Double, messageID: UUID? = nil) {
        stop(); error = nil
        activeMessageID = messageID; playbackElapsed = 0
        let token = generation
        isBusy = true; status = "正在合成声音"; onState?("thinking")
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if !ready { await check() }
                try Task.checkCancellation()
                guard ready, token == generation else { isBusy = false; return }
                // Speak the first short sentence while preparing the next. Full replies
                // need not wait for one long synthesis request, and cancellation owns both tasks.
                var chunks: [String] = []; var fragment = ""
                // Replies may include several saved memories; every chunk must be spoken.
                for character in text {
                    fragment.append(character)
                    if "。！？!?\n".contains(character) || fragment.count >= 55 { chunks.append(fragment); fragment = "" }
                }
                if !fragment.isEmpty { chunks.append(fragment) }
                func fetch(_ part: String) async throws -> Data {
                    try await self.synthesize(part,speed:speed)
                }
                guard let first = chunks.first else { stop(); return }
                var pending: Task<Data,Error>? = Task { try await fetch(first) }
                requestTask = pending
                defer { pending?.cancel() }
                var completedDuration: TimeInterval = 0
                for index in chunks.indices {
                    let data = try await pending!.value
                    try Task.checkCancellation(); guard token == generation else { return }
                    pending = index+1 < chunks.count ? Task { try await fetch(chunks[index+1]) } : nil
                    requestTask = pending
                    try soundscape.beginVoice(.speech)
                    let audio = try AVAudioPlayer(data:data); audio.isMeteringEnabled = true; audio.volume = Float(soundscape.speechVolume)
                    let segmentOffset = completedDuration
                    player = audio; guard audio.play() else { throw URLError(.cannotDecodeContentData) }
                    diagnostic("audio-playing")
                    isBusy = false; isSpeaking = true; status = "正在说话 · 轻点可打断"; onState?("speaking")
                    timer?.invalidate()
                    segmentMeasured = false
                    timer = Timer.scheduledTimer(withTimeInterval:0.05,repeats:true) { [weak self] _ in
                        Task { @MainActor in
                            guard let self, let player = self.player else { return }
                            player.updateMeters()
                            let level = min(1,max(0,pow(10,player.averagePower(forChannel:0)/20)*4))
                            self.playbackElapsed = segmentOffset + player.currentTime
                            self.playbackLevel = level
                            if !self.segmentMeasured && level > 0.02 {
                                self.segmentMeasured = true; self.audibleSegments += 1
                                self.diagnostic("audio-meter-nonzero")
                            }
                            self.onLevel?(level)
                            self.onFrame?(player.currentTime,level)
                        }
                    }
                    while audio.isPlaying { try await Task.sleep(for:.milliseconds(60)); try Task.checkCancellation() }
                    timer?.invalidate(); timer = nil; onLevel?(0)
                    completedDuration += audio.duration
                    if index == chunks.count-1, let messageID {
                        durations[messageID] = completedDuration; durationSpeeds[messageID] = speed
                        onDuration?(messageID,speed,completedDuration)
                    }
                    if index+1 < chunks.count { isSpeaking = false; isBusy = true; status = "正在准备下一句"; onState?("thinking") }
                }
                guard token == generation else { return }; stop()
            } catch {
                guard token == generation, !Task.isCancelled else { return }
                diagnostic("tts-error-\((error as NSError).domain)-\((error as NSError).code)")
                stop(); self.error = "手机内的朗读暂时不可用，请稍后重试。"
            }
        }
    }
    func toggleRecording() {
        if isRecording { finishRecording(); return }
        stop(); error = nil; let token = generation
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            let allowed = await AVAudioApplication.requestRecordPermission()
            guard token == generation, !Task.isCancelled else { return }
            guard allowed else { error = "麦克风权限未开启，可在系统设置中允许星夜使用麦克风。"; return }
            do {
                try soundscape.beginVoice(.recording)
                let settings: [String:Any] = [AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:16000,AVNumberOfChannelsKey:1,AVLinearPCMBitDepthKey:16,AVLinearPCMIsFloatKey:false,AVLinearPCMIsBigEndianKey:false]
                recorder = try AVAudioRecorder(url:recordingURL,settings:settings)
                guard recorder!.record() else { throw URLError(.cannotCreateFile) }
                isRecording = true; status = "正在聆听 · 再点结束，最长 30 秒"; onState?("listening")
                timer = Timer.scheduledTimer(withTimeInterval:30,repeats:false) { [weak self] _ in Task { @MainActor in self?.finishRecording() } }
            } catch { stop(); self.error = "无法开始录音，请检查麦克风权限或是否被其他应用占用。" }
        }
    }
    private func finishRecording() {
        guard isRecording else { return }
        recorder?.stop(); recorder = nil; isRecording = false; timer?.invalidate(); timer = nil
        do { let data = try Data(contentsOf:recordingURL); try? FileManager.default.removeItem(at:recordingURL); transcribe(data) }
        catch { stop(); self.error = "没有读到录音，请重试。" }
    }
    func transcribe(_ data: Data) {
        stop(); error = nil; isBusy = true; status = "正在识别，结果可编辑"; onState?("thinking"); let token = generation
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                diagnostic("offline-asr-start")
                let started = Date()
                let text: String = try await withCheckedThrowingContinuation { continuation in
                    Self.engine.recognizeWave(data) { text,error in
                        if let error { continuation.resume(throwing:error) }
                        else { continuation.resume(returning:text ?? "") }
                    }
                }
                diagnostic("offline-asr-finished-ms-\(Int(Date().timeIntervalSince(started)*1000))")
                try Task.checkCancellation(); guard token == generation else { return }
                stop()
                if text.isEmpty { error = "没有识别到清晰的人声，请靠近麦克风后重试。" }
                else { onTranscript?(text); status = "识别完成，确认文字后发送" }
            } catch {
                guard token == generation, !Task.isCancelled else { return }
                stop(); self.error = "手机内的语音识别失败，请重新录音后重试。"
            }
        }
    }
    func stop() {
        diagnostic("stop")
        Self.engine.cancel()
        generation = UUID(); task?.cancel(); task = nil; requestTask?.cancel(); requestTask = nil
        timer?.invalidate(); timer = nil
        player?.stop(); player = nil; recorder?.stop(); recorder = nil
        try? FileManager.default.removeItem(at:recordingURL)
        isSpeaking = false; isRecording = false; isBusy = false
        activeMessageID = nil; playbackLevel = 0; playbackElapsed = 0
        onLevel?(0); onState?("idle")
        status = ready ? "离线语音已就绪 · 可以轻声说" : "语音暂未就绪，先打字聊聊"
        soundscape.endVoice()
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finished = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.player, ObjectIdentifier(current) == finished else { return }
            self.stop()
        }
    }
}
