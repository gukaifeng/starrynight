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
                    if coordinator.stageLoadingVisible && !coordinator.startupInProgress {
                        CharacterArrivalView(name:coordinator.profile(for:coordinator.selectedModel).name)
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
