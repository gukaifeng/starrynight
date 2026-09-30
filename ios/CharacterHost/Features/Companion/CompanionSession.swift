import Foundation
import Observation

@MainActor @Observable
final class CompanionSession {
    let store: CompanionStore
    let model: ModelDescriptor
    let speech: CloudSpeech
    let soundscape: CompanionSoundscape
    let api: CharacterAI
    var inspectionActive = false
    var dismissKeyboardRequest = 0
    var characterEditorPresented = false { didSet { if !characterEditorPresented { deliverPendingGreeting() } } }
    var input = ""
    var generating = false
    var notice: String?
    var currentAction = ""
    private(set) var focusedMessageID: UUID?
    private(set) var messageFocusRequest = 0
    var visibleMessages: [CompanionMessage] { ConversationSearch.window(record.messages,around:focusedMessageID) }
    func focusMessage(_ id: UUID) {
        guard record.messages.contains(where:{ $0.id == id }) else { return }
        dismissKeyboardRequest += 1; focusedMessageID = id; messageFocusRequest += 1
    }
    func clearMessageFocus() { focusedMessageID = nil }
    func clearMessages() {
        stop()
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await api.clearMessages(); try Task.checkCancellation()
                guard store.accountID == ownerID else { return }
                store.update(model.id) { $0.messages = [] }; clearMessageFocus()
            } catch { if !Task.isCancelled { notice = "尚未清空：请确认 AI 服务连接后重试。" } }
        }
    }
    var isGuest: Bool { store.accountID == "guest" }
    var remainingGuestTurns: Int { max(0,5-store.guestTurns) }
    @ObservationIgnored var onLoginRequested: (() -> Void)?
    @ObservationIgnored var onIntent: ((CharacterIntent) -> Void)?
    @ObservationIgnored var onAppearance: ((CharacterProfile) -> Void)?
    @ObservationIgnored var onPosture: ((PosturePreferences) async -> String?)?
    @ObservationIgnored var onAIVisual: (([AIVisual]) -> Void)?
    @ObservationIgnored var onEndAIVisual: (() -> Void)?
    @ObservationIgnored private var task: Task<Void,Never>?
    @ObservationIgnored private var idleTask: Task<Void,Never>?
    @ObservationIgnored private var silentVisualTask: Task<Void,Never>?
    @ObservationIgnored private var token = UUID()
    @ObservationIgnored private var activeTurn = false
    @ObservationIgnored private var pendingGreeting: ConversationEntry?
    @ObservationIgnored private let ownerID: String
    @ObservationIgnored private var activeScript: AIScript?
    @ObservationIgnored private var performedBeats = Set<String>()
    @ObservationIgnored private var microphoneDraft = ""
    var record: CharacterRecord {
        var value = store.record(model.id)
        value.profile = model.conversationProfile(preserving:value.profile)
        return value
    }
    func requestLogin() { dismissKeyboardRequest += 1; onLoginRequested?() }
    private func allowReply() -> Bool {
        if isGuest && store.guestLimitReached { requestLogin(); return false }; return true
    }
    var muted: Bool { soundscape.speechVolume <= 0 }
    var effectiveVoiceSpeed: Double { 1 } // Voice Design and per-beat delivery own the voice.
    func setSpeechVolume(_ value: Double) {
        soundscape.setSpeechVolume(value)
        if muted {
            speech.stop()
            if let activeScript { playSilentVisuals(activeScript) }
        } else { speech.refreshVolume() }
    }
    var availableActions: [CharacterAction] { model.availableActions(for:record.profile.resolvedStudio.posture ?? PosturePreferences()) }
    func performAction(_ id: String) {
        guard availableActions.contains(where:{ $0.id == id }) else { return }
        onEndAIVisual?(); onIntent?(CharacterIntent(eventName:"action.request",target:id))
    }
    init(store: CompanionStore, model: ModelDescriptor, soundscape: CompanionSoundscape) {
        self.store = store; self.model = model; self.soundscape = soundscape; ownerID = store.accountID
        api = CharacterAI(accountID:store.accountID,characterID:model.id)
        speech = CloudSpeech(soundscape:soundscape,api:api,cacheScope:store.accountID+"|"+model.id)
        let account = store.accountID
        speech.onDuration = { [weak store] id,speed,duration in
            guard let store, store.accountID == account else { return }
            store.update(model.id) { record in
                if let index = record.messages.firstIndex(where:{ $0.id == id }) {
                    record.messages[index].speechDuration = duration; record.messages[index].speechSpeed = speed
                }
            }
        }
        soundscape.configure(collection:model.collection,profile:model.conversationProfile(preserving:store.record(model.id).profile)) { [weak store] preferences in
            guard let store, store.accountID == account else { return }; store.update(model.id) { $0.profile.audio = preferences }
        }
        speech.nickname = { [weak self] in self?.record.together.preferences.normalized.nickname ?? "" }
        speech.onTranscript = { [weak self] text in
            guard let self else { return }; self.input = String((self.microphoneDraft+text).prefix(500)); self.microphoneDraft = ""
        }
        speech.onPartial = { [weak self] text in
            guard let self else { return }; self.input = String((self.microphoneDraft+text).prefix(500))
        }
        speech.onState = { [weak self] state in
            guard let self else { return }
            if state == "listening" { self.microphoneDraft = self.input.isEmpty ? "" : self.input+" " }
            self.emit("state."+state)
        }
        speech.onFrame = { [weak self] time,level in
            guard let self, self.activeTurn else { return }
            self.onIntent?(CharacterIntent(eventName:"speech.frame",turnId:self.token.uuidString,audioTime:time,level:Double(level)))
        }
        speech.onBeat = { [weak self] id in
            guard let self, let beat = self.activeScript?.beats.first(where:{ $0.beatId == id }) else { return }
            self.performedBeats.insert(id)
            self.onAIVisual?(beat.visuals)
        }
    }
    func enterConversation(_ entry: ConversationEntry) {
        guard entry.characterID == model.id, entry.accountID == ownerID, store.accountID == ownerID,
              ConversationGreetingPolicy.shouldGreet(record,entry:entry) else { return }
        pendingGreeting = entry; deliverPendingGreeting()
    }
    private func deliverPendingGreeting() {
        guard let entry = pendingGreeting, !characterEditorPresented, store.accountID == ownerID else { return }
        pendingGreeting = nil
        guard ConversationGreetingPolicy.shouldGreet(record,entry:entry), !generating, !speech.isRecording, !speech.isBusy, !speech.isSpeaking else { return }
        let context = ConversationGreetingContext.make(reason:entry.reason,record:record,
            hasMetAnyone:store.currentRecords.values.contains { $0.greeting != nil || !$0.messages.isEmpty })
        generate("",trigger:context.scene,entry:entry)
    }
    func send() {
        let text = String(input.trimmingCharacters(in:.whitespacesAndNewlines).prefix(500))
        guard !text.isEmpty, allowReply() else { return }
        stop(); input = ""; notice = nil
        store.update(model.id,countGuestTurn:true) { record in
            record.messages.append(CompanionMessage(role:"user",text:text,source:"cloud-v1"))
        }
        guard store.error == nil else { input = text; return }
        generate(text,trigger:record.together.activeStoryID == nil ? "user_message" : "story")
    }
    func beginStory(_ story: CompanionStory,replay: Bool = false) {
        guard store.accountID == ownerID, allowReply() else { return }
        store.update(model.id) { record in
            var experience = record.together; experience.activeStoryID = story.id
            experience.stories[story.id] = StoryProgress(storyID:story.id); record.experiences = experience
        }
        input = "我们来共同创作一个虚构故事："+story.title+"。"+story.subtitle+" 请以讲故事的方式开场，不能把故事中的行动说成模型实际做出的动作。"
        send()
    }
    func continueStory() { input = "请接着讲我们的故事，留一点空间让我决定接下来发生什么。"; send() }
    private func emit(_ name: String) { onIntent?(CharacterIntent(eventName:name,turnId:activeTurn ? token.uuidString : "")) }
    private func beginTurn() { activeTurn = true; emit("turn.begin") }
    func requestBody(_ text:String,trigger:String)->[String:Any] {
        let p = record.together.preferences.normalized
        var recent = record.messages.filter { $0.source == "cloud-v1" }
        if recent.last?.role == "user", recent.last?.text == text { recent.removeLast() }
        return ["request_id":UUID().uuidString,"character_id":model.id,"text":text,"trigger":trigger,
            "preferences":["nickname":p.nickname,"aboutMe":p.aboutMe,"relationship":p.relationship,"responseStyle":p.responseStyle,"avoidedTopics":p.avoidedTopics],
            "memories":record.memories.suffix(100).map { ["id":$0.id.uuidString,"text":$0.text] },
            "recent_messages":recent.suffix(12).map { ["role":$0.role,"text":String($0.text.prefix(700))] },
            "scene":["time":Date().formatted(date:.omitted,time:.shortened),"environment":model.display.description],
            "available_assets":model.performance?.options.map(\.id) ?? [],"wants_audio":!muted]
    }
    private func generate(_ text: String,trigger: String,entry: ConversationEntry? = nil) {
        stop(); let current = token; generating = true; beginTurn(); emit("state.thinking")
        var body=requestBody(text,trigger:trigger)
        if let entry { body["entry_id"] = entry.id.uuidString }
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            var received = false
            do {
                try await api.events(path:"/v1/conversations/"+model.id+"/messages",body:body) { [weak self] event in
                    guard let self, current == self.token, self.store.accountID == self.ownerID else { throw CancellationError() }
                    switch event.type {
                    case "reply.narration.ready":
                        guard let script = event.script, !script.beats.isEmpty else { return }
                        received = true; self.activeScript = script; self.generating = false
                        let message = CompanionMessage(id:UUID(uuidString:script.messageId) ?? UUID(),role:"assistant",text:script.text,
                            proactiveScene:trigger == "user_message" ? nil : trigger,aiScript:script,source:"cloud-v1")
                        self.store.update(self.model.id) { record in
                            if !record.messages.contains(where:{ $0.id == message.id }) { record.messages.append(message) }
                            if let source = record.messages.last(where:{ $0.role == "user" }) {
                                var together = record.together
                                for text in script.memorySuggestions ?? [] where !record.memories.contains(where:{ $0.text == text }) && !together.suggestions.contains(where:{ $0.text == text }) {
                                    together.suggestions.append(MemorySuggestion(sourceMessageID:source.id,text:text))
                                }
                                together.suggestions = Array(together.suggestions.suffix(12)); record.experiences = together
                            }
                            if let entry {
                                record.greeting = ConversationGreetingHistory(count:(record.greeting?.count ?? 0)+1,lastDate:Date(),lastText:script.text,lastEntryID:entry.id)
                            }
                        }
                        if !self.muted {
                            self.speech.prepare(message.id,script:script)
                            // React when the text arrives, even while voice is
                            // connecting. Audio onset then aligns/renews the beat.
                            if let first=script.beats.first {
                                self.performedBeats.insert(first.beatId)
                                self.onAIVisual?(first.visuals)
                            }
                        }
                        else { self.playSilentVisuals(script) }
                    case "reply.script.updated":
                        guard let script=event.script,let id=UUID(uuidString:script.messageId) else {return}
                        if self.activeScript?.messageId==script.messageId {self.activeScript=script}
                        self.store.update(self.model.id) { record in
                            if let index=record.messages.firstIndex(where:{$0.id==id}) {
                                record.messages[index].aiScript=script
                            }
                        }
                    case "reply.warning": self.notice = event.message
                    case "segment.audio.started", "segment.audio.chunk", "segment.audio.ready", "audio.error":
                        if !self.muted { try await self.speech.accept(event) }
                        if event.type == "audio.error", let script=self.activeScript { self.playSilentVisuals(script) }
                    default: break
                    }
                }
                guard current == token else { return }
                generating = false; speech.finish()
                if !muted, let script=activeScript { playSilentVisuals(script) }
                // Each group has its own bounded restore timer. Finishing a
                // short utterance must not immediately erase its expression.
                emit("state.idle")
                if trigger == "user_message" { scheduleIdle() }
            } catch {
                guard current == token, !Task.isCancelled else { return }
                generating = false; speech.stop()
                if received, let script=activeScript { playSilentVisuals(script) }
                else { onEndAIVisual?() }
                emit("state.idle")
                if !(error is CancellationError) {
                    notice = (error as? LocalizedError)?.errorDescription ?? "AI 连接中断，请稍后重试。"
                    if !received && !text.isEmpty && input.isEmpty { input = text }
                }
            }
        }
    }
    private func scheduleIdle() {
        idleTask?.cancel()
        idleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for:.seconds(Int.random(in:150...240)))
            guard !Task.isCancelled, let self, !self.generating, !self.speech.isRecording, !self.speech.isBusy,
                  !self.speech.isSpeaking, self.input.isEmpty, !self.characterEditorPresented else { return }
            self.generate("",trigger:"idle")
        }
    }
    private func playSilentVisuals(_ script: AIScript) {
        let remaining=script.beats.filter { !performedBeats.contains($0.beatId) }
        guard !remaining.isEmpty else { return }
        silentVisualTask?.cancel()
        silentVisualTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for beat in remaining {
                guard !Task.isCancelled else { return }
                // A voice beat may have arrived since this fallback was queued.
                guard !performedBeats.contains(beat.beatId) else { continue }
                performedBeats.insert(beat.beatId)
                onAIVisual?(beat.visuals)
                try? await Task.sleep(for:.milliseconds(beat.visuals.map(\.durationMs).max() ?? 2500))
            }
        }
    }
    func playMessage(_ message: CompanionMessage) {
        if speech.activeMessageID == message.id { stop(); return }
        guard !muted else { notice = "请先在声音面板调高角色语音音量。"; return }
        guard let script = message.aiScript else { return }
        stop(); let current = token; activeScript = script; beginTurn()
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if try await speech.cachedReplay(script,messageID:message.id) { playSilentVisuals(script); return }
                speech.prepare(message.id,script:script)
                try await api.events(path:"/v1/conversations/"+model.id+"/messages/"+script.messageId+"/audio",body:nil) { [weak self] event in
                    guard let self, self.token == current else { throw CancellationError() }
                    try await self.speech.accept(event)
                }
                guard current == token else { return }; speech.finish(); playSilentVisuals(script)
            } catch {
                guard current == token, !Task.isCancelled else { return }
                speech.stop(); playSilentVisuals(script); notice = (error as? LocalizedError)?.errorDescription ?? "语音暂时不可用。"
            }
        }
    }
    func stop() {
        pendingGreeting = nil; task?.cancel(); task = nil; idleTask?.cancel(); idleTask = nil
        silentVisualTask?.cancel(); silentVisualTask = nil
        if activeTurn { emit("turn.cancel") }
        activeTurn = false; token = UUID(); generating = false; activeScript = nil
        performedBeats.removeAll()
        speech.stop(); onEndAIVisual?()
    }
}
