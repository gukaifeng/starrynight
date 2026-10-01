import SwiftUI
import UIKit

/// The render server breathes only the scrim, without a per-frame SwiftUI
/// update or scaling the cover while Unity prepares its first frame.
struct LoadingBreathingScrim:UIViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    func makeUIView(context:Context)->ScrimView {ScrimView()}
    func updateUIView(_ view:ScrimView,context:Context) {
        view.breathing = !reduceMotion && scenePhase == .active
        view.updateAnimation()
    }
    final class ScrimView:UIView {
        override class var layerClass:AnyClass {CAGradientLayer.self}
        var breathing=false
        private var gradient:CAGradientLayer {layer as! CAGradientLayer}
        override init(frame:CGRect) {
            super.init(frame:frame)
            isUserInteractionEnabled=false;isAccessibilityElement=false;backgroundColor = .clear
            gradient.colors=[0.58,0.16,0.22,0.85].map {UIColor.black.withAlphaComponent($0).cgColor}
            gradient.locations=[0,0.30,0.55,1]
            gradient.startPoint=CGPoint(x:0.5,y:0);gradient.endPoint=CGPoint(x:0.5,y:1)
            gradient.opacity=0.93
        }
        required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
        override func didMoveToWindow() {super.didMoveToWindow();updateAnimation()}
        func updateAnimation() {
            guard breathing,window != nil else {gradient.removeAnimation(forKey:"coverBreath");return}
            guard gradient.animation(forKey:"coverBreath")==nil else {return}
            let animation=CAKeyframeAnimation(keyPath:"opacity")
            animation.values=[0.93,0.84,0.93,1.0,0.93]
            animation.keyTimes=[0,0.25,0.5,0.75,1]
            animation.timingFunctions=(0..<4).map {_ in CAMediaTimingFunction(name:.easeInEaseOut)}
            animation.duration=7.2;animation.repeatCount = .infinity
            gradient.add(animation,forKey:"coverBreath")
        }
    }
}
