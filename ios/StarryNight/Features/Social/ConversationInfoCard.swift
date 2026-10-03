import SwiftUI

/// Conversation history and management share one panel and one header.
struct ConversationInfoCard<Avatar:View>:View {
    let name:String
    let characterID:String
    let summary:ConversationRelationshipSummary
    var onEnter:()->Void
    var onHide:()->Void
    var onReset:@MainActor () async throws -> Void
    @ViewBuilder var avatar:()->Avatar
    @State private var management=false
    @State private var confirmingReset=false
    @State private var resetting=false
    @State private var resetError:String?
    @State private var resetNotice=false
    @Environment(\.softPanelDismiss) private var dismiss
    @Environment(\.softPanelCloseRequest) private var closeRequest
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var motion:Animation {.easeInOut(duration:reduceMotion ? 0.15 : 0.28)}
    var body:some View {
        ZStack {
            VStack(spacing:0) {
                PanelPageHeader(management ? "会话管理" : "你们的故事",
                    backID:management ? "backConversationDetail" : "closeConversationDetail",
                    backAction:{if management {withAnimation(motion){management=false}} else {dismiss()}}) {
                        if !management {
                            Button {withAnimation(motion){management=true}} label: {
                                Image(systemName:"ellipsis").font(.system(size:17,weight:.medium))
                                    .frame(width:44,height:44).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("更多会话选项")
                                .accessibilityIdentifier("moreConversationActions-"+characterID)
                        }
                    }
                ScrollView {
                    if management {managementPage.transition(.opacity.combined(with:.offset(y:8)))}
                    else {overview.transition(.opacity.combined(with:.offset(y:-8)))}
                }.scrollIndicators(.hidden)
                if !management {entryActions.padding(.horizontal,24).padding(.top,14).padding(.bottom,22)}
            }.accessibilityHidden(confirmingReset)
            if confirmingReset {
                ConversationDeleteConfirmation(name:name,kind:.reset,
                    onCancel:{confirmingReset=false},onDelete:{confirmingReset=false;reset()})
            }
        }.foregroundStyle(Theme.ink).softSheetSurface()
            .accessibilityElement(children:.contain).accessibilityIdentifier("conversationInfoCard")
            .onAppear(perform:updateClosePolicy)
            .onChange(of:confirmingReset){updateClosePolicy()}
            .onChange(of:resetting){updateClosePolicy()}
            .onDisappear {closeRequest?.beforeClose=nil}
    }
    private var overview:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack(spacing:12) {
                avatar().frame(width:52,height:52)
                VStack(alignment:.leading,spacing:5) {
                    Text(name).font(.system(size:19,weight:.semibold,design:.rounded)).lineLimit(1)
                    (Text(LocalizedStringKey(summary.relationship)) + Text(" · ") +
                     Text(summary.nickname.isEmpty ? L10n.text("一起留下故事") : L10n.format("TA 叫你「%@」",summary.nickname)))
                        .font(.system(size:11)).foregroundStyle(Theme.secondary).lineLimit(2)
                }
                Spacer(minLength:0)
            }
            VStack(alignment:.leading,spacing:14) {
                HStack {
                    Label("你们的羁绊",systemImage:"sparkle").font(.system(size:12,weight:.medium))
                    Spacer()
                    Text(LocalizedStringKey(summary.stage)).font(.system(size:11,weight:.medium)).foregroundStyle(Theme.accent)
                        .accessibilityIdentifier("conversationBondStage")
                }
                HStack(alignment:.firstTextBaseline,spacing:5) {
                    Group {
                        if summary.daysSinceMeeting == 0 {Text("故事，等你开篇")}
                        else {Text("相识 \(summary.daysSinceMeeting) 天")}
                    }.font(.system(size:21,weight:.medium,design:.rounded))
                    Spacer(minLength:0)
                }
                HStack(spacing:0) {
                    metric("对话",value:L10n.format("%lld 轮",summary.userTurns),id:"conversationTurnCount")
                    metric("相伴",value:L10n.format("%lld 天",summary.activeDays),id:"conversationActiveDays")
                    metric("记忆",value:L10n.format("%lld 件",summary.memories.count),id:"conversationMemoryCount")
                }
            }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
                .background(LinearGradient(colors:[Theme.accent.opacity(0.10),Theme.surface.opacity(0.3)],
                    startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:20))
            if let first=summary.firstDate,let last=summary.lastMessage {
                VStack(alignment:.leading,spacing:14) {
                    timeline("初次相遇",date:first,symbol:"sparkle")
                    VStack(alignment:.leading,spacing:8) {
                        timeline("最近互动",date:last.date,symbol:"bubble.left")
                        Text((last.role == "user" ? "你：" : "\(name)：")+last.text)
                            .font(.system(size:13)).foregroundStyle(Theme.secondary).lineSpacing(4).lineLimit(3)
                            .padding(.leading,28).accessibilityIdentifier("conversationLatestMessage")
                    }
                }
            }
            VStack(alignment:.leading,spacing:10) {
                HStack {
                    Text("共同记忆").font(.system(size:12,weight:.medium))
                    Spacer()
                    if summary.memories.count>2 {
                        Text("共 \(summary.memories.count) 件").font(.system(size:10)).foregroundStyle(Theme.secondary)
                    }
                }
                if summary.memories.isEmpty {
                    Text("值得记住的小事，会慢慢留在这里。")
                        .font(.system(size:12)).foregroundStyle(Theme.secondary).lineSpacing(3)
                } else {
                    ForEach(Array(summary.memories.prefix(2))) { memory in
                        HStack(alignment:.top,spacing:9) {
                            Circle().fill(Theme.peach.opacity(0.8)).frame(width:4,height:4).padding(.top,7)
                            Text(memory.text).font(.system(size:12)).foregroundStyle(Theme.secondary).lineLimit(2).lineSpacing(3)
                        }
                    }
                }
            }
            if resetNotice {
                Label("已重置，下次进入会重新认识",systemImage:"checkmark")
                    .font(.system(size:12)).foregroundStyle(Theme.accent).accessibilityIdentifier("conversationResetSuccess")
            }
            if summary.resetPending {
                Text("上次清空尚未完成，请在更多选项中继续重置后再聊天。")
                    .font(.system(size:12)).foregroundStyle(Theme.peach)
            }
        }.padding(.horizontal,24).padding(.top,6).padding(.bottom,10)
    }
    private var entryActions:some View {
        HStack(spacing:10) {
            Button(action:onEnter) {
                HStack(spacing:9) {Text("进入会话");Image(systemName:"arrow.up.right").font(.system(size:12))}
                    .font(.system(size:14,weight:.semibold)).frame(maxWidth:.infinity,minHeight:46)
            }.buttonStyle(.plain).foregroundStyle(Theme.background)
                .background(Theme.gradient,in:Capsule()).disabled(summary.resetPending)
                .accessibilityIdentifier("enterConversation-"+characterID)
            Button(action:onHide) {
                Text("不显示").font(.system(size:12,weight:.medium)).frame(width:82,height:46)
            }.buttonStyle(.plain).foregroundStyle(Theme.secondary).background(Theme.card.opacity(0.6),in:Capsule())
                .accessibilityIdentifier("detailHideConversation-"+characterID)
        }
    }
    private var managementPage:some View {
        VStack(alignment:.leading,spacing:18) {
            Text("重新认识").font(.system(size:22,weight:.medium,design:.rounded))
            Text("清空你与「\(name)」的对话和记忆，从初次见面重新开始。")
                .font(.system(size:13)).foregroundStyle(Theme.secondary).lineSpacing(5)
            VStack(alignment:.leading,spacing:9) {
                Label("清空全部聊天记录、共同记忆和相处进度",systemImage:"bubble.left.and.bubble.right")
                Label("保留角色订阅、称呼和个人设置",systemImage:"person.crop.circle")
                Label("确认后无法撤销",systemImage:"exclamationmark.circle")
            }.font(.system(size:12)).foregroundStyle(Theme.secondary).padding(16)
                .frame(maxWidth:.infinity,alignment:.leading).background(Theme.card.opacity(0.5),in:RoundedRectangle(cornerRadius:17))
            Button(role:.destructive) {confirmingReset=true} label: {
                HStack(spacing:8) {
                    if resetting {ProgressView().tint(Color(hex:0xF1A2AD))}
                    else {Image(systemName:"arrow.counterclockwise")}
                    Text(LocalizedStringKey(resetting ? "正在重置…" : "重置角色"))
                }.font(.system(size:14,weight:.medium)).frame(maxWidth:.infinity,minHeight:46)
            }.buttonStyle(.plain).foregroundStyle(Color(hex:0xF1A2AD)).disabled(resetting)
                .background(Color(hex:0xC54659).opacity(0.16),in:Capsule())
                .accessibilityIdentifier("resetConversation-"+characterID)
            if let resetError {
                Text(LocalizedStringKey(resetError)).font(.system(size:12)).foregroundStyle(Theme.peach).lineSpacing(4)
                    .accessibilityIdentifier("conversationResetError")
            }
        }.padding(24)
    }
    private func metric(_ title:String,value:String,id:String) -> some View {
        VStack(alignment:.leading,spacing:5) {
            Text(value).font(.system(size:15,weight:.semibold,design:.rounded)).monospacedDigit()
                .accessibilityIdentifier(id)
            Text(LocalizedStringKey(title)).font(.system(size:10)).foregroundStyle(Theme.secondary)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func timeline(_ title:String,date:Date,symbol:String) -> some View {
        HStack(spacing:12) {
            Image(systemName:symbol).font(.system(size:12)).foregroundStyle(Theme.accent).frame(width:16)
            Text(LocalizedStringKey(title)).font(.system(size:12,weight:.medium))
            Spacer()
            Text(date,format:.dateTime.year().month().day()).font(.system(size:10)).foregroundStyle(Theme.secondary)
        }
    }
    private func updateClosePolicy() {
        closeRequest?.beforeClose={ !confirmingReset && !resetting }
    }
    private func reset() {
        guard !resetting else {return};resetting=true;resetError=nil
        Task { @MainActor in
            defer {resetting=false}
            do {
                try await onReset()
                withAnimation(motion) {resetNotice=true;management=false}
            } catch is CancellationError {}
            catch {resetError="重置尚未完成，请检查网络后重试。原记录会保留到服务确认完成。"}
        }
    }
}
