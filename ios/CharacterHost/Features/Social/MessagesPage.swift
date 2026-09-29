import SwiftUI

struct MessagesPage: View {
    @Bindable var coordinator:ViewerCoordinator
    @State private var search = ""
    @FocusState private var searching:Bool
    private var query:String { search.trimmingCharacters(in:.whitespacesAndNewlines) }
    private var models:[ModelDescriptor] {
        Set(coordinator.library.subscriptions).compactMap { coordinator.library.model($0) }.sorted {
            let a = coordinator.companionStore.record($0.id).messages.last?.date ?? .distantPast
            let b = coordinator.companionStore.record($1.id).messages.last?.date ?? .distantPast
            return a == b ? $0.id < $1.id : a > b
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
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass").foregroundStyle(Theme.secondary)
                TextField("搜索本地聊天记录",text:$search).font(.subheadline).focused($searching)
                    .submitLabel(.search).onSubmit { searching = false }
                    .accessibilityIdentifier("conversationSearchField")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(Theme.secondary).frame(width:28,height:28) }
                        .buttonStyle(.plain).accessibilityLabel("清除搜索").accessibilityIdentifier("clearConversationSearch")
                }
            }.padding(.horizontal,14).frame(minHeight:48).background(Theme.surface,in:RoundedRectangle(cornerRadius:15))
                .padding(.horizontal,24).padding(.bottom,12)
            if !query.isEmpty {
                searchResults
            } else if models.isEmpty {
                NightEmptyState(symbol:"bubble.left",title:"等一句，初次见面",detail:coordinator.library.subscriptions.isEmpty ? "订阅一个角色，开始你们的故事。" : "已订阅的角色暂时不可用，历史记录仍保留。",actionTitle:"去发现") { searching = false; coordinator.navigate(.discover) }
            } else {
                ScrollView {
                    LazyVStack(spacing:0) {
                        ForEach(models) { model in
                            Button { searching = false; coordinator.openCharacter(model.id) } label: { row(model) }
                                .buttonStyle(.plain).accessibilityIdentifier("message-"+model.id)
                        }
                    }.padding(.horizontal,24).frame(maxWidth:800).frame(maxWidth:.infinity)
                }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
            }
        }.onChange(of:coordinator.companionStore.accountID) { search = ""; searching = false }
            .accessibilityElement(children:.contain).accessibilityIdentifier("messagesPage")
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
                            searching = false
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
                Text(last.map { ($0.role == "user" ? "你：" : "")+$0.text } ?? "已订阅 · 轻点开始聊天")
                    .font(.system(size:13)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
        }.padding(.vertical,11).overlay(alignment:.bottom) { Rectangle().fill(Theme.line.opacity(0.6)).frame(height:0.5).padding(.leading,54) }
            .contentShape(Rectangle())
    }
}
