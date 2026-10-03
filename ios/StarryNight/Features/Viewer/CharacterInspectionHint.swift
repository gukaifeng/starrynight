import UIKit
import SwiftUI

/// A transient, touch-through orbital glyph. The two small glints explain the
/// horizontal and vertical axes without adding a button or covering the actor.
final class CharacterInspectionHint:UIView {
    private let horizontal = CAShapeLayer()
    private let vertical = CAShapeLayer()
    private let arrowheads = CAShapeLayer()
    private let centerPoint = CAShapeLayer()
    private let horizontalGlint = CAShapeLayer()
    private let verticalGlint = CAShapeLayer()
    private var drawnSize = CGSize.zero
    private(set) var active = false
    var animated:Bool { active && !UIAccessibility.isReduceMotionEnabled && window != nil }

    override init(frame:CGRect) {
        super.init(frame:frame)
        backgroundColor = .clear; isOpaque = false; isUserInteractionEnabled = false
        isAccessibilityElement = false; accessibilityElementsHidden = true
        alpha = 0
        for stroke in [horizontal,vertical,arrowheads] {
            stroke.fillColor = UIColor.clear.cgColor
            stroke.lineWidth = 1.15; stroke.lineCap = .round; stroke.lineJoin = .round
            layer.addSublayer(stroke)
        }
        for dot in [centerPoint,horizontalGlint,verticalGlint] { layer.addSublayer(dot) }
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.45; layer.shadowRadius = 3; layer.shadowOffset = .zero
        refreshTheme()
        NotificationCenter.default.addObserver(self,selector:#selector(accessibilityChanged),
            name:UIAccessibility.reduceMotionStatusDidChangeNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(accessibilityChanged),
            name:UIAccessibility.reduceTransparencyStatusDidChangeNotification,object:nil)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refreshTheme() {
        let ink = UIColor(Theme.accent)
        let solid = UIAccessibility.isReduceTransparencyEnabled
        horizontal.strokeColor = ink.withAlphaComponent(solid ? 0.95 : 0.58).cgColor
        vertical.strokeColor = ink.withAlphaComponent(solid ? 0.85 : 0.40).cgColor
        arrowheads.strokeColor = ink.withAlphaComponent(solid ? 1 : 0.66).cgColor
        centerPoint.fillColor = ink.withAlphaComponent(solid ? 0.90 : 0.46).cgColor
        horizontalGlint.fillColor = ink.withAlphaComponent(solid ? 1 : 0.80).cgColor
        verticalGlint.fillColor = ink.withAlphaComponent(solid ? 1 : 0.72).cgColor
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, bounds.size != drawnSize else { return }
        drawnSize = bounds.size
        let scale = min(bounds.width,bounds.height)/44
        let center = CGPoint(x:bounds.midX,y:bounds.midY)
        let xOrbit = UIBezierPath(ovalIn:CGRect(x:center.x-17*scale,y:center.y-6.5*scale,width:34*scale,height:13*scale))
        let yOrbit = UIBezierPath(ovalIn:CGRect(x:center.x-6.5*scale,y:center.y-17*scale,width:13*scale,height:34*scale))
        CATransaction.begin(); CATransaction.setDisableActions(true)
        horizontal.path = xOrbit.cgPath; vertical.path = yOrbit.cgPath
        let arrows = UIBezierPath()
        func arrow(_ x:CGFloat,_ y:CGFloat,_ dx:CGFloat,_ dy:CGFloat) {
            let p = CGPoint(x:center.x+x*scale,y:center.y+y*scale)
            arrows.move(to:CGPoint(x:p.x-dx*3*scale-dy*2.2*scale,y:p.y-dy*3*scale+dx*2.2*scale))
            arrows.addLine(to:p)
            arrows.addLine(to:CGPoint(x:p.x-dx*3*scale+dy*2.2*scale,y:p.y-dy*3*scale-dx*2.2*scale))
        }
        arrow(-17,0,-1,0); arrow(17,0,1,0)
        arrow(0,-17,0,-1); arrow(0,17,0,1)
        arrowheads.path = arrows.cgPath
        centerPoint.path = UIBezierPath(ovalIn:CGRect(x:center.x-1.5*scale,y:center.y-1.5*scale,width:3*scale,height:3*scale)).cgPath
        for dot in [horizontalGlint,verticalGlint] {
            dot.path = UIBezierPath(ovalIn:CGRect(x:-1.4*scale,y:-1.4*scale,width:2.8*scale,height:2.8*scale)).cgPath
        }
        horizontalGlint.position = CGPoint(x:center.x+17*scale,y:center.y)
        verticalGlint.position = CGPoint(x:center.x,y:center.y-17*scale)
        CATransaction.commit()
        updateMotion()
    }
    func setActive(_ value:Bool) {
        guard active != value else { return }
        active = value
        updateMotion()
        UIView.animate(withDuration:UIAccessibility.isReduceMotionEnabled ? 0.12 : (value ? 0.24 : 0.26),
            delay:0,options:[.beginFromCurrentState,.allowUserInteraction,.curveEaseInOut]) {
            self.alpha = value ? 1 : 0
        }
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { setActive(false) }
        updateMotion()
    }
    @objc private func accessibilityChanged() { refreshTheme(); updateMotion() }
    private func updateMotion() {
        horizontalGlint.removeAnimation(forKey:"orbit")
        verticalGlint.removeAnimation(forKey:"orbit")
        guard animated else { return }
        for (dot,orbit,duration) in [(horizontalGlint,horizontal,3.8),(verticalGlint,vertical,4.6)] {
            guard let path = orbit.path else { continue }
            let animation = CAKeyframeAnimation(keyPath:"position")
            animation.path = path; animation.duration = duration
            animation.calculationMode = .paced; animation.repeatCount = .infinity
            dot.add(animation,forKey:"orbit")
        }
    }
}
