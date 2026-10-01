import SwiftUI

struct CharacterAvatar: View {
    let model: ModelDescriptor
    let profile: CharacterProfile
    let portraits: CharacterPortraitStore
    var size: CGFloat
    var floatingEnabled = true
    var speaking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false
    var body: some View {
        ZStack {
            if speaking {
                if reduceMotion {
                    Circle().stroke(Theme.accent.opacity(0.55),lineWidth:1).padding(-4)
                } else { AvatarVoiceRipples().padding(-1).allowsHitTesting(false) }
            }
            Group {
                if let definition=CharacterCoverDefinition.find(model),let head=definition.headBounds,
                   let cover=UIImage(named:definition.asset) {
                    CharacterFocusedArtwork(artwork:cover,head:head,circle:true)
                } else {
                    Image(uiImage:portraits.image(model,profile:profile) ?? UIImage(named:model.thumbnail+"Portrait") ?? UIImage(named:model.thumbnail) ?? UIImage())
                        .resizable().scaledToFill()
                }
            }.frame(width:size,height:size)
                .clipShape(Circle()).overlay(Circle().stroke(Theme.accent.opacity(0.24),lineWidth:0.7))
                .offset(y:floatingEnabled && !reduceMotion && floating ? -1 : 0)
        }.frame(width:size,height:size).accessibilityHidden(true)
            .onAppear {
                if floatingEnabled && !reduceMotion {
                    withAnimation(.easeInOut(duration:4.2).repeatForever(autoreverses:true)) { floating = true }
                }
            }
    }
}

private struct AvatarVoiceRipples: View {
    @State private var started = Date()
    var body: some View {
        TimelineView(.animation(minimumInterval:1.0/30)) { context in
            let elapsed = max(0,context.date.timeIntervalSince(started)) / 1.8
            ZStack {
                ForEach(0..<2) { index in
                    let progress = (elapsed + Double(index)*0.5).truncatingRemainder(dividingBy:1)
                    Circle().stroke(Theme.accent.opacity(0.48*(1-progress)),lineWidth:0.8)
                        .scaleEffect(1+progress*0.65)
                }
            }
        }
    }
}

@MainActor @Observable final class CharacterIdentityDiagnostics {var value:String?}

struct CharacterConversationIdentity:View {
    static func fittingWidth(for name:String)->CGFloat {CharacterIdentityCapsule.fittingWidth(for:name)}
    let session:CompanionSession
    let portraits:CharacterPortraitStore
    let library:CharacterLibrary
    let diagnostics:CharacterIdentityDiagnostics
    var onDetails:()->Void
    var body:some View {
        CharacterIdentityCapsule(model:session.model,profile:session.record.profile,speaking:session.speech.isSpeaking,
            portraits:portraits,library:library,diagnostics:diagnostics,onDetails:onDetails)
            .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.leading)
    }
}

struct CharacterIdentityCapsule: View {
    private static var subscriptionWidth:CGFloat {AppLanguageSettings.shared.resolved == .english ? 64 : 46}
    static func fittingWidth(for name:String) -> CGFloat {
        let text = (name as NSString).size(withAttributes:[.font:UIFont.systemFont(ofSize:13,weight:.medium)]).width
        return ceil(text + 24 + 7 + 8 + 7 + subscriptionWidth + 0.5)
    }
    let model:ModelDescriptor
    let profile:CharacterProfile
    var speaking=false
    var interactive=true
    let portraits: CharacterPortraitStore
    let library:CharacterLibrary
    var onPreparingTap:(()->Void)? = nil
    var diagnostics:CharacterIdentityDiagnostics? = nil
    var onDetails:()->Void = {}
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var subscribed:Bool {library.subscriptions.contains(model.id)}
    @ViewBuilder var body: some View {
        if interactive {
            capsule.accessibilityElement(children:.contain)
                .accessibilityIdentifier("conversationIdentityCapsule")
        } else if let onPreparingTap {
            Button(action:onPreparingTap) {capsule.accessibilityHidden(true)}
                .buttonStyle(.plain).accessibilityLabel(profile.name+"，正在准备会话，轻点查看提示")
                .accessibilityIdentifier("preparingIdentityButton")
        } else {
            capsule.allowsHitTesting(false).accessibilityElement(children:.ignore)
                .accessibilityLabel(profile.name+"，正在准备会话")
                .accessibilityIdentifier("preparingIdentityCapsule")
        }
    }
    private var capsule:some View {
        HStack(spacing:0) {
            if interactive {
                Button(action:onDetails) {identityLabel}
                    .buttonStyle(.plain).accessibilityIdentifier("customizationButton")
                    .accessibilityLabel(profile.name+"，查看角色资料")
                    .accessibilityValue(diagnostics?.value ?? "")
            } else {identityLabel}
            Rectangle().fill(Theme.ink.opacity(0.13)).frame(width:0.5,height:13)
            if subscribed {
                Text("已订阅").font(.system(size:10)).foregroundStyle(Theme.ink.opacity(0.38))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width:Self.subscriptionWidth,height:44).accessibilityIdentifier("capsuleSubscribed")
            } else {
                if interactive {
                    Button {library.subscribe(model.id,true)} label: {subscribeLabel}
                        .buttonStyle(.plain).accessibilityIdentifier("capsuleSubscribeButton")
                        .accessibilityLabel("订阅"+profile.name)
                } else {subscribeLabel}
            }
        }.background { Capsule().fill(Theme.surface.opacity(reduceTransparency ? 1 : Theme.controlOpacity)).frame(height:36) }
            .overlay(Capsule().stroke(LinearGradient(colors:[.white.opacity(0.16),.white.opacity(0.035)],
                startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:0.5).frame(height:36).allowsHitTesting(false))
            .shadow(color:.black.opacity(0.12),radius:7,y:3)
    }
    private var identityLabel:some View {
        HStack(spacing:7) {
            CharacterAvatar(model:model,profile:profile,portraits:portraits,
                size:24,floatingEnabled:false,speaking:speaking)
            Text(profile.name).font(.system(size:13,weight:.medium)).lineLimit(1)
                .foregroundStyle(Theme.ink.opacity(0.9)).minimumScaleFactor(0.85)
        }.padding(.leading,8).padding(.trailing,7).frame(height:44).contentShape(Rectangle())
    }
    private var subscribeLabel:some View {
        Text("+ 订阅").font(.system(size:11,weight:.medium)).foregroundStyle(Theme.accent.opacity(0.85))
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(width:Self.subscriptionWidth,height:44).contentShape(Rectangle())
    }
}

/// The same identity card is used by discovery and the live character header.
/// Editing stays in the existing sheet; its back button returns to this card.
struct CharacterDetailsPanel: View {
    let model: ModelDescriptor
    let store: CompanionStore
    let library: CharacterLibrary
    let portraits: CharacterPortraitStore
    var showsLiveCharacter = false
    var onChat: () -> Void
    var onCustomize: () -> Void = {}
    var customization: (() -> AnyView)? = nil
    var session: CompanionSession? = nil
    var performanceState: CharacterPerformanceState? = nil
    var onSelectPerformance: (String,Bool) -> Void = { _,_ in }
    var onResetPerformance: (String) -> Void = { _ in }
    var onAdjustPerformance: (String,Double) -> Void = { _,_ in }
    var onPerformanceVisibility: (Bool) -> Void = { _ in }
    var onOpenCharacter: ((String,Bool) -> Void)? = nil
    var allowsAuthorNavigation = true
    @State private var editing = false
    @State private var together = false
    @State private var imageExport: ConversationExportSnapshot?
    @State private var showingAuthor = false
    @State private var showingCredits = false
    @State private var showingDeveloper = false
    @State private var confirmingUnsubscribe = false
    @State private var loadedPublicProfile:CharacterPublicProfile?
    @State private var editorClose = SoftPanelCloseRequest()
    @Environment(\.softPanelCloseRequest) private var close
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var profile:CharacterProfile {
        model.conversationProfile(preserving:store.contains(model.id) ? store.record(model.id).profile : nil)
    }
    private var subscribed:Bool { library.subscriptions.contains(model.id) }
    private var publicProfile:CharacterPublicProfile? {loadedPublicProfile ?? CharacterPublicProfile.find(model.id)}
    private var motion:Animation { .easeInOut(duration:reduceMotion ? 0.15 : 0.28) }
    var body: some View {
        ZStack(alignment:.topLeading) {
            if showingDeveloper {
#if STARRY_TEST_TOOLS
                CharacterDeveloperPanel(model:model,store:store,session:session,performanceState:performanceState,
                    onSelect:onSelectPerformance,onReset:onResetPerformance,onAdjust:onAdjustPerformance,
                    onVisibility:onPerformanceVisibility,onOpenConversation:{onChat()})
                    .environment(\.softPanelCloseRequest,editorClose)
                    .environment(\.softPanelDismiss,{editorClose.request()}).transition(.opacity)
#endif
            } else if showingAuthor, let author = library.author(for:model.id) {
                AnyView(AuthorProfilePanel(authorID:author.id,library:library,store:store,portraits:portraits,
                    onOpenCharacter:{ id,customize in onOpenCharacter?(id,customize) }))
                    .environment(\.softPanelCloseRequest,editorClose)
                    .environment(\.softPanelDismiss,{ editorClose.request() }).transition(.opacity)
            } else if showingCredits {
                CharacterSourceCreditsView(model:model).environment(\.softPanelCloseRequest,editorClose)
                    .environment(\.softPanelDismiss,{ editorClose.request() }).transition(.opacity)
            } else if let imageExport {
                ConversationExportView(snapshot:imageExport).environment(\.softPanelCloseRequest,editorClose)
                    .environment(\.softPanelDismiss,{ editorClose.request() }).transition(.opacity)
            } else if together, let session {
                TogetherPanel(session:session).environment(\.softPanelCloseRequest,editorClose)
                    .environment(\.softPanelDismiss,{ editorClose.request() }).transition(.opacity)
            } else if editing, let customization {
                customization().environment(\.softPanelCloseRequest,editorClose)
                    .environment(\.softPanelDismiss,{ editorClose.request() })
                    .transition(.opacity)
            } else { introduction.transition(.opacity) }
        }.foregroundStyle(Theme.ink).tint(Theme.accent).softSheetSurface()
            .softPanelPageSurface(opaque:!showsLiveCharacter)
            .alert("取消订阅「" + profile.name + "」？",isPresented:$confirmingUnsubscribe) {
                Button("保留订阅",role:.cancel) {}
                Button("取消订阅",role:.destructive) { library.subscribe(model.id,false) }
            } message: { Text("角色将从订阅列表移除，聊天记录和共同记忆仍会保留。") }
            .onAppear { close?.beforeClose = { editorClose.beforeClose?() ?? true } }
            .onDisappear { close?.beforeClose = nil }
            .task(id:model.id) {
                if model.isPreviewOnly { return }
                let api=CharacterAI(accountID:store.accountID,characterID:model.id)
                if let value:CharacterPublicProfile=try? await api.configuration("/v1/characters/"+model.id+"/profile"),!Task.isCancelled,
                   value.supersedes(CharacterPublicProfile.find(model.id)) {
                    loadedPublicProfile=value
                }
            }
    }
    private var introduction:some View {
        VStack(spacing:0) {
            PanelPageHeader("角色资料",backID:"closeCharacterDetails")
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    CharacterCover(model:model,focalCrop:true).aspectRatio(1.2,contentMode:.fit)
                        .clipShape(RoundedRectangle(cornerRadius:16,style:.continuous))
                    ProfileIdentityHeader(name:profile.name,subtitle:publicProfile?.occupation ?? profile.personality+" · "+profile.tone,nameID:"profileName") {
                        CharacterAvatar(model:model,profile:profile,portraits:portraits,size:52,floatingEnabled:false)
                    } accessory: { subscriptionButton }
                    VStack(alignment:.leading,spacing:10) {
                        Text(publicProfile?.invitation ?? model.display.invitation).font(.system(size:16,weight:.medium,design:.serif)).lineSpacing(4)
                            .foregroundStyle(Theme.ink.opacity(0.92))
                        if let publicProfile {
                            Text(publicProfile.traits.joined(separator:" · ")).font(.system(size:12,weight:.medium))
                                .foregroundStyle(Theme.accent).fixedSize(horizontal:false,vertical:true)
                                .accessibilityIdentifier("publicCharacterTraits")
                        }
                        Text(publicProfile?.story ?? profile.background).font(.system(size:13)).lineSpacing(5).foregroundStyle(Theme.secondary)
                            .frame(maxWidth:.infinity,alignment:.leading)
                            .accessibilityIdentifier("publicCharacterStory")
                        if let publicProfile {
                            HStack(alignment:.top,spacing:8) {
                                Image(systemName:"heart").font(.system(size:11))
                                Text(publicProfile.likes.joined(separator:"、")).font(.system(size:12)).lineSpacing(3)
                            }.foregroundStyle(Theme.peach.opacity(0.85)).padding(.vertical,3)
                                .accessibilityIdentifier("publicCharacterLikes")
                            Text(publicProfile.world+" · "+publicProfile.tone).font(.system(size:11)).foregroundStyle(Theme.secondary.opacity(0.8))
                        }
                        HStack(spacing:8) {
                            customizeButton

                        }
                    }
                    if let author = library.author(for:model.id) {
                        HStack(spacing:10) {
                            Button {
                                beginChild { showingAuthor = false }
                                withAnimation(motion) { showingAuthor = true }
                            } label: {
                                HStack(spacing:10) {
                                    AuthorAvatar(author:author,size:32)
                                    VStack(alignment:.leading,spacing:3) {
                                        Text("角色作者").font(.system(size:10)).foregroundStyle(Theme.secondary)
                                        Text(author.name).font(.system(size:13,weight:.medium)).lineLimit(1)
                                    }
                                    if allowsAuthorNavigation { Image(systemName:"chevron.right").font(.system(size:9)).foregroundStyle(Theme.secondary) }
                                    Spacer(minLength:0)
                                }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(!allowsAuthorNavigation).accessibilityIdentifier("characterAuthorButton")
                        }.padding(.vertical,4)
                    }
                    if let session {
                        Button {
                            beginChild { together = false }
                            withAnimation(motion) { together = true }
                        } label: {
                            HStack(spacing:12) {
                                Image(systemName:"sparkle").font(.system(size:21,weight:.light)).foregroundStyle(Theme.peach)
                                VStack(alignment:.leading,spacing:4) {
                                    Text("相处与剧情").font(.system(size:15,weight:.semibold))
                                    Text(session.record.together.suggestions.isEmpty ? (publicProfile?.scenarios?.map(\.title).joined(separator:" · ") ?? "故事 · 相处 · 时光手记") : "有新的记忆，等你确认")
                                        .lineLimit(1)
                                        .font(.system(size:11)).foregroundStyle(Theme.secondary)
                                }
                                Spacer();Image(systemName:"chevron.right").font(.system(size:11)).foregroundStyle(Theme.secondary)
                            }.padding(14).background(Theme.surface.opacity(0.65),in:RoundedRectangle(cornerRadius:17))
                        }.buttonStyle(.plain).accessibilityIdentifier("profileTogetherButton")
                        Button {
                            let snapshot = ConversationExportSnapshot.capture(model:model,record:session.record,portraits:portraits)
                            beginChild { imageExport = nil }
                            withAnimation(motion) { imageExport = snapshot }
                        } label: {
                            HStack(spacing:12) {
                                Image(systemName:"square.and.arrow.up").font(.system(size:21,weight:.light)).foregroundStyle(Theme.peach)
                                VStack(alignment:.leading,spacing:4) {
                                    Text("对话长图").font(.system(size:15,weight:.semibold))
                                    Text("选一段对话，收好这段时光").font(.system(size:11)).foregroundStyle(Theme.secondary)
                                }
                                Spacer();Image(systemName:"chevron.right").font(.system(size:11)).foregroundStyle(Theme.secondary)
                            }.padding(14).frame(maxWidth:.infinity,alignment:.leading)
                                .background(Theme.surface.opacity(0.65),in:RoundedRectangle(cornerRadius:17)).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("profileExportButton")
                    }
                    Button {
                        beginChild { showingCredits = false }
                        withAnimation(motion) { showingCredits = true }
                    } label: { Label("模型素材与原始署名",systemImage:"doc.text").font(.system(size:11)).foregroundStyle(Theme.secondary).frame(minHeight:44) }
                        .buttonStyle(.plain).accessibilityIdentifier("characterCreditsButton")
                    if let error = library.error { Text(LocalizedStringKey(error)).font(.caption).foregroundStyle(Theme.peach) }
#if STARRY_TEST_TOOLS
                    Button {
                        beginChild {showingDeveloper=false}
                        withAnimation(motion) {showingDeveloper=true}
                    } label: {
                        HStack(spacing:8) {
                            Image(systemName:"hammer")
                            Text("角色开发者页面")
                            Spacer();Image(systemName:"chevron.right").font(.system(size:10))
                        }.font(.system(size:12)).foregroundStyle(Theme.secondary).frame(minHeight:44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("openCharacterDeveloper")
#endif
                    HStack(spacing:8) {
                        Image(systemName:"sparkles").font(.system(size:12))
                        Text(model.isPreviewOnly ? "本地模型预览 · 暂未制作语音与对话" : "听着专属音乐，把重要的话留在共同记忆里。")
                            .font(.system(size:11)).lineLimit(2)
                    }.foregroundStyle(Theme.secondary.opacity(0.8)).padding(.top,4)
                }.padding(.horizontal,22).padding(.bottom,16)
            }.scrollIndicators(.hidden)
            // Live profiles dismiss back to their existing conversation. Discovery and
            // author profiles still need an explicit destination for starting a chat.
            if !showsLiveCharacter {
                Button { if library.select(model.id) { onChat() } } label: {
                    HStack { Text(model.isPreviewOnly ? "查看模型" : (subscribed ? "进入会话" : "订阅并聊天")); Image(systemName:"arrow.up.right").font(.system(size:12)) }
                        .frame(maxWidth:.infinity)
                }.buttonStyle(NightPrimaryButton()).accessibilityIdentifier("profileChatButton")
                    .padding(.horizontal,22).padding(.top,14).padding(.bottom,20)
            }
        }
            .accessibilityElement(children:.contain).accessibilityIdentifier("characterDetails-"+model.id)
    }
    private func beginChild(_ back:@escaping () -> Void) {
        editorClose = SoftPanelCloseRequest()
        editorClose.begin { withAnimation(motion,back) }
    }
    private var subscriptionButton:some View {
        Button {
            if subscribed { confirmingUnsubscribe = true }
            else { library.subscribe(model.id,true) }
        } label: {
            ProfileRelationshipLabel(title:subscribed ? "已订阅" : "订阅",selected:subscribed)
        }.buttonStyle(.plain).accessibilityIdentifier("characterSubscribeButton")
            .accessibilityValue(subscribed ? "已订阅" : "未订阅")
            .accessibilityHint(subscribed ? "取消订阅，聊天记录仍保留" : "订阅角色，在对话和消息中继续聊天")
    }
    private var customizeButton:some View {
        Button {
            if customization != nil {
                beginChild { editing = false }
                withAnimation(motion) { editing = true }
            } else { onCustomize() }
        } label: {
            Label("定制相处",systemImage:"slider.horizontal.3").font(.system(size:12,weight:.medium))
                .fixedSize().padding(.horizontal,12).frame(height:30)
                .background(Theme.card.opacity(0.55),in:Capsule())
                .overlay(Capsule().stroke(Theme.ink.opacity(0.1),lineWidth:0.5))
                .frame(minWidth:44,minHeight:44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("profileCustomizeButton")
    }
}
