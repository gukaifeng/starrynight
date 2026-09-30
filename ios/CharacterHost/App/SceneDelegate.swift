import UIKit
import SwiftUI

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var coordinator: ViewerCoordinator?
    private var startupWindow:UIWindow?
    private var startup:AppStartupController?
    private var bootstrapTask:Task<Void,Never>?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        LaunchTrace.begin()
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        let placeholder = UIViewController()
        placeholder.view.backgroundColor = AppStartupController.night
        window.rootViewController = placeholder
        window.overrideUserInterfaceStyle = .dark
        window.makeKeyAndVisible()
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--voice-atmosphere-check") {
            window.rootViewController=UIHostingController(rootView:VoiceAtmosphereFixture());return
        }
        if ProcessInfo.processInfo.arguments.contains("--reply-flow-check") {
            window.rootViewController=UIHostingController(rootView:ReplyFlowFixture());return
        }
        if ProcessInfo.processInfo.arguments.contains("--conversation-presentation-check") {
            window.rootViewController=UIHostingController(rootView:ConversationPresentationFixture())
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--chat-input-check") {
            let label = UILabel(); label.numberOfLines = 0; label.textColor = .white
            label.frame = CGRect(x:24,y:100,width:window.bounds.width-48,height:450)
            label.accessibilityIdentifier = "chatInputCoreResult"
            do { label.text = try ChatComposerInputTests.run() }
            catch { label.text = "FAIL: \(error.localizedDescription)" }
            placeholder.view.addSubview(label); return
        }
        if ProcessInfo.processInfo.arguments.contains("--speech-playback-check") {
            let label = UILabel(); label.numberOfLines = 0; label.textColor = .white
            label.frame = CGRect(x:24,y:100,width:window.bounds.width-48,height:450)
            label.accessibilityIdentifier = "speechPlaybackResult"; label.text = "正在检查声音播放…"
            placeholder.view.addSubview(label)
            Task {
                do { label.text = try await CloudSpeechPlaybackTests.run() }
                catch { label.text = "FAIL: \(error.localizedDescription)" }
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--view-presets-check") {
            let label=UILabel();label.numberOfLines=0;label.textColor = .white
            label.frame=CGRect(x:24,y:100,width:window.bounds.width-48,height:450)
            label.accessibilityIdentifier="viewPresetsCoreResult"
            do {label.text=try CharacterViewPresetTests.run()} catch {label.text="FAIL: \(error)"}
            placeholder.view.addSubview(label);return
        }
        if ProcessInfo.processInfo.arguments.contains("--cache-core-check") {
            let label = UILabel(); label.numberOfLines = 0; label.textColor = .white
            label.frame = CGRect(x:24,y:100,width:window.bounds.width-48,height:450)
            label.accessibilityIdentifier = "cacheCoreResult"; label.text = "正在检查缓存…"
            placeholder.view.addSubview(label)
            Task {
                do { label.text = try await CacheStorageTests.run() }
                catch { label.text = "FAIL: \(error)" }
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--cache-fixture"), !ProcessInfo.processInfo.arguments.contains("--keep-cache-fixture") {
            do { try CacheStorageTests.prepareUIFixture() }
            catch { assertionFailure("Isolated cache fixture failed: \(error)") }
        }
        if ProcessInfo.processInfo.arguments.contains("--market-core-check") {
            let label = UILabel(); label.numberOfLines = 0; label.textColor = .white
            label.frame = CGRect(x:24,y:100,width:window.bounds.width-48,height:450)
            label.accessibilityIdentifier = "marketCoreResult"
            do { label.text = try MarketplaceCoreTests.run() } catch { label.text = "FAIL: \(error)" }
            placeholder.view.addSubview(label); return
        }
        if ProcessInfo.processInfo.arguments.contains("--social-core-check") {
            let label = UILabel(); label.numberOfLines = 0; label.textColor = .white
            label.frame = CGRect(x:24,y:100,width:window.bounds.width-48,height:500)
            label.accessibilityIdentifier = "socialCoreResult"
            do { label.text = try AuthorSubscriptionTests.run() + "\n" + CharacterLibraryTests.run() }
            catch { label.text = "FAIL: \(error)" }
            placeholder.view.addSubview(label); return
        }
        if ProcessInfo.processInfo.arguments.contains("--export-ui-check") {
            let controller = UIHostingController(rootView: ConversationExportView(snapshot: ConversationExportTests.fixture()).preferredColorScheme(.dark))
            window.rootViewController = controller
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--export-core-check") {
            let label = UILabel(); label.numberOfLines = 0; label.textColor = .white
            label.frame = CGRect(x: 24, y: 100, width: window.bounds.width - 48, height: 350)
            label.accessibilityIdentifier = "exportCoreResult"; label.text = "正在验证导出…"
            placeholder.view.addSubview(label)
            Task {
                do { label.text = try await ConversationExportTests.run() }
                catch { label.text = "FAIL: \(error)" }
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--greeting-core-check") {
            let label = UILabel(); label.numberOfLines = 0; label.textColor = .white
            label.frame = CGRect(x:24,y:100,width:window.bounds.width-48,height:350)
            label.accessibilityIdentifier = "greetingCoreResult"
            do { label.text = try ConversationGreetingTests.run() }
            catch { label.text = "FAIL: \(error)" }
            placeholder.view.addSubview(label)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--experience-core-check") {
            let label=UILabel();label.numberOfLines=0;label.textColor = .white
            label.frame=CGRect(x:24,y:100,width:window.bounds.width-48,height:350)
            label.accessibilityIdentifier="experienceCoreResult"
            do { label.text = try CompanionExperienceTests.run() }
            catch { label.text = "FAIL: \(error)" }
            placeholder.view.addSubview(label)
            return
        }
#endif
        let cover = UIWindow(windowScene:windowScene)
        let startup = AppStartupController()
        cover.windowLevel = UIWindow.Level(rawValue:UIWindow.Level.normal.rawValue+3)
        cover.rootViewController = startup; cover.overrideUserInterfaceStyle = .dark
        self.startupWindow = cover; self.startup = startup
        cover.makeKeyAndVisible(); startup.begin()
        bootstrap(in:windowScene)
    }
    private func bootstrap(in windowScene:UIWindowScene) {
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains(where: { ["--voice-atmosphere-check", "--reply-flow-check", "--conversation-presentation-check", "--chat-input-check", "--speech-playback-check", "--greeting-core-check", "--view-presets-check", "--experience-core-check", "--export-core-check", "--export-ui-check", "--social-core-check", "--cache-core-check", "--market-core-check"].contains($0) }) { return }
#endif
        guard coordinator == nil, bootstrapTask == nil else { return }
        // Paint the lightweight brand cover, then prepare only the native shell.
        // Unity is scheduled after the cover has gone and the menu is usable.
        bootstrapTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for:.milliseconds(80)) } catch { return }
            guard let self, let window = self.window else { return }
            guard windowScene.activationState == .foregroundActive else {
                self.bootstrapTask = nil; return
            }
            let coordinator = ViewerCoordinator(window:window,scene:windowScene)
            self.coordinator = coordinator
            coordinator.onShellReady = { [weak self] in
                self?.startup?.finish { [weak self] in
                    guard let self else { return }
                    self.coordinator?.completeStartup()
                    self.startupWindow?.isHidden = true
                    self.startupWindow = nil; self.startup = nil
                    if self.coordinator?.page != .viewer { self.window?.makeKeyAndVisible() }
                }
            }
            let controller = UIHostingController(rootView:AppRootView(coordinator:coordinator))
            controller.view.backgroundColor = UIColor(Theme.background)
            controller.view.accessibilityElementsHidden = true
            window.rootViewController = controller
            coordinator.activate()
        }
    }
    func sceneDidBecomeActive(_ scene: UIScene) {
        startup?.setActive(true)
        if let windowScene = scene as? UIWindowScene { bootstrap(in:windowScene) }
        coordinator?.activate()
    }
    func sceneWillResignActive(_ scene: UIScene) { startup?.setActive(false); coordinator?.deactivate() }
    func sceneDidEnterBackground(_ scene: UIScene) { coordinator?.enteredBackground() }
    func sceneDidDisconnect(_ scene:UIScene) {
        bootstrapTask?.cancel(); startupWindow?.isHidden = true
        startupWindow = nil; startup = nil
    }
}
