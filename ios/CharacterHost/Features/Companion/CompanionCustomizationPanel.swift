import SwiftUI

struct CompanionCustomizationPanel: View {
    let model: ModelDescriptor
    let session: CompanionSession?
    @State var destination: CustomizationDestination? = nil
    var portraits: CharacterPortraitStore? = nil
    @State private var childClose = SoftPanelCloseRequest()
    @Environment(\.softPanelCloseRequest) private var close
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var motion: Animation { .easeInOut(duration:reduceMotion ? 0.18 : 0.28) }
    var body: some View {
        ZStack {
            if let destination {
                page(destination)
                    .environment(\.softPanelCloseRequest,childClose)
                    .environment(\.softPanelDismiss,{ childClose.request() })
                    .id(destination).transition(.opacity).zIndex(1)
            } else { overview.transition(.opacity).zIndex(0) }
        }.softPanelPageSurface()
            .foregroundStyle(Theme.ink).tint(Theme.accent).softSheetSurface()
            .onAppear {
                configureChildBack()
                close?.beforeClose = { childClose.beforeClose?() ?? true }
            }
            .onDisappear { close?.beforeClose = nil; childClose.beforeClose = nil; childClose.onClose = nil }
    }
    private func configureChildBack() {
        childClose.onClose = { withAnimation(motion) { destination = nil } }
    }
    private func open(_ page: CustomizationDestination) {
        childClose = SoftPanelCloseRequest(); configureChildBack()
        withAnimation(motion) { destination = page }
    }
    @ViewBuilder private func page(_ page: CustomizationDestination) -> some View {
        if let session {
            switch page {
            case .memory: CompanionMemoryView(store:session.store,model:model)
            case .history: CompanionHistoryView(session:session,portraits:portraits)
            }
        }
    }
    private var overview: some View {
        VStack(spacing:0) {
            PanelPageHeader(L10n.text("定制我们的相处 · ") + (session?.record.profile.name ?? model.name),backID:"closeCustomizationButton")
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    if session != nil {
                        VStack(spacing:0) {
                            row(.memory)
                            Rectangle().fill(Theme.line.opacity(0.5)).frame(height:0.5).padding(.leading,58)
                            row(.history)
                        }.background(Theme.surface.opacity(0.65),in:RoundedRectangle(cornerRadius:22))

                    }
                }.padding(.horizontal,22).padding(.bottom,24)
            }.scrollIndicators(.hidden).accessibilityIdentifier("customizationSections")
        }
    }
    private func row(_ page:CustomizationDestination) -> some View {
        Button { open(page) } label: {
            HStack(spacing:14) {
                Image(systemName:page.symbol).font(.system(size:18,weight:.light)).frame(width:24).foregroundStyle(Theme.accent)
                VStack(alignment:.leading,spacing:5) {
                    Text(LocalizedStringKey(page.title)).font(.system(size:15,weight:.medium))
                    Text(LocalizedStringKey(page.detail)).font(.system(size:12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName:"chevron.right").font(.system(size:11)).foregroundStyle(Theme.secondary.opacity(0.6))
            }.padding(18).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("customize-" + page.rawValue)
    }
}
