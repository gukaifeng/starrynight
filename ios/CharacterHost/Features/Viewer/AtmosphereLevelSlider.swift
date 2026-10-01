import SwiftUI

/// Continuous preview uses ephemeral session state; commit once on release.
/// Native tracking owns the thumb so SwiftUI redraws cannot pull it backwards.
struct AtmosphereLevelSlider:UIViewRepresentable {
    @Binding var intensity:Double
    var onCommit:()->Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeUIView(context:Context)->UISlider {
        let slider=UISlider()
        slider.minimumValue=0;slider.maximumValue=1;slider.isContinuous=true
        slider.accessibilityIdentifier="atmosphereLevelSlider"
        slider.accessibilityLabel=L10n.text("氛围效果")
        slider.accessibilityHint="连续调节，滑到最左侧关闭"
        slider.setValue(Float(intensity),animated:false)
        slider.addTarget(context.coordinator,action:#selector(Coordinator.changed(_:)),for:.valueChanged)
        slider.addTarget(context.coordinator,action:#selector(Coordinator.ended(_:)),for:[.touchUpInside,.touchUpOutside,.touchCancel])
        return slider
    }
    func updateUIView(_ slider:UISlider,context:Context) {
        context.coordinator.parent=self
        slider.minimumTrackTintColor=UIColor(Theme.accent)
        slider.maximumTrackTintColor=UIColor(Theme.ink.opacity(0.16))
        slider.thumbTintColor=UIColor(Theme.ink)
        slider.accessibilityValue=intensity<=0 ? L10n.text("关闭") : "\(Int((intensity*100).rounded()))%"
        if !slider.isTracking,abs(slider.value-Float(intensity))>0.0001 {
            slider.setValue(Float(intensity),animated:!reduceMotion)
        }
    }
    final class Coordinator:NSObject {
        var parent:AtmosphereLevelSlider
        init(_ parent:AtmosphereLevelSlider) {self.parent=parent}
        @objc func changed(_ slider:UISlider) {
            parent.intensity=Double(slider.value)
            // VoiceOver adjustments have no touch-up event.
            if !slider.isTracking {parent.onCommit()}
        }
        @objc func ended(_ slider:UISlider) {
            parent.intensity=Double(slider.value);parent.onCommit()
        }
    }
}
