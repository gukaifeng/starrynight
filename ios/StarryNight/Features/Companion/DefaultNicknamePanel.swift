import SwiftUI

struct DefaultNicknamePanel: View {
    let store:CompanionStore
    let models:[ModelDescriptor]
    let portraits:CharacterPortraitStore
    @State private var nickname:String
    @State private var originalNickname:String
    @State private var roleNames:[String:String]
    @State private var originalRoleNames:[String:String]
    @Environment(\.softPanelCloseRequest) private var close
    init(store:CompanionStore,models:[ModelDescriptor]=[],portraits:CharacterPortraitStore) {
        self.store = store
        self.portraits = portraits
        var ids=Set<String>()
        let unique=models.filter{ids.insert($0.id).inserted}
        self.models=unique
        _nickname = State(initialValue:store.defaultNickname)
        _originalNickname = State(initialValue:store.defaultNickname)
        let names=Dictionary(uniqueKeysWithValues:unique.map{($0.id,store.record($0.id).together.preferences.normalized.nickname)})
        _roleNames=State(initialValue:names);_originalRoleNames=State(initialValue:names)
    }
    private var clean:String { TogetherPreferences.cleanNickname(nickname) }
    var body:some View {
        VStack(spacing:0) {
            PanelPageHeader("AI 对我的称呼",backID:"closeDefaultNicknameButton")
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    Text("这里决定角色在聊天中怎样叫你，不会更改你的昵称。没有专属称呼的角色，会使用默认称呼。")
                        .font(.system(size:13)).lineSpacing(5).foregroundStyle(Theme.secondary)
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
                    Text("角色专属称呼会覆盖全局称呼，留空则使用全局称呼。返回时保存。")
                        .font(.system(size:12)).lineSpacing(5).foregroundStyle(Theme.secondary)
                    if !models.isEmpty {
                        Text("各角色的专属称呼").font(.system(size:14,weight:.medium))
                        LazyVStack(spacing:10) {
                            ForEach(models) {model in
                                HStack(spacing:12) {
                                    let profile=store.record(model.id).profile
                                    CharacterAvatar(model:model,profile:profile,portraits:portraits,size:40,floatingEnabled:false)
                                    VStack(alignment:.leading,spacing:8) {
                                        Text(profile.name).font(.system(size:14,weight:.medium))
                                        TextField("留空使用全局默认称呼",text:Binding(get:{roleNames[model.id] ?? ""},set:{roleNames[model.id]=String($0.prefix(20))}))
                                            .font(.system(size:15)).textInputAutocapitalization(.never).submitLabel(.done).onSubmit{save()}
                                            .accessibilityIdentifier("roleNicknameInput-"+model.id)
                                    }
                                }.padding(14).frame(maxWidth:.infinity,alignment:.leading)
                                    .background(Theme.surface.opacity(0.8),in:RoundedRectangle(cornerRadius:16))
                            }
                        }
                    }
                    if !nickname.isEmpty {
                        Button("清空默认称呼") { nickname = "" }
                            .font(.system(size:13)).frame(minHeight:44).accessibilityIdentifier("clearDefaultNickname")
                    }
                    if let error = store.error { Text(LocalizedStringKey(error)).font(.caption).foregroundStyle(Theme.peach) }
                }.padding(.horizontal,22).padding(.bottom,24)
            }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
        }.foregroundStyle(Theme.ink).tint(Theme.accent).softPanelPageSurface()
            .onAppear { close?.beforeClose = { save(); return store.error == nil } }
            .onDisappear { close?.beforeClose = nil }
    }
    private func save() {
        if nickname != originalNickname {store.saveDefaultNickname(nickname);if store.error==nil {nickname=clean;originalNickname=nickname}}
        for model in models where roleNames[model.id] != originalRoleNames[model.id] {
            let value=TogetherPreferences.cleanNickname(roleNames[model.id] ?? "")
            var preferences=store.record(model.id).together.preferences;preferences.nickname=value
            store.saveTogether(preferences,id:model.id)
            if store.error==nil {roleNames[model.id]=value;originalRoleNames[model.id]=value}
        }
    }
}
