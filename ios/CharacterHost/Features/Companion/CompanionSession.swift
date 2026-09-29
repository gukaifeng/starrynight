import Foundation
import Observation

@MainActor @Observable
final class CompanionSession {
    let store: CompanionStore
    let model: ModelDescriptor
    let speech: LocalSpeech
    let soundscape: CompanionSoundscape
    var inspectionActive = false
    var dismissKeyboardRequest = 0
    var characterEditorPresented = false {
        didSet { if !characterEditorPresented { deliverPendingGreeting() } }
    }
    var input = ""
    var draftReply = ""
    var generating = false
    var notice: String?
    var currentAction = ""
    private(set) var focusedMessageID:UUID?
    private(set) var messageFocusRequest = 0
    var visibleMessages:[CompanionMessage] { ConversationSearch.window(record.messages,around:focusedMessageID) }
    func focusMessage(_ id:UUID) {
        guard record.messages.contains(where:{ $0.id == id }) else { return }
        dismissKeyboardRequest += 1; focusedMessageID = id; messageFocusRequest += 1
    }
    func clearMessageFocus() { focusedMessageID = nil }
    var isGuest: Bool { store.accountID == "guest" }
    var remainingGuestTurns: Int { max(0,5-store.guestTurns) }
    @ObservationIgnored var onLoginRequested: (() -> Void)?
    func requestLogin() { dismissKeyboardRequest += 1; onLoginRequested?() }
    private func allowReply() -> Bool {
        if isGuest && store.guestLimitReached { requestLogin(); return false }
        return true
    }
    var muted: Bool { soundscape.speechVolume <= 0 }
    func setSpeechVolume(_ value:Double) {
        soundscape.setSpeechVolume(value)
        if muted { speech.stop() } else { speech.refreshVolume() }
    }
    var effectiveVoiceSpeed:Double {
        let profile = model.collection.normalize(record.profile)
        return min(1.4,max(0.7,profile.voiceSpeed * model.collection.voice(profile.voiceID).speed))
    }
    func playMessage(_ message:CompanionMessage) {
        if speech.activeMessageID == message.id { speech.stop(); return }
        readAloud(message.text,messageID:message.id,manual:true)
    }
    func readAloud(_ text:String, messageID:UUID? = nil, manual:Bool = false) {
        guard !muted else { return }
        speech.speak(text,speed:effectiveVoiceSpeed,messageID:messageID)
    }
    var availableActions: [CharacterAction] {
        model.availableActions(for:record.profile.resolvedStudio.posture ?? PosturePreferences())
    }
    func performAction(_ id:String) {
        guard availableActions.contains(where:{ $0.id == id }) else {
            notice = "当前姿势暂不支持这个动作，可以先调整姿势。"; return
        }
        // Explicit gestures do not become chat messages or interrupt a spoken reply.
        onIntent?(CharacterIntent(eventName:"action.request",target:id))
    }
    @ObservationIgnored var onIntent: ((CharacterIntent) -> Void)?
    
    @ObservationIgnored var onAppearance: ((CharacterProfile) -> Void)?
    @ObservationIgnored var onPosture: ((PosturePreferences) async -> String?)?
    @ObservationIgnored private var task: Task<Void,Never>?
    @ObservationIgnored private var token = UUID()
    @ObservationIgnored private var variant = 0
    @ObservationIgnored private var activeTurn = false
    @ObservationIgnored private var pendingGreeting: ConversationEntry?
    @ObservationIgnored private let ownerID: String
    var record: CharacterRecord {
        var value = store.record(model.id)
        value.profile = model.conversationProfile(preserving:value.profile)
        return value
    }
    init(store: CompanionStore, model: ModelDescriptor, soundscape: CompanionSoundscape) {
        self.store = store; self.model = model; self.soundscape = soundscape; ownerID = store.accountID
        speech = LocalSpeech(soundscape:soundscape,cacheScope:store.accountID+"|"+model.id)
        let accountID = store.accountID
        speech.onDuration = { [weak store] id,speed,duration in
            guard let store, store.accountID == accountID else { return }
            store.update(model.id) { record in
                if let index = record.messages.firstIndex(where:{ $0.id == id }) {
                    record.messages[index].speechDuration = duration; record.messages[index].speechSpeed = speed
                }
            }
        }
        soundscape.configure(collection:model.collection,profile:model.conversationProfile(preserving:store.record(model.id).profile)) { [weak store] preferences in
            guard let store, store.accountID == accountID else { return }
            store.update(model.id) { $0.profile.audio = preferences }
        }
        speech.onTranscript = { [weak self] text in self?.input = String(text.prefix(500)) }
        speech.onState = { [weak self] state in
            guard let self else { return }
            if state != "idle" && !self.activeTurn { self.beginTurn() }
            self.emit("state." + state)
        }
        speech.onFrame = { [weak self] time, value in
            guard let self, self.activeTurn else { return }
            self.onIntent?(CharacterIntent(eventName:"speech.frame",turnId:self.token.uuidString,audioTime:time,level:Double(value)))
        }
    }
    func enterConversation(_ entry:ConversationEntry) {
        guard entry.characterID == model.id, entry.accountID == ownerID, store.accountID == ownerID,
              ConversationGreetingPolicy.shouldGreet(record,entry:entry) else { return }
        pendingGreeting = entry
        deliverPendingGreeting()
    }
    private func deliverPendingGreeting() {
        guard let entry = pendingGreeting, !characterEditorPresented, store.accountID == ownerID else { return }
        pendingGreeting = nil
        // Explicit input/replies have priority over a deferred welcome.
        // Recheck after a sheet closes: the journal may have changed while this
        // entry was deferred, or the same entry may already have been delivered.
        guard ConversationGreetingPolicy.shouldGreet(record,entry:entry),
              !generating, !speech.isRecording, !speech.isBusy, !speech.isSpeaking else { return }
        let context = ConversationGreetingContext.make(reason:entry.reason,record:record,
            hasMetAnyone:store.currentRecords.values.contains { $0.greeting != nil || !$0.messages.isEmpty })
        let reply = store.dialogue.greeting(for:context,record:record)
        let message = CompanionMessage(role:"assistant",text:reply.text,date:context.date,proactiveScene:context.scene)
        store.update(model.id) { record in
            record.messages.append(message)
            record.greeting = ConversationGreetingHistory(count:min(max(0,record.greeting?.count ?? 0),Int.max-1)+1,
                lastDate:context.date,lastText:reply.text,lastEntryID:entry.id)
        }
        guard store.error == nil else { return }
        stop(); beginTurn()
        onIntent?(CharacterIntent(eventName:"expression.request",turnId:token.uuidString,target:reply.emotion))
        readAloud(reply.text,messageID:message.id)
    }
    func send() {
        let text = String(input.trimmingCharacters(in:.whitespacesAndNewlines).prefix(500))
        guard !text.isEmpty, allowReply() else { return }
        stop(); input = ""; variant = 0
        store.update(model.id,countGuestTurn:true) { record in
            let message = CompanionMessage(role:"user",text:text)
            record.messages.append(message)
            if let suggestion = MemoryCandidates.extract(message,record:record) {
                var experience = record.together
                experience.suggestions = Array((experience.suggestions + [suggestion]).suffix(12))
                record.experiences = experience
            }
        }
        guard store.error == nil else { input = text; return }
        generate(text)
    }
    private func emit(_ name: String) { onIntent?(CharacterIntent(eventName:name,turnId:activeTurn ? token.uuidString : "")) }
    private func beginTurn() { activeTurn = true; emit("turn.begin") }
    func beginStory(_ story:CompanionStory,replay:Bool = false) {
        guard store.accountID == ownerID, allowReply() else { return }
        stop()
        if let message = store.beginStory(story,model:model,replay:replay) { speakExperience(message) }
    }
    func chooseStory(_ choiceID:String,nodeID:String,story:CompanionStory) {
        guard store.accountID == ownerID, allowReply() else { return }
        stop()
        if let message = store.chooseStory(choiceID,nodeID:nodeID,story:story,model:model) { speakExperience(message) }
    }
    private func speakExperience(_ message:CompanionMessage) {
        // Story transitions keep the user's camera and use only expression + voice.
        beginTurn()
        onIntent?(CharacterIntent(eventName:"expression.request",turnId:token.uuidString,target:"joy"))
        readAloud(message.text,messageID:message.id)
    }
    private func generate(_ text: String) {
        let current = token; generating = true; beginTurn(); emit("state.thinking")
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                var reply = store.dialogue.reply(to:text,record:record,variant:variant)
                var requestedActionID:String?
                let avoided = record.together.preferences.avoids(text)
                if !avoided, PostureDialogue.parse(text,model:model,current:record.profile.resolvedStudio.posture ?? PosturePreferences()) != nil {
                    reply = DialogueReply(text:"我会保持现在的出场姿态陪着你。也可以让我做一个已有的小动作。",eventName:"dialogue.reply",emotion:"neutral")
                } else if !avoided, let action = CharacterActionDialogue.parse(text,model:model,posture:record.profile.resolvedStudio.posture ?? PosturePreferences()) {
                    requestedActionID = action.actionID
                    reply = DialogueReply(text:action.reply,eventName:"dialogue.reply",emotion:"neutral")
                }
                try await Task.sleep(for:.milliseconds(220))
                let characters = Array(reply.text)
                for offset in stride(from:0,to:characters.count,by:3) {
                    try Task.checkCancellation(); guard current == token else { return }
                    draftReply = String(characters.prefix(min(offset+3,characters.count)))
                    try await Task.sleep(for:.milliseconds(28))
                }
                guard current == token else { return }
                let message = CompanionMessage(role:"assistant",text:reply.text)
                store.update(model.id) { $0.messages.append(message) }
                draftReply = ""; generating = false; emit("state.idle")
                onIntent?(CharacterIntent(eventName:reply.eventName,turnId:token.uuidString,emotion:reply.emotion))
                if let requestedActionID {
                    onIntent?(CharacterIntent(eventName:"action.request",turnId:token.uuidString,target:requestedActionID))
                }
                if store.error == nil { readAloud(reply.text,messageID:message.id) }
            } catch { return }
        }
    }
    func stop() {
        pendingGreeting = nil
        if activeTurn { emit("turn.cancel") }; activeTurn = false
        token = UUID(); task?.cancel(); task = nil
        if generating, !draftReply.isEmpty {
            let text = draftReply
            store.update(model.id) { $0.messages.append(CompanionMessage(role:"assistant",text:text,interrupted:true)) }
        }
        generating = false; draftReply = ""; speech.stop()
    }
    func applyProfile(_ profile: CharacterProfile) {
        let greetingAfterEditing = pendingGreeting
        stop(); store.saveProfile(model.conversationProfile(preserving:profile),id:model.id)
        pendingGreeting = greetingAfterEditing
    }
}
