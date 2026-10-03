import UIKit
import SwiftUI

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var coordinator: ViewerCoordinator?
    private var startupWindow:UIWindow?
    private var startup:AppStartupController?
    private var bootstrapTask:Task<Void,Never>?
    private var isolatedGoalFixture = false
    private var isolatedModelReviewCheck = false

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        CharacterModelReview.configure()
        LaunchTrace.begin()
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        let placeholder = UIViewController()
        placeholder.view.backgroundColor = AppStartupController.night
        window.rootViewController = placeholder
        window.overrideUserInterfaceStyle = .dark
        window.makeKeyAndVisible()
#if STARRY_TEST_TOOLS
        if ProcessInfo.processInfo.arguments.contains("--model-review-core-check") {
            isolatedModelReviewCheck = true
            let label=UILabel();label.numberOfLines=0;label.textColor = .white
            label.frame=CGRect(x:24,y:100,width:window.bounds.width-48,height:400)
            label.accessibilityIdentifier="modelReviewCoreResult"
            do {
                let result=try CharacterModelReviewTests.run()+"\n"+CharacterAudioUpgradeTests.run()
                label.text=result
                let report:[String:Any] = ["result":result,"previewModels":ModelDescriptor.all.filter(\.isPreviewOnly).map(\.id),
                    "conversationModels":ModelDescriptor.all.filter {!$0.isPreviewOnly}.map(\.id),
                    "models":ModelDescriptor.all.map(\.id)]
                let file=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
                    .appendingPathComponent("model-review-core-check.json")
                try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]).write(to:file,options:.atomic)
            } catch {label.text="FAIL: \(error)"}
            placeholder.view.addSubview(label);return
        }
        if ProcessInfo.processInfo.arguments.contains("--connection-check") {
            window.rootViewController=LanguageHostingController(rootView:AIConnectionDiagnostics());return
        }
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--voice-timeline-review") {
            Task { @MainActor in
                for _ in 0..<100 {
                    if let record=VoiceTimeline.shared.records.last(where:{$0.account.hasPrefix("audio-regression:") && $0.marks["first_output"] != nil}) {
                        window.rootViewController=LanguageHostingController(rootView:VoiceTimingPanel(account:record.account,initialSelection:record.id));return
                    }
                    try? await Task.sleep(for:.milliseconds(20))
                }
            }
            return
        }
#endif
#endif
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--download-confirmation-check") {
            isolatedGoalFixture=true
            window.rootViewController=LanguageHostingController(rootView:CharacterDownloadConfirmationCheckView())
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--developer-float-check") {
            isolatedGoalFixture=true
            let folder=FileManager.default.temporaryDirectory.appendingPathComponent("developer-float-\(UUID())/journal.json")
            let session=CompanionSession(store:CompanionStore(storageURL:folder,arguments:[]),model:.defaultCharacter,soundscape:CompanionSoundscape())
            let controller=ViewerOverlayController()
            controller.setModel(.defaultCharacter);controller.setCompanion(session)
            window.rootViewController=controller
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--goal-page-fixture") {
            isolatedGoalFixture = true
            let store=CompanionStore()
            let model=ModelDescriptor.all.first { $0.id=="anime-ichigo" } ?? ModelDescriptor.defaultCharacter
            let session=CompanionSession(store:store,model:model,soundscape:CompanionSoundscape())
            window.rootViewController=LanguageHostingController(rootView:TogetherPanel(session:session).preferredColorScheme(.dark))
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--language-check") {
            window.rootViewController=LanguageHostingController(rootView:AppLanguageFixture());return
        }
        if ProcessInfo.processInfo.arguments.contains("--opening-check") {
            let label=UILabel();label.numberOfLines=0;label.textColor = .white
            label.frame=CGRect(x:24,y:100,width:window.bounds.width-48,height:450)
            label.accessibilityIdentifier="openingCheckResult";label.text="Checking bundled first meetings"
            placeholder.view.addSubview(label)
            Task {
                do {label.text=try await CharacterOpeningChecks.run()}
                catch {label.text="FAIL: \(error.localizedDescription)"}
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--voice-atmosphere-check") {
            window.rootViewController=LanguageHostingController(rootView:VoiceAtmosphereFixture());return
        }
        if ProcessInfo.processInfo.arguments.contains("--reply-flow-check") {
            window.rootViewController=LanguageHostingController(rootView:ReplyFlowFixture());return
        }
        if ProcessInfo.processInfo.arguments.contains("--conversation-presentation-check") {
            window.rootViewController=LanguageHostingController(rootView:ConversationPresentationFixture())
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
        if ProcessInfo.processInfo.arguments.contains("--character-resource-check") {
            let label=UILabel();label.numberOfLines=0;label.textColor = .white
            label.frame=CGRect(x:24,y:100,width:window.bounds.width-48,height:450)
            label.accessibilityIdentifier="characterResourceCheckResult";label.text="正在检查角色资源…"
            placeholder.view.addSubview(label)
            Task {do {label.text=try await CharacterResourceChecks.run()}catch {label.text="FAIL: \(error)"}}
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
            let controller = LanguageHostingController(rootView: ConversationExportView(snapshot: ConversationExportTests.fixture()).preferredColorScheme(.dark))
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
        guard !isolatedGoalFixture, !isolatedModelReviewCheck else { return }
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains(where: { ["--character-resource-check", "--language-check", "--opening-check", "--voice-atmosphere-check", "--reply-flow-check", "--conversation-presentation-check", "--chat-input-check", "--speech-playback-check", "--voice-timeline-review", "--greeting-core-check", "--view-presets-check", "--experience-core-check", "--export-core-check", "--export-ui-check", "--social-core-check", "--cache-core-check", "--market-core-check"].contains($0) }) { return }
#endif
#if STARRY_TEST_TOOLS
        if ProcessInfo.processInfo.arguments.contains("--connection-check") {return}
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
            let controller = LanguageHostingController(rootView:AppRootView(coordinator:coordinator))
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
