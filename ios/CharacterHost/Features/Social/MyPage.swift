import SwiftUI

struct MyPage: View {
    @Bindable var coordinator:ViewerCoordinator
    @State private var showingSettings = false
    @State private var showingAccount = false
    @State private var showingFollows = false
    @State private var showingSubscriptions = false
    @State private var pendingEntry: (String,Bool)?
    @State private var showingCreations = false
    @State private var showingConversations = false
    @State private var toolsPage:String?
    @State private var showingTools=false
    private var chattedModels:[ModelDescriptor] {
        coordinator.companionStore.currentRecords.filter { !$0.value.messages.isEmpty }.keys
            .compactMap { coordinator.library.model($0) }.sorted {
                let a = coordinator.companionStore.record($0.id).messages.last?.date ?? .distantPast
                let b = coordinator.companionStore.record($1.id).messages.last?.date ?? .distantPast
                return a == b ? $0.id < $1.id : a > b
            }
    }
    private func open(_ id:String) {
        openAuthoredCharacter(id,false)
    }
    private func openAuthoredCharacter(_ id:String,_ customize:Bool) {
        pendingEntry = (id,customize)
        showingFollows = false; showingCreations = false; showingConversations = false
        showingSubscriptions = false
    }
    private func openPendingCharacter() {
        guard let entry = pendingEntry else { return }; pendingEntry = nil
        coordinator.openCharacter(entry.0,customize:entry.1)
    }
    private var signed:Bool { coordinator.account.isSignedIn }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                HStack(alignment:.center,spacing:12) {
                    identity
                    Button { showingSettings = true } label: {
                        Image(systemName:"gearshape").font(.system(size:17,weight:.regular))
                            .foregroundStyle(Theme.secondary)
                            .frame(width:32,height:32).background(Theme.surface.opacity(Theme.controlOpacity),in:Circle())
                            .frame(width:44,height:44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("设置").accessibilityIdentifier("profileSettingsButton")
                }
                Text(signed ? (coordinator.account.cloudSession?.user.profile["bio"]?.string ?? coordinator.library.currentAuthor?.bio ?? "让日常的小事，也有人认真听。") : "先聊一会儿，喜欢的话就留下来。")
                    .font(.system(size:12)).foregroundStyle(Theme.secondary).lineSpacing(3).lineLimit(2)
                    .frame(maxWidth:.infinity,alignment:.leading).accessibilityIdentifier("profileBio")
                HStack(spacing:0) {
                    statistic(coordinator.library.subscriptions.count,title:"订阅",identifier:"mySubscriptionsButton") { showingSubscriptions = true }
                    statistic(coordinator.library.followedAuthors.count,title:"关注",identifier:"myFollowsButton") { showingFollows = true }
                    statistic(coordinator.library.creations.count,title:"角色",identifier:"myCreationsButton") { showingCreations = true }
                    statistic(chattedModels.count,title:"聊过",identifier:"myConversationsButton") { showingConversations = true }
                }.padding(.vertical,4)
                    .background(Theme.surface.opacity(0.35),in:RoundedRectangle(cornerRadius:16))
                if let error = coordinator.library.error { Text(LocalizedStringKey(error)).font(.caption).foregroundStyle(Theme.peach) }
                VStack(spacing:0) {
                    toolRow("存储与缓存",symbol:"internaldrive",page:"storage")
                    toolRow("隐私与数据",symbol:"hand.raised",page:"privacy")
                    toolRow("帮助与反馈",symbol:"questionmark.circle",page:"help")
                }.background(Theme.surface.opacity(0.55),in:RoundedRectangle(cornerRadius:18))
                Text("星夜 · "+(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""))
                    .font(.system(size:10)).foregroundStyle(Theme.secondary.opacity(0.6)).frame(maxWidth:.infinity).padding(.top,4)
            }.padding(.horizontal,24).padding(.top,20).padding(.bottom,20)
        }.scrollIndicators(.hidden)
            .softSheet(isPresented:$showingTools,height:860) {
                NavigationStack {
                    Group {
                        if toolsPage=="storage" {CacheSettingsView(coordinator:coordinator)}
                        else if toolsPage=="privacy" {ProfilePrivacyView(account:coordinator.account)}
                        else {ProfileHelpView(account:coordinator.account)}
                    }.toolbar {ToolbarItem(placement:.topBarLeading) {PanelBackButton(identifier:"closeProfileTools")}}
                }.foregroundStyle(Theme.ink).tint(Theme.accent).softSheetSurface()
            }
            .softSheet(isPresented:$showingSettings,height:860) {
                ProfileSettingsView(coordinator:coordinator,onClose:{ showingSettings = false })
            }
            .softSheet(isPresented:$showingAccount,height:860) {
                NavigationStack {
                    AccountView(account:coordinator.account,onSignOut:{ showingAccount = false; coordinator.account.signOut() },embedded:true)
                        .navigationTitle("账户").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement:.topBarLeading) { PanelBackButton(identifier:"closeAccountButton") } }
                }.softSheetSurface()
            }
            .softSheet(isPresented:$showingSubscriptions,height:860,onDismiss:openPendingCharacter) {
                NavigationStack {
                    ScrollView { subscriptions.padding(20) }.scrollIndicators(.hidden).background(Theme.background)
                        .navigationTitle("订阅的角色").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement:.topBarLeading) { PanelBackButton(identifier:"closeSubscriptionsButton") } }
                }.foregroundStyle(Theme.ink).tint(Theme.accent).softSheetSurface()
            }
            .softSheet(isPresented:$showingFollows,height:860,onDismiss:openPendingCharacter) {
                AuthorDirectoryPanel(kind:.following,library:coordinator.library,store:coordinator.companionStore,
                    portraits:coordinator.portraits,onOpenCharacter:openAuthoredCharacter)
            }
            .softSheet(isPresented:$showingCreations,height:860,onDismiss:openPendingCharacter) {
                MyCreationsPanel(coordinator:coordinator,onOpenCharacter:openAuthoredCharacter) { creations }
            }
            .softSheet(isPresented:$showingConversations,height:860,onDismiss:openPendingCharacter) {
                NavigationStack {
                    ScrollView { conversations.padding(20) }.scrollIndicators(.hidden).background(Theme.background)
                        .navigationTitle("聊过的角色").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement:.topBarLeading) { PanelBackButton(identifier:"closeConversationsButton") } }
                }.foregroundStyle(Theme.ink).tint(Theme.accent).softSheetSurface()
            }.accessibilityElement(children:.contain).accessibilityIdentifier("myPage")
    }
    private var identity:some View {
        Button { if signed { showingAccount = true } else { coordinator.requestLogin() } } label: {
        HStack(spacing:12) {
            if let remote=coordinator.account.cloudSession {UserAccountAvatar(size:56,symbol:remote.user.profile["avatar"]?.string)}
            else if let author = coordinator.library.currentAuthor, signed { AuthorAvatar(author:author,size:56) }
            else { UserAccountAvatar(size:56,signed:signed) }
            VStack(alignment:.leading,spacing:6) {
                HStack(spacing:7) {
                    Text(signed ? coordinator.account.cloudSession?.user.displayName ?? coordinator.library.currentAuthor?.name ?? L10n.text("星夜体验者") : L10n.text("初来星夜"))
                        .font(.system(size:20,weight:.semibold,design:.rounded)).lineLimit(1)
                    Image(systemName:"chevron.right").font(.system(size:9,weight:.medium)).foregroundStyle(Theme.secondary.opacity(0.7))
                }
                Text(signed ? L10n.text("星夜号：") + (coordinator.account.cloudSession.map { $0.user.id } ?? coordinator.account.session?.accountID ?? "") : L10n.text("游客 · 正在开始的故事"))
                    .font(.system(size:10)).foregroundStyle(Theme.secondary).lineLimit(1).accessibilityIdentifier("profileAccountID")
            }.frame(maxWidth:.infinity,alignment:.leading)
        }.padding(.vertical,4).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("accountCenterButton")
            .accessibilityHint(signed ? "打开账户" : "登录星夜")
    }
    private func toolRow(_ title:String,symbol:String,page:String) -> some View {
        Button {toolsPage=page;showingTools=true} label: {
            HStack(spacing:12) {
                Image(systemName:symbol).font(.system(size:16,weight:.regular)).foregroundStyle(Theme.accent).frame(width:22)
                Text(LocalizedStringKey(title)).font(.system(size:13))
                Spacer();Image(systemName:"chevron.right").font(.system(size:9)).foregroundStyle(Theme.secondary)
            }.padding(.horizontal,16).frame(minHeight:50).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("profileTool-"+page)
    }
    private func statistic(_ value:Int,title:String,identifier:String,action:@escaping ()->Void) -> some View {
        Button(action:action) {
            let layout:AnyLayout = AppLanguageSettings.shared.resolved == .english
                ? AnyLayout(VStackLayout(alignment:.center,spacing:3))
                : AnyLayout(HStackLayout(alignment:.firstTextBaseline,spacing:5))
            layout {
                Text("\(value)").font(.system(size:18,weight:.semibold,design:.rounded)).monospacedDigit()
                Text(LocalizedStringKey(title)).font(.system(size:11)).foregroundStyle(Theme.secondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }.frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(identifier).accessibilityLabel("\(value) \(title)")
            .accessibilityHint("查看列表")
    }
    private var conversations:some View {
        LazyVStack(spacing:10) {
            if chattedModels.isEmpty {
                Text("还没有聊过的角色，去认识一个新伙伴吧。").font(.subheadline).foregroundStyle(Theme.secondary).padding(.vertical,20)
                Button("去发现") { showingConversations = false; coordinator.navigate(.discover) }.buttonStyle(NightPrimaryButton())
            }
            ForEach(chattedModels) { model in
                Button { open(model.id) } label: {
                    HStack(spacing:12) {
                        CharacterAvatar(model:model,profile:coordinator.profile(for:model),portraits:coordinator.portraits,size:42)
                        VStack(alignment:.leading,spacing:6) {
                            Text(coordinator.profile(for:model).name).font(.subheadline.weight(.medium))
                            Text(coordinator.companionStore.record(model.id).messages.last?.text ?? "")
                                .font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                        Image(systemName:"chevron.right").font(.system(size:10)).foregroundStyle(Theme.secondary)
                    }.padding(12).background(Theme.surface,in:RoundedRectangle(cornerRadius:18))
                }.buttonStyle(.plain).accessibilityIdentifier("chatted-"+model.id)
            }
        }
    }
    private var subscriptions:some View {
        VStack(spacing:10) {
            if coordinator.library.subscriptions.isEmpty {
                Text("还没有订阅的角色。去发现，遇见一个喜欢的伙伴。").font(.subheadline).foregroundStyle(Theme.secondary).frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,20)
                Button("去发现") { showingSubscriptions = false; coordinator.navigate(.discover) }.buttonStyle(NightPrimaryButton())
            }
            ForEach(coordinator.library.subscriptions,id:\.self) { id in
                if let model = coordinator.library.model(id) {
                    HStack(spacing:12) {
                        Button { open(id) } label: {
                            HStack(spacing:12) {
                                CharacterAvatar(model:model,profile:coordinator.profile(for:model),portraits:coordinator.portraits,size:44)
                                VStack(alignment:.leading,spacing:5) {
                                    Text(coordinator.profile(for:model).name).font(.subheadline.weight(.medium))
                                    Text(L10n.text("作者 · ") + (coordinator.library.author(for:id)?.name ?? "暂不可用")).font(.caption).foregroundStyle(Theme.secondary)
                                }
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }.buttonStyle(.plain)
                        Button("取消订阅") { coordinator.library.subscribe(id,false) }
                            .font(.system(size:11)).foregroundStyle(Theme.secondary).frame(minHeight:44)
                            .accessibilityIdentifier("unsubscribe-"+id)
                    }.padding(12).background(Theme.surface.opacity(Theme.panelOpacity),in:RoundedRectangle(cornerRadius:18))
                } else {
                    HStack(spacing:12) {
                        Image(systemName:"person.crop.circle.badge.questionmark").font(.title2).foregroundStyle(Theme.secondary)
                        VStack(alignment:.leading,spacing:5) {
                            Text("暂不可用的角色").font(.subheadline)
                            Text("作品已收起，聊天记录仍保留。").font(.caption).foregroundStyle(Theme.secondary)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                        Button("取消订阅") { coordinator.library.subscribe(id,false) }.font(.system(size:11)).frame(minHeight:44)
                            .accessibilityIdentifier("unsubscribe-"+id)
                    }.padding(12).background(Theme.surface,in:RoundedRectangle(cornerRadius:18))
                }
            }
            if let error = coordinator.library.error { Text(LocalizedStringKey(error)).font(.caption).foregroundStyle(Theme.peach) }
        }
    }
    private var creations:some View {
        VStack(spacing:12) {
            if coordinator.library.creations.isEmpty {
                Text("把想象里的伙伴，带到身边。").font(.subheadline).foregroundStyle(Theme.secondary).padding(.vertical,20)
                Button("创建角色") { showingCreations = false; coordinator.navigate(.create) }.buttonStyle(NightPrimaryButton())
            }
            ForEach(coordinator.library.creations) { item in
                if let model = coordinator.library.model(item.id) {
                    VStack(alignment:.leading,spacing:8) {
                        HStack {
                            Button(coordinator.profile(for:model).name) { open(item.id) }.font(.subheadline.weight(.medium))
                            Spacer(); Text(item.published ? "本机公开" : "仅自己").font(.caption).foregroundStyle(Theme.secondary)
                        }
                        HStack {
                            Button(item.published ? "设为私有" : "发布到发现") {
                                coordinator.library.publish(item.id,value:!item.published,profile:coordinator.profile(for:model))
                            }.accessibilityIdentifier("publish-"+item.id)
                            Spacer()
                        }.font(.caption).frame(minHeight:38)
                    }.padding(16).background(Theme.surface,in:RoundedRectangle(cornerRadius:18))
                }
            }
        }
    }
}

/// Creator tools live with owned characters, while My keeps account and relationships compact.
/// The public author preview reuses the same panel instead of stacking a second sheet.
private struct MyCreationsPanel<Content:View>:View {
    let coordinator:ViewerCoordinator
    var onOpenCharacter:(String,Bool)->Void
    @ViewBuilder var content:()->Content
    @State private var showingAuthor = false
    @State private var authorClose = SoftPanelCloseRequest()
    @Environment(\.softPanelCloseRequest) private var close
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var motion:Animation { .easeInOut(duration:reduceMotion ? 0.1 : 0.25) }
    var body:some View {
        ZStack {
            if showingAuthor, let author = coordinator.library.currentAuthor {
                AuthorProfilePanel(authorID:author.id,library:coordinator.library,store:coordinator.companionStore,
                    portraits:coordinator.portraits,onOpenCharacter:onOpenCharacter)
                    .environment(\.softPanelCloseRequest,authorClose)
                    .environment(\.softPanelDismiss,{ authorClose.request() }).transition(.opacity)
            } else {
                VStack(spacing:0) {
                    PanelPageHeader("我创建的角色",backID:"closeCreationsButton")
                    ScrollView {
                        VStack(spacing:18) {
                            if coordinator.account.isSignedIn, let author = coordinator.library.currentAuthor {
                                Button {
                                    let nextClose = SoftPanelCloseRequest()
                                    nextClose.begin { withAnimation(motion) { showingAuthor = false } }
                                    authorClose = nextClose
                                    withAnimation(motion) { showingAuthor = true }
                                } label: {
                                    HStack(spacing:10) {
                                        AuthorAvatar(author:author,size:32)
                                        VStack(alignment:.leading,spacing:4) {
                                            Text("我的作者主页").font(.system(size:13,weight:.medium))
                                            Text("个人介绍与公开作品").font(.system(size:11)).foregroundStyle(Theme.secondary)
                                        }
                                        Spacer(minLength:8)
                                        Image(systemName:"chevron.right").font(.system(size:10)).foregroundStyle(Theme.secondary)
                                    }.padding(12).contentShape(Rectangle())
                                        .background(Theme.surface.opacity(0.6),in:RoundedRectangle(cornerRadius:16))
                                }.buttonStyle(.plain).accessibilityIdentifier("myAuthorProfileButton")
                            }
                            content()
                        }.padding(.horizontal,24).padding(.bottom,24)
                    }.scrollIndicators(.hidden)
                }.transition(.opacity)
            }
        }.softPanelPageSurface(opaque:true).foregroundStyle(Theme.ink).tint(Theme.accent).softSheetSurface()
            .onAppear { close?.beforeClose = { authorClose.beforeClose?() ?? true } }
            .onDisappear { close?.beforeClose = nil }
    }
}

struct ProfileSettingsView: View {
    @Bindable var coordinator:ViewerCoordinator
    var onClose:()->Void
    @State private var showingDeveloper = false
    @State private var showingChatDisplay = false
    @State private var showingNickname = false
    @State private var chatDisplayClose = SoftPanelCloseRequest()
    @Environment(\.softPanelCloseRequest) private var close
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var motion:Animation { .easeInOut(duration:reduceMotion ? 0.1 : 0.25) }
    var body:some View {
        ZStack {
            if showingDeveloper {
#if STARRY_TEST_TOOLS
                AppDeveloperPanel(coordinator:coordinator,onOpenCharacter:{id in onClose();coordinator.openCharacter(id)})
                    .environment(\.softPanelCloseRequest,chatDisplayClose)
                    .environment(\.softPanelDismiss,{chatDisplayClose.request()}).transition(.opacity)
#endif
            } else if showingNickname {
                DefaultNicknamePanel(store:coordinator.companionStore)
                    .environment(\.softPanelCloseRequest,chatDisplayClose)
                    .environment(\.softPanelDismiss,{ chatDisplayClose.request() })
                    .transition(.opacity)
            } else if showingChatDisplay {
                ChatDisplayPanel(store:coordinator.companionStore)
                    .environment(\.softPanelCloseRequest,chatDisplayClose)
                    .environment(\.softPanelDismiss,{ chatDisplayClose.request() })
                    .transition(.opacity)
            } else { settings.transition(.opacity) }
        }.softPanelPageSurface(opaque:true)
            .foregroundStyle(Theme.ink).tint(Theme.accent).softSheetSurface()
            .onAppear { close?.beforeClose = { chatDisplayClose.beforeClose?() ?? true } }
            .onDisappear { close?.beforeClose = nil }
    }
    private var settings:some View {
        NavigationStack {
            List {
                Section("我的星夜") {
                    Button {
                        let nextClose = SoftPanelCloseRequest()
                        nextClose.begin { withAnimation(motion) { showingNickname = false } }
                        chatDisplayClose = nextClose
                        withAnimation(motion) { showingNickname = true }
                    } label: {
                        HStack {
                            Label("AI 对我的称呼",systemImage:"text.bubble")
                            Spacer()
                            Text(coordinator.companionStore.defaultNickname.isEmpty ? "未设置" : coordinator.companionStore.defaultNickname)
                                .lineLimit(1).foregroundStyle(Theme.secondary)
                            Image(systemName:"chevron.right").font(.caption).foregroundStyle(Theme.secondary)
                        }
                    }.accessibilityIdentifier("defaultNicknameSettingsButton")
                    Button {
                        let nextClose = SoftPanelCloseRequest()
                        nextClose.begin { withAnimation(motion) { showingChatDisplay = false } }
                        chatDisplayClose = nextClose
                        withAnimation(motion) { showingChatDisplay = true }
                    } label: {
                        HStack {
                            Label("聊天字号",systemImage:"textformat.size")
                            Spacer()
                            Text("\(Int(coordinator.companionStore.chatDisplay.normalized.fontSize))")
                                .foregroundStyle(Theme.secondary)
                            Image(systemName:"chevron.right").font(.caption).foregroundStyle(Theme.secondary)
                        }
                    }.accessibilityIdentifier("chatDisplaySettingsButton")
                    NavigationLink { AppLanguageSettingsView() } label: { Label("语言",systemImage:"globe") }
                        .accessibilityIdentifier("languageSettingsButton")
                    NavigationLink { ThemeSettingsView() } label: { Label("主题与样式",systemImage:"circle.lefthalf.filled") }
                        .accessibilityIdentifier("themeSettingsButton")
                    NavigationLink { CacheSettingsView(coordinator:coordinator) } label: { Label("存储与缓存",systemImage:"internaldrive") }
                        .accessibilityIdentifier("cacheSettingsButton")
                    NavigationLink { AboutView(embedded:true) } label: { Label("关于星夜",systemImage:"info.circle") }
                        .accessibilityIdentifier("aboutStarryButton")
                }.listRowBackground(Theme.surface)
#if STARRY_TEST_TOOLS
                Section {
                    Button {
                        let nextClose=SoftPanelCloseRequest()
                        nextClose.begin {withAnimation(motion) {showingDeveloper=false}}
                        chatDisplayClose=nextClose
                        withAnimation(motion) {showingDeveloper=true}
                    } label: {Label("开发者页面",systemImage:"hammer")}
                        .accessibilityIdentifier("openAppDeveloper")
                }.listRowBackground(Theme.surface)
#endif
                if coordinator.account.isSignedIn && coordinator.account.cloudSession == nil {
                    Section("体验设置") {
                        Button { onClose(); coordinator.account.switchDemoIdentity() } label: {
                            Label("切换到体验身份 " + (coordinator.account.session?.accountID == DemoAccount.id ? "B" : "A"),systemImage:"person.2")
                        }.accessibilityIdentifier("switchDemoIdentity")
                        Text("当前为本机体验。角色订阅、作者关注和对话按身份独立保存，公开作品尚未同步到网络。")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }.listRowBackground(Theme.surface)
                }
            }.scrollContentBackground(.hidden).scrollIndicators(.hidden).background(Theme.background)
                .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.topBarLeading) { PanelBackButton(identifier:"closeSettingsButton") } }
        }.foregroundStyle(Theme.ink).tint(Theme.accent).softSheetSurface()
    }
}
