import UIKit

/// Keep the live Metal surface opaque and in a fixed stacking order. Only the
/// native shell content fades. Keep its transparent window in place even after
/// completion: removing/reordering a window can invalidate the compositor's last frame.
@MainActor final class NativeWindowHandoff: NSObject {
    enum Destination:String { case conversation, shell }
    static let coverLevel = UIWindow.Level(rawValue:UIWindow.Level.normal.rawValue+2)
    private var animator:UIViewPropertyAnimator?
    private var revision = 0
#if DEBUG
    var onSample: (([String:Any])->Void)?
    private var displayLink:CADisplayLink?
    private weak var sampledShell:UIWindow?
    private weak var sampledRuntime:UIWindow?
    private var sampledDestination = Destination.conversation
#endif
    func cancel() {
        revision += 1
        animator?.stopAnimation(true); animator = nil
#if DEBUG
        displayLink?.invalidate(); displayLink = nil
#endif
    }
    func settle() {
        guard let animator, animator.state == .active else { return }
        animator.stopAnimation(false); animator.finishAnimation(at:.end)
    }
    func cover(_ shell:UIWindow) {
        cancel()
        UIView.performWithoutAnimation {
            shell.backgroundColor = .clear; shell.isOpaque = false
            shell.alpha = 1; shell.rootViewController?.view.alpha = 1
            shell.isUserInteractionEnabled = true
            shell.rootViewController?.view.isUserInteractionEnabled = true
            shell.windowLevel = Self.coverLevel
            shell.makeKeyAndVisible()
        }
    }
    func showShellImmediately(_ shell:UIWindow) {
        cover(shell)
    }
    func transition(to destination:Destination, shell:UIWindow, runtime:UIWindow,
                    duration:TimeInterval, activateRuntime:()->Void, completion:@escaping ()->Void) {
        let canvas = shell.rootViewController!.view!
        let initialOpacity = animator == nil ? (destination == .conversation ? 1.0 : 0.0) :
            Double(canvas.layer.presentation()?.opacity ?? Float(canvas.alpha))
        cancel()
        let current = revision
        UIView.performWithoutAnimation {
            shell.backgroundColor = .clear; shell.isOpaque = false
            shell.windowLevel = Self.coverLevel; shell.alpha = 1
            shell.isUserInteractionEnabled = false
            canvas.isOpaque = false
            canvas.alpha = initialOpacity; canvas.isUserInteractionEnabled = false
            shell.isHidden = false
            runtime.alpha = 1
            activateRuntime()
            canvas.layoutIfNeeded()
        }
        let target:CGFloat = destination == .conversation ? 0 : 1
        let animation = UIViewPropertyAnimator(duration:duration,curve:.easeInOut) { canvas.alpha = target }
        animator = animation
#if DEBUG
        if onSample != nil {
            sampledShell = shell; sampledRuntime = runtime; sampledDestination = destination
            displayLink = CADisplayLink(target:self,selector:#selector(sample))
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum:30,maximum:60,preferred:60)
            displayLink?.add(to:.main,forMode:.common)
        }
#endif
        animation.addCompletion { [weak self, weak shell, weak runtime] _ in
            guard let self, self.revision == current, let shell, let runtime else { return }
#if DEBUG
            self.sample(); self.displayLink?.invalidate(); self.displayLink = nil
#endif
            self.animator = nil
            UIView.performWithoutAnimation {
                if destination == .conversation {
                    // No window visibility, order or alpha restoration at the end.
                    // The invisible native shell passes all touches to the runtime.
                    canvas.alpha = 0
                    shell.isUserInteractionEnabled = false
                } else {
                    runtime.isHidden = true
                    shell.isUserInteractionEnabled = true
                    shell.makeKeyAndVisible()
                }
                canvas.isUserInteractionEnabled = destination == .shell
            }
            completion()
        }
        animation.startAnimation()
    }
#if DEBUG
    @objc private func sample() {
        guard let shell = sampledShell, let runtime = sampledRuntime else { return }
        let canvas = shell.rootViewController!.view!
        onSample?(["name":"windowHandoffSample","direction":sampledDestination.rawValue,
            "transition":revision,"time":ProcessInfo.processInfo.systemUptime,
            "coverOpacity":Double(canvas.layer.presentation()?.opacity ?? Float(canvas.alpha)),
            "runtimeOpacity":Double(runtime.layer.presentation()?.opacity ?? Float(runtime.alpha)),
            "coverAboveRuntime":shell.windowLevel > runtime.windowLevel,
            "coverHidden":shell.isHidden,"runtimeHidden":runtime.isHidden])
    }
#endif
}
