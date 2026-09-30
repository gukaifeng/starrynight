import SwiftUI

struct AppRootView: View {
    @Bindable var coordinator: ViewerCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            NightBackdrop()
            if coordinator.bundledBackdropVisible && coordinator.visibleShellTab == .home {
                GeometryReader { geometry in
                    if geometry.size.height > geometry.size.width {
                        Image("FirstCompanionBackdrop").resizable().scaledToFill()
                            .frame(width:geometry.size.width,height:geometry.size.height).clipped()
                            .accessibilityLabel("初始角色场景").accessibilityIdentifier("firstCompanionBackdrop")
                    }
                }.ignoresSafeArea().allowsHitTesting(false)
            }
            VStack(spacing:0) {
                Group {
                    if coordinator.stageLoadingVisible {
                        ConversationPreparingCover(coordinator:coordinator)
                    } else { switch coordinator.visibleShellTab {
                    case .home: ConversationLanding(coordinator:coordinator)
                    case .messages: MessagesPage(coordinator:coordinator)
                    case .create: CreateCharacterPage(coordinator:coordinator)
                    case .discover: DiscoverPage(coordinator:coordinator)
                    case .mine: MyPage(coordinator:coordinator)
                    } }
                }.frame(maxWidth:.infinity,maxHeight:.infinity).transition(.opacity)
                AppDock(selection:coordinator.visibleShellTab,onSelect:coordinator.navigate)
            }
        }.foregroundStyle(Theme.ink).tint(Theme.accent).preferredColorScheme(.dark)
            .animation(.easeInOut(duration:reduceMotion ? 0.15 : 0.25),value:coordinator.selectedTab)
            .softSheet(isPresented:$coordinator.loginPresented) {
                NavigationStack {
                    LoginView(account:coordinator.account)
                        .navigationTitle("登录星夜").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement:.topBarLeading) { PanelBackButton(identifier:"closeLoginButton") } }
                }.softSheetSurface()
            }
            .task { coordinator.startShell() }
            .onChange(of:coordinator.account.session) { _,_ in coordinator.accountChanged() }
    }
}

/// Native content is usable before Unity starts. Only bundled artwork and the
/// existing local transcript are read here; no network request or fake reply.
private struct ConversationPreparingCover: View {
    let coordinator: ViewerCoordinator
    private var model: ModelDescriptor { coordinator.selectedModel }
    private var profile: CharacterProfile { coordinator.profile(for:model) }
    private var lastMessage: CompanionMessage? {
        coordinator.companionStore.record(model.id).messages.last { !$0.text.isEmpty && !$0.interrupted }
    }
    var body: some View {
        ZStack {
            CharacterCover(model:model).opacity(0.3)
                .mask(LinearGradient(colors:[.clear,.white,.white.opacity(0.2),.clear],
                    startPoint:.top,endPoint:.bottom))
                .allowsHitTesting(false)
                .accessibilityIdentifier("conversationPreparingCover-"+model.id)
            VStack(alignment:.leading,spacing:0) {
                HStack(spacing:9) {
                    CharacterAvatar(model:model,profile:profile,portraits:coordinator.portraits,
                                    size:28,floatingEnabled:false)
                    Text(profile.name).font(.system(size:14,weight:.medium)).lineLimit(1)
                }.padding(.leading,9).padding(.trailing,14).padding(.vertical,7)
                    .background(Theme.surface.opacity(Theme.controlOpacity),in:Capsule())
                    .overlay(Capsule().stroke(Theme.ink.opacity(0.09),lineWidth:0.5))
                    .padding(.top,8)
                Spacer(minLength:24)
                if let lastMessage {
                    VStack(alignment:.leading,spacing:10) {
                        Text("上次聊到").font(.system(size:11)).foregroundStyle(Theme.secondary)
                        Text(lastMessage.text).font(.system(size:15)).lineSpacing(5)
                            .lineLimit(4).foregroundStyle(Theme.ink.opacity(0.85))
                    }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
                        .background(Theme.surface.opacity(0.48),in:RoundedRectangle(cornerRadius:22))
                        .accessibilityIdentifier("lastConversationPreview")
                        .padding(.bottom,22)
                }
                HStack(spacing:10) {
                    ProgressView().controlSize(.mini).tint(Theme.secondary)
                    Text("\(profile.name)正在来到你身边")
                        .font(.system(size:12)).foregroundStyle(Theme.secondary)
                }.frame(maxWidth:.infinity).padding(.bottom,28)
            }.padding(.horizontal,22)
        }.accessibilityElement(children:.contain).accessibilityIdentifier("conversationPreparing")
    }
}
private struct ConversationLanding: View {
    @Bindable var coordinator:ViewerCoordinator
    var body:some View {
        VStack(spacing:0) {
            if coordinator.library.lastCharacter != nil {
                // A retained conversation resumes directly. Only a new scene uses the
                // arrival canvas above; errors keep an explicit way back to discovery.
                ZStack {
                    Color.clear
                    if coordinator.page == .error {
                        LoadingView(failed:true,errorMessage:coordinator.errorMessage) { coordinator.navigate(.discover) }
                            .padding(24)
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                NightEmptyState(symbol:"sparkle",title:"这里，留给你的伙伴",detail:coordinator.library.subscriptions.isEmpty ? "还没有订阅的角色。\n去发现一个，或用中间的 ＋ 创造自己的角色。" : "已订阅的角色暂时不可用。\n可以先去发现，遇见新的伙伴。",actionTitle:"去发现角色") { coordinator.navigate(.discover) }

            }
            if let error = coordinator.library.error ?? coordinator.companionStore.error { Text(error).font(.caption).foregroundStyle(Theme.peach).padding() }
        }
    }
}
