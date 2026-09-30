import SwiftUI

struct DefaultNicknamePanel: View {
    let store:CompanionStore
    @State private var nickname:String
    @Environment(\.softPanelCloseRequest) private var close
    init(store:CompanionStore) {
        self.store = store
        _nickname = State(initialValue:store.defaultNickname)
    }
    private var clean:String { TogetherPreferences.cleanNickname(nickname) }
    var body:some View {
        VStack(spacing:0) {
            PanelPageHeader("AI 对我的称呼",backID:"closeDefaultNicknameButton")
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    VStack(alignment:.leading,spacing:8) {
                        Text("一个熟悉的称呼，让相处更亲近。")
                            .font(.system(size:21,weight:.medium,design:.rounded))
                        Text("为当前账号设置默认称呼。没有专属称呼的角色，都会使用它。")
                            .font(.system(size:13)).lineSpacing(4).foregroundStyle(Theme.secondary)
                    }
                    VStack(alignment:.leading,spacing:12) {
                        HStack {
                            Text("全局默认称呼").font(.system(size:14,weight:.medium))
                            Spacer()
                            Text("\(clean.count)/20").font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary)
                        }
                        TextField("你希望被怎样称呼",text:$nickname)
                            .font(.system(size:17)).textInputAutocapitalization(.never)
                            .submitLabel(.done).onSubmit { save() }
                            .accessibilityIdentifier("defaultNicknameInput")
                        Text(clean.isEmpty ? "留空时，角色会自然地与你交谈。" : "默认称呼你为「\(clean)」")
                            .font(.system(size:12)).foregroundStyle(Theme.secondary)
                            .accessibilityIdentifier("defaultNicknamePreview")
                    }.padding(18).background(Theme.surface.opacity(0.8),in:RoundedRectangle(cornerRadius:20))
                    Text("想让某个角色有不同的叫法？在角色资料的「相处与剧情 → 相处」中设置专属称呼。专属称呼优先，清空后重新使用这里的默认值。返回时保存。")
                        .font(.system(size:12)).lineSpacing(5).foregroundStyle(Theme.secondary)
                    if !nickname.isEmpty {
                        Button("清空默认称呼") { nickname = "" }
                            .font(.system(size:13)).frame(minHeight:44).accessibilityIdentifier("clearDefaultNickname")
                    }
                    if let error = store.error { Text(error).font(.caption).foregroundStyle(Theme.peach) }
                }.padding(.horizontal,22).padding(.bottom,24)
            }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
        }.foregroundStyle(Theme.ink).tint(Theme.accent).softPanelPageSurface()
            .onAppear { close?.beforeClose = { save(); return store.error == nil } }
            .onDisappear { close?.beforeClose = nil }
    }
    private func save() { store.saveDefaultNickname(nickname); nickname = clean }
}
