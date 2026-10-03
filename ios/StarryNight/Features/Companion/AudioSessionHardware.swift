import AVFoundation

/// Serializes audio-route mutations without blocking SwiftUI's animation thread.
/// Music, capture and speech still share a single owner: CompanionSoundscape.
enum AudioSessionHardware {
    private static let queue = DispatchQueue(label:"app.starry.audio-session",qos:.userInitiated)
    // Ownership is transferred exactly once to MainActor after preparation.
    final class PreparedMusic: @unchecked Sendable {
        let player:AVAudioPlayer
        init(_ player:AVAudioPlayer) {self.player=player}
    }
    static func prepareMusic(_ url:URL) async throws -> PreparedMusic {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let player=try AVAudioPlayer(contentsOf:url)
                    player.numberOfLoops = -1;player.volume=0;player.isMeteringEnabled=true
                    guard player.prepareToPlay() else {throw CocoaError(.fileReadCorruptFile)}
                    continuation.resume(returning:PreparedMusic(player))
                } catch {continuation.resume(throwing:error)}
            }
        }
    }
    static func configure(recording:Bool,speaking:Bool,active:Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
            queue.async {
                do {
                    let audio=AVAudioSession.sharedInstance()
                    if active {
                        let category:AVAudioSession.Category=recording ? .playAndRecord : .playback
                        let mode:AVAudioSession.Mode=speaking ? .spokenAudio : .default
                        let options:AVAudioSession.CategoryOptions=recording ? [.defaultToSpeaker,.allowBluetoothHFP] : speaking ? [.duckOthers] : []
                        if audio.category != category || audio.mode != mode || audio.categoryOptions != options {
                            try audio.setCategory(category,mode:mode,options:options)
                        }
                        try audio.setActive(true)
                    } else { try audio.setActive(false,options:.notifyOthersOnDeactivation) }
                    continuation.resume()
                } catch {continuation.resume(throwing:error)}
            }
        }
    }
}
