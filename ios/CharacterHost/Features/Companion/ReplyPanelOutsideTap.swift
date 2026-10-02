import SwiftUI
import UIKit

/// Observe completed outside taps at the app window, including sibling bars,
/// bubbles and controls. Never install a surface over the model or consume taps.
struct ReplyPanelOutsideTap:UIViewRepresentable {
    let dismiss:()->Void
    func makeCoordinator()->Coordinator {Coordinator(dismiss:dismiss)}
    func makeUIView(context:Context)->Host {
        let view=Host();view.isUserInteractionEnabled=false
        view.moved={ [weak coordinator=context.coordinator,weak view] in if let view {coordinator?.attach(view)}}
        context.coordinator.attach(view);return view
    }
    func updateUIView(_ view:Host,context:Context) {context.coordinator.dismiss=dismiss;context.coordinator.attach(view)}
    static func dismantleUIView(_ view:Host,coordinator:Coordinator) {coordinator.detach();view.moved=nil}
    final class Host:UIView {
        var moved:(()->Void)?
        override func didMoveToWindow() {super.didMoveToWindow();moved?()}
    }
    final class Coordinator:NSObject,UIGestureRecognizerDelegate {
        var dismiss:()->Void
        weak var host:Host?
        weak var window:UIWindow?
        private lazy var tap:UITapGestureRecognizer = {
            let value=UITapGestureRecognizer(target:self,action:#selector(ended(_:)))
            value.cancelsTouchesInView=false;value.delaysTouchesBegan=false;value.delaysTouchesEnded=false;value.delegate=self
            return value
        }()
        init(dismiss:@escaping ()->Void) {self.dismiss=dismiss}
        func attach(_ view:Host) {
            host=view
            guard window !== view.window else{return}
            detach();window=view.window;window?.addGestureRecognizer(tap)
        }
        func detach() {window?.removeGestureRecognizer(tap);window=nil}
        func gestureRecognizer(_ recognizer:UIGestureRecognizer,shouldReceive touch:UITouch)->Bool {
            guard let host,host.window != nil else{return false}
            return !host.bounds.contains(touch.location(in:host))
        }
        func gestureRecognizer(_ recognizer:UIGestureRecognizer,shouldRecognizeSimultaneouslyWith other:UIGestureRecognizer)->Bool {true}
        @objc private func ended(_ recognizer:UITapGestureRecognizer) {if recognizer.state == .ended {dismiss()}}
    }
}
