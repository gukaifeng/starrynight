import UIKit
import CoreHaptics

/// A short rising tactile envelope for charging, followed by a distinct unlock impact.
/// Haptics-only engine never changes the shared speech/music audio session.
@MainActor final class CharacterHoldHaptics {
    private var engine:CHHapticEngine?
    private var player:(any CHHapticPatternPlayer)?
    private let impact = UIImpactFeedbackGenerator(style:.heavy)
    private var fallback:Timer?
    private var fallbackStep = 0
    func prepare() { impact.prepare() }
    func begin() {
        stop()
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            if engine == nil { engine = try CHHapticEngine(); engine?.playsHapticsOnly = true; engine?.isAutoShutdownEnabled = true }
            guard let engine else { return }; try engine.start()
            let event = CHHapticEvent(eventType:.hapticContinuous,parameters:[
                .init(parameterID:.hapticIntensity,value:1),.init(parameterID:.hapticSharpness,value:0.25)],relativeTime:0,duration:1)
            let curve = CHHapticParameterCurve(parameterID:.hapticIntensityControl,controlPoints:[
                .init(relativeTime:0,value:0.06),.init(relativeTime:0.3,value:0.13),
                .init(relativeTime:0.65,value:0.32),.init(relativeTime:1,value:0.62)],relativeTime:0)
            let pattern = try CHHapticPattern(events:[event],parameterCurves:[curve])
            player = try engine.makePlayer(with:pattern); try player?.start(atTime:CHHapticTimeImmediate)
        } catch {
            // Supported devices can temporarily lose their haptic engine during an
            // audio interruption. Use a few bounded UIKit pulses for this hold only.
            fallbackStep = 0
            fallback = Timer.scheduledTimer(withTimeInterval:0.2,repeats:true) { [weak self] timer in
                Task { @MainActor in
                    guard let self else { return }
                    self.fallbackStep += 1
                    self.impact.impactOccurred(intensity:CGFloat(self.fallbackStep)*0.1)
                    if self.fallbackStep >= 4 { self.fallback?.invalidate(); self.fallback = nil }
                }
            }
        }
    }
    func unlock() { stop(); impact.impactOccurred(intensity:0.95) }
    func stop() { try? player?.stop(atTime:CHHapticTimeImmediate); player = nil; fallback?.invalidate(); fallback = nil }
}
