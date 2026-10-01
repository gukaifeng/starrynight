import SwiftUI

private struct ConversationScrollGeometry: Equatable {
    var height: CGFloat
    var bottomDistance: CGFloat
}
private struct ConversationBottomPreference: PreferenceKey {
    static let defaultValue: ConversationScrollGeometry? = nil
    static func reduce(value: inout ConversationScrollGeometry?, nextValue: () -> ConversationScrollGeometry?) { value = nextValue() ?? value }
}
private struct ConversationMessageFramePreference: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { let next = nextValue(); if !next.isEmpty { value = next } }
}
private struct ConversationComposerFramePreference: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { let next = nextValue(); if !next.isEmpty { value = next } }
}

struct CompanionChatView: View {
    @Bindable var session: CompanionSession
    var onEditingChanged: ((Bool) -> Void)?
    var onDisplayChanged: (() -> Void)?
    var onMessageFrameChanged: ((CGRect) -> Void)?
    var onComposerFrameChanged: ((CGRect) -> Void)?
    var onHitRegionsChanged: (([String:ConversationHitRegion]) -> Void)?
    @ScaledMetric(relativeTo:.body) private var textScale: CGFloat = 1
    private var chatFontSize: CGFloat { CGFloat(session.store.chatDisplay.normalized.fontSize)*textScale }
    @State private var scrollState = ConversationScrollState()
    @State private var measuredContentHeight: CGFloat = 0
    @State private var bottomScrollTask: Task<Void,Never>?
    @Namespace private var chatViewport
    @State private var editing = false
    @State private var voiceMode=false
    @State private var voiceEditing=false
    // Keep outgoing content mounted through its dismissal, even when sending
    // immediately clears the session's suggestions for the next reply.
    @State private var presentedReplies:[AIQuickReply]=[]
    @State private var voiceEditTarget=VoiceCaptureTouchTarget()
    @State private var voiceCancelTarget=VoiceCaptureTouchTarget()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var interfaceAnimation: Animation { reduceMotion ? .easeInOut(duration:0.18) : .spring(response:0.42,dampingFraction:0.9) }
    private var latestContent: [String] { [String(session.record.messages.count),String(session.replyReveal.revision),String(session.generating)] + (session.record.messages.last?.visibleContentKey ?? []) }
    var body: some View {
        GeometryReader { geometry in
          if session.voiceInput.phase == .editing {
            // In short landscape windows the keyboard leaves too little room
            // for an overlay above the composer. Keep the editor inside the
            // existing hit-test area, with send/cancel beside its text field.
            VoiceCaptureOverlay(session:session,editing:$voiceEditing,compact:geometry.size.height < 250)
                .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.bottom)
                .padding(.horizontal,16)
          } else {
          VStack(spacing:0) {
            messages.simultaneousGesture(TapGesture().onEnded { editing = false }).zIndex(2)
            if !session.model.isPreviewOnly && geometry.size.height >= 360 && session.record.messages.isEmpty && !editing && !session.generating { topics.opacity(session.voiceInput.active ? 0 : 1).allowsHitTesting(!session.voiceInput.active).transition(.opacity.combined(with:.move(edge:.bottom))) }
            if let text = session.notice ?? session.store.error ?? session.speech.error {
              HStack(spacing:2) {
                    HStack(spacing:5) {
                        Text(LocalizedStringKey(text)).font(.system(size:11)).lineLimit(2)
                            .accessibilityLabel(text)
                        Button { session.notice = nil; session.speech.error = nil; session.store.error = nil } label: {
                            Image(systemName:"xmark").font(.system(size:9,weight:.medium)).frame(width:30,height:30)
                        }.accessibilityLabel("关闭提示")
                    }.padding(.leading,9).foregroundStyle(Theme.peach.opacity(0.9))
                        .frame(maxHeight:32).background(Theme.peach.opacity(0.1),in:RoundedRectangle(cornerRadius:10))
                        .accessibilityIdentifier("chatNotice").conversationHitRegion(.control,id:"chatNotice")
                        .transition(.opacity)
                Spacer()
              }.disabled(session.voiceInput.active).foregroundStyle(Theme.ink.opacity(0.56)).padding(.horizontal,22).frame(height:34)
            }
            if session.model.isPreviewOnly {
                Text("模型预览 · 可查看原作造型与表现")
                    .font(.system(size:12,weight:.medium))
                    .foregroundStyle(Theme.ink.opacity(0.72))
                    .padding(.horizontal,16).padding(.vertical,10)
                    .background(Theme.surface.opacity(0.55),in:Capsule())
                    .frame(maxWidth:.infinity)
                    .padding(.bottom,12)
                    .accessibilityIdentifier("localModelPreview")
            } else {
                composer(compact:geometry.size.height < 300).zIndex(4)
            }

          }
          }
        }
        .coordinateSpace(name:"companionPanel")
        .onPreferenceChange(ConversationMessageFramePreference.self) { onMessageFrameChanged?($0) }
        .onPreferenceChange(ConversationComposerFramePreference.self) { onComposerFrameChanged?($0) }
        .onPreferenceChange(ConversationHitPreference.self) { onHitRegionsChanged?($0) }
        .foregroundStyle(Theme.ink).tint(Theme.accent).scrollIndicators(.hidden)
        .animation(interfaceAnimation,value:editing)
        .animation(interfaceAnimation,value:session.generating)
        .animation(interfaceAnimation,value:session.quickReplyPanelPresented)
        .animation(.easeInOut(duration:reduceMotion ? 0.12 : 0.18),value:session.voiceInput.phase)
        .animation(interfaceAnimation,value:session.notice ?? session.store.error ?? session.speech.error)
        .task { if !session.model.isPreviewOnly { await session.speech.check() } }
        .onChange(of:session.store.chatDisplay) { onDisplayChanged?() }
        .onChange(of:session.dismissKeyboardRequest) { editing = false;voiceEditing=false;session.quickReplyPanelPresented=false }
        .onChange(of:session.quickReplyPanelPresented) {
            if session.quickReplyPanelPresented {presentedReplies=session.quickReplies}
        }
        .onChange(of:session.quickReplies.map(\.id)) {
            if session.quickReplyPanelPresented,!session.quickReplies.isEmpty {presentedReplies=session.quickReplies}
        }
        .onChange(of:session.voiceInput.phase) {
            if session.voiceInput.phase == .editing {voiceEditing=true}
            else if !session.voiceInput.active {voiceEditing=false}
        }
        .onChange(of:voiceEditing) {onEditingChanged?(voiceEditing)}
        .onDisappear {session.quickReplyPanelPresented=false;if session.voiceInput.active {session.cancelVoiceInput()}}
        .onChange(of:editing) {
            if editing {session.quickReplyPanelPresented=false}
            if editing && session.characterEditorPresented { editing = false }
            onEditingChanged?(editing)
        }
    }
    private var messages: some View {
      GeometryReader { viewport in
        ScrollViewReader { proxy in
            ZStack(alignment:.bottom) {
                ScrollView {
                    // This live window is capped at 60 messages. Eager measurement keeps
                    // scroll-to-bottom stable while the keyboard animates a very short
                    // landscape viewport and a streamed reply changes its content height.
                    VStack(alignment:.leading,spacing:10) {
                        if !session.model.isPreviewOnly && session.record.messages.isEmpty && !session.generating {
                            invitation.frame(minHeight:max(0,viewport.size.height-24),alignment:.bottom)
                        }
                        ForEach(session.visibleMessages) { message in
                            messageView(message).id(message.id)
                                .transition(reduceMotion ? .opacity : .opacity.combined(with:.offset(y:10)).combined(with:.scale(scale:0.98,anchor:.bottomTrailing)))
                        }
                        if session.generating {
                            Image(systemName:"ellipsis").font(.system(size:chatFontSize))
                                .symbolEffect(.variableColor,isActive:!reduceMotion)
                                .padding(14).background(Theme.surface.opacity(reduceTransparency ? 1 : Theme.panelOpacity),in:RoundedRectangle(cornerRadius:22))
                                .accessibilityLabel("正在回复").accessibilityIdentifier("streamingReply")
                                .conversationHitRegion(.message,id:"streaming")
                        }
                        // Include the entire bottom inset in the scroll target.
                        Color.clear.frame(height:18).id("latest")
                    }.animation(interfaceAnimation,value:session.record.messages.last?.id)
                        .padding(.horizontal,22)
                        // Real scrollable breathing room lets the first line travel below
                        // the mask's fade, even when the history is already at its beginning.
                        .padding(.top,reduceTransparency || (session.record.messages.isEmpty && !session.generating)
                            ? 10 : ConversationContentMask.readableStart(in:viewport.size.height)+12)
                        .background {
                            GeometryReader { content in
                                Color.clear.preference(key:ConversationBottomPreference.self,
                                    value:ConversationScrollGeometry(height:content.size.height,
                                        bottomDistance:content.frame(in:.named(chatViewport)).maxY - viewport.size.height))
                            }
                        }
                }.scrollDisabled(session.inspectionActive || session.voiceInput.active).scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively).accessibilityIdentifier("chatMessages")
                    .accessibilityValue(scrollState.isAtLatest ? "最新消息" : "历史消息")
                    .coordinateSpace(name:chatViewport)
                    .onPreferenceChange(ConversationBottomPreference.self) { geometry in
                        guard let geometry else { return }
                        scrollState.update(bottomDistance:Double(geometry.bottomDistance),resumeFollowing:session.focusedMessageID == nil)
                        // Content grows after the model update (ellipsis insertion,
                        // staged paragraphs, wrapping). Follow the measured layout too.
                        if abs(measuredContentHeight-geometry.height)>0.5 {
                            measuredContentHeight = geometry.height
                            if scrollState.followingLatest { settleAtBottom(using:proxy) }
                        }
                    }
                    .compositingGroup()
                    .mask {
                        ConversationContentMask(reduceTransparency:reduceTransparency)
                    }
                    .simultaneousGesture(DragGesture(minimumDistance:20)
                        .onChanged { if $0.translation.height > 20 { scrollState.scrollTowardHistory(); bottomScrollTask?.cancel() } }
                        .onEnded { _ in if scrollState.isAtLatest { scrollState.returnToLatest() } })
                    .onAppear { showFocusedMessage(using:proxy) }
                    .onChange(of:session.messageFocusRequest) { showFocusedMessage(using:proxy) }
                    .onChange(of:session.store.chatDisplay.fontSize) { if scrollState.followingLatest { settleAtBottom(using:proxy) } }
                    .onChange(of:viewport.size.height) { if scrollState.followingLatest { settleAtBottom(using:proxy) } }
                    .onChange(of:latestContent) { receiveContent(using:proxy) }
                    .onDisappear { bottomScrollTask?.cancel() }
                if (scrollState.showsReturnButton || session.focusedMessageID != nil) && !session.record.messages.isEmpty {
                    ReturnLatestControl {
                        session.clearMessageFocus(); scrollState.returnToLatest()
                        // The latest window must exist before scrolling to it.
                        settleAtBottom(using:proxy)
                    }.conversationHitRegion(.control,id:"returnLatest").transition(.opacity)
                }
            }
            .animation(interfaceAnimation,value:scrollState.showsReturnButton)
        }
        .preference(key:ConversationMessageFramePreference.self,value:viewport.frame(in:.named("companionPanel")))
      }
    }
    private var invitation: some View {
        VStack(alignment:.leading,spacing:6) {
            if editing {
                Text("写下此刻想说的话").font(.subheadline).foregroundStyle(Theme.secondary)
            } else {
                Text("开启对话")
                    .font(.system(size:21,weight:.medium,design:.rounded)).fixedSize(horizontal:false,vertical:true)
                Text("写下此刻想说的话")
                    .font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal:false,vertical:true)
            }
        }.padding(.vertical,editing ? 0 : 5).frame(maxWidth:.infinity,alignment:.leading).accessibilityIdentifier("chatEmptyState")
    }
    private var topics: some View {
        ScrollView(.horizontal) {
            HStack(spacing:8) {
                topic("你好",symbol:"hand.wave",id:"hello")
                topic("今天有点累",symbol:"cloud.sun",id:"tired")
                topic("分享一件开心的事",symbol:"sparkles",id:"joy")
                if session.model.isCustomizable { topic("你好，挥挥手",symbol:"hand.wave",id:"wave") }
                else { topic("说说你的小世界",symbol:"sparkles",id:"world") }
            }.padding(.horizontal,20)
        }.scrollIndicators(.hidden).fixedSize(horizontal:false,vertical:true).padding(.vertical,5)
    }
    private func topic(_ text: String,symbol: String,id: String) -> some View {
        Button { session.input = text; send() } label: {
            Label(LocalizedStringKey(text),systemImage:symbol).font(.caption).padding(.horizontal,12).frame(minHeight:44)
                .background(Theme.surface.opacity(reduceTransparency ? 1 : Theme.controlOpacity),in:Capsule()).overlay(Capsule().stroke(Theme.line.opacity(0.8)))
        }.accessibilityIdentifier("starter-" + id)
    }
    private var voiceHoldTitle:String {
        switch session.voiceInput.phase {
        case .holding:return session.voiceInput.cancelArmed ? "松开，取消发送" : (session.voiceInput.editArmed ? "松开，编辑文字" : "松开发送 · 上滑选择")
        case .finishing:return "正在整理…"
        default:return "按住说话"
        }
    }
    private func composer(compact:Bool) -> some View {
        HStack(alignment:.bottom,spacing:3) {
            Button {
                editing=false;voiceEditing=false;session.quickReplyPanelPresented=false
                if session.voiceInput.active {session.cancelVoiceInput()}
                withAnimation(interfaceAnimation) {voiceMode.toggle()}
            } label: {
                Image(systemName:voiceMode ? "keyboard" : "waveform.circle")
                    .font(.system(size:voiceMode ? 19 : 18,weight:.light)).foregroundStyle(Theme.ink.opacity(0.65))
                    .frame(width:44,height:44).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(session.voiceInput.active).padding(.leading,3)
                .accessibilityLabel(voiceMode ? "切换键盘输入" : "切换语音输入").accessibilityIdentifier("inputModeButton")
            if voiceMode {
                VoiceHoldSurface(title:voiceHoldTitle,active:session.voiceInput.phase == .holding,armed:session.voiceInput.editArmed || session.voiceInput.cancelArmed,fontSize:chatFontSize,
                    onBegin:{
                        session.quickReplyPanelPresented=false
                        return session.beginVoiceInput()
                    },onMove:{point in
                        let cancel=voiceCancelTarget.contains(point,armed:session.voiceInput.cancelArmed)
                        session.voiceInput.armCancel(cancel)
                        session.voiceInput.armEdit(!cancel && voiceEditTarget.contains(point,armed:session.voiceInput.editArmed))
                        return session.voiceInput.editArmed || session.voiceInput.cancelArmed
                    },onRelease:{if session.voiceInput.cancelArmed {session.cancelVoiceInput()} else {session.finishVoiceInput(edit:session.voiceInput.editArmed)}},
                    onCancel:{session.cancelVoiceHold()},onAccessibleEdit:{session.finishVoiceInput(edit:true)},onAccessibleCancel:{session.cancelVoiceInput()})
                    .frame(maxWidth:.infinity).frame(height:ComposerPromptStyle.height(chatFontSize))
                    .background(Theme.accent.opacity(session.voiceInput.phase == .holding ? 0.075 : 0),in:RoundedRectangle(cornerRadius:20,style:.continuous))
                    .padding(.leading,2).padding(.trailing,4)
            } else {
                ChatComposerInput(text:$session.input,isFocused:$editing,fontSize:chatFontSize,
                                  foreground:UIColor(Theme.ink),accent:UIColor(Theme.accent),
                                  maxLines:compact ? 1 : 3,isEnabled:!session.characterEditorPresented,onSend:send)
                    .frame(maxWidth:.infinity)
                    .overlay(alignment:.topLeading) {
                        if session.input.isEmpty {
                            Text("想和你说…").font(ComposerPromptStyle.font(chatFontSize)).foregroundStyle(ComposerPromptStyle.color)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }.padding(.leading,2).padding(.trailing,4).padding(.vertical,12)
            }
            Button {
                editing=false
                withAnimation(interfaceAnimation) {session.quickReplyPanelPresented.toggle()}
                if session.quickReplyPanelPresented && session.quickReplies.isEmpty && !session.quickRepliesLoading {session.requestQuickReplies()}
            } label: {
                Image(systemName:"sparkles").font(.system(size:17,weight:.light))
                    .foregroundStyle(Theme.gradient.opacity(session.quickReplyPanelPresented ? 1 : 0.66))
                    .frame(width:42,height:44).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(session.voiceInput.active)
                .accessibilityLabel("灵感接话").accessibilityHint("选择一句适合此刻的回复").accessibilityIdentifier("smartReplyButton")
        }.padding(.trailing,4).padding(.vertical,2)
            .conversationHitRegion(.control,id:"chatComposer")
            .background(Theme.surface.opacity(reduceTransparency ? 1 : Theme.controlOpacity),in:RoundedRectangle(cornerRadius:25,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:25,style:.continuous).stroke(Theme.line.opacity(0.8),lineWidth:0.75).allowsHitTesting(false))
            .shadow(color:Theme.ink.opacity(0.025),radius:8,y:3)
            .background {
                GeometryReader { composer in
                    Color.clear.preference(key:ConversationComposerFramePreference.self,
                        value:composer.frame(in:.named("companionPanel")))
                }
            }
            .padding(.horizontal,20)
            .overlay {
                GeometryReader { composer in
                    // Prepare the glass panel when switching to voice mode;
                    // pressing only fades it in, without mounting a new surface.
                    if voiceMode {
                        Color.clear.overlay(alignment:.bottom) {
                            VoiceCaptureOverlay(session:session,editing:$voiceEditing,compact:compact,editTarget:voiceEditTarget,cancelTarget:voiceCancelTarget)
                                .frame(width:max(0,min(360,composer.size.width-40))).fixedSize(horizontal:false,vertical:true)
                                .offset(y:-composer.size.height-12)
                        }
                        .opacity(session.voiceInput.active ? 1 : 0)
                        .allowsHitTesting(session.voiceInput.active && session.voiceInput.phase != .holding)
                        .accessibilityHidden(!session.voiceInput.active)
                    }
                    Color.clear.overlay(alignment:.bottomTrailing) {
                        if session.quickReplyPanelPresented && !session.voiceInput.active {
                            smartRepliesPanel.frame(width:max(0,min(270,composer.size.width-72)))
                                .fixedSize(horizontal:false,vertical:true).padding(.trailing,20)
                                .offset(y:-composer.size.height-8)
                                .transition(reduceMotion ? .opacity : .asymmetric(
                                    insertion:.opacity.combined(with:.offset(y:12)).combined(with:.scale(scale:0.96,anchor:.bottomTrailing)),
                                    removal:.opacity.combined(with:.offset(y:8)).combined(with:.scale(scale:0.98,anchor:.bottomTrailing))))
                        }
                    }.animation(interfaceAnimation,value:session.quickReplyPanelPresented)
                }.allowsHitTesting((session.voiceInput.active && session.voiceInput.phase != .holding) || (session.quickReplyPanelPresented && !session.voiceInput.active))
            }
            .onChange(of:session.quickReplySource) {if session.quickReplySource==nil {session.quickReplyPanelPresented=false}}

    }
    private var smartRepliesPanel:some View {
        VStack(alignment:.leading,spacing:2) {
            HStack {
                Text("灵感接话").font(.system(size:11,weight:.medium)).foregroundStyle(Theme.secondary)
                Spacer()
                Button {withAnimation(interfaceAnimation) {session.quickReplyPanelPresented=false}} label: {
                    Image(systemName:"xmark").font(.system(size:9,weight:.medium)).frame(width:23,height:23)
                }.buttonStyle(.plain).accessibilityLabel("关闭灵感接话").accessibilityIdentifier("closeSmartReplies")
            }.padding(.leading,7)
            if presentedReplies.isEmpty {
                HStack(spacing:9) {
                    if session.quickRepliesLoading {ProgressView().controlSize(.small)}
                    Text(session.quickRepliesLoading ? "想几个适合你的回答…" : "聊起来后，这里会有适合你的接话。")
                        .font(.system(size:12)).foregroundStyle(Theme.secondary)
                }.padding(8)
            }
            ForEach(Array(presentedReplies.enumerated()),id:\.element.id) {index,option in
                Button {
                    withAnimation(interfaceAnimation) {
                        session.quickReplyPanelPresented=false
                        editing=false;session.clearMessageFocus();scrollState.returnToLatest();session.sendSuggested(option)
                    }
                } label: {
                    HStack(spacing:7) {
                        Text(option.text).font(.system(size:12)).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength:4)
                        Image(systemName:"arrow.up.right").font(.system(size:10,weight:.medium)).foregroundStyle(Theme.secondary.opacity(0.7))
                    }.padding(.horizontal,9).padding(.vertical,6).frame(maxWidth:.infinity,minHeight:34,alignment:.leading)
                        .background(Theme.ink.opacity(index==0 ? 0.075 : 0.035),in:RoundedRectangle(cornerRadius:10))
                }.buttonStyle(ReplySuggestionPressStyle(reduceMotion:reduceMotion))
                    .accessibilityLabel(option.text).accessibilityIdentifier("smartReplyOption-\(index)")
            }
        }.padding(6).background(Theme.surface.opacity(reduceTransparency ? 1 : 0.96),in:RoundedRectangle(cornerRadius:15))
            .overlay(RoundedRectangle(cornerRadius:15).stroke(Theme.gradient.opacity(0.24),lineWidth:0.65))
            .shadow(color:.black.opacity(0.18),radius:16,y:5)
            .conversationHitRegion(.control,id:"smartRepliesPanel")
            .accessibilityElement(children:.contain).accessibilityIdentifier("smartRepliesPanel")
    }
    private var canSend: Bool { !session.input.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }

    private func showFocusedMessage(using proxy:ScrollViewProxy) {
        guard let id = session.focusedMessageID else { if scrollState.followingLatest { settleAtBottom(using:proxy) }; return }
        bottomScrollTask?.cancel()
        scrollState.scrollTowardHistory()
        DispatchQueue.main.async { proxy.scrollTo(id,anchor:UnitPoint(x:0.5,y:0.8)) }
    }
    private func receiveContent(using proxy:ScrollViewProxy) {
        session.clearMessageFocus(); scrollState.returnToLatest()
        // Clearing a search focus replaces the historical window. Scroll after
        // that layout update so the real latest message already exists.
        settleAtBottom(using:proxy)
    }
    private func settleAtBottom(using proxy:ScrollViewProxy) {
        bottomScrollTask?.cancel()
        bottomScrollTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, scrollState.followingLatest else { return }
            withAnimation(.easeOut(duration:reduceMotion ? 0.1 : 0.22)) { proxy.scrollTo("latest",anchor:.bottom) }
            // A layout/keyboard transition can finish after the first scroll.
            // Reconcile once after it settles, without a second visible animation.
            do { try await Task.sleep(for:.milliseconds(450)) } catch { return }
            guard !Task.isCancelled, scrollState.followingLatest else { return }
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { proxy.scrollTo("latest",anchor:.bottom) }
        }
    }
    private func send() {
        guard canSend, !session.characterEditorPresented else { return }
        withAnimation(interfaceAnimation) {
            editing = false; session.clearMessageFocus(); scrollState.returnToLatest(); session.send()
        }
    }
    private func messageView(_ message: CompanionMessage) -> some View {
        VStack(alignment:message.role == "user" ? .trailing : .leading,spacing:0) {
            if message.role == "assistant" {
                VStack(alignment:.leading,spacing:0) {
                    MessageVoiceControl(session:session,message:message)
                        .conversationHitRegion(.control,id:"voice-"+message.id.uuidString)
                        // Body begins 12pt below the 23pt shoulder, matching its
                        // bottom inset. The 44pt audio hit area extends upward.
                        .frame(height:35,alignment:.bottom)
                    TranslatableReplyContent(session:session,message:message,fontSize:chatFontSize)
                }.padding(.horizontal,15).padding(.bottom,12)
                    .frame(minWidth:136,alignment:.leading)
                    .background(Theme.surface.opacity(reduceTransparency ? 1 : 0.64),in:AssistantBubbleShape())
                    .overlay { AssistantBubbleShape().stroke(Theme.gradient.opacity(session.focusedMessageID == message.id ? 0.65 : 0.20),lineWidth:0.6) }
            } else {
                Text(message.text).font(.system(size:chatFontSize)).lineSpacing(5)
                    .accessibilityIdentifier("userMessage")
                    .padding(.horizontal,15).padding(.vertical,11)
                    .background(Theme.jade.opacity(reduceTransparency ? 1 : 0.60),in:RoundedRectangle(cornerRadius:22))
                    .overlay { RoundedRectangle(cornerRadius:22).stroke(Theme.gradient.opacity(session.focusedMessageID == message.id ? 0.65 : 0.08),lineWidth:0.6) }
            }
            if message.interrupted { Text("已停止生成").font(.caption2).foregroundStyle(Theme.secondary) }
        }.conversationHitRegion(.message,id:message.id.uuidString)
            .frame(maxWidth:.infinity,alignment:message.role == "user" ? .trailing : .leading)
    }
}

private struct ReplySuggestionPressStyle:ButtonStyle {
    let reduceMotion:Bool
    func makeBody(configuration:Configuration)->some View {
        configuration.label.opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.easeOut(duration:0.16),value:configuration.isPressed)
    }
}
