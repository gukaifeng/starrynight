import UIKit
import Observation
import OSLog

@MainActor @Observable
final class ViewerCoordinator: NSObject, UnityRuntimeBridgeDelegate {
    enum Page { case home, loading, viewer, error }
    private(set) var page: Page = .home
    private(set) var errorMessage = ""
    @ObservationIgnored private let bridge = UnityRuntimeBridge()
    @ObservationIgnored private weak var window: UIWindow?
    @ObservationIgnored private weak var scene: UIWindowScene?
    @ObservationIgnored private var overlay: ViewerOverlayController?
    @ObservationIgnored private var active = false
    @ObservationIgnored private var desiredVisible = false
    @ObservationIgnored private var ready = false
    @ObservationIgnored private var presentation = 0
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var pendingReset = ""
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var foregroundWait = 0.0
    @ObservationIgnored private var openTime = Date()
#if DEBUG
    @ObservationIgnored private var didDeferTestReady = false
#endif
    @ObservationIgnored private let logger = Logger(subsystem:"com.modelspace.viewer",category:"Viewer")

    init(window: UIWindow, scene: UIWindowScene) {
        self.window = window; self.scene = scene
        super.init()
        bridge.delegate = self
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           let directory = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first {
            try? FileManager.default.removeItem(at:directory.appendingPathComponent("viewer-events.jsonl"))
        }
#endif
    }
    func openViewer() {
        guard page == .home, let scene else { return }
        presentation += 1; desiredVisible = true; page = .loading
        foregroundWait = 0; openTime = Date()
        logger.info("viewer_open presentation=\(self.presentation) warm=\(self.ready)")
        startTimeout()
        // Allow SwiftUI to submit the loading view before Unity's synchronous startup.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for:.milliseconds(80))
            guard let self, self.desiredVisible else { return }
            if !self.bridge.started {
                self.bridge.start(in:scene)
                self.window?.makeKeyAndVisible()
            } else {
                self.bridge.setPaused(false)
                if self.ready { self.preparePresentation() }
            }
        }
    }
    func closeViewer() {
        desiredVisible = false; pendingReset = ""; page = .home
        timer?.invalidate(); timer = nil
        send("clearInput")
        bridge.setPaused(true)
        window?.makeKeyAndVisible()
        logger.info("viewer_close presentation=\(self.presentation)")
    }
    func resetView() {
        guard ready, desiredVisible, page == .viewer else { return }
        send("resetView", payload:["immediate":UIAccessibility.isReduceMotionEnabled])
    }
    func playAction(_ action: String) {
        guard ready, desiredVisible, page == .viewer else { return }
        send("playAction",payload:["action":action])
    }
    func activate() {
        active = true
        if bridge.started, desiredVisible {
            bridge.setPaused(false)
            if page == .viewer { reveal() }
            else if page == .loading { preparePresentation() }
        }
    }
    func deactivate() {
        active = false
        send("clearInput")
        bridge.setPaused(true)
    }
    private func preparePresentation() {
        guard ready, desiredVisible, active else { return }
        bridge.setPaused(false)
        pendingReset = nextRequest()
        send("resetView", payload:["immediate":true], request:pendingReset)
    }
    private func reveal() {
        guard ready, desiredVisible, active, let scene else { return }
        if overlay == nil, let root = bridge.rootController() {
            let overlay = ViewerOverlayController()
            overlay.onBack = { [weak self] in self?.closeViewer() }
            overlay.onReset = { [weak self] in self?.resetView() }
            overlay.onAction = { [weak self] action in self?.playAction(action) }
            overlay.onResize = { [weak self] in self?.send("configureViewport") }
            root.addChild(overlay); root.view.addSubview(overlay.view)
            overlay.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                overlay.view.leadingAnchor.constraint(equalTo:root.view.leadingAnchor),
                overlay.view.trailingAnchor.constraint(equalTo:root.view.trailingAnchor),
                overlay.view.topAnchor.constraint(equalTo:root.view.topAnchor),
                overlay.view.bottomAnchor.constraint(equalTo:root.view.bottomAnchor)])
            overlay.didMove(toParent:root)
            self.overlay = overlay
        }
        bridge.show(in:scene)
        page = .viewer
        timer?.invalidate(); timer = nil
        send("configureViewport")
        logger.info("viewer_visible elapsed=\(Date().timeIntervalSince(self.openTime)) presentation=\(self.presentation)")
    }
    nonisolated func runtimeDidReceive(_ json: String) {
        Task { @MainActor [weak self] in self?.receive(json) }
    }
    private func receive(_ json: String) {
        guard let data = json.data(using:.utf8),
              let event = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              event["schemaVersion"] as? Int == 1,
              let name = event["name"] as? String else { return }
#if DEBUG
        // Deterministically exercise cancellation and timeout with the real engine.
        // Only the delivery of the first ready event is delayed, never scene content.
        if name == "sceneReady", !didDeferTestReady,
           ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--test-ready-delay=") }),
           let seconds = Double(argument.split(separator:"=").last ?? ""), seconds > 0 {
            didDeferTestReady = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(for:.seconds(min(seconds,25)))
                self?.receive(json)
            }
            return
        }
#endif
        logger.info("unity_event \(json, privacy:.public)")
        recordTestEvent(json)
        switch name {
        case "sceneReady":
            ready = true
            if desiredVisible && active { preparePresentation() }
            else { bridge.setPaused(true); window?.makeKeyAndVisible() }
        case "viewReset":
            guard event["presentationId"] as? Int == presentation else { return }
            if page == .loading, event["requestId"] as? String == pendingReset { pendingReset = ""; reveal() }
        case "actionStarted", "actionCompleted", "actionIdle":
            guard event["presentationId"] as? Int == presentation else { return }
            overlay?.setAction(name == "actionStarted" ? event["action"] as? String ?? "" : "")
        case "headTapped":
            guard desiredVisible, event["presentationId"] as? Int == presentation else { return }
            UIImpactFeedbackGenerator(style:.light).impactOccurred()
        case "error":
            guard desiredVisible else { return }
            errorMessage = "请返回首页后重新尝试。如果仍无法打开，请关闭并重新打开 App。"
            page = .error; desiredVisible = false
            timer?.invalidate(); bridge.setPaused(true); window?.makeKeyAndVisible()
        default: break
        }
    }
    private func recordTestEvent(_ json: String) {
#if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing"),
              let directory = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first,
              let data = (json + "\n").data(using:.utf8) else { return }
        let url = directory.appendingPathComponent("viewer-events.jsonl")
        if !FileManager.default.fileExists(atPath:url.path) { FileManager.default.createFile(atPath:url.path,contents:nil) }
        if let handle = try? FileHandle(forWritingTo:url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd(); try? handle.write(contentsOf:data)
        }
#endif
    }
    private func nextRequest() -> String { sequence += 1; return "view-\(presentation)-\(sequence)" }
    private func send(_ name: String, payload: [String:Any] = [:], request: String? = nil) {
        guard bridge.started else { return }
        let value: [String:Any] = ["schemaVersion":1,"kind":"command","name":name,
            "requestId":request ?? nextRequest(),"presentationId":presentation,"payload":payload]
        guard let data = try? JSONSerialization.data(withJSONObject:value), let json = String(data:data,encoding:.utf8) else { return }
        bridge.send(json)
    }
    private func startTimeout() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.active, self.page == .loading else { return }
                self.foregroundWait += 1
                if self.foregroundWait >= 15 {
                    self.errorMessage = "准备模型所需时间较长，请返回后重试。"
                    self.page = .error; self.desiredVisible = false
                    self.timer?.invalidate(); self.bridge.setPaused(true); self.window?.makeKeyAndVisible()
                }
            }
        }
    }
}
