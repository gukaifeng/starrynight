import SwiftUI

struct AppRootView: View {
    @Bindable var coordinator: ViewerCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            NightBackdrop()
            if coordinator.stageLoadingVisible {
                // Artwork belongs to the full window, while the identity and
                // dock below keep the same safe-area layout as the live scene.
                GeometryReader { geometry in
                    CharacterCover(model:coordinator.selectedModel)
                        .frame(width:geometry.size.width,height:geometry.size.height).clipped()
                        .overlay {LoadingBreathingScrim().accessibilityHidden(true)}
                }.ignoresSafeArea().allowsHitTesting(false)
                    .accessibilityElement(children:.ignore).accessibilityLabel("角色加载封面")
                    .accessibilityIdentifier("conversationPreparingArtwork")
            } else if coordinator.bundledBackdropVisible && coordinator.visibleShellTab == .home {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hintVisible=false
    @State private var hintTask:Task<Void,Never>?
    private var model: ModelDescriptor { coordinator.selectedModel }
    private var profile: CharacterProfile { coordinator.profile(for:model) }
    private var lastMessage: CompanionMessage? {
        coordinator.companionStore.record(model.id).messages.last { !$0.text.isEmpty && !$0.interrupted }
    }
    var body: some View {
        ZStack {
            VStack(alignment:.leading,spacing:0) {
                CharacterIdentityCapsule(model:model,profile:profile,interactive:false,
                    portraits:coordinator.portraits,library:coordinator.library,onPreparingTap:showHint)
                    .frame(width:CharacterIdentityCapsule.fittingWidth(for:profile.name),height:44)
                    .padding(.top,8).padding(.horizontal,16)
                Spacer(minLength:24)
                if let lastMessage {
                    VStack(alignment:.leading,spacing:10) {
                        Text("上次聊到").font(.system(size:11)).foregroundStyle(Theme.secondary)
                        Text(lastMessage.text).font(.system(size:15)).lineSpacing(5)
                            .lineLimit(4).foregroundStyle(Theme.ink.opacity(0.85))
                    }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
                        .background(Theme.surface.opacity(0.48),in:RoundedRectangle(cornerRadius:22))
                        .accessibilityIdentifier("lastConversationPreview")
                        .padding(.horizontal,22).padding(.bottom,22)
                }
                HStack(spacing:10) {
                    ProgressView().controlSize(.mini).tint(Theme.secondary)
                    Text("\(profile.name)正在来到你身边")
                        .font(.system(size:12)).foregroundStyle(Theme.secondary)
                }.frame(maxWidth:.infinity).padding(.bottom,28)
            }.overlay(alignment:.topLeading) {
                if hintVisible {
                    HStack(alignment:.top,spacing:7) {
                        Image(systemName:"sparkle").font(.system(size:12,weight:.light)).foregroundStyle(Theme.peach).padding(.top,2)
                        Text("马上就能见面啦，\n准备好后，再点这里认识我吧。")
                            .font(.system(size:12)).lineSpacing(3).foregroundStyle(Theme.ink.opacity(0.88))
                    }.padding(.horizontal,12).padding(.vertical,10).fixedSize(horizontal:true,vertical:true)
                        .background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:14))
                        .overlay(RoundedRectangle(cornerRadius:14).stroke(Theme.ink.opacity(0.10),lineWidth:0.5))
                        .shadow(color:.black.opacity(0.12),radius:10,y:4)
                        .accessibilityElement(children:.combine).accessibilityIdentifier("preparingIdentityHint")
                        .padding(.leading,16).padding(.top,60)
                        .transition(.opacity.combined(with:.offset(y:reduceMotion ? 0 : -4)))
                        .allowsHitTesting(false)
                }
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .accessibilityElement(children:.contain).accessibilityIdentifier("conversationPreparing")
            .onDisappear {hintTask?.cancel()}
            .onChange(of:model.id) {hintTask?.cancel();hintVisible=false}
    }
    private func showHint() {
        hintTask?.cancel()
        withAnimation(.easeInOut(duration:reduceMotion ? 0.15 : 0.28)) {hintVisible=true}
        hintTask=Task { @MainActor in
            do {try await Task.sleep(for:.seconds(4))} catch {return}
            withAnimation(.easeInOut(duration:0.3)) {hintVisible=false}
        }
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
