import UIKit

/// A brief brand transition ends when the native shell is ready. Character and
/// network preparation never extend this cover's lifetime.
final class AppStartupController: UIViewController {
    static let night = UIColor(red:16/255,green:17/255,blue:20/255,alpha:1)
    private let content = UIView()
    private let glyph = UIImageView(image:UIImage(named:"BrandMark"))
    private let wordmark = UILabel()
    private let caption = UILabel()
    private let halo = CAGradientLayer()
    private let shimmer = CALayer()
    private let beam = CAGradientLayer()
    private var startedAt: TimeInterval?
    private var pendingCompletion: (() -> Void)?
    private var finishTask: Task<Void,Never>?
    private var phaseTask: Task<Void,Never>?
    private var leaving = false
    private var paused = false
    private var introDuration:TimeInterval { UIAccessibility.isReduceMotionEnabled ? 0.12 : 0.42 }
    override var prefersStatusBarHidden:Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Self.night
        view.isAccessibilityElement = true
        view.accessibilityViewIsModal = true
        view.accessibilityIdentifier = "appStartupScreen"
        view.accessibilityLabel = L10n.text("星夜，正在打开")
        view.accessibilityValue = L10n.text("开场动画")
        content.isUserInteractionEnabled = false
        view.addSubview(content)
        halo.type = .radial
        halo.startPoint = CGPoint(x:0.5,y:0.5); halo.endPoint = CGPoint(x:1,y:1)
        halo.colors = [UIColor(white:0.9,alpha:0.10).cgColor,
            UIColor(red:0.57,green:0.65,blue:0.74,alpha:0.028).cgColor,
            UIColor.clear.cgColor]
        halo.locations = [0,0.48,1]
        content.layer.addSublayer(halo)
        glyph.contentMode = .scaleAspectFit
        content.addSubview(glyph)
        wordmark.textAlignment = .center
        wordmark.attributedText = NSAttributedString(string:L10n.text("星夜"),attributes:[
            .font:UIFont.systemFont(ofSize:28,weight:.light), .kern:8,
            .foregroundColor:UIColor(white:0.94,alpha:1)])
        caption.textAlignment = .center
        caption.attributedText = NSAttributedString(string:L10n.text("每一句，都有回声"),attributes:[
            .font:UIFont.systemFont(ofSize:11,weight:.regular), .kern:3,
            .foregroundColor:UIColor(white:0.67,alpha:0.74)])
        content.addSubview(wordmark); content.addSubview(caption)
        let mask = CALayer()
        mask.contents = glyph.image?.cgImage
        mask.contentsGravity = .resizeAspect
        shimmer.mask = mask
        shimmer.masksToBounds = true
        beam.startPoint = CGPoint(x:0,y:0.15); beam.endPoint = CGPoint(x:1,y:0.85)
        beam.colors = [UIColor.clear.cgColor,UIColor(white:1,alpha:0.32).cgColor,UIColor.clear.cgColor]
        beam.locations = [0,0.48,1]
        shimmer.addSublayer(beam); content.layer.addSublayer(shimmer)
        NotificationCenter.default.addObserver(self,selector:#selector(motionPreferenceChanged),
            name:UIAccessibility.reduceMotionStatusDidChangeNotification,object:nil)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        content.bounds = CGRect(x:0,y:0,width:300,height:260)
        content.center = CGPoint(x:view.bounds.midX,y:view.bounds.height*0.47)
        glyph.frame = CGRect(x:85,y:0,width:130,height:130)
        halo.frame = glyph.frame.insetBy(dx:-68,dy:-68)
        wordmark.frame = CGRect(x:4,y:151,width:300,height:42)
        caption.frame = CGRect(x:1.5,y:211,width:300,height:20)
        shimmer.frame = glyph.frame; shimmer.mask?.frame = shimmer.bounds
        beam.frame = CGRect(x:-130,y:0,width:130,height:130)
        CATransaction.commit()
    }
    func begin() {
        guard startedAt == nil else { return }
        loadViewIfNeeded(); view.layoutIfNeeded()
        startedAt = ProcessInfo.processInfo.systemUptime
        configureAnimation()
        phaseTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for:.seconds(self?.introDuration ?? 0.42)) } catch { return }
            guard let self, !self.leaving else { return }
            self.view.accessibilityValue = L10n.text("等待就绪")
        }
    }
    private func configureAnimation() {
        for layer in [glyph.layer,halo,wordmark.layer,caption.layer,beam] { layer.removeAllAnimations() }
        guard !UIAccessibility.isReduceMotionEnabled else { shimmer.isHidden = true; return }
        shimmer.isHidden = false
        let now = content.layer.convertTime(CACurrentMediaTime(),from:nil)
        func entrance(_ layer:CALayer,delay:TimeInterval,duration:TimeInterval) {
            let fade = CABasicAnimation(keyPath:"opacity")
            fade.fromValue = 0; fade.toValue = 1; fade.beginTime = now+delay
            fade.duration = duration; fade.fillMode = .backwards
            fade.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut)
            layer.add(fade,forKey:"entrance")
        }
        entrance(glyph.layer,delay:0,duration:0.30)
        entrance(halo,delay:0,duration:0.42)
        entrance(wordmark.layer,delay:0.08,duration:0.26)
        entrance(caption.layer,delay:0.16,duration:0.24)
        let scale = CABasicAnimation(keyPath:"transform.scale")
        scale.fromValue = 0.94; scale.toValue = 1; scale.duration = 0.42
        scale.timingFunction = CAMediaTimingFunction(controlPoints:0.16,0.8,0.24,1)
        glyph.layer.add(scale,forKey:"gather")

        // A slow local-data recovery can still breathe without waiting for a
        // main-thread completion; Unity has not started behind this cover.
        let breathe = CAKeyframeAnimation(keyPath:"opacity")
        breathe.values = [1,0.60,1]; breathe.keyTimes = [0,0.5,1]
        breathe.duration = 3.6; breathe.beginTime = now+0.42; breathe.repeatCount = .infinity
        breathe.timingFunctions = [.init(name:.easeInEaseOut),.init(name:.easeInEaseOut)]
        glyph.layer.add(breathe,forKey:"waiting-breath")
        let glow = CAKeyframeAnimation(keyPath:"transform.scale")
        glow.values = [1,1.13,1]; glow.keyTimes = [0,0.5,1]
        glow.duration = 3.6; glow.beginTime = now+0.42; glow.repeatCount = .infinity
        glow.timingFunctions = breathe.timingFunctions
        halo.add(glow,forKey:"waiting-glow")
        let flow = CAKeyframeAnimation(keyPath:"transform.translation.x")
        flow.values = [0,0,260,260]; flow.keyTimes = [0,0.12,0.70,1]
        flow.duration = 3.6; flow.beginTime = now+0.42; flow.repeatCount = .infinity
        beam.add(flow,forKey:"waiting-flow")
    }
    @objc private func motionPreferenceChanged() {
        configureAnimation()
        if pendingCompletion != nil { scheduleExit() }
    }
    func finish(completion:@escaping ()->Void) {
        guard !leaving else { return }
        pendingCompletion = completion
        scheduleExit()
    }
    private func scheduleExit() {
        guard !leaving, !paused, pendingCompletion != nil else { return }
        finishTask?.cancel()
        let remaining = max(0,introDuration-(ProcessInfo.processInfo.systemUptime-(startedAt ?? 0)))
        finishTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for:.seconds(remaining)) } catch { return }
            guard let self, !self.leaving, !self.paused else { return }
            self.leaving = true; self.phaseTask?.cancel()
            self.view.accessibilityValue = L10n.text("进入页面")
            UIView.animate(withDuration:UIAccessibility.isReduceMotionEnabled ? 0.12 : 0.22,
                           delay:0,options:[.curveEaseInOut,.beginFromCurrentState],animations:{
                self.view.alpha = 0
            }) { [weak self] _ in
                guard let self else { return }
                let completion = self.pendingCompletion; self.pendingCompletion = nil
                completion?()
            }
        }
    }
    func setActive(_ active:Bool) {
        guard isViewLoaded, paused != !active else { return }
        if !active {
            let time = view.layer.convertTime(CACurrentMediaTime(),from:nil)
            view.layer.speed = 0; view.layer.timeOffset = time; paused = true
            finishTask?.cancel()
        } else {
            let offset = view.layer.timeOffset
            view.layer.speed = 1; view.layer.timeOffset = 0; view.layer.beginTime = 0
            view.layer.beginTime = view.layer.convertTime(CACurrentMediaTime(),from:nil)-offset
            paused = false; scheduleExit()
        }
    }
}
