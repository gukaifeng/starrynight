import SwiftUI
import UIKit

struct CharacterProfileView: View {
    let model: ModelDescriptor
    let store: CompanionStore
    var onSave: ((CharacterProfile) -> Void)?
    @Environment(\.softPanelDismiss) private var dismiss
    @Environment(\.softPanelCloseRequest) private var close
    @State private var profile: CharacterProfile
    private enum InputField: Hashable { case name, background }
    @FocusState private var focusedField: InputField?
    init(model: ModelDescriptor, store: CompanionStore, onSave: ((CharacterProfile) -> Void)? = nil) {
        self.model = model; self.store = store; self.onSave = onSave
        _profile = State(initialValue:store.record(model.id).profile)
    }
    var body: some View {
        VStack(spacing:0) {
            PanelPageHeader("塑造角色",backID:"closeProfileButton") {
                if focusedField != nil {
                    Button { focusedField = nil } label: {
                        Image(systemName:"keyboard.chevron.compact.down").frame(width:44,height:44)
                    }.accessibilityLabel("收起键盘").accessibilityIdentifier("finishProfileInput")
                }
            }
            Form {
                Group {
                Section("我们的相处方式") {
                    TextField("角色昵称",text:$profile.name).focused($focusedField,equals:.name).accessibilityIdentifier("profileName")
                    TextField("背景与关系",text:$profile.background,axis:.vertical).lineLimit(3...5).focused($focusedField,equals:.background).accessibilityIdentifier("profileBackground")
                    Picker("性格",selection:$profile.personality) { ForEach(["温柔","活泼","理性"],id:\.self) { Text($0) } }
                    Picker("语气",selection:$profile.tone) { ForEach(["自然","温暖","轻松"],id:\.self) { Text($0) } }
                    Toggle("偏好简短回复",isOn:$profile.concise).accessibilityIdentifier("conciseToggle")
                }
                Section("角色的色彩与空间") {
                    Picker("点缀配色",selection:$profile.accent) { ForEach(["玉青","鸢紫","暖金"],id:\.self) { Text($0) } }.accessibilityIdentifier("accentPicker")
                    Picker("空间氛围",selection:$profile.ambience) { ForEach(["晨光","暖暮","月色"],id:\.self) { Text($0) } }
                    Text("配色作用于 Luma 的珐琅与灯光、初音的发色；保留角色原有服装和材质细节。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("声音") {
                    Toggle("自动朗读回复",isOn:$profile.autoSpeak).accessibilityIdentifier("autoSpeakToggle")
                    HStack { Text("语速"); Slider(value:$profile.voiceSpeed,in:0.7...1.4,step:0.1); Text(String(format:"%.1f×",profile.voiceSpeed)).monospacedDigit() }
                    Picker("说话节奏",selection:Binding(get:{model.collection.voice(profile.voiceID).id},set:{profile.voiceID = $0})) {
                        ForEach(model.collection.voices) { voice in Text(voice.title).tag(voice.id) }
                    }.accessibilityIdentifier("characterVoicePicker")
                    Text("此角色的离线中文声音预设。预设调整说话节奏，语速可继续微调。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section { Text("当前为本地情景对话。设定影响称呼、介绍和回复风格，不代表已经训练了通用 AI 模型。").font(.footnote).foregroundStyle(.secondary) }
                if let error = store.error { Text(error).foregroundStyle(.red) }
                }.listRowBackground(Theme.surface.opacity(0.72))
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden).scrollContentBackground(.hidden)
            .contentMargins(.top,0,for:.scrollContent).pickerStyle(.menu)
        }.tint(Theme.accent).softPanelPageSurface()
            .onAppear { close?.beforeClose = {
                focusedField = nil
                if let onSave { onSave(profile) } else { store.saveProfile(model.collection.normalize(profile),id:model.id) }
                return store.error == nil
            } }
            .onDisappear { close?.beforeClose = nil }
    }
}

struct CompanionMemoryView: View {
    let store: CompanionStore
    let model: ModelDescriptor
    @Environment(\.softPanelDismiss) private var dismiss
    @State private var draft = ""
    @State private var editing: UUID?
    var body: some View {
        VStack(spacing:0) {
            PanelPageHeader("共同记忆",backID:"closeMemoryButton")
            List {
                Group {
                Section {
                    Text("只有你主动保存的内容会成为记忆。它们只属于这个角色，可以随时修改或删除。")
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                }
                Section(editing == nil ? "留下一件重要的事" : "编辑记忆") {
                    TextField("例如：我喜欢海边和安静的音乐",text:$draft,axis:.vertical).lineLimit(2...4).accessibilityIdentifier("memoryInput")
                    Button(editing == nil ? "保存记忆" : "保存修改") {
                        if let id = editing {
                            let text = String(draft.trimmingCharacters(in:.whitespacesAndNewlines).prefix(300))
                            store.update(model.id) { if let index = $0.memories.firstIndex(where: { $0.id == id }) { $0.memories[index].text = text } }
                        } else { store.addMemory(draft,id:model.id) }
                        if store.error == nil { draft = ""; editing = nil }
                    }.disabled(draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveMemoryButton")
                    if editing != nil { Button("取消编辑") { editing = nil; draft = "" } }
                }
                if !store.record(model.id).together.suggestions.isEmpty {
                    Section("从聊天里发现 · 等你确认") {
                        ForEach(store.record(model.id).together.suggestions) { suggestion in
                            VStack(alignment:.leading,spacing:10) {
                                Text(suggestion.text).font(.subheadline)
                                Text("来自你说的话 · 确认后才会记住").font(.caption2).foregroundStyle(Theme.secondary)
                                HStack {
                                    Button("记住这件事") { store.reviewMemory(suggestion.id,id:model.id,accept:true) }
                                        .buttonStyle(.borderless).accessibilityIdentifier("acceptMemorySuggestion")
                                    Spacer()
                                    Button("忽略") { store.reviewMemory(suggestion.id,id:model.id,accept:false) }
                                        .buttonStyle(.borderless).foregroundStyle(Theme.secondary).accessibilityIdentifier("dismissMemorySuggestion")
                                }.font(.caption).frame(minHeight:36)
                            }.padding(.vertical,5)
                        }
                    }
                }
                Section("\(model.conversationProfile(preserving:store.record(model.id).profile).name) 的记忆 · \(store.record(model.id).memories.count)") {
                    if store.record(model.id).memories.isEmpty { Text("还没有记忆。从一件小事开始吧。").foregroundStyle(.secondary) }
                    ForEach(store.record(model.id).memories) { memory in
                        VStack(alignment:.leading,spacing:10) {
                            Text(memory.text)
                            HStack {
                                Button("编辑") { editing = memory.id; draft = memory.text }.buttonStyle(.borderless).accessibilityIdentifier("editMemoryButton")
                                Spacer()
                                Button("删除",role:.destructive) { store.update(model.id) { $0.memories.removeAll { $0.id == memory.id } } }.buttonStyle(.borderless).accessibilityIdentifier("deleteMemoryButton")
                            }.font(.caption)
                        }.padding(.vertical,6)
                    }
                }
                if let error = store.error { Text(error).foregroundStyle(.red) }
                }.listRowBackground(Theme.surface.opacity(0.72))
            }
            .scrollIndicators(.hidden).scrollContentBackground(.hidden)
            .contentMargins(.top,0,for:.scrollContent)
        }.tint(Theme.accent).softPanelPageSurface()
    }
}

struct CompanionHistoryView: View {
    let session: CompanionSession
    var portraits: CharacterPortraitStore? = nil
    @Environment(\.softPanelDismiss) private var dismiss
    @Environment(\.softPanelCloseRequest) private var close
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var confirmClear = false
    @State private var exportURL: URL?
    @State private var imageExport: ConversationExportSnapshot?
    @State private var exportClose = SoftPanelCloseRequest()
    @FocusState private var searchFocused: Bool
    private var motion: Animation { .easeInOut(duration:reduceMotion ? 0.1 : 0.25) }
    var body: some View {
        ZStack {
            // Keep the history list mounted so its filter and scroll position
            // survive every export-page round trip inside this same panel.
            history.opacity(imageExport == nil ? 1 : 0)
                .allowsHitTesting(imageExport == nil).disabled(imageExport != nil)
                // A layout-only VStack can have its accessibility children
                // flattened into the parent. Give the retained page an explicit
                // boundary, and omit its descendants while it is covered.
                .accessibilityElement(children:imageExport == nil ? .contain : .ignore)
                .accessibilityHidden(imageExport != nil)
            if let imageExport {
                ConversationExportView(snapshot:imageExport)
                    .environment(\.softPanelCloseRequest,exportClose)
                    .environment(\.softPanelDismiss,{ exportClose.request() })
                    .transition(.opacity).zIndex(1)
            }
        }.tint(Theme.accent).softPanelPageSurface()
            .onAppear { close?.beforeClose = { exportClose.beforeClose?() ?? true } }
            .onDisappear { close?.beforeClose = nil; exportClose.beforeClose = nil }
    }
    private var history: some View {
        VStack(spacing:0) {
            if imageExport == nil {
                PanelPageHeader("聊天与资料",backID:"closeHistoryButton")
            } else {
                // Retain the list's layout and state, but remove the inactive
                // button itself: UIKit accessibility can otherwise keep a
                // flattened SwiftUI header alive despite ancestor AX hiding.
                // PanelPageHeader is 44 pt + 16 pt top + 12 pt bottom.
                Color.clear.frame(height:72).accessibilityHidden(true)
            }
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass").foregroundStyle(Theme.secondary)
                TextField("搜索聊天",text:$query).focused($searchFocused)
                    .font(.subheadline).accessibilityIdentifier("historySearch")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName:"xmark.circle.fill").foregroundStyle(Theme.secondary)
                            .frame(width:32,height:32)
                    }.buttonStyle(.plain).accessibilityLabel("清除搜索")
                }
            }.padding(.horizontal,14).frame(minHeight:44)
                .background(Theme.surface.opacity(0.72),in:Capsule())
                .padding(.horizontal,22).padding(.bottom,12)
            List {
                Group {
                Section {
                    Button {
                        searchFocused = false
                        let snapshot = ConversationExportSnapshot.capture(model:session.model,record:session.record,portraits:portraits)
                        // Each new entry resets the one-shot close request.
                        exportClose.begin { withAnimation(motion) { imageExport = nil } }
                        withAnimation(motion) { imageExport = snapshot }
                    } label: { Label("选择片段，导出对话长图",systemImage:"square.and.arrow.up") }
                        .accessibilityIdentifier("historyExportImageButton")
                }
                Section {
                    Text("最近 1,000 条消息保存在本机。导出含这个角色的设定、记忆和聊天记录，请自行选择分享对象。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let exportURL { ShareLink("分享导出的资料",item:exportURL).accessibilityIdentifier("shareArchiveButton") }
                    Button("准备导出资料") { do { exportURL = try session.store.export(session.model.id) } catch { session.notice = "导出失败，请稍后重试。" } }.accessibilityIdentifier("exportArchiveButton")
                    Button("清空此角色的聊天",role:.destructive) { confirmClear = true }.accessibilityIdentifier("clearHistoryButton")
                }
                ForEach(session.record.messages.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) }) { message in
                    VStack(alignment:.leading,spacing:7) {
                        HStack { Text(message.role == "user" ? "我" : session.record.profile.name); Spacer(); Text(message.date,style:.time) }
                            .font(.caption).foregroundStyle(.secondary)
                        Text(message.text).font(.system(size:session.store.chatDisplay.normalized.fontSize)).textSelection(.enabled)
                    }.padding(.vertical,4)
                }
                }.listRowBackground(Theme.surface.opacity(0.72))
            }
            .scrollIndicators(.hidden).scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively).contentMargins(.top,0,for:.scrollContent)
            .confirmationDialog("清空后无法恢复，角色设定与记忆仍保留。",isPresented:$confirmClear,titleVisibility:.visible) {
                Button("确认清空聊天",role:.destructive) { session.stop(); session.store.update(session.model.id) { $0.messages = [] } }
            }
        }
    }
}
