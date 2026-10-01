import SwiftUI

/// Five visible stops. Touches select a stop immediately; the native thumb
/// eases between stops, never following a fractional value then jumping back.
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
        return slider
    }
    func updateUIView(_ slider:DetentSlider,context:Context) {
        context.coordinator.parent=self
        slider.animateChanges = !reduceMotion
        slider.minimumTrackTintColor=UIColor(Theme.accent)
        slider.maximumTrackTintColor=UIColor(Theme.ink.opacity(0.16))
        slider.thumbTintColor=UIColor(Theme.ink)
        slider.tickColor=UIColor(Theme.ink.opacity(0.48))
        slider.accessibilityValue=AtmosphereBlend.levelNames[level]
        if abs(slider.value-Float(level))>0.001 {
            slider.setValue(Float(level),animated:!reduceMotion)
        }
    }
    final class Coordinator:NSObject {
        var parent:AtmosphereLevelSlider
        init(_ parent:AtmosphereLevelSlider) {self.parent=parent}
        @objc func changed(_ slider:DetentSlider) {
            let next=Int(slider.value.rounded())
            slider.accessibilityValue=AtmosphereBlend.levelNames[next]
            if parent.level != next {parent.level=next}
        }
    }
    final class DetentSlider:UISlider {
        var animateChanges=true
        var tickColor=UIColor.white {didSet {ticks.fillColor=tickColor.cgColor}}
        private let ticks=CAShapeLayer()
        private let feedback=UISelectionFeedbackGenerator()
        override init(frame:CGRect) {
            super.init(frame:frame)
            ticks.fillColor=tickColor.cgColor;layer.addSublayer(ticks)
            accessibilityHint="沿刻度选择，关闭、轻盈、适中、浓郁或绚烂"
        }
        required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
        override func layoutSubviews() {
            super.layoutSubviews()
            let path=UIBezierPath(),ends=thumbCenters
            for index in 0...4 {
                let x=ends.lowerBound+(ends.upperBound-ends.lowerBound)*CGFloat(index)/4
                path.append(UIBezierPath(roundedRect:CGRect(x:x-1,y:bounds.maxY-5,width:2,height:4),cornerRadius:1))
            }
            CATransaction.begin();CATransaction.setDisableActions(true)
            ticks.frame=bounds;ticks.path=path.cgPath
            CATransaction.commit()
        }
        private var thumbCenters:ClosedRange<CGFloat> {
            let track=trackRect(forBounds:bounds)
            let first=thumbRect(forBounds:bounds,trackRect:track,value:minimumValue).midX
            let last=thumbRect(forBounds:bounds,trackRect:track,value:maximumValue).midX
            return min(first,last)...max(first,last)
        }
        override func beginTracking(_ touch:UITouch,with event:UIEvent?)->Bool {
            feedback.prepare();selectStop(at:touch.location(in:self));return true
        }
        override func continueTracking(_ touch:UITouch,with event:UIEvent?)->Bool {
            selectStop(at:touch.location(in:self));return true
        }
        override func endTracking(_ touch:UITouch?,with event:UIEvent?) {
            if let touch {selectStop(at:touch.location(in:self))}
        }
        private func selectStop(at point:CGPoint) {
            let ends=thumbCenters
            let fraction=min(1,max(0,(point.x-ends.lowerBound)/max(1,ends.upperBound-ends.lowerBound)))
            let directed=effectiveUserInterfaceLayoutDirection == .rightToLeft ? 1-fraction : fraction
            let next=(minimumValue+Float(directed)*(maximumValue-minimumValue)).rounded()
            guard next != value else {return}
            setValue(next,animated:animateChanges)
            feedback.selectionChanged();feedback.prepare()
            sendActions(for:.valueChanged)
        }
        override func accessibilityIncrement() {adjust(1)}
        override func accessibilityDecrement() {adjust(-1)}
        private func adjust(_ delta:Float) {
            setValue(min(maximumValue,max(minimumValue,value.rounded()+delta)),animated:animateChanges)
            sendActions(for:.valueChanged)
        }
    }
}
