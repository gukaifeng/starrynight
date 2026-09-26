import UIKit

private final class TouchThroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point,with:event), hit !== self else { return nil }
        var candidate: UIView? = hit
        while let current = candidate, current !== self {
            if current is UIControl { return hit }
            candidate = current.superview
        }
        return nil
    }
}

final class ViewerOverlayController: UIViewController {
    var onBack: (() -> Void)?
    var onReset: (() -> Void)?
    var onResize: (() -> Void)?
    var onAction: ((String) -> Void)?
    var onFrameRate: ((Int) -> Void)?
    private let performance = UIButton(type:.system)
    private var previousSize: CGSize = .zero
    private let subtitle = UILabel()
    private var actionButtons: [String:UIButton] = [:]

    func setAction(_ action: String) {
        let names = ["Wave":"挥手", "Jump":"跳跃", "Dance":"跳舞", "No":"摇头"]
        subtitle.text = names[action].map { "正在" + $0 } ?? "LUMA · STUDIO ROBOT"
        for (name,button) in actionButtons {
            button.isSelected = name == action
            button.accessibilityValue = name == action ? "正在播放" : "轻点播放"
            button.configuration?.baseBackgroundColor = name == action
                ? UIColor(red:0.86,green:0.9,blue:1,alpha:1) : .white.withAlphaComponent(0.95)
        }
    }
    func setPerformance(fps:Double,target:Int,screenMaximum:Int) {
        performance.configuration?.title = String(format:"%.0f FPS  ·  目标 %d",fps,target)
        performance.configuration?.subtitle = "当前屏幕上限 \(screenMaximum) Hz"
        performance.accessibilityValue = String(format:"实测渲染循环 %.1f 帧，目标 %d 帧，屏幕上限 %d 赫兹",fps,target,screenMaximum)
    }

    override func loadView() { view = TouchThroughView(); view.backgroundColor = .clear }
    override func viewDidLoad() {
        super.viewDidLoad()
        let ink = UIColor(red:20/255,green:35/255,blue:56/255,alpha:1)
        let blue = UIColor(red:53/255,green:99/255,blue:233/255,alpha:1)
        let back = UIButton(type:.system)
        var backConfig = UIButton.Configuration.filled()
        backConfig.image = UIImage(systemName:"chevron.left")
        backConfig.baseBackgroundColor = .white.withAlphaComponent(0.94)
        backConfig.baseForegroundColor = ink
        backConfig.cornerStyle = .capsule
        back.configuration = backConfig
        back.accessibilityLabel = "返回首页"; back.accessibilityIdentifier = "viewerBackButton"
        back.addAction(UIAction { [weak self] _ in self?.onBack?() },for:.touchUpInside)
        let reset = UIButton(type:.system)
        var resetConfig = UIButton.Configuration.filled()
        resetConfig.title = "复位"; resetConfig.image = UIImage(systemName:"arrow.counterclockwise")
        resetConfig.imagePadding = 6; resetConfig.baseBackgroundColor = .white.withAlphaComponent(0.94)
        resetConfig.baseForegroundColor = blue; resetConfig.cornerStyle = .capsule
        reset.configuration = resetConfig
        reset.accessibilityIdentifier = "resetViewButton"
        reset.addAction(UIAction { [weak self] _ in self?.onReset?() },for:.touchUpInside)
        let title = UILabel(); title.text = "Luma"; title.textColor = ink
        title.font = .preferredFont(forTextStyle:.headline); title.adjustsFontForContentSizeCategory = true
        title.textAlignment = .center
        subtitle.text = "LUMA · STUDIO ROBOT"; subtitle.textAlignment = .center
        subtitle.font = .monospacedSystemFont(ofSize:9,weight:.medium); subtitle.textColor = ink.withAlphaComponent(0.48)
        let hint = UILabel(); hint.text = "拖动旋转 · 双指缩放 · 点头部互动"
        hint.font = .preferredFont(forTextStyle:.caption1); hint.textColor = ink.withAlphaComponent(0.66)
        hint.adjustsFontForContentSizeCategory = true; hint.textAlignment = .center
        let hintBackground = UIVisualEffectView(effect:UIBlurEffect(style:.systemUltraThinMaterialLight))
        hintBackground.layer.cornerRadius = 23; hintBackground.clipsToBounds = true
        let actions = UIStackView(); actions.axis = .horizontal; actions.spacing = 10; actions.distribution = .fillEqually
        for (action,name,symbol) in [("Wave","挥手","hand.wave"),("Jump","跳跃","arrow.up"),("Dance","跳舞","music.note")] {
            let button = UIButton(type:.system)
            var config = UIButton.Configuration.filled()
            config.title = name; config.image = UIImage(systemName:symbol)
            config.imagePlacement = .top; config.imagePadding = 6; config.cornerStyle = .large
            config.baseBackgroundColor = .white.withAlphaComponent(0.95); config.baseForegroundColor = blue
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming; outgoing.font = .preferredFont(forTextStyle:.subheadline); return outgoing
            }
            button.configuration = config
            button.accessibilityIdentifier = "action" + action + "Button"
            button.accessibilityLabel = "让机器人" + name
            button.accessibilityValue = "轻点播放"
            button.addAction(UIAction { [weak self] _ in self?.onAction?(action) },for:.touchUpInside)
            actions.addArrangedSubview(button); actionButtons[action] = button
        }
        for item in [back,reset,title,subtitle,hintBackground,hint,actions] {
            view.addSubview(item); item.translatesAutoresizingMaskIntoConstraints = false
        }
        let safe = view.safeAreaLayoutGuide
        var fpsConfig = UIButton.Configuration.tinted()
        fpsConfig.title = "目标 120 FPS · 测量中"; fpsConfig.cornerStyle = .capsule
        fpsConfig.baseForegroundColor = ink; fpsConfig.baseBackgroundColor = .white
        fpsConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming; outgoing.font = .monospacedDigitSystemFont(ofSize:11,weight:.medium); return outgoing
        }
        fpsConfig.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming; outgoing.font = .systemFont(ofSize:9); return outgoing
        }
        performance.configuration = fpsConfig
        performance.accessibilityIdentifier = "frameRateButton"
        performance.accessibilityLabel = "帧率设置与实测"
        performance.menu = UIMenu(title:"渲染目标（实际帧率由设备与系统决定）",children:[
            UIAction(title:"120 FPS · 高刷新率") { [weak self] _ in self?.onFrameRate?(120) },
            UIAction(title:"60 FPS · 标准") { [weak self] _ in self?.onFrameRate?(60) }])
        performance.showsMenuAsPrimaryAction = true
        view.addSubview(performance); performance.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            performance.topAnchor.constraint(equalTo:back.bottomAnchor,constant:18),
            performance.centerXAnchor.constraint(equalTo:view.centerXAnchor),performance.heightAnchor.constraint(equalToConstant:44),
            back.leadingAnchor.constraint(equalTo:safe.leadingAnchor,constant:20),
            back.topAnchor.constraint(equalTo:safe.topAnchor,constant:12),
            back.widthAnchor.constraint(equalToConstant:46),back.heightAnchor.constraint(equalToConstant:46),
            reset.trailingAnchor.constraint(equalTo:safe.trailingAnchor,constant:-20),
            reset.centerYAnchor.constraint(equalTo:back.centerYAnchor),reset.heightAnchor.constraint(equalToConstant:46),
            reset.widthAnchor.constraint(greaterThanOrEqualToConstant:84),
            title.centerXAnchor.constraint(equalTo:view.centerXAnchor),title.topAnchor.constraint(equalTo:back.topAnchor,constant:3),
            title.leadingAnchor.constraint(greaterThanOrEqualTo:back.trailingAnchor,constant:8),
            title.trailingAnchor.constraint(lessThanOrEqualTo:reset.leadingAnchor,constant:-8),
            subtitle.centerXAnchor.constraint(equalTo:title.centerXAnchor),subtitle.topAnchor.constraint(equalTo:title.bottomAnchor,constant:5),
            actions.centerXAnchor.constraint(equalTo:view.centerXAnchor),actions.bottomAnchor.constraint(equalTo:safe.bottomAnchor,constant:-20),
            actions.widthAnchor.constraint(equalToConstant:320),actions.heightAnchor.constraint(equalToConstant:70),
            hint.centerXAnchor.constraint(equalTo:view.centerXAnchor),hint.bottomAnchor.constraint(equalTo:actions.topAnchor,constant:-24),
            hintBackground.centerXAnchor.constraint(equalTo:hint.centerXAnchor),hintBackground.centerYAnchor.constraint(equalTo:hint.centerYAnchor),
            hintBackground.widthAnchor.constraint(equalTo:hint.widthAnchor,constant:40),hintBackground.heightAnchor.constraint(equalTo:hint.heightAnchor,constant:26)])
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if previousSize != view.bounds.size { previousSize = view.bounds.size; onResize?() }
    }
}
