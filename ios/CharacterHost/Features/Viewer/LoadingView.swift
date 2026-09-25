import SwiftUI

struct LoadingView: View {
    var coordinator: ViewerCoordinator
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing:22) {
                Image(systemName:coordinator.page == .error ? "exclamationmark.triangle" : "cube.transparent")
                    .font(.largeTitle).foregroundStyle(Theme.blue)
                Text(coordinator.page == .error ? "暂时无法打开模型" : "正在准备模型")
                    .font(.title2.bold())
                Text(coordinator.page == .error ? coordinator.errorMessage : "第一次打开需要一点时间")
                    .font(.subheadline).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                if coordinator.page == .loading { ProgressView().tint(Theme.blue) }
                Button(action:coordinator.closeViewer) {
                    Text("返回首页").font(.headline).frame(minWidth:160,minHeight:48)
                }
                    .buttonStyle(.borderedProminent).tint(Theme.blue)
                    .accessibilityIdentifier("cancelLoadingButton")
            }.padding(32)
        }
    }
}
