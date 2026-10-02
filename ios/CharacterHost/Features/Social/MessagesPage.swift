import SwiftUI

struct MessagesPage: View {
    @Bindable var coordinator:ViewerCoordinator
    @State private var search = ""
    @State private var hiddenPresented = false
    @State private var hiddenNotice: String?
    @State private var deletionCandidate:ModelDescriptor?
    @State private var showingDeletionConfirmation=false
    @State private var deletionOwner=""
    @State private var deleting=false
    @State private var deletionError:String?
    @State private var revealedConversation:String?
    @State private var swipeRestoreTask:Task<Void,Never>?
    @State private var detailCandidate:ModelDescriptor?
    @State private var showingConversationDetail=false
    @State private var pendingDetailEntry:String?
    private func showConversation(_ model:ModelDescriptor) {
        revealedConversation=nil
        detailCandidate=model;showingConversationDetail=true
    }
    private func detailDismissed() {
        detailCandidate=nil
        if let id=pendingDetailEntry {
            pendingDetailEntry=nil;coordinator.openCharacter(id)
        }
    }
    private func confirmDeletion(_ model:ModelDescriptor) {
        swipeRestoreTask?.cancel()
        deletionOwner=coordinator.companionStore.accountID;deletionCandidate=model;showingDeletionConfirmation=true
    }
    private func deletionDialogClosed() {
        deletionCandidate=nil;swipeRestoreTask?.cancel()
        // Let the confirmation finish dismissing, then softly close the row.
        // A reopened alert or a confirmed deletion owns its own completion.
        swipeRestoreTask=Task { @MainActor in
            do {try await Task.sleep(for:.milliseconds(reduceMotion ? 180 : 350))} catch {return}
            guard deletionCandidate==nil,!deleting else {return}
            withAnimation(.easeInOut(duration:0.25)) {revealedConversation=nil}
        }
    }
    private func deleteConfirmed(_ model:ModelDescriptor) {
        guard !deleting,deletionOwner==coordinator.companionStore.accountID else {return}
        deleting=true;deletionError=nil
        Task { @MainActor in
            defer{deleting=false;withAnimation(.easeInOut(duration:0.25)) {revealedConversation=nil}}
            do {try await coordinator.deleteConversation(model.id);hiddenNotice=nil}
            catch is CancellationError {}
            catch {deletionError="删除尚未完成，请确认服务连接后重试。已暂停这个角色的新对话，重试不会重复删除其他内容。"}
        }
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var query:String { search.trimmingCharacters(in:.whitespacesAndNewlines) }
    private var models:[ModelDescriptor] {
        coordinator.library.availableSubscriptions.filter { !isHidden($0) }.sorted {
            let a = coordinator.companionStore.record($0.id).messages.last?.date ?? .distantPast
            let b = coordinator.companionStore.record($1.id).messages.last?.date ?? .distantPast
            return a == b ? $0.id < $1.id : a > b
        }
    }
    private var hiddenModels:[ModelDescriptor] { coordinator.library.availableSubscriptions.filter(isHidden) }
    private func isHidden(_ model:ModelDescriptor) -> Bool {
        coordinator.library.isConversationHidden(model.id,latestMessage:coordinator.companionStore.record(model.id).messages.last?.date)
    }
    private func hide(_ model:ModelDescriptor) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration:0.22)) {
            revealedConversation=nil
            if coordinator.library.hideConversation(model.id,latestMessage:coordinator.companionStore.record(model.id).messages.last?.date) {
                hiddenNotice = model.id
            }
        }
    }
    private var results:[ConversationSearchHit] {
        let records = coordinator.companionStore.currentRecords
        let accessible = Set(records.keys.filter { coordinator.library.model($0) != nil })
        return ConversationSearch.find(query,records:records,visibleIDs:accessible)
    }
    var body:some View {
        VStack(spacing:0) {
            NightHeader(title:"消息",subtitle:"每一次靠近，都留在这里")
            CatalogSearchField(placeholder:"搜索本地聊天记录",text:$search,
                identifier:"conversationSearchField",clearIdentifier:"clearConversationSearch")
                .padding(.horizontal,24).padding(.bottom,12)
            if let id = hiddenNotice {
                HStack(spacing:10) {
                    Text("已不显示，聊天记录保留").font(.system(size:12)).foregroundStyle(Theme.secondary)
                    Spacer(minLength:0)
                    Button("撤销") {
                        if coordinator.library.restoreConversation(id) { hiddenNotice = nil }
                    }.font(.system(size:12,weight:.medium)).accessibilityIdentifier("undoHideConversation")
                }.padding(.horizontal,24).padding(.bottom,12).transition(.opacity)
            }
            if !hiddenModels.isEmpty {
                HStack {
                    Spacer()
                    Button { hiddenPresented = true } label: {
                        Label("不显示的对话 · \(hiddenModels.count)",systemImage:"eye.slash")
                            .font(.system(size:11)).foregroundStyle(Theme.secondary)
                            .padding(.vertical,8)
                    }.buttonStyle(.plain).accessibilityIdentifier("hiddenConversationsButton")
                }.padding(.horizontal,24)
            }
            if !query.isEmpty {
                searchResults
            } else if models.isEmpty {
                NightEmptyState(symbol:"bubble.left",title:hiddenModels.isEmpty ? "等一句，初次见面" : "消息列表，暂时留白",
                    detail:hiddenModels.isEmpty ? "订阅一个角色，开始你们的故事。" : "对话只是暂不显示，聊天记录仍保留。\n可以恢复，或去发现遇见新的伙伴。",
                    actionTitle:hiddenModels.isEmpty ? "去发现" : "恢复对话") {
                        if hiddenModels.isEmpty { coordinator.navigate(.discover) } else { hiddenPresented = true }
                    }
            } else {
                ScrollView {
                    LazyVStack(spacing:0) {
                        ForEach(models) { model in
                            ConversationSwipeRow(id:model.id,revealedID:$revealedConversation,locked:deleting || deletionCandidate != nil,
                                onOpen:{showConversation(model)},onHide:{hide(model)},onDelete:{confirmDeletion(model)}) {row(model)}
                        }
                    }.padding(.horizontal,24)
                }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively).accessibilityIdentifier("messageList")
            }
            if let error = coordinator.library.error { Text(LocalizedStringKey(error)).font(.caption).foregroundStyle(Theme.peach).padding(12) }
            if deleting {ProgressView("正在清空对话与记忆").font(.caption).padding(12)}
            if let deletionError {Text(LocalizedStringKey(deletionError)).font(.caption).foregroundStyle(Theme.peach).padding(12)}
        }.onChange(of:coordinator.companionStore.accountID) {
            swipeRestoreTask?.cancel();revealedConversation=nil
            search = ""; hiddenNotice = nil; hiddenPresented = false;showingDeletionConfirmation=false;deletionCandidate=nil;deletionError=nil
            showingConversationDetail=false;detailCandidate=nil;pendingDetailEntry=nil
        }
            .onDisappear {swipeRestoreTask?.cancel()}
            .accessibilityElement(children:.contain).accessibilityIdentifier("messagesPage")
            .softSheet(isPresented:$hiddenPresented,height:440) { hiddenConversations }
            .softSheet(isPresented:$showingConversationDetail,height:590,onDismiss:detailDismissed) {
                if let model=detailCandidate {conversationDetail(model)}
            }
            .onChange(of:showingDeletionConfirmation) {if !showingDeletionConfirmation {deletionDialogClosed()}}
            .accessibilityHidden(showingDeletionConfirmation)
            .overlay {
                if showingDeletionConfirmation, let model = deletionCandidate {
                    ConversationDeleteConfirmation(name:coordinator.profile(for:model).name,
                        onCancel:{showingDeletionConfirmation=false},
                        onDelete:{deleteConfirmed(model);showingDeletionConfirmation=false})
                }
            }
    }
    private func conversationDetail(_ model:ModelDescriptor) -> some View {
        let profile=coordinator.profile(for:model)
        let summary=ConversationRelationshipSummary(record:coordinator.companionStore.record(model.id),
            nickname:coordinator.companionStore.effectiveNickname(for:model.id))
        return ConversationInfoCard(name:profile.name,characterID:model.id,summary:summary,
            onEnter:{pendingDetailEntry=model.id;showingConversationDetail=false},
            onHide:{hide(model);showingConversationDetail=false},
            onReset:{try await coordinator.resetConversation(model.id)}) {
                CharacterAvatar(model:model,profile:profile,portraits:coordinator.portraits,size:52,floatingEnabled:false)
            }
    }
    private var hiddenConversations: some View {
        VStack(spacing:0) {
            PanelPageHeader("不显示的对话",backID:"closeHiddenConversations")
            Text("仅从消息列表隐藏。恢复后，聊天记录还在。")
                .font(.system(size:12)).foregroundStyle(Theme.secondary).padding(.horizontal,24).padding(.bottom,12)
            ScrollView {
                LazyVStack(spacing:8) {
                    ForEach(hiddenModels) { model in
                        HStack(spacing:12) {
                            CharacterAvatar(model:model,profile:coordinator.profile(for:model),portraits:coordinator.portraits,size:36,floatingEnabled:false)
                            Text(coordinator.profile(for:model).name).font(.system(size:14))
                            Spacer()
                            Button("恢复显示") {
                                if coordinator.library.restoreConversation(model.id) { hiddenNotice = nil }
                            }.font(.system(size:12,weight:.medium)).padding(.horizontal,12).frame(height:40)
                                .background(Theme.card,in:Capsule()).accessibilityIdentifier("restoreConversation-"+model.id)
                            Button(role:.destructive) {hiddenPresented=false;confirmDeletion(model)} label: {
                                Image(systemName:"trash").font(.system(size:13)).frame(width:36,height:40)
                            }.foregroundStyle(Color(hex:0xE2707E)).accessibilityLabel("删除对话和记忆").disabled(deleting)
                        }.padding(.vertical,8)
                    }
                    if hiddenModels.isEmpty { Text("所有对话都已恢复").font(.subheadline).foregroundStyle(Theme.secondary).padding(.top,40) }
                }.padding(.horizontal,24)
            }.scrollIndicators(.hidden)
        }.foregroundStyle(Theme.ink).softSheetSurface()
    }
    private var searchResults:some View {
        let hits = results
        return ScrollView {
            LazyVStack(alignment:.leading,spacing:0) {
                Text(hits.isEmpty ? "没有找到相关聊天记录" : "找到 \(hits.count) 条聊天记录")
                    .font(.system(size:12)).foregroundStyle(Theme.secondary).padding(.vertical,12)
                    .accessibilityIdentifier("conversationSearchCount")
                ForEach(hits) { hit in
                    if let model = coordinator.library.model(hit.characterID) {
                        Button {
                            coordinator.openCharacter(hit.characterID,messageID:hit.message.id)
                        } label: {
                            HStack(alignment:.top,spacing:12) {
                                CharacterAvatar(model:model,profile:coordinator.profile(for:model),portraits:coordinator.portraits,size:36)
                                VStack(alignment:.leading,spacing:7) {
                                    HStack {
                                        Text(coordinator.profile(for:model).name).font(.system(size:14,weight:.medium)).lineLimit(1)
                                        Spacer(minLength:8)
                                        Text(hit.message.date,format:.dateTime.month().day().hour().minute()).font(.system(size:10)).foregroundStyle(Theme.secondary)
                                    }
                                    (Text(hit.message.role == "user" ? "你：" : "") + highlighted(hit.excerpt))
                                        .font(.system(size:13)).foregroundStyle(Theme.secondary).lineLimit(3).lineSpacing(3)
                                }
                            }.padding(.vertical,13).contentShape(Rectangle())
                                .overlay(alignment:.bottom) { Rectangle().fill(Theme.line.opacity(0.45)).frame(height:0.5).padding(.leading,48) }
                        }.buttonStyle(.plain).accessibilityIdentifier("conversationHit-"+hit.id)
                    }
                }
            }.padding(.horizontal,24).frame(maxWidth:800).frame(maxWidth:.infinity)
        }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
    }
    private func highlighted(_ text:String) -> Text {
        // AttributedString uses safe Unicode indices, including Chinese and emoji.
        var value = AttributedString(text)
        for word in query.split(whereSeparator:{ $0.isWhitespace }) {
            var start = text.startIndex
            while start < text.endIndex, let range = text.range(of:String(word),options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],range:start..<text.endIndex) {
                if let converted = Range(range,in:value) { value[converted].foregroundColor = Theme.accent }
                start = range.upperBound
            }
        }
        return Text(value)
    }
    private func row(_ model:ModelDescriptor) -> some View {
        let profile = coordinator.profile(for:model), last = coordinator.companionStore.record(model.id).messages.last
        return HStack(spacing:12) {
            CharacterAvatar(model:model,profile:profile,portraits:coordinator.portraits,size:42)
            VStack(alignment:.leading,spacing:5) {
                HStack {
                    Text(profile.name).font(.system(size:15,weight:.medium)).lineLimit(1)
                    Spacer()
                    if let last { Text(last.date,format:.dateTime.month().day().hour().minute()).font(.system(size:10)).foregroundStyle(Theme.secondary) }
                }
                Text(last.map { ($0.role == "user" ? "你：" : "")+$0.text } ?? L10n.text("已订阅 · 查看相处资料"))
                    .font(.system(size:13)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
        }.padding(.vertical,11).overlay(alignment:.bottom) { Rectangle().fill(Theme.line.opacity(0.6)).frame(height:0.5).padding(.leading,54) }
            .contentShape(Rectangle())
    }
}
