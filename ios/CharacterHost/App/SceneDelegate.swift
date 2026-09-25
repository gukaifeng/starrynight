import UIKit
import SwiftUI

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var coordinator: ViewerCoordinator?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let coordinator = ViewerCoordinator(window: window, scene: windowScene)
        self.window = window
        self.coordinator = coordinator
        let controller = UIHostingController(rootView: HomeView(coordinator: coordinator))
        controller.view.backgroundColor = UIColor(Theme.background)
        window.rootViewController = controller
        window.overrideUserInterfaceStyle = .light
        window.makeKeyAndVisible()
        coordinator.activate()
    }
    func sceneDidBecomeActive(_ scene: UIScene) { coordinator?.activate() }
    func sceneWillResignActive(_ scene: UIScene) { coordinator?.deactivate() }
    func sceneDidEnterBackground(_ scene: UIScene) { coordinator?.deactivate() }
}
