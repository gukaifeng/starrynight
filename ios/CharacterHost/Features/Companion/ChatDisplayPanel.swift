import SwiftUI

struct ChatDisplayPanel: View {
    @Bindable var store: CompanionStore
    @Environment(\.softPanelCloseRequest) private var close
    var body: some View {
        VStack(spacing:0) {
            PanelPageHeader("聊天字号",backID:"closeChatDisplayButton")
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    VStack(alignment:.leading,spacing:7) {
                        Text("让每句话，都读得舒服。").font(.title2.weight(.medium))
                        Text("所有角色共用，切换账号也会保留。")
                            .font(.subheadline).foregroundStyle(Theme.secondary)
                    }
                    VStack(alignment:.leading,spacing:12) {
                        HStack {
                            Text("聊天字号").font(.headline)
                            Spacer()
                            Text("\(Int(store.chatDisplay.fontSize))")
                                .monospacedDigit().accessibilityIdentifier("chatFontValue")
                        }
                        Slider(value:$store.chatDisplay.fontSize,in:14...24,step:1)
                            .accessibilityLabel("聊天字号").accessibilityIdentifier("chatFontSlider")
                        Text("你慢慢说，我在听。")
                            .font(.system(size:store.chatDisplay.normalized.fontSize)).lineSpacing(5)
                            .padding(16).frame(maxWidth:.infinity,alignment:.leading)
                            .background(Theme.surface.opacity(0.65),in:RoundedRectangle(cornerRadius:22))
                            .accessibilityIdentifier("chatFontPreview")
                        Text("消息、回复、输入文字和聊天记录会一起调整。")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                    Button("恢复默认") { store.chatDisplay = ChatDisplaySettings() }
                        .frame(minHeight:44).accessibilityIdentifier("resetChatDisplayButton")
                }.padding(.horizontal,22).padding(.bottom,24)
            }.scrollIndicators(.hidden).background(Color.clear).accessibilityIdentifier("chatDisplayScroll")
        }.foregroundStyle(Theme.ink).tint(Theme.accent).softPanelPageSurface()
            .onChange(of:store.chatDisplay) { _ = store.saveChatDisplay() }
            .onAppear { close?.beforeClose = { store.saveChatDisplay() } }
            .onDisappear { close?.beforeClose = nil }
    }
}
