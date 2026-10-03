import UIKit
import SwiftUI

/// Adaptive panel surfaces never scale or snapshot the underlying Unity view.
final class SoftSheetTransition: NSObject, UIViewControllerTransitioningDelegate {
    var onDismissRequested: (() -> Void)?
    func presentationController(forPresented presented:UIViewController,presenting:UIViewController?,source:UIViewController) -> UIPresentationController? {
        let controller = SoftSheetPresentation(presentedViewController:presented,presenting:presenting)
        controller.onDismissRequested = onDismissRequested
        return controller
    }
    func animationController(forPresented presented:UIViewController,presenting:UIViewController,source:UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SoftSheetAnimation(presenting:true)
    }
    func animationController(forDismissed dismissed:UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SoftSheetAnimation(presenting:false)
    }
}

private final class SoftSheetAnimation: NSObject, UIViewControllerAnimatedTransitioning {
    let presenting:Bool
    private var animator:UIViewPropertyAnimator?
    init(presenting:Bool) { self.presenting = presenting }
    func transitionDuration(using context:UIViewControllerContextTransitioning?) -> TimeInterval {
        UIAccessibility.isReduceMotionEnabled ? 0.2 : 0.9
    }
    func animateTransition(using context:UIViewControllerContextTransitioning) {
        interruptibleAnimator(using:context).startAnimation()
    }
    func interruptibleAnimator(using context:UIViewControllerContextTransitioning) -> UIViewImplicitlyAnimating {
        if let animator { return animator }
        guard let controller = context.viewController(forKey:presenting ? .to : .from),
              let panel = context.view(forKey:presenting ? .to : .from) else {
            let fallback = UIViewPropertyAnimator(duration:0,curve:.linear)
            fallback.addCompletion { _ in context.completeTransition(false) }; return fallback
        }
        let resting = context.finalFrame(for:controller)
        if presenting { context.containerView.addSubview(panel); panel.frame = resting; panel.layoutIfNeeded() }
        let offset = UIAccessibility.isReduceMotionEnabled ? CGFloat(0) : max(panel.bounds.height,context.containerView.bounds.height-panel.frame.minY)+32
        let side = AdaptiveViewerLayout.sideBySide(context.containerView.bounds.size)
        let departure = side ? CGAffineTransform(translationX:panel.bounds.width+32,y:0) : CGAffineTransform(translationX:0,y:offset)
        if presenting { panel.transform = departure; panel.alpha = 0 }
        let animator = UIViewPropertyAnimator(duration:transitionDuration(using:context),dampingRatio:0.82) {
            panel.transform = self.presenting ? .identity : departure
            panel.alpha = self.presenting ? 1 : 0
        }
        animator.addCompletion { _ in
            let finished = !context.transitionWasCancelled
            if !self.presenting && finished { panel.removeFromSuperview() }
            panel.transform = .identity
            context.completeTransition(finished)
            self.animator = nil
        }
        self.animator = animator
        return animator
    }
}

private final class SoftSheetPresentation: UIPresentationController {
    var onDismissRequested: (() -> Void)?
    private let outside = UIButton(type:.custom)
    private let grabber = UIView()
    private let handle = UIView()
    private var expanded = false
    private var dragging = false
    private var closing = false
    private var startFrame = CGRect.zero
    private var resizeAnimator:UIViewPropertyAnimator?
    private var surfaceOpacity:CGFloat = -1
    override var shouldRemovePresentersView: Bool { false }
    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView else { return .zero }
        let bounds = containerView.bounds
        let safe = containerView.safeAreaInsets
        return AdaptiveViewerLayout.sheet(bounds.size,inset:.init(top:safe.top,left:safe.left,bottom:safe.bottom,right:safe.right),
            preferred:presentedViewController.preferredContentSize,expanded:expanded)
    }
    override func presentationTransitionWillBegin() {
        guard let panel = presentedView, let containerView else { return }
        // A transparent hit surface behind the sheet consumes the closing tap so it
        // cannot also rotate the character or navigate away from the conversation.
        outside.backgroundColor = .clear
        outside.accessibilityLabel = "关闭窗口"
        outside.accessibilityIdentifier = "panelOutsideDismiss"
        outside.addTarget(self,action:#selector(requestClose),for:.touchUpInside)
        containerView.insertSubview(outside,at:0)
        updateSurface(frame:frameOfPresentedViewInContainerView,animated:false)
        panel.layer.cornerRadius = 30; panel.layer.maskedCorners = [.layerMinXMinYCorner,.layerMaxXMinYCorner]
        panel.clipsToBounds = true
        panel.accessibilityViewIsModal = true
        handle.backgroundColor = UIColor.label.withAlphaComponent(0.2)
        handle.layer.cornerRadius = 2.5
        grabber.addSubview(handle); panel.addSubview(grabber)
        grabber.addGestureRecognizer(UIPanGestureRecognizer(target:self,action:#selector(pan(_:))))
        grabber.isAccessibilityElement = true; grabber.accessibilityLabel = "调整面板高度"
        grabber.accessibilityIdentifier = "softPanelHandle"
        grabber.accessibilityTraits = .button
        grabber.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name:"展开面板",actionHandler:{ [weak self] _ in self?.setExpanded(true); return true }),
            UIAccessibilityCustomAction(name:"收起面板",actionHandler:{ [weak self] _ in self?.setExpanded(false); return true })
        ]
    }
    override func dismissalTransitionDidEnd(_ completed: Bool) {
        if completed { outside.removeFromSuperview() }
    }
    @objc private func requestClose() {
        guard !presentedViewController.isBeingPresented, !presentedViewController.isBeingDismissed else { return }
        presentedView?.endEditing(true)
        onDismissRequested?()
    }
    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        outside.frame = containerView?.bounds ?? .zero
        if !dragging && !closing && resizeAnimator == nil && !presentedViewController.isBeingPresented && !presentedViewController.isBeingDismissed { presentedView?.frame = frameOfPresentedViewInContainerView }
        guard let panel = presentedView else { return }
        if !dragging { updateSurface(frame:frameOfPresentedViewInContainerView,animated:!presentedViewController.isBeingPresented) }
        let side = AdaptiveViewerLayout.sideBySide(containerView?.bounds.size ?? .zero)
        grabber.accessibilityLabel = side ? "向右滑动关闭面板" : "调整面板高度"
        grabber.accessibilityCustomActions = side ? [] : [
            UIAccessibilityCustomAction(name:"展开面板",actionHandler:{ [weak self] _ in self?.setExpanded(true); return true }),
            UIAccessibilityCustomAction(name:"收起面板",actionHandler:{ [weak self] _ in self?.setExpanded(false); return true })]
        panel.layer.maskedCorners = side ? [.layerMinXMinYCorner,.layerMaxXMinYCorner,.layerMinXMaxYCorner,.layerMaxXMaxYCorner] : [.layerMinXMinYCorner,.layerMaxXMinYCorner]
        grabber.frame = CGRect(x:0,y:0,width:panel.bounds.width,height:22)
        handle.frame = CGRect(x:(panel.bounds.width-34)/2,y:7,width:34,height:5)
        panel.bringSubviewToFront(grabber)
    }
    private func updateSurface(frame:CGRect,animated:Bool) {
        guard let panel = presentedView, let containerView else { return }
        let safe = containerView.safeAreaInsets
        let opacity:CGFloat = UIAccessibility.isReduceTransparencyEnabled || ThemeSettings.shared.solid ? 1 :
            AdaptiveViewerLayout.sheetSurfaceOpacity(frame,in:containerView.bounds.size,
                inset:.init(top:safe.top,left:safe.left,bottom:safe.bottom,right:safe.right))
        guard abs(surfaceOpacity-opacity) > 0.0001 || panel.backgroundColor != UIColor(Theme.background).withAlphaComponent(opacity) else { return }
        let initialized = surfaceOpacity >= 0
        surfaceOpacity = opacity
        let update = { panel.backgroundColor = UIColor(Theme.background).withAlphaComponent(opacity) }
        panel.isOpaque = opacity == 1
        if animated && initialized {
            UIView.animate(withDuration:UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.35,
                delay:0,options:[.beginFromCurrentState,.allowUserInteraction,.curveEaseInOut],animations:update)
        } else { UIView.performWithoutAnimation(update) }
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            grabber.accessibilityValue = String(format:"surfaceAlpha=%.3f",panel.backgroundColor?.cgColor.alpha ?? -1)
        }
#endif
    }
    private func setExpanded(_ value:Bool) {
        expanded = value
        let target = frameOfPresentedViewInContainerView
        updateSurface(frame:target,animated:true)
        resizeAnimator?.stopAnimation(true)
        let animator = UIViewPropertyAnimator(duration:UIAccessibility.isReduceMotionEnabled ? 0.2 : 0.8,dampingRatio:0.84) {
            self.presentedView?.frame = target
            self.presentedView?.layoutIfNeeded()
        }
        animator.addCompletion { [weak self] _ in self?.resizeAnimator = nil }
        resizeAnimator = animator; animator.startAnimation()
    }
    @objc private func pan(_ gesture:UIPanGestureRecognizer) {
        guard let panel = presentedView, let containerView else { return }
        let side = AdaptiveViewerLayout.sideBySide(containerView.bounds.size)
        let offset = side ? gesture.translation(in:containerView).x : gesture.translation(in:containerView).y
        switch gesture.state {
        case .began:
            resizeAnimator?.stopAnimation(true); resizeAnimator = nil
            dragging = true; startFrame = panel.frame
        case .changed:
            if side {
                panel.frame = startFrame.offsetBy(dx:max(0,offset),dy:0)
                updateSurface(frame:panel.frame,animated:false)
                panel.layoutIfNeeded(); break
            }
            let y = max(containerView.safeAreaInsets.top+28,startFrame.minY+offset)
            let height = offset >= 0 ? startFrame.height : max(100,containerView.bounds.height-y)
            panel.frame = CGRect(x:startFrame.minX,y:y,width:startFrame.width,height:height)
            updateSurface(frame:panel.frame,animated:false)
            panel.layoutIfNeeded()
        case .ended:
            dragging = false
            if offset > 110 || (side ? gesture.velocity(in:containerView).x : gesture.velocity(in:containerView).y) > 700 {
                requestClose()
                // A failed save leaves the panel open; settle it back into place.
                if !presentedViewController.isBeingDismissed { setExpanded(expanded) }
            } else { setExpanded(!side && offset < -65 ? true : expanded) }
        case .cancelled,.failed:
            dragging = false; setExpanded(expanded)
        default: break
        }
    }
}
