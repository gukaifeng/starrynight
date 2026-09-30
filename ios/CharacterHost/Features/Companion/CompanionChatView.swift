import SwiftUI

private struct ConversationBottomPreference: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = nextValue() ?? value }
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
    var onPerformance: (() -> Void)?
    var onSoundSettings: (() -> Void)?
    var onEditingChanged: ((Bool) -> Void)?
    var onDisplayChanged: (() -> Void)?
    var onMessageFrameChanged: ((CGRect) -> Void)?
    var onComposerFrameChanged: ((CGRect) -> Void)?
    var onHitRegionsChanged: (([String:ConversationHitRegion]) -> Void)?
    @ScaledMetric(relativeTo:.body) private var textScale: CGFloat = 1
    private var chatFontSize: CGFloat { CGFloat(session.store.chatDisplay.normalized.fontSize)*textScale }
    @State private var scrollState = ConversationScrollState()
    @Namespace private var chatViewport
    @State private var editing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var interfaceAnimation: Animation { reduceMotion ? .easeInOut(duration:0.18) : .spring(response:0.42,dampingFraction:0.9) }
    private var latestContent: [String] { [String(session.record.messages.count),String(session.replyReveal.revision)] + (session.record.messages.last?.visibleContentKey ?? []) }
    var body: some View {
        GeometryReader { geometry in
          VStack(spacing:0) {
            messages.simultaneousGesture(TapGesture().onEnded { editing = false }).zIndex(2)
            if let text = session.notice ?? session.store.error ?? session.speech.error {
                HStack(spacing:10) {
                    Text(text).font(.caption).lineLimit(geometry.size.height < 240 ? 2 : nil).fixedSize(horizontal:false,vertical:true)
                    Spacer(minLength:0)
                    Button { session.notice = nil; session.speech.error = nil; session.store.error = nil } label: { Image(systemName:"xmark").frame(width:32,height:32) }
                        .accessibilityLabel("关闭提示")
                }.padding(12).background(Theme.peach.opacity(0.3),in:RoundedRectangle(cornerRadius:16)).padding(.horizontal,20).accessibilityIdentifier("chatNotice")
            }
            if geometry.size.height >= 360 && session.record.messages.isEmpty && !editing && !session.generating && !session.speech.isRecording { topics.transition(.opacity.combined(with:.move(edge:.bottom))) }
            HStack(spacing:2) {
                Spacer()
                Button { editing = false; onPerformance?() } label: {
                    Image(systemName:"sparkles").font(.system(size:14,weight:.regular))
                        .frame(width:36,height:36).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("角色表现").accessibilityIdentifier("conversationPerformanceButton")
                ConversationSoundButton(session:session,onSettings:{ editing = false; onSoundSettings?() })
            }.foregroundStyle(Theme.ink.opacity(0.56)).padding(.trailing,23).frame(height:34)
            composer(compact:geometry.size.height < 220)

          }
        }
        .coordinateSpace(name:"companionPanel")
        .onPreferenceChange(ConversationMessageFramePreference.self) { onMessageFrameChanged?($0) }
        .onPreferenceChange(ConversationComposerFramePreference.self) { onComposerFrameChanged?($0) }
        .onPreferenceChange(ConversationHitPreference.self) { onHitRegionsChanged?($0) }
        .foregroundStyle(Theme.ink).tint(Theme.accent).scrollIndicators(.hidden)
        .animation(interfaceAnimation,value:editing)
        .animation(interfaceAnimation,value:session.generating)
        .animation(interfaceAnimation,value:session.speech.isRecording)
        .animation(interfaceAnimation,value:session.notice ?? session.store.error ?? session.speech.error)
        .task { await session.speech.check() }
        .onChange(of:session.store.chatDisplay) { onDisplayChanged?() }
        .onChange(of:session.dismissKeyboardRequest) { editing = false }
        .onChange(of:editing) {
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
                        if session.record.messages.isEmpty && !session.generating {
                            invitation.frame(minHeight:max(0,viewport.size.height-24),alignment:.bottom)
                        }
                        ForEach(session.visibleMessages) { message in messageView(message).id(message.id) }
                        if session.generating {
                            Image(systemName:"ellipsis").font(.system(size:chatFontSize))
                                .symbolEffect(.variableColor,isActive:!reduceMotion)
                                .padding(14).background(Theme.surface.opacity(reduceTransparency ? 1 : Theme.panelOpacity),in:RoundedRectangle(cornerRadius:22))
                                .accessibilityLabel("正在回复").accessibilityIdentifier("streamingReply")
                                .conversationHitRegion(.message,id:"streaming")
                        }
                        Color.clear.frame(height:3).id("latest")
                    }.padding(.horizontal,22)
                        // Real scrollable breathing room lets the first line travel below
                        // the mask's fade, even when the history is already at its beginning.
                        .padding(.top,reduceTransparency || (session.record.messages.isEmpty && !session.generating)
                            ? 10 : ConversationContentMask.readableStart(in:viewport.size.height)+12)
                        .padding(.bottom,18)
                        .background {
                            GeometryReader { content in
                                Color.clear.preference(key:ConversationBottomPreference.self,
                                    value:content.frame(in:.named(chatViewport)).maxY - viewport.size.height)
                            }
                        }
                }.scrollDisabled(session.inspectionActive).scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively).accessibilityIdentifier("chatMessages")
                    .accessibilityValue(scrollState.isAtLatest ? "最新消息" : "历史消息")
                    .coordinateSpace(name:chatViewport)
                    .onPreferenceChange(ConversationBottomPreference.self) { distance in
                        if let distance { scrollState.update(bottomDistance:Double(distance)) }
                    }
                    .compositingGroup()
                    .mask {
                        ConversationContentMask(reduceTransparency:reduceTransparency)
                    }
                    .simultaneousGesture(DragGesture(minimumDistance:20)
                        .onChanged { if $0.translation.height > 20 { scrollState.scrollTowardHistory() } }
                        .onEnded { _ in if scrollState.isAtLatest { scrollState.returnToLatest() } })
                    .onAppear { showFocusedMessage(using:proxy) }
                    .onChange(of:session.messageFocusRequest) { showFocusedMessage(using:proxy) }
                    .onChange(of:session.store.chatDisplay.fontSize) { if scrollState.followingLatest { proxy.scrollTo("latest",anchor:.bottom) } }
                    .onChange(of:viewport.size.height) { if scrollState.followingLatest { proxy.scrollTo("latest",anchor:.bottom) } }
                    .onChange(of:latestContent) { receiveContent(using:proxy) }
                if (scrollState.showsReturnButton || session.focusedMessageID != nil) && !session.record.messages.isEmpty {
                    ReturnLatestControl {
                        session.clearMessageFocus(); scrollState.returnToLatest()
                        // The latest window must exist before scrolling to it.
                        DispatchQueue.main.async { withAnimation(interfaceAnimation) { proxy.scrollTo("latest",anchor:.bottom) } }
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
                Text("今天，有什么想和我分享？")
                    .font(.system(size:21,weight:.medium,design:.rounded)).fixedSize(horizontal:false,vertical:true)
                Text("我在这里，听你慢慢说。")
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
            Label(text,systemImage:symbol).font(.caption).padding(.horizontal,12).frame(minHeight:44)
                .background(Theme.surface.opacity(reduceTransparency ? 1 : Theme.controlOpacity),in:Capsule()).overlay(Capsule().stroke(Theme.line.opacity(0.8)))
        }.accessibilityIdentifier("starter-" + id)
    }
    private func composer(compact:Bool) -> some View {
        HStack(alignment:.bottom,spacing:2) {
            ChatComposerInput(text:$session.input,isFocused:$editing,fontSize:chatFontSize,
                              foreground:UIColor(Theme.ink),accent:UIColor(Theme.accent),
                              maxLines:compact ? 1 : 3,isEnabled:!session.characterEditorPresented,onSend:send)
                .frame(maxWidth:.infinity)
                .overlay(alignment:.topLeading) {
                    if session.input.isEmpty {
                        Text("想和你说…").font(.system(size:chatFontSize)).foregroundStyle(Theme.ink.opacity(0.35))
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .padding(.leading,16).padding(.trailing,4).padding(.vertical,12)
            Button {
                editing = false
                if !session.speech.isRecording { session.stop() }
                session.speech.toggleRecording()
            } label: {
                Image(systemName:session.speech.isRecording ? "stop.fill" : "mic")
                    .font(.system(size:session.speech.isRecording ? 11 : 17,weight:.regular))
                    .foregroundStyle(session.speech.isRecording ? Color(red:0.68,green:0.30,blue:0.24) : Theme.ink.opacity(0.72))
                    .frame(width:session.speech.isRecording ? 26 : 32,height:session.speech.isRecording ? 26 : 32)
                    .background(session.speech.isRecording ? Theme.peach.opacity(0.3) : .clear,in:Circle())
                    .frame(width:44,height:44).contentShape(Circle())
            }.buttonStyle(.plain).accessibilityLabel(session.speech.isRecording ? "结束录音" : "语音输入")
                .accessibilityIdentifier("recordVoiceButton")
            Button { if session.generating { session.stop() } else { send() } } label: {
                Image(systemName:session.generating ? "stop.fill" : "arrow.up")
                    .font(.system(size:session.generating ? 12 : 16,weight:.medium))
                    .foregroundStyle(canSend || session.generating ? Theme.background : Theme.ink.opacity(0.4))
                    .frame(width:32,height:32)
                    .background(Theme.ink.opacity(canSend || session.generating ? 0.88 : 0.08),in:Circle())
                    .frame(width:44,height:44).contentShape(Circle())
            }.buttonStyle(.plain).disabled(!session.generating && !canSend)
                .accessibilityLabel(session.generating ? "停止回复" : "发送")
                .accessibilityIdentifier(session.generating ? "stopReplyButton" : "sendMessageButton")
        }.padding(.trailing,4).padding(.vertical,2)
            .background(Theme.surface.opacity(reduceTransparency ? 1 : Theme.controlOpacity),in:RoundedRectangle(cornerRadius:25,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:25,style:.continuous).stroke(Theme.line.opacity(0.8),lineWidth:0.75))
            .shadow(color:Theme.ink.opacity(0.025),radius:8,y:3)
            .background {
                GeometryReader { composer in
                    Color.clear.preference(key:ConversationComposerFramePreference.self,
                        value:composer.frame(in:.named("companionPanel")))
                }
            }
            .padding(.horizontal,20)

    }
    private var canSend: Bool { !session.input.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }

    private func showFocusedMessage(using proxy:ScrollViewProxy) {
        guard let id = session.focusedMessageID else { proxy.scrollTo("latest",anchor:.bottom); return }
        scrollState.scrollTowardHistory()
        DispatchQueue.main.async { proxy.scrollTo(id,anchor:UnitPoint(x:0.5,y:0.8)) }
    }
    private func receiveContent(using proxy:ScrollViewProxy) {
        session.clearMessageFocus(); scrollState.returnToLatest()
        // Clearing a search focus replaces the historical window. Scroll after
        // that layout update so the real latest message already exists.
        DispatchQueue.main.async {
            if scrollState.followingLatest { withAnimation(interfaceAnimation) { proxy.scrollTo("latest",anchor:.bottom) } }
        }
    }
    private func send() {
        guard canSend, !session.characterEditorPresented else { return }
        editing = false; session.clearMessageFocus(); scrollState.returnToLatest(); session.send()
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
                    AIReplyContent(message:message,fontSize:chatFontSize,reveal:session.replyReveal)
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
