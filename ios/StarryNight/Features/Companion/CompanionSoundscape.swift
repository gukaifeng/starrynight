import AVFoundation
import Observation
import UIKit

/// The only owner of the app's audio session. Speech releases focus, not the session.
@MainActor @Observable
final class CompanionSoundscape: NSObject {
    enum VoiceFocus { case none, speech, recording }
    var masterMuted: Bool { speechVolume == 0 && volume == 0 }
    private(set) var speechVolume: Double = 1
    var enabled: Bool { volume > 0 }
    private(set) var trackID = ""
    private(set) var availableTracks: [SoundscapeTrack] = []
    private(set) var collectionScope = ""
    @ObservationIgnored var onPreferences: ((CharacterAudioPreferences) -> Void)?
    private(set) var volume: Double = 0.28
    private(set) var playing = false
    private(set) var interrupted = false
    private(set) var focus = VoiceFocus.none
    private(set) var active = false
    private(set) var measuredSamples = 0
    private(set) var duckedSamples = 0
    private(set) var minimumDuckedVolume: Float = 1
    private(set) var lifecyclePauses = 0
    private(set) var playbackTime: Double = 0
    private(set) var outputVolume: Float = 0
    var error: String?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var retired: AVAudioPlayer?
    @ObservationIgnored private var retirement: Task<Void,Never>?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var sessionTask:Task<Void,Never>?
    @ObservationIgnored private var sessionRevision=0
    @ObservationIgnored private var musicPreparation:Task<Void,Never>?
    @ObservationIgnored private var musicRevision=UUID()
    var track: SoundscapeTrack? { availableTracks.first { $0.id == trackID } }
    func configure(collection:CharacterCollection,profile:CharacterProfile,onChange:@escaping (CharacterAudioPreferences)->Void) {
        // Stop, don't crossfade: a previous role must never remain audible in this one.
        retirement?.cancel(); retired?.stop(); retired = nil
        musicPreparation?.cancel();musicPreparation=nil;musicRevision=UUID()
        player?.stop(); player = nil; stopMeter(); playing = false; focus = .none
        let clean = collection.normalize(profile).audio!
        availableTracks = collection.music; collectionScope = collection.optionScope; trackID = clean.trackID
        volume = clean.volume
        speechVolume = clean.speechVolume ?? 1; interrupted = false; error = nil
        onPreferences = onChange
        reconcile()
    }
    var status: String {
        if masterMuted { return "声音已关闭" }
        if error != nil { return "音乐暂时无法播放" }
        if interrupted { return "音乐已暂停，轻点继续" }
        if !enabled { return "给此刻一点音乐" }
        if focus == .recording { return "录音时暂停音乐" }
        if !active { return "离开空间，音乐已暂停" }
        return focus == .speech ? "轻声伴奏，让角色先说" : "正在播放 · " + (track?.title ?? "")
    }
    override init() {
        super.init()
        NotificationCenter.default.addObserver(self,selector:#selector(audioInterrupted),name:AVAudioSession.interruptionNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(routeChanged),name:AVAudioSession.routeChangeNotification,object:nil)
    }
    func setActive(_ value: Bool) {
        let wasPlaying = player?.isPlaying == true
        active = value
        if !value { player?.pause(); retired?.stop(); playing = false; stopMeter() }
        if !value && wasPlaying && player?.isPlaying == false { lifecyclePauses += 1 }
        reconcile()
    }
    func setEnabled(_ value:Bool) { setVolume(value ? max(volume,0.28) : 0) }
    func setSpeechVolume(_ value:Double) { speechVolume = value.isFinite ? min(1,max(0,value)) : 1; persist() }
    func toggle() {
        if interrupted { interrupted = false; volume = max(volume,0.28) } else { volume = enabled ? 0 : 0.28 }
        error = nil; persist(); reconcile()
    }
    func select(_ id: String) {
        guard availableTracks.contains(where: { $0.id == id }) else { return }
        if trackID != id { retirePlayer(); trackID = id }
        interrupted = false; error = nil; persist(); reconcile()
    }
    func setVolume(_ value: Double) {
        volume = value.isFinite ? min(1,max(0,value)) : 0.28
        interrupted = false; error = nil; persist(); reconcile()
    }
    func beginVoice(_ value: VoiceFocus) async throws {
        guard active, !interrupted else { throw NSError(domain:"XuyuAudio",code:1) }
        focus = value
        if value == .recording { player?.pause(); playing = false; stopMeter() }
        sessionTask?.cancel();sessionRevision += 1
        let revision=sessionRevision
        try await configureSession()
        try Task.checkCancellation()
        guard revision==sessionRevision,active,!interrupted else {throw CancellationError()}
        reconcileMusic()
    }
    func endVoice() { focus = .none; reconcile() }
    private func persist() { onPreferences?(CharacterAudioPreferences(enabled:true,trackID:trackID,volume:volume,masterMuted:false,speechVolume:speechVolume,volumeControlsVersion:CharacterAudioPreferences.currentVolumeControlsVersion)) }
    private func configureSession() async throws {
        try await AudioSessionHardware.configure(recording:focus == .recording,speaking:focus == .speech,
            active:active && !interrupted && (focus != .none || enabled))
    }
    private func reconcile() {
        if !active || interrupted {
            player?.pause(); playing = false; stopMeter()
        }
        sessionTask?.cancel();sessionRevision += 1
        let revision=sessionRevision
        sessionTask=Task { @MainActor [weak self] in
            guard let self else {return}
            do {
                try await configureSession();try Task.checkCancellation()
                guard revision==sessionRevision else {return};reconcileMusic()
            } catch is CancellationError {} catch {
                guard revision==sessionRevision else {return}
                self.error = "音乐没有成功播放，请稍后再试。"; player?.pause(); playing = false; stopMeter()
            }
        }
    }
    private func reconcileMusic() {
        guard active, enabled, !interrupted, focus != .recording else { player?.pause(); playing = false; stopMeter(); return }
        do {
            if player == nil {
                guard let track, track.id.hasPrefix(collectionScope+"/"), let url = track.resourceURL else { throw CocoaError(.fileNoSuchFile) }
                guard musicPreparation==nil else {return}
                let revision=musicRevision
                musicPreparation=Task { @MainActor [weak self] in
                    do {
                        let prepared=try await AudioSessionHardware.prepareMusic(url)
                        try Task.checkCancellation()
                        guard let self,revision==musicRevision else {return}
                        player=prepared.player;musicPreparation=nil;reconcileMusic()
                    } catch {
                        guard let self,revision==musicRevision,!Task.isCancelled else {return}
                        musicPreparation=nil;self.error="音乐资源暂时无法读取，请重新打开空间后重试。"
                    }
                }
                return
            }
            guard let player else { return }
            if !player.isPlaying { guard player.play() else { throw CocoaError(.fileReadCorruptFile) } }
            outputVolume = Float(volume) * (focus == .speech ? 0.18 : 1)
            player.setVolume(outputVolume,fadeDuration:0.45); playing = player.isPlaying
            startMeter()
        } catch { self.error = "音乐资源暂时无法读取，请重新打开空间后重试。"; playing = false; stopMeter() }
    }
    private func retirePlayer() {
        musicPreparation?.cancel();musicPreparation=nil;musicRevision=UUID()
        retirement?.cancel(); retired?.stop()
        retired = player; player = nil; retired?.setVolume(0,fadeDuration:0.3)
        retirement = Task { @MainActor [weak self] in
            do { try await Task.sleep(for:.milliseconds(320)) } catch { return }
            self?.retired?.stop(); self?.retired = nil
        }
    }
    private func startMeter() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval:0.25,repeats:true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.playing = player.isPlaying; self.playbackTime = player.currentTime
                player.updateMeters()
                if player.isPlaying && self.outputVolume > 0.001 && player.averagePower(forChannel:0) > -65 {
                    self.measuredSamples += 1
                    if self.focus == .speech {
                        self.duckedSamples += 1
                        self.minimumDuckedVolume = min(self.minimumDuckedVolume,player.volume)
                    }
                }
            }
        }
    }
    private func stopMeter() { timer?.invalidate(); timer = nil; outputVolume = 0 }
    @objc nonisolated private func audioInterrupted(_ note: Notification) {
        let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
        if began { Task { @MainActor [weak self] in self?.interrupted = true; self?.reconcile() } }
    }
    @objc nonisolated private func routeChanged(_ note: Notification) {
        let removed = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
        if removed { Task { @MainActor [weak self] in self?.interrupted = true; self?.reconcile() } }
    }
    var accessibilityEvidence: String {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let data = try? JSONSerialization.data(withJSONObject:["masterMuted":masterMuted,"speechVolume":speechVolume,"sessionCategory":AVAudioSession.sharedInstance().category.rawValue,"enabled":enabled,"playing":player?.isPlaying == true,"active":active,"track":trackID,
                "collectionScope":collectionScope,"asset":track?.asset ?? "","sourceModelID":track?.sourceModelID ?? "","assetSHA256":track?.sha256 ?? "",
                "availableTrackIDs":availableTracks.map(\.id),"duration":player?.duration ?? 0,
                "volume":volume,"outputVolume":outputVolume,"samples":measuredSamples,"duckedSamples":duckedSamples,"minimumDuckedVolume":minimumDuckedVolume,"lifecyclePauses":lifecyclePauses,"time":playbackTime,"interrupted":interrupted])
            if let data { return String(decoding:data,as:UTF8.self) }
        }
#endif
        return status
    }
}
