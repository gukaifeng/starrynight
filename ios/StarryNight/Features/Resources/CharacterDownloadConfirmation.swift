import SwiftUI
import UIKit

/// An explicit, slightly wider confirmation that keeps the profile and Unity
/// surface underneath intact. UIKit owns the full-window overlay/hit boundary.
struct CharacterDownloadConfirmationPresenter:UIViewControllerRepresentable {
    @Binding var isPresented:Bool
    let name,size:String
    let onDownload:()->Void
    func makeCoordinator()->Coordinator {Coordinator()}
    func makeUIViewController(context:Context)->UIViewController {
        let controller=UIViewController();controller.view.backgroundColor = .clear;return controller
    }
    func updateUIViewController(_ controller:UIViewController,context:Context) {
        let coordinator=context.coordinator
        coordinator.binding=$isPresented;coordinator.onDownload=onDownload
        let requested=isPresented
        DispatchQueue.main.async { [weak controller,weak coordinator] in
            guard let controller,let coordinator else {return}
            if requested && coordinator.binding?.wrappedValue == true {
                guard coordinator.host == nil,controller.view.window != nil,controller.presentedViewController == nil else {return}
                let host=LanguageHostingController(rootView:CharacterDownloadConfirmation(name:name,size:size) { [weak coordinator] confirmed in
                    coordinator?.dismiss(confirmed:confirmed)
                }.preferredColorScheme(.dark))
                host.view.backgroundColor = .clear;host.view.isOpaque=false
                host.modalPresentationStyle = .overFullScreen
                host.view.accessibilityViewIsModal=true
                coordinator.host=host;controller.present(host,animated:false)
            } else {coordinator.dismiss(confirmed:false)}
        }
    }
    static func dismantleUIViewController(_ controller:UIViewController,coordinator:Coordinator) {coordinator.dismiss(confirmed:false)}
    @MainActor final class Coordinator:NSObject {
        var binding:Binding<Bool>?
        weak var host:UIViewController?
        var onDownload:(()->Void)?
        func dismiss(confirmed:Bool) {
            guard let host,!host.isBeingDismissed else {return}
            binding?.wrappedValue=false
            host.dismiss(animated:false) { [weak self] in
                guard let self else {return};self.host=nil
                if confirmed {self.onDownload?()}
            }
        }
    }
}

private struct CharacterDownloadConfirmation:View {
    let name,size:String
    let onDismiss:(Bool)->Void
    @State private var visible=false
    @State private var closing=false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var titleFocused:Bool
    private var animation:Animation {.easeInOut(duration:reduceMotion ? 0.15 : 0.28)}
    var body:some View {
        ZStack {
            Color.black.opacity(visible ? 0.55 : 0).ignoresSafeArea()
                .contentShape(Rectangle()).onTapGesture {dismiss(false)}.accessibilityHidden(true)
            VStack(alignment:.leading,spacing:16) {
                HStack(spacing:10) {
                    Image(systemName:"arrow.down.circle").font(.system(size:22,weight:.light)).foregroundStyle(Theme.accent)
                    Text("下载「\(name)」").font(.system(size:17,weight:.semibold))
                        .accessibilityAddTraits(.isHeader).accessibilityFocused($titleFocused)
                    Spacer(minLength:0)
                }
                Text("包含模型、动作、背景和声音，需要约 \(size) 下载流量及额外安装空间。建议使用 Wi-Fi，并保持 App 打开。下载过程中可以取消，完成后无需再次下载。")
                    .font(.system(size:13)).lineSpacing(4).foregroundStyle(Theme.secondary).fixedSize(horizontal:false,vertical:true)
                HStack(spacing:10) {
                    Button("暂不下载") {dismiss(false)}.frame(maxWidth:.infinity,minHeight:44)
                        .background(Theme.card,in:Capsule()).accessibilityIdentifier("cancelCharacterDownloadConfirmation")
                    Button("下载 · \(size)") {dismiss(true)}.frame(maxWidth:.infinity,minHeight:44)
                        .background(Theme.accent.opacity(0.18),in:Capsule()).foregroundStyle(Theme.accent)
                        .accessibilityIdentifier("confirmCharacterDownload")
                }.font(.system(size:13,weight:.medium)).buttonStyle(.plain)
            }.padding(22).frame(maxWidth:350).background(Theme.surface,in:RoundedRectangle(cornerRadius:24))
                .overlay(RoundedRectangle(cornerRadius:24).stroke(Theme.line.opacity(0.4),lineWidth:0.5))
                .padding(.horizontal,28).opacity(visible ? 1 : 0).offset(y:visible || reduceMotion ? 0 : 10)
                .accessibilityElement(children:.contain)
                .accessibilityIdentifier("characterDownloadConfirmationCard")
        }.foregroundStyle(Theme.ink).disabled(closing).accessibilityElement(children:.contain)
            .accessibilityAddTraits(.isModal).accessibilityIdentifier("characterDownloadConfirmation")
            .onAppear {withAnimation(animation) {visible=true};titleFocused=true}
            .accessibilityAction(.escape) {dismiss(false)}
    }
    private func dismiss(_ confirmed:Bool) {
        guard !closing else {return};closing=true
        withAnimation(animation,completionCriteria:.logicallyComplete) {visible=false} completion: {onDismiss(confirmed)}
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Isolated presentation check: confirmation calls a counter, never a download.
struct CharacterDownloadConfirmationCheckView:View {
    @State private var presented=false
    @State private var accepted=0
    var body:some View {
        VStack(spacing:20) {
            Text("下载确认检查").font(.title3)
            Button("下载角色，开始相处") {presented=true}.accessibilityIdentifier("showDownloadConfirmationCheck")
            Text("\(accepted)").accessibilityIdentifier("downloadConfirmationAccepted")
        }.frame(maxWidth:.infinity,maxHeight:.infinity).foregroundStyle(Theme.ink).background(Theme.background)
            .background {
                CharacterDownloadConfirmationPresenter(isPresented:$presented,name:"Fiona",size:"128 MB") {accepted+=1}
                    .frame(width:0,height:0).accessibilityHidden(true)
            }
    }
}
#endif
