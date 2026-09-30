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
    @State private var measuredContentHeight: CGFloat = 0
    @State private var bottomScrollTask: Task<Void,Never>?
    @Namespace private var chatViewport
    @State private var editing = false
    @State private var smartRepliesPresented=false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var interfaceAnimation: Animation { reduceMotion ? .easeInOut(duration:0.18) : .spring(response:0.42,dampingFraction:0.9) }
    private var latestContent: [String] { [String(session.record.messages.count),String(session.replyReveal.revision),String(session.generating)] + (session.record.messages.last?.visibleContentKey ?? []) }
    var body: some View {
        GeometryReader { geometry in
          VStack(spacing:0) {
            messages.simultaneousGesture(TapGesture().onEnded { editing = false }).zIndex(2)
            if geometry.size.height >= 360 && session.record.messages.isEmpty && !editing && !session.generating && !session.speech.isRecording { topics.transition(.opacity.combined(with:.move(edge:.bottom))) }
            HStack(spacing:2) {
                if let text = session.notice ?? session.store.error ?? session.speech.error {
                    HStack(spacing:5) {
                        Text(text).font(.system(size:11)).lineLimit(2)
                            .accessibilityLabel(text)
                        Button { session.notice = nil; session.speech.error = nil; session.store.error = nil } label: {
                            Image(systemName:"xmark").font(.system(size:9,weight:.medium)).frame(width:30,height:30)
                        }.accessibilityLabel("关闭提示")
                    }.padding(.leading,9).foregroundStyle(Theme.peach.opacity(0.9))
                        .frame(maxHeight:32).background(Theme.peach.opacity(0.1),in:RoundedRectangle(cornerRadius:10))
                        .accessibilityIdentifier("chatNotice").conversationHitRegion(.control,id:"chatNotice")
                        .transition(.opacity)
                }
                Spacer()
                Button { editing = false; onPerformance?() } label: {
                    Image(systemName:"sparkles").font(.system(size:14,weight:.regular))
                        .frame(width:36,height:36).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("角色表现").accessibilityIdentifier("conversationPerformanceButton")
                ConversationSoundButton(session:session,onSettings:{ editing = false; onSoundSettings?() })
            }.foregroundStyle(Theme.ink.opacity(0.56)).padding(.leading,22).padding(.trailing,23).frame(height:34)
            composer(compact:geometry.size.height < 220).zIndex(smartRepliesPresented ? 4 : 0)

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
            if editing {smartRepliesPresented=false}
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
                        // Include the entire bottom inset in the scroll target.
                        Color.clear.frame(height:18).id("latest")
                    }.padding(.horizontal,22)
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
                }.scrollDisabled(session.inspectionActive).scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively).accessibilityIdentifier("chatMessages")
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
            Label(text,systemImage:symbol).font(.caption).padding(.horizontal,12).frame(minHeight:44)
                .background(Theme.surface.opacity(reduceTransparency ? 1 : Theme.controlOpacity),in:Capsule()).overlay(Capsule().stroke(Theme.line.opacity(0.8)))
        }.accessibilityIdentifier("starter-" + id)
    }
    private func composer(compact:Bool) -> some View {
        HStack(alignment:.bottom,spacing:2) {
            Button {
                editing=false
                withAnimation(interfaceAnimation) {smartRepliesPresented.toggle()}
                if smartRepliesPresented && session.quickReplies.isEmpty && !session.quickRepliesLoading {session.requestQuickReplies()}
            } label: {
                Image(systemName:"sparkles").font(.system(size:16,weight:.light))
                    .foregroundStyle(Theme.gradient.opacity(smartRepliesPresented ? 1 : 0.7))
                    .frame(width:30,height:32)
                    .background(Theme.ink.opacity(smartRepliesPresented ? 0.10 : 0.035),in:RoundedRectangle(cornerRadius:11))
                    .frame(width:39,height:44).contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.leading,5)
                .accessibilityLabel("智能回复").accessibilityIdentifier("smartReplyButton")
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
                .padding(.leading,3).padding(.trailing,4).padding(.vertical,12)
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
            .overlay {
                GeometryReader { composer in
                    if smartRepliesPresented {
                        Color.clear.overlay(alignment:.bottom) {
                            smartRepliesPanel.padding(.horizontal,22)
                                .fixedSize(horizontal:false,vertical:true)
                                .offset(y:-composer.size.height-8)
                                .transition(.opacity.combined(with:.offset(y:8)))
                        }
                    }
                }
            }
            .onChange(of:session.quickReplySource) {if session.quickReplySource==nil {smartRepliesPresented=false}}

    }
    private var smartRepliesPanel:some View {
        VStack(alignment:.leading,spacing:5) {
            HStack {
                Text("接着聊").font(.system(size:12,weight:.medium)).foregroundStyle(Theme.secondary)
                Spacer()
                Button {withAnimation(interfaceAnimation) {smartRepliesPresented=false}} label: {
                    Image(systemName:"xmark").font(.system(size:10,weight:.medium)).frame(width:28,height:28)
                }.buttonStyle(.plain).accessibilityLabel("关闭智能回复")
            }.padding(.leading,8)
            if session.quickReplies.isEmpty {
                HStack(spacing:9) {
                    if session.quickRepliesLoading {ProgressView().controlSize(.small)}
                    Text(session.quickRepliesLoading ? "想几个适合你的回答…" : "聊起来后，这里会有适合你的接话。")
                        .font(.system(size:12)).foregroundStyle(Theme.secondary)
                }.padding(10)
            }
            ForEach(Array(session.quickReplies.enumerated()),id:\.element.id) {index,option in
                Button {
                    withAnimation(interfaceAnimation) {smartRepliesPresented=false}
                    editing=false;session.clearMessageFocus();scrollState.returnToLatest();session.sendSuggested(option)
                } label: {
                    HStack(spacing:10) {
                        Text(option.text).font(.system(size:14)).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength:4)
                        Image(systemName:"arrow.up.right").font(.system(size:10,weight:.medium)).foregroundStyle(Theme.secondary.opacity(0.7))
                    }.padding(.horizontal,12).padding(.vertical,10).frame(maxWidth:.infinity,alignment:.leading)
                        .background(Theme.ink.opacity(index==0 ? 0.075 : 0.035),in:RoundedRectangle(cornerRadius:12))
                }.buttonStyle(.plain).accessibilityLabel(option.text).accessibilityIdentifier("smartReplyOption-\(index)")
            }
        }.padding(9).background(Theme.surface.opacity(reduceTransparency ? 1 : 0.96),in:RoundedRectangle(cornerRadius:20))
            .overlay(RoundedRectangle(cornerRadius:20).stroke(Theme.gradient.opacity(0.24),lineWidth:0.65))
            .shadow(color:.black.opacity(0.18),radius:16,y:5)
            .conversationHitRegion(.control,id:"smartRepliesPanel")
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
