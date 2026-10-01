import SwiftUI
import UIKit

/// Owns the original touch until it ends, including movement outside the input.
/// SwiftUI can update transcripts/overlays without replacing the gesture owner.
private final class VoiceHoldGesture:UIGestureRecognizer {
    private var finger:UITouch?
    private(set) var windowPoint=CGPoint.zero
    override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent) {
        guard finger == nil,let first=touches.first else {return}
        finger=first;windowPoint=first.location(in:view?.window);state = .began
        for touch in touches where touch !== first {ignore(touch,for:event)}
    }
    override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent) {
        guard let finger,touches.contains(finger) else {return}
        windowPoint=finger.location(in:view?.window);state = .changed
    }
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent) {
        guard let finger,touches.contains(finger) else {return}
        windowPoint=finger.location(in:view?.window);state = .ended
    }
    override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent) {
        guard let finger,touches.contains(finger) else {return};state = .cancelled
    }
    override func reset() {finger=nil;super.reset()}
}

struct VoiceHoldSurface:UIViewRepresentable {
    var title:String
    var active:Bool
    var armed:Bool
    var fontSize:CGFloat=15
    var onBegin:()->Bool
    var onMove:(CGPoint)->Bool
    var onRelease:()->Void
    var onCancel:()->Void
    var onAccessibleEdit:()->Void
    var onAccessibleCancel:()->Void

    func makeUIView(context:Context)->HoldView {HoldView()}
    func updateUIView(_ view:HoldView,context:Context) {
        view.label.text=title;view.label.font=ComposerPromptStyle.uiFont(fontSize)
        view.label.textColor=active ? UIColor(Theme.ink).withAlphaComponent(0.95) : UIColor(ComposerPromptStyle.color)
        view.onBegin=onBegin;view.onMove=onMove;view.onRelease=onRelease;view.onCancel=onCancel
        view.onAccessibleEdit=onAccessibleEdit;view.onAccessibleCancel=onAccessibleCancel;view.active=active
        view.accessibilityValue=armed ? "松开后编辑" : (active ? "正在录音" : "未录音")
    }
    static func dismantleUIView(_ view:HoldView,coordinator:()) {view.cancelTouch()}

    final class HoldView:UIView {
        let label=UILabel()
        var onBegin:(()->Bool)?
        var onMove:((CGPoint)->Bool)?
        var onRelease:(()->Void)?
        var onCancel:(()->Void)?
        var onAccessibleEdit:(()->Void)?
        var onAccessibleCancel:(()->Void)?
        var active=false
        private var tracking=false
        private var armed=false
        private let selection=UISelectionFeedbackGenerator()
        private let impact=UIImpactFeedbackGenerator(style:.soft)
        override init(frame:CGRect) {
            super.init(frame:frame)
            backgroundColor = .clear;isOpaque=false;isMultipleTouchEnabled=true
            label.font = ComposerPromptStyle.uiFont(15);label.textAlignment = .center
            label.adjustsFontSizeToFitWidth=true;label.minimumScaleFactor=0.8
            label.translatesAutoresizingMaskIntoConstraints=false;addSubview(label)
            NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo:leadingAnchor),
                label.trailingAnchor.constraint(equalTo:trailingAnchor),label.centerYAnchor.constraint(equalTo:centerYAnchor)])
            let gesture=VoiceHoldGesture(target:self,action:#selector(track(_:)))
            addGestureRecognizer(gesture)
            isAccessibilityElement=true;accessibilityTraits = .button
            accessibilityLabel="按住说话，上滑选择取消或编辑，松开发送";accessibilityIdentifier="holdToTalkButton"
            accessibilityHint="双击开始或结束录音，也可以使用结束并编辑操作"
            accessibilityCustomActions=[UIAccessibilityCustomAction(name:"结束并编辑",target:self,selector:#selector(accessibleEdit)),UIAccessibilityCustomAction(name:"取消语音消息",target:self,selector:#selector(accessibleCancel))]
        }
        required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
        @objc private func track(_ gesture:VoiceHoldGesture) {
            switch gesture.state {
            case .began:
                tracking=onBegin?() == true;armed=false
                if tracking {impact.impactOccurred(intensity:0.5);selection.prepare()}
            case .changed: if tracking {updateHover(gesture.windowPoint)}
            case .ended:
                guard tracking else {return}
                updateHover(gesture.windowPoint);tracking=false;onRelease?()
            case .cancelled,.failed: cancelTouch()
            default:break
            }
        }
        private func updateHover(_ point:CGPoint) {
            let next=onMove?(point) ?? false
            if next != armed {armed=next;selection.selectionChanged();selection.prepare()}
        }
        func cancelTouch() {
            guard tracking else {return};tracking=false;onCancel?()
        }
        override func accessibilityActivate()->Bool {
            if active {onRelease?()} else {_=onBegin?()};return true
        }
        @objc private func accessibleCancel()->Bool {onAccessibleCancel?();return true}
        @objc private func accessibleEdit()->Bool {onAccessibleEdit?();return true}
    }
}

/// Both the touch and target are converted through the same UIWindow. SwiftUI
/// global coordinates can have a different origin inside our embedded chat host.
@MainActor final class VoiceCaptureTouchTarget {
    weak var view:UIView?
    func contains(_ point:CGPoint,armed:Bool)->Bool {
        guard let view,let window=view.window else {return false}
        return VoiceEditHitTarget.contains(view.convert(point,from:window),frame:view.bounds,armed:armed)
    }
}

struct VoiceEditTargetAnchor:UIViewRepresentable {
    let target:VoiceCaptureTouchTarget
    func makeUIView(context:Context)->UIView {
        let view=UIView();view.isUserInteractionEnabled=false;target.view=view;return view
    }
    func updateUIView(_ view:UIView,context:Context) {target.view=view}
}
