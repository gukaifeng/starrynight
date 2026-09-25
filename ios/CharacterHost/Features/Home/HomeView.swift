import SwiftUI

struct HomeView: View {
    @Bindable var coordinator: ViewerCoordinator
    @State private var showingAbout = false
    private let model = ModelDescriptor.robot

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    VStack(alignment: .leading, spacing: 9) {
                        Text("把每一面，\n都看清楚。")
                            .font(.largeTitle.weight(.bold)).tracking(-0.8)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("选择一个模型，开始自由探索。")
                            .font(.subheadline).foregroundStyle(Theme.secondary)
                    }
                    if geometry.size.width > 760 {
                        HStack(spacing: 36) {
                            modelPreview.frame(maxWidth: 490)
                            modelDetails.frame(maxWidth: 350)
                        }
                    } else {
                        VStack(spacing: 0) {
                            modelPreview
                            modelDetails.padding(22).background(.white)
                        }
                        .clipShape(.rect(cornerRadius: 28))
                        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Theme.line.opacity(0.65), lineWidth: 1))
                    }
                    Label("模型已内置，随时离线查看", systemImage: "checkmark.circle")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, geometry.size.width > 760 ? 40 : 24)
                .padding(.top, 12).padding(.bottom, 30)
                .frame(maxWidth: geometry.size.width > 760 ? 1040 : 600)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background.ignoresSafeArea())
            .accessibilityHidden(coordinator.page != .home)
        }
        .foregroundStyle(Theme.ink)
        .sheet(isPresented: $showingAbout) { AboutView() }
        .overlay {
            if coordinator.page == .loading || coordinator.page == .error {
                LoadingView(coordinator: coordinator)
            }
        }
        .preferredColorScheme(.light)
    }
    private var header: some View {
        HStack {
            HStack(spacing: 9) {
                Image(systemName: "cube.transparent.fill").foregroundStyle(Theme.blue).font(.title2)
                Text("模型空间").font(.headline)
            }
            Spacer()
            Button("关于模型空间", systemImage: "info.circle") { showingAbout = true }
                .labelStyle(.iconOnly).font(.title3).foregroundStyle(Theme.secondary)
                .frame(width: 44,height: 44).contentShape(.rect)
                .accessibilityIdentifier("aboutButton")
        }
    }
    private var modelPreview: some View {
        Button(action: coordinator.openViewer) {
            ZStack(alignment: .topLeading) {
                Theme.background
                Image(model.thumbnail).resizable().scaledToFit()
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
                    .accessibilityHidden(true)
                Label("内置模型", systemImage: "cube")
                    .font(.caption.weight(.medium)).foregroundStyle(Theme.ink)
                    .padding(.horizontal,12).padding(.vertical,8)
                    .background(.white.opacity(0.84),in: Capsule())
                    .padding(18)
            }
            .aspectRatio(1.12, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看示例机器人")
        .accessibilityIdentifier("modelCard")
    }
    private var modelDetails: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(alignment: .leading,spacing: 5) {
                Text(model.originalName.uppercased()).font(.caption2.monospaced()).tracking(1.5)
                    .foregroundStyle(Theme.secondary)
                Text(model.name).font(.title2.weight(.bold))
                Text(model.description).font(.subheadline).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: coordinator.openViewer) {
                HStack {
                    Text("打开模型").font(.headline)
                    Spacer()
                    Image(systemName:"arrow.up.right").font(.headline)
                }
                .padding(.horizontal,20).frame(minHeight:54)
                .foregroundStyle(.white).background(Theme.blue,in:RoundedRectangle(cornerRadius:16))
            }
            .buttonStyle(.plain).accessibilityIdentifier("openModelButton")
            .disabled(coordinator.page == .loading)
            HStack(spacing: 18) {
                Label("旋转",systemImage:"hand.draw")
                Label("缩放",systemImage:"arrow.up.left.and.arrow.down.right")
                Label("复位",systemImage:"arrow.counterclockwise")
            }.font(.caption).foregroundStyle(Theme.secondary).frame(maxWidth:.infinity)
        }
    }
}
