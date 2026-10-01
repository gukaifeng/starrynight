import SwiftUI
import UIKit

private struct SoftPanelDismissKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable () -> Void = {}
}
extension EnvironmentValues {
    var softPanelDismiss: @MainActor @Sendable () -> Void {
        get { self[SoftPanelDismissKey.self] }
        set { self[SoftPanelDismissKey.self] = newValue }
    }
}

extension View {
    func softSheet<Content:View>(isPresented:Binding<Bool>,height:CGFloat = 720,onDismiss:@escaping () -> Void = {},@ViewBuilder content:@escaping () -> Content) -> some View {
        background {
            SoftSheetPresenter(isPresented:isPresented,height:height,onDismiss:onDismiss,content:content)
                .frame(width:0,height:0).accessibilityHidden(true)
        }
    }
    func softSheet<Item:Identifiable,Content:View>(item:Binding<Item?>,@ViewBuilder content:@escaping (Item) -> Content) -> some View {
        softSheet(isPresented:Binding(get:{ item.wrappedValue != nil },set:{ if !$0 { item.wrappedValue = nil } })) {
            if let value = item.wrappedValue { content(value) }
        }
    }
}

private struct SoftSheetPresenter<Content:View>: UIViewControllerRepresentable {
    @Binding var isPresented:Bool
    var height:CGFloat
    var onDismiss: () -> Void
    @ViewBuilder var content: () -> Content
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context:Context) -> UIViewController {
        let controller = UIViewController(); controller.view.backgroundColor = .clear
        return controller
    }
    func updateUIViewController(_ controller:UIViewController,context:Context) {
        let requested = isPresented
        let coordinator = context.coordinator
        coordinator.binding = $isPresented
        coordinator.onDismiss = onDismiss
        let body = AnyView(content()
            .environment(\.softPanelDismiss,{ [weak coordinator] in coordinator?.close.request() })
            .environment(\.softPanelCloseRequest,coordinator.close)
            .softPanelPageSurface(opaque:true)
            .preferredColorScheme(.dark))
        // Presentation occurs after SwiftUI has finished this update and attached the anchor.
        DispatchQueue.main.async { [weak controller, weak coordinator] in
            guard let controller, let coordinator else { return }
            if requested && coordinator.binding?.wrappedValue == true {
                if let host = coordinator.host {
                    if !host.isBeingDismissed { host.content = body }
                    return
                }
                guard controller.view.window != nil, controller.presentedViewController == nil else { return }
                coordinator.close.begin { [weak coordinator] in coordinator?.binding?.wrappedValue = false }
                coordinator.transition.onDismissRequested = { [weak coordinator] in coordinator?.close.request() }
                let host = LanguageHostingController(rootView:body)
                host.view.backgroundColor = .clear; host.view.isOpaque = false
                host.modalPresentationStyle = .custom; host.transitioningDelegate = coordinator.transition
                host.preferredContentSize = CGSize(width:600,height:height)
                host.presentationController?.delegate = coordinator
                coordinator.host = host
                controller.present(host,animated:true) {
                    if coordinator.binding?.wrappedValue == false { coordinator.dismiss() }
                }
            } else { coordinator.dismiss() }
        }
    }
    static func dismantleUIViewController(_ controller:UIViewController,coordinator:Coordinator) {
        coordinator.host?.dismiss(animated:true)
    }
    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var binding:Binding<Bool>?
        weak var host:LanguageHostingController<AnyView>?
        let transition = SoftSheetTransition()
        let close = SoftPanelCloseRequest()
        var onDismiss: () -> Void = {}
        func dismiss() {
            guard let host, !host.isBeingPresented, !host.isBeingDismissed else { return }
            host.dismiss(animated:true) { [weak self] in
                guard let self else { return }; self.host = nil; self.onDismiss()
            }
        }
        func presentationControllerDidDismiss(_ presentationController:UIPresentationController) {
            host = nil; binding?.wrappedValue = false
            onDismiss()
        }
    }
}
