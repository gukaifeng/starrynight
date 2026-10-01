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
    var quickReplyPanelPresented = false
    var atmospherePreviewIntensity:Double?
    var atmosphereIntensity:Double {atmospherePreviewIntensity ?? record.profile.resolvedAtmosphereIntensity}
    func commitAtmosphereIntensity() {
        guard let value=atmospherePreviewIntensity else {return}
        defer {atmospherePreviewIntensity=nil}
        guard store.accountID==ownerID else {return}
        let clean=AtmosphereBlend.normalized(value)
        guard record.profile.atmosphereIntensity != clean else {return}
        store.update(model.id) {$0.profile.atmosphereIntensity=clean;$0.profile.atmosphereEnabled=clean>0}
    }
    var characterEditorPresented = false { didSet { if !characterEditorPresented { refreshAddressPreferences(); deliverPendingGreeting() } } }
    var input = ""
    let voiceInput=VoiceInputDraft()
    var generating = false
    private(set) var presentationActive = true
    /// Leaving a retained tab hides its presentation, not its network turn.
    func setPresentationActive(_ active:Bool) {
        guard presentationActive != active else {return}
        presentationActive=active
        if !active {
            idleTask?.cancel();idleTask=nil
            silentVisualTask?.cancel();silentVisualTask=nil
            revealTask?.cancel();revealTask=nil;replyReveal.finish()
            if voiceInput.active {cancelVoiceInput()}
            quickReplyPanelPresented=false
            onEndAIVisual?()
        }
        speech.setPresentationActive(active)
        if active {
            emit(generating ? "state.thinking" : "state.idle")
            if !generating {scheduleIdle()}
        }
    }
    var notice: String?
    var currentAction = ""
    var replyReveal = ReplyReveal()
    private(set) var focusedMessageID: UUID?
    private(set) var messageFocusRequest = 0
    var visibleMessages: [CompanionMessage] { ConversationSearch.window(record.messages,around:focusedMessageID) }
    func focusMessage(_ id: UUID) {
        guard record.messages.contains(where:{ $0.id == id }) else { return }
        dismissKeyboardRequest += 1; focusedMessageID = id; messageFocusRequest += 1
    }
    func clearMessageFocus() { focusedMessageID = nil }
    func clearMessages() {
        guard !model.isPreviewOnly else { return }
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
    @ObservationIgnored var onAdditionalAIVisual: (([AIVisual]) -> Void)?
    @ObservationIgnored var onEndAIVisual: (() -> Void)?
    @ObservationIgnored private var task: Task<Void,Never>?
    @ObservationIgnored private var idleTask: Task<Void,Never>?
    @ObservationIgnored private var silentVisualTask: Task<Void,Never>?
    @ObservationIgnored private var shakeTask: Task<Void,Never>?
    @ObservationIgnored private var revealTask: Task<Void,Never>?
    @ObservationIgnored private var reactionPreparationTask: Task<Void,Never>?
    @ObservationIgnored private var reactionPreparationLease:String?
    @ObservationIgnored private var quickReplyTask:Task<Void,Never>?
    private(set) var quickReplies:[AIQuickReply]=[]
    private(set) var quickRepliesLoading=false
    private(set) var quickReplySource:String?
    private(set) var preparedInflightHits=0 {didSet {onPreparationChanged?()}}
    @ObservationIgnored var onPreparationChanged:(() -> Void)?
    private(set) var preparedReactionHits=0 {didSet {onPreparationChanged?()}}
    private(set) var preparedReactionReady:[String:Int]=[:] {didSet {onPreparationChanged?()}}
    private(set) var shakeReactions=0
    private(set) var pinchReactions=0
    private(set) var lastModelInteraction=""
    private(set) var lateVisualUpdates=0
    private(set) var lateVisualsDuringSpeech=0
    @ObservationIgnored private var token = UUID()
    @ObservationIgnored private var activeTurn = false
    @ObservationIgnored private var pendingGreeting: ConversationEntry?
    @ObservationIgnored private let ownerID: String
    @ObservationIgnored private var preparedNickname:String
    @ObservationIgnored private var activeScript: AIScript?
    @ObservationIgnored private var performedBeats = Set<String>()
    @ObservationIgnored private var registeredOpening:String?
    private func registerOpeningContext() async throws {
        guard let script=record.messages.first(where:{$0.aiScript?.openingID != nil})?.aiScript,
              registeredOpening != script.messageId else {return}
        try await api.registerOpening(script,resetID:record.conversationResetID ?? "")
        try Task.checkCancellation();registeredOpening=script.messageId
    }
    var record: CharacterRecord {
        var value = store.record(model.id)
        value.profile = model.conversationProfile(preserving:value.profile)
        return value
    }
    func requestLogin() { dismissKeyboardRequest += 1; onLoginRequested?() }
    private func allowReply() -> Bool {
        if model.isPreviewOnly { return false }
        if api.requiresAuthentication { requestLogin(); return false }
        guard record.pendingDeletionID==nil else {notice="上次删除尚未完成，请在消息页重试删除。";return false}
        if isGuest && store.guestLimitReached { requestLogin(); return false }; return true
    }
    var muted: Bool { soundscape.speechVolume <= 0 }
    var effectiveVoiceSpeed: Double { 1 } // Voice Design and per-beat delivery own the voice.
    func setSpeechVolume(_ value: Double) {
        soundscape.setSpeechVolume(value)
        if muted {
            speech.stop()
            if let activeScript { playSilentVisuals(activeScript);revealSilently(activeScript) }
        } else { speech.refreshVolume() }
    }
    var availableActions: [CharacterAction] { model.availableActions(for:record.profile.resolvedStudio.posture ?? PosturePreferences()) }
    func performAction(_ id: String) {
        guard availableActions.contains(where:{ $0.id == id }) else { return }
        onEndAIVisual?(); onIntent?(CharacterIntent(eventName:"action.request",target:id))
    }
    init(store: CompanionStore, model: ModelDescriptor, soundscape: CompanionSoundscape) {
        self.store = store; self.model = model; self.soundscape = soundscape; ownerID = store.accountID
        preparedNickname = store.effectiveNickname(for:model.id)
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
        speech.nickname = { [weak self] in
            guard let self else { return "" }
            return self.store.effectiveNickname(for:self.model.id)
        }
        speech.onCaptureCancelled = { [weak self] in self?.voiceInput.cancel() }
        speech.onCaptureRecovery = { [weak self] text in
            self?.voiceInput.recover(text)
        }
        speech.onPartial = { [weak self] text in self?.voiceInput.partial(text) }
        speech.onTranscript = { [weak self] text in
            guard let self else {return}
            if let ready=self.voiceInput.accept(text) {self.sendVoiceText(ready)}
        }
        speech.onState = { [weak self] state in
            guard let self else { return }
            self.emit("state."+state)
        }
        speech.onFrame = { [weak self] time,level in
            guard let self, self.presentationActive,self.activeTurn else { return }
            self.onIntent?(CharacterIntent(eventName:"speech.frame",turnId:self.token.uuidString,audioTime:time,level:Double(level)))
        }
        speech.onBeat = { [weak self] id in
            guard let self,self.presentationActive,let beat = self.activeScript?.beats.first(where:{ $0.beatId == id }) else { return }
            self.performedBeats.insert(id)
            self.onAIVisual?(beat.visuals)
            self.replyReveal.advance(id,fraction:0)
        }
        speech.onBeatProgress = { [weak self] id,fraction in self?.replyReveal.advance(id,fraction:fraction) }
    }
    func enterConversation(_ entry: ConversationEntry) {
        guard entry.characterID == model.id, entry.accountID == ownerID, store.accountID == ownerID else { return }
        if model.isPreviewOnly { return }
        guard record.pendingDeletionID==nil else {notice="上次删除尚未完成，请在消息页重试删除。";return}
        refreshAddressPreferences()
        guard ConversationGreetingPolicy.shouldGreet(record,entry:entry) else {
            scheduleReactionPreparation();scheduleIdle();return
        }
        pendingGreeting = entry; deliverPendingGreeting()
    }
    func adoptPreparationLease(_ value:String?) {reactionPreparationLease=value}
    private func refreshAddressPreferences() {
        guard store.accountID == ownerID else { return }
        let current = store.effectiveNickname(for:model.id)
        guard current != preparedNickname else { return }
        preparedNickname = current
        quickReplyTask?.cancel(); quickReplyTask = nil
        quickReplies = []; quickReplySource = nil; quickRepliesLoading = false
        preparedReactionReady = [:]
        // The server fingerprint rejects old-name text/audio. Warm the new
        // context on returning to this conversation, without a new greeting.
        scheduleReactionPreparation()
    }
    private func deliverPendingGreeting() {
        guard let entry = pendingGreeting, !characterEditorPresented, store.accountID == ownerID else { return }
        pendingGreeting = nil
        guard ConversationGreetingPolicy.shouldGreet(record,entry:entry), !voiceInput.active, !generating, !speech.isRecording, !speech.isBusy, !speech.isSpeaking else { return }
        if ConversationGreetingPolicy.shouldIntroduce(record) {
            guard let opening=CharacterOpenings.random(for:model.runtimeID) else {
                notice="这个角色的初次见面内容尚未打包。";return
            }
            playOpening(opening,entry:entry);return
        }
        let context = ConversationGreetingContext.make(reason:entry.reason,record:record,
            hasMetAnyone:store.currentRecords.values.contains { $0.greeting != nil || !$0.messages.isEmpty })
        generate("",trigger:context.scene,entry:entry)
    }
    private func playOpening(_ opening:CharacterOpening,entry:ConversationEntry) {
        stop();notice=nil
        let current=token,script=opening.script(characterID:model.id)
        let id=UUID(uuidString:script.messageId)!
        activeScript=script;beginTurn()
        let message=CompanionMessage(id:id,role:"assistant",text:script.text,
            speechDuration:opening.duration,speechSpeed:1,
            proactiveScene:"firstMeeting",aiScript:script,source:opening.parts == nil ? "bundled-opening-v1" : "bundled-opening-v2")
        replyReveal.begin(id,script:script)
        store.update(model.id) { record in
            record.messages.append(message)
            record.greeting=ConversationGreetingHistory(count:1,lastDate:Date(),lastText:script.text,lastEntryID:entry.id)
        }
        quickReplySource=script.messageId.lowercased()
        quickReplies=CharacterOpenings.initialReplies(for:model.runtimeID,messageID:script.messageId)
        scheduleQuickReplies(script)
        // Record once before playback, so rapid remounts and interruption never
        // draw another first-meeting variant. Later greetings remain contextual AI.
        task=Task { @MainActor [weak self] in
            guard let self else {return}
            do {
                if muted {playSilentVisuals(script);revealSilently(script)}
                else {_ = try await speech.cachedReplay(script,messageID:id);replyReveal.finish()}
                guard token==current,store.accountID==ownerID else {return}
                emit("state.idle");scheduleIdle()
                // Preparation is for future interactions, never for this opening.
                scheduleReactionPreparation(delay:1)
            } catch {
                guard token==current,!Task.isCancelled else {return}
                speech.stop();playSilentVisuals(script);replyReveal.finish();emit("state.idle")
                // Missing package media is a build error. Never silently replace
                // a first meeting with a paid/network-generated greeting.
                notice="这份角色的开场语音尚未打包，文字与表情仍可查看。"
            }
        }
    }
    func send(quickReplyID:String? = nil) {
        let text = String(input.trimmingCharacters(in:.whitespacesAndNewlines).prefix(500))
        guard !text.isEmpty, allowReply() else { return }
        stop(preservePreparation:true); input = ""; notice = nil
        store.update(model.id,countGuestTurn:true) { record in
            var message=CompanionMessage(role:"user",text:text,source:"cloud-v1")
            message.storyID=record.together.activeStoryID
            record.messages.append(message)
        }
        guard store.error == nil else { input = text; return }
        generate(text,trigger:record.together.activeStoryID == nil ? "user_message" : "story",quickReplyID:quickReplyID)
    }
    func sendSuggested(_ option:AIQuickReply) {
        guard quickReplies.contains(where:{$0.id==option.id}),
              record.messages.last?.aiScript?.messageId.lowercased()==quickReplySource else {return}
        let draft=input;input=option.text
        send(quickReplyID:option.id.hasPrefix("opening-local-") ? nil : option.id)
        if !draft.isEmpty {input=draft}
    }
    @discardableResult func beginVoiceInput() -> Bool {
        guard !voiceInput.active,!characterEditorPresented,allowReply() else {return false}
        stop(preservePreparation:true);voiceInput.begin();speech.startRecording();return true
    }
    func finishVoiceInput(edit:Bool) {
        guard voiceInput.phase == .holding else {return}
        let ready=voiceInput.release(edit:edit)
        speech.finishRecording()
        if let ready {sendVoiceText(ready)}
    }
    func cancelVoiceInput() {voiceInput.cancel();speech.stop()}
    func cancelVoiceHold() {
        guard voiceInput.phase == .holding else {return}
        // An interrupted touch never sends. Keep already recognized words for review.
        speech.stop()
        if voiceInput.text.isEmpty {voiceInput.cancel()}
        else {voiceInput.recover(voiceInput.text);voiceInput.release(edit:true)}
    }
    func sendVoiceText(_ text:String) {
        let draft=input;voiceInput.cancel();speech.stop();input=text;send()
        if !draft.isEmpty {input=draft}
    }
    func beginStory(_ story: CompanionStory,replay: Bool = false) {
        guard store.accountID == ownerID,CompanionStory.available(for:model).contains(where:{$0.id==story.id}),allowReply() else { return }
        let draft=input
        let resuming = !replay && record.together.stories[story.id] != nil
        store.update(model.id) { record in
            var experience = record.together; experience.activeStoryID = story.id
            if replay || experience.stories[story.id] == nil {
                var progress=StoryProgress(storyID:story.id)
                progress.revision=(experience.stories[story.id]?.revision ?? 0)+1
                experience.stories[story.id]=progress
            }
            record.experiences = experience
        }
        guard store.error == nil else {return}
        input = CharacterPublicProfile.find(model.id)?.englishOnly == true
            ? (resuming ? "Let's pick up this scene where we left off. Leave the next choice to me." : "Let's begin this scene together. Give me a small opening I can respond to.")
            : (resuming ? "我们接着「"+story.title+"」的情境聊吧，不用重新开场。" : "我们来玩「"+story.title+"」。先从一个小小的开场开始，接下来由我们一起决定。")
        send()
        if !draft.isEmpty {input=draft}
    }
    func continueStory() {
        let draft=input
        input = CharacterPublicProfile.find(model.id)?.englishOnly == true
            ? "Let's pick up our scene where we left off. Leave the next choice to me."
            : "我们接着刚才的情境聊吧，留一点空间让我决定接下来发生什么。"
        send();if !draft.isEmpty {input=draft}
    }
    func pauseStory() {
        stop();quickReplies=[];quickReplySource=nil
        store.pauseStory(id:model.id)
        scheduleReactionPreparation()
    }
    private func emit(_ name: String) {
        guard presentationActive else {return}
        onIntent?(CharacterIntent(eventName:name,turnId:activeTurn ? token.uuidString : ""))
    }
    private func beginTurn() { activeTurn = true; emit("turn.begin") }
    func requestBody(_ text:String,trigger:String)->[String:Any] {
        Self.requestBody(store:store,model:model,text:text,trigger:trigger)
    }
    static func requestBody(store:CompanionStore,model:ModelDescriptor,text:String,trigger:String)->[String:Any] {
        let record=store.record(model.id)
        let p = record.together.preferences.normalized
        var recent = record.messages.filter { $0.source == "cloud-v1" || $0.source == "bundled-opening-v1" }
        if recent.last?.role == "user", recent.last?.text == text { recent.removeLast() }
        return ["request_id":UUID().uuidString,"character_id":model.id,"text":text,"trigger":trigger,
            "conversation_reset":record.conversationResetID ?? "",
            "preferences":["nickname":store.effectiveNickname(for:model.id),"nicknameSource":store.nicknameSource(for:model.id),
                           "aboutMe":p.aboutMe,"relationship":p.relationship,"responseStyle":p.responseStyle,"avoidedTopics":p.avoidedTopics],
            "memories":record.memories.suffix(100).map { ["id":$0.id.uuidString,"text":$0.text] },
            "recent_messages":recent.suffix(12).map { ["role":$0.role,"text":String($0.text.prefix(700))] },
            "scene":["time":Date().formatted(date:.omitted,time:.shortened),"environment":model.display.description,
                "story_id":record.together.activeStoryID ?? "",
                "story_revision":String(record.together.activeStoryID.flatMap {record.together.stories[$0]?.revision} ?? 1)],
            "available_assets":model.performance?.options.map(\.id) ?? [],
            "wants_audio":(record.profile.audio?.speechVolume ?? 1)>0]
    }
    func reactToShake(intensity:Double) {
        reactToModelInteraction(kind:"shake",intensity:intensity)
    }
    func reactToModelInteraction(kind:String,intensity:Double) {
        guard ["shake","pinch_out","pinch_in"].contains(kind),intensity.isFinite else {return}
        guard !api.requiresAuthentication,!inspectionActive,!characterEditorPresented,store.accountID==ownerID,
              !(isGuest && store.guestLimitReached),!voiceInput.active,!speech.isRecording,shakeTask==nil else {return}
        if kind=="shake" {shakeReactions+=1} else {pinchReactions+=1}
        lastModelInteraction=kind
        // Physical play interrupts current playback instead of waiting up to
        // fifteen seconds. The shared Unity/server cooldown still applies.
        generate("",trigger:kind=="shake" ? "model_shaken" : "model_pinched",
            interaction:["kind":kind,"intensity":min(1,max(0,intensity))])
    }
    private func generate(_ text: String,trigger: String,entry: ConversationEntry? = nil,interaction:[String:Any]? = nil,quickReplyID:String? = nil) {
        guard !model.isPreviewOnly else { return }
        guard !api.requiresAuthentication else {return}
        guard record.pendingDeletionID==nil else {return}
        stop(preservePreparation:true);quickReplies=[];quickReplySource=nil
        let current = token; generating = true; beginTurn(); emit("state.thinking")
        var body=requestBody(text,trigger:trigger)
        if let entry { body["entry_id"] = entry.id.uuidString }
        if let interaction {body["interaction"]=interaction}
        if let quickReplyID {body["quick_reply_id"]=quickReplyID}
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            var received = false
            let audio=ReplyAudioPump { [weak self] event in
                guard let self,self.token==current,self.store.accountID==self.ownerID else {throw CancellationError()}
                if event.type=="audio.completed" {
                    if !self.muted {self.speech.finish();self.replyReveal.finish();self.emit("state.idle")}
                } else {
                    if !self.muted {try await self.speech.accept(event)}
                    if event.type=="audio.error",let script=self.activeScript {self.playSilentVisuals(script);self.revealSilently(script)}
                }
            }
            defer {audio.cancel()}
            do {
                try await registerOpeningContext()
                try await api.events(path:"/v1/conversations/"+model.id+"/messages",body:body) { [weak self] event in
                    guard let self, current == self.token, self.store.accountID == self.ownerID else { throw CancellationError() }
                    switch event.type {
                    case "reply.narration.ready":
                        guard let script = event.script, !script.beats.isEmpty else { return }
                        if event.prepared==true {self.preparedReactionHits+=1}
                        if event.preparationInflight==true {self.preparedInflightHits+=1}
                        received = true; self.activeScript = script; self.generating = false
                        var message = CompanionMessage(id:UUID(uuidString:script.messageId) ?? UUID(),role:"assistant",text:script.text,
                            proactiveScene:trigger == "user_message" ? nil : trigger,aiScript:script,source:"cloud-v1")
                        message.storyID=self.record.together.activeStoryID
                        if self.presentationActive,!self.record.messages.contains(where:{$0.id==message.id}) {self.replyReveal.begin(message.id,script:script)}
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
                        self.scheduleReactionPreparation(delay:0.2)
                        self.scheduleQuickReplies(script)
                        if !self.muted {
                            self.speech.prepare(message.id,script:script)
                            // React when the text arrives, even while voice is
                            // connecting. Audio onset then aligns/renews the beat.
                            if self.presentationActive,let first=script.beats.first {
                                self.performedBeats.insert(first.beatId)
                                self.onAIVisual?(first.visuals)
                            }
                        }
                        else { self.playSilentVisuals(script);self.revealSilently(script) }
                    case "reply.script.updated":
                        guard let script=event.script,let id=UUID(uuidString:script.messageId) else {return}
                        if self.activeScript?.messageId==script.messageId {self.activeScript=script}
                        self.store.update(self.model.id) { record in
                            if let index=record.messages.firstIndex(where:{$0.id==id}) {
                                record.messages[index].aiScript=script
                            }
                        }
                    case "reply.visuals.updated":
                        guard let script=event.script,script.characterId==self.model.id,
                              self.activeScript?.messageId==script.messageId,let id=UUID(uuidString:script.messageId) else {return}
                        // Update only replayable visual controls. Never restart
                        // speech, change its text/parts or append late narration.
                        self.activeScript=script
                        self.store.update(self.model.id) {record in
                            if let index=record.messages.firstIndex(where:{$0.id==id}) {record.messages[index].aiScript=script}
                        }
                        if self.presentationActive,!self.inspectionActive,!self.characterEditorPresented,let visuals=event.visuals,!visuals.isEmpty {
                            self.lateVisualUpdates+=1
                            if self.speech.isSpeaking {self.lateVisualsDuringSpeech+=1}
                            self.onAdditionalAIVisual?(visuals)
                        }
                    case "reply.warning": self.notice = event.message
                    case "segment.audio.started", "segment.audio.chunk", "segment.audio.ready", "audio.error", "audio.completed":
                        try audio.send(event)
                    default: break
                    }
                }
                try await audio.finish()
                guard current == token else { return }
                generating = false; speech.finish()
                if !muted && speech.error == nil {replyReveal.finish()}
                if !muted, let script=activeScript { playSilentVisuals(script) }
                // Each group has its own bounded restore timer. Finishing a
                // short utterance must not immediately erase its expression.
                emit("state.idle")
                if reactionPreparationTask==nil {scheduleReactionPreparation(delay:0.2)}
                scheduleIdle()
            } catch {
                guard current == token, !Task.isCancelled else { return }
                generating = false; speech.stop()
                replyReveal.finish()
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
        guard !model.isPreviewOnly else { return }
        idleTask?.cancel()
        guard !api.requiresAuthentication,presentationActive,record.messages.contains(where:{$0.role=="user"}),!(isGuest && store.guestLimitReached) else {return}
        idleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for:.seconds(Int.random(in:150...240)))
            guard !Task.isCancelled, let self, self.presentationActive, !self.generating, !self.speech.isRecording, !self.speech.isBusy,
                  !self.speech.isSpeaking, !self.voiceInput.active, self.input.isEmpty, !self.characterEditorPresented else { return }
            self.generate("",trigger:"idle")
        }
    }
    private func scheduleReactionPreparation(delay:Double = 0.2) {
        guard !model.isPreviewOnly else { return }
        reactionPreparationTask?.cancel()
        guard !api.requiresAuthentication,presentationActive,CharacterAI.reactionPreparationEnabled,!(isGuest && store.guestLimitReached) else {return}
        let current=token
        reactionPreparationTask=Task { @MainActor [weak self] in
            do {
                // Start while the current voice is playing, not three seconds
                // after it ends. Foreground events can adopt in-flight work.
                try await Task.sleep(for:.seconds(delay))
                guard let self,self.token==current,self.store.accountID==self.ownerID,
                      !self.generating,!self.voiceInput.active,!self.speech.isRecording,self.input.isEmpty else {return}
                let body=self.requestBody("",trigger:"idle")
                try await self.registerOpeningContext()
                self.reactionPreparationLease=body["request_id"] as? String
                var status=try await self.api.prepareReactions(body)
                for _ in 0..<60 {
                    guard self.token==current,!Task.isCancelled else {return}
                    self.preparedReactionReady=status.ready
                    if !status.preparing {break}
                    try await Task.sleep(for:.seconds(2))
                    status=try await self.api.reactionStatus(body)
                }
            } catch { /* Optional warming never adds an error bubble. */ }
        }
    }
    func requestQuickReplies() {
#if DEBUG && targetEnvironment(simulator)
        // Layout-only fixture. Never available in device builds or live AI tests.
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           ProcessInfo.processInfo.arguments.contains("--smart-reply-layout-fixture"),
           !ProcessInfo.processInfo.arguments.contains("--live-ai") {
            quickReplies=["可以再和我多说一点吗？","你最喜欢刚才的哪个发现？","我也想和你分享今天的小事。"].enumerated().map {
                AIQuickReply(id:"layout-\($0.offset)",text:$0.element,likelihood:1-Double($0.offset)*0.2)
            };quickReplySource=record.messages.last?.aiScript?.messageId.lowercased();return
        }
#endif
        guard let script=record.messages.last?.aiScript else {return}
        scheduleQuickReplies(script)
    }
    private func scheduleQuickReplies(_ script:AIScript) {
        guard !model.isPreviewOnly else { return }
        quickReplyTask?.cancel()
        guard !api.requiresAuthentication,CharacterAI.smartReplyPreparationEnabled,!(isGuest && store.guestLimitReached) else {return}
        let current=token;quickReplySource=script.messageId.lowercased();quickRepliesLoading=true
        quickReplyTask=Task { @MainActor [weak self] in
            guard let self else {return}
            defer {if self.token==current {self.quickRepliesLoading=false}}
            do {
                var body=self.requestBody("",trigger:"idle");body["source_message_id"]=script.messageId
                try await self.registerOpeningContext()
                var response=try await self.api.quickReplies(body,prepare:true)
                for _ in 0..<30 {
                    guard !Task.isCancelled,self.token==current,self.store.accountID==self.ownerID,
                          self.quickReplySource==response.sourceMessageId.lowercased() else {return}
                    if !response.options.isEmpty {self.quickReplies=response.options;self.onPreparationChanged?();return}
                    if !response.preparing {return}
                    try await Task.sleep(for:.milliseconds(500))
                    response=try await self.api.quickReplies(body,prepare:false)
                }
            } catch { /* Suggestions are optional; ordinary input stays usable. */ }
        }
    }
    private func revealSilently(_ script:AIScript) {
        guard presentationActive else {replyReveal.finish();return}
        revealTask?.cancel()
        revealTask=Task { @MainActor [weak self] in
            guard let self else {return}
            for beat in script.beats {
                let duration=beat.readingDuration ?? 3
                let steps=Int((duration.isFinite ? min(45,max(0.5,duration)) : 3)*10)
                for step in 0...steps {
                    guard !Task.isCancelled else {return}
                    replyReveal.advance(beat.beatId,fraction:Double(step)/Double(steps))
                    try? await Task.sleep(for:.milliseconds(100))
                }
            }
            if !Task.isCancelled {replyReveal.finish()}
        }
    }
    private func playSilentVisuals(_ script: AIScript) {
        guard presentationActive else {return}
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
                try? await Task.sleep(for:.milliseconds(beat.visuals.map{($0.offsetMs ?? 0)+$0.durationMs}.max() ?? 2500))
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
    func stop(preservePreparation:Bool = false) {
        preparedReactionReady=[:]
        quickReplyTask?.cancel();quickReplyTask=nil;quickRepliesLoading=false
        reactionPreparationTask?.cancel();reactionPreparationTask=nil
        if !preservePreparation,let lease=reactionPreparationLease {
            reactionPreparationLease=nil
            var body=requestBody("",trigger:"idle");body["request_id"]=lease
            let api=self.api
            Task {await api.pauseReactions(body)}
        }
        pendingGreeting = nil; task?.cancel(); task = nil; idleTask?.cancel(); idleTask = nil
        silentVisualTask?.cancel(); silentVisualTask = nil
        revealTask?.cancel();revealTask=nil;replyReveal.finish()
        shakeTask?.cancel();shakeTask=nil
        if activeTurn { emit("turn.cancel") }
        activeTurn = false; token = UUID(); generating = false; activeScript = nil
        performedBeats.removeAll()
        voiceInput.cancel();speech.stop(); onEndAIVisual?()
    }
}
