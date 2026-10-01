import SwiftUI

/// A continuous native thumb with discrete saved values. During a drag the
/// thumb follows the finger; only releasing it animates to the nearest detent.
struct AtmosphereLevelSlider:UIViewRepresentable {
    @Binding var level:Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeUIView(context:Context)->DetentSlider {
        let slider=DetentSlider()
        slider.minimumValue=0;slider.maximumValue=4;slider.isContinuous=true
        slider.accessibilityIdentifier="atmosphereLevelSlider"
        slider.accessibilityLabel="氛围效果"
        slider.setValue(Float(level),animated:false)
        slider.addTarget(context.coordinator,action:#selector(Coordinator.changed(_:)),for:.valueChanged)
        slider.addTarget(context.coordinator,action:#selector(Coordinator.began),for:.touchDown)
        slider.addTarget(context.coordinator,action:#selector(Coordinator.ended(_:)),for:[.touchUpInside,.touchUpOutside,.touchCancel])
        return slider
    }
    func updateUIView(_ slider:DetentSlider,context:Context) {
        context.coordinator.parent=self
        slider.animateChanges = !reduceMotion
        slider.minimumTrackTintColor=UIColor(Theme.accent)
        slider.maximumTrackTintColor=UIColor(Theme.ink.opacity(0.16))
        slider.thumbTintColor=UIColor(Theme.ink)
        slider.accessibilityValue=AtmosphereBlend.levelNames[level]
        if !slider.isTracking && !context.coordinator.tracking,abs(slider.value-Float(level))>0.001 {
            slider.setValue(Float(level),animated:!reduceMotion)
        }
    }
    final class Coordinator:NSObject {
        var parent:AtmosphereLevelSlider
        var tracking=false
        init(_ parent:AtmosphereLevelSlider) {self.parent=parent}
        @objc func began() {tracking=true}
        @objc func changed(_ slider:DetentSlider) {
            let next=Int(slider.value.rounded())
            slider.accessibilityValue=AtmosphereBlend.levelNames[next]
            if parent.level != next {parent.level=next}
        }
        @objc func ended(_ slider:DetentSlider) {
            tracking=false;changed(slider)
            slider.setValue(Float(parent.level),animated:slider.animateChanges)
        }
    }
    final class DetentSlider:UISlider {
        var animateChanges=true
        override func accessibilityIncrement() {adjust(1)}
        override func accessibilityDecrement() {adjust(-1)}
        private func adjust(_ delta:Float) {
            setValue(min(maximumValue,max(minimumValue,value.rounded()+delta)),animated:animateChanges)
            sendActions(for:.valueChanged)
        }
    }
}
