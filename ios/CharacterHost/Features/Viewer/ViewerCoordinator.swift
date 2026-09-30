import UIKit
import Observation
import OSLog

@MainActor @Observable
final class ViewerCoordinator: NSObject, UnityRuntimeBridgeDelegate {
    enum Page { case home, loading, viewer, closing, error }
    let account = AccountStore()
    let library = CharacterLibrary()
    @ObservationIgnored private var platformSync:AccountSync?
    var selectedTab: AppTab = .home
    var loginPresented = false
    private(set) var startupInProgress = true
    @ObservationIgnored var onShellReady: (() -> Void)?
    @ObservationIgnored private var shellReady = false
    private func finishShellPreparation() {
        guard startupInProgress, !shellReady else { return }
        shellReady = true
        LaunchTrace.mark("nativeShellPrepared")
        onShellReady?()
    }
    func completeStartup() {
        guard startupInProgress else { return }
        startupInProgress = false
        onShellReady = nil
        overlay?.view.accessibilityElementsHidden = page != .viewer
        window?.rootViewController?.view.accessibilityElementsHidden = page == .viewer
        LaunchTrace.mark("nativeShellVisible")
        recordTestEvent("{\"name\":\"appStartupCompleted\",\"presentationId\":\(presentation)}")
        scheduleRuntimeStart()
        greetVisibleConversation()
    }
    private(set) var transitionSourceTab: AppTab?
    private(set) var bundledBackdropVisible = false
    var visibleShellTab: AppTab { transitionSourceTab ?? selectedTab }
    @ObservationIgnored private var retainedAccount: String?
    @ObservationIgnored private var retainedReady = false
    @ObservationIgnored private var prediction = CharacterPrediction()
    @ObservationIgnored private var prewarmTask: Task<Void,Never>?
    @ObservationIgnored private var entryPreparationTask:Task<Void,Never>?
    @ObservationIgnored private var entryPreparation:(api:CharacterAI,body:[String:Any])?
    @ObservationIgnored private var warmedKeys = Set<String>()
    @ObservationIgnored private var prewarmRequest: (id:String,key:String)?
    private var predictionDefaults: UserDefaults {
        ProcessInfo.processInfo.arguments.contains("--companion-testing") ? UserDefaults(suiteName:"com.modelspace.prediction.testing")! : .standard
    }
    private var predictionKey: String { "character-prediction.v1." + companionStore.accountID }
    private func recordVisit(_ id:String) {
        prediction.record(id)
        if let data = try? JSONEncoder().encode(prediction.visits) { predictionDefaults.set(data,forKey:predictionKey) }
    }
    private func discardConversation() {
        companion?.stop(); overlay?.setCompanion(nil); companion = nil; retainedAccount = nil
        retainedReady = false
    }
    private func cancelPrewarm(preservingEntryFor character:String? = nil) {
        prewarmTask?.cancel(); prewarmTask = nil; prewarmRequest = nil
        cancelEntryPreparation(preserveGeneration:character != nil && entryPreparation?.api.characterID==character && entryPreparation?.api.accountID==companionStore.accountID)
    }
    private func cancelEntryPreparation(preserveGeneration:Bool = false) {
        entryPreparationTask?.cancel();entryPreparationTask=nil
        if let pending=entryPreparation {
            entryPreparation=nil
            if !preserveGeneration {Task {await pending.api.pauseReactions(pending.body)}}
        }
    }
    private func prepareEntry(_ model:ModelDescriptor,trigger:String,delay:Double) {
        cancelEntryPreparation()
        guard CharacterAI.reactionPreparationEnabled,
              !(companionStore.accountID=="guest" && companionStore.guestLimitReached) else {return}
        let owner=companionStore.accountID
        entryPreparationTask=Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for:.seconds(delay))
                guard let self,self.active,self.companionStore.accountID==owner else {return}
                let api=CharacterAI(accountID:owner,characterID:model.id)
                var body=CompanionSession.requestBody(store:self.companionStore,model:model,text:"",trigger:trigger)
                body["preparation_scope"]="entry"
                self.entryPreparation=(api,body)
                _ = try await api.prepareReactions(body)
            } catch { /* A cold/missing draft uses the foreground AI path. */ }
        }
    }
    private func schedulePrewarm() {
        cancelPrewarm()
        guard active, !desiredVisible, !ProcessInfo.processInfo.isLowPowerModeEnabled,
              ProcessInfo.processInfo.thermalState == .nominal else { return }
        let records = companionStore.currentRecords
        // Reuse the existing recency/frequency/transition predictor; prepare only
        // one likely next role's entry greeting, never the entire marketplace.
        if let id=prediction.next(after:library.lastCharacter,candidates:library.discover.filter {$0.id != selectedModel.id}.map(\.id),
            dialogueCounts:records.mapValues {$0.messages.filter {$0.role=="user"}.count},
            recent:records.mapValues {$0.messages.last?.date ?? .distantPast}),let model=library.model(id) {
            prepareEntry(model,trigger:"characterSwitch",delay:1.5)
        }
        guard ready else {return}
        let candidates = library.discover.filter { model in
            model.id != selectedModel.id && !warmedKeys.contains(CharacterPortraitStore.key(model:model,profile:profile(for:model)))
        }
        guard let id = prediction.next(after:library.lastCharacter,candidates:candidates.map(\.id),
            dialogueCounts:records.mapValues { $0.messages.filter { $0.role == "user" }.count },
            recent:records.mapValues { $0.messages.last?.date ?? .distantPast }), let model = library.model(id) else { return }
        let owner = companionStore.accountID
        prewarmTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for:.milliseconds(850)) } catch { return }
            guard let self, self.page == .home, !self.desiredVisible, self.active, self.companionStore.accountID == owner else { return }
            let profile = self.profile(for:model), request = self.nextRequest()
            let key = CharacterPortraitStore.key(model:model,profile:profile)
            self.prewarmRequest = (request,key)
            self.bridge.setPaused(false)
            self.send("prewarmModel",payload:["modelId":model.runtimeID,"studio":profile.resolvedStudio.payload,
                "accent":profile.accent,"parameters":(profile.resolvedStudio.parameters ?? [:]).map { ["id":$0.key,"value":$0.value] as [String:Any] }],request:request)
            do { try await Task.sleep(for:.seconds(4)) } catch { return }
            if self.prewarmRequest?.id == request {
                self.prewarmRequest = nil
                if !self.desiredVisible { self.bridge.setPaused(true) }
            }
        }
    }
    @ObservationIgnored private var pendingLogin = false
    @ObservationIgnored private var pendingCharacter: (model:ModelDescriptor,reason:ConversationEntryReason)?
    @ObservationIgnored private var pendingMessage: (characterID:String,messageID:UUID)?
    @ObservationIgnored private var needsAccountActivation = false
    @ObservationIgnored private var shellStarted = false
    func startShell() {
        guard !shellStarted else { return }; shellStarted = true
        activateLibrary()
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--conversation-gesture-fixture") {
            ConversationGestureFixture.seed(companionStore)
        }
        if ProcessInfo.processInfo.arguments.contains("--expressive-conversation-fixture") {
            ConversationGestureFixture.seedPerformance(companionStore)
        }
#endif
        if ProcessInfo.processInfo.arguments.contains("--shell-discover") { selectedTab = .discover }
        else if page == .home { resumeLastCharacter(reason:.appLaunch) }
        // The native page is sufficient to dismiss startup, even when its 3D
        // character is still pending. Commit its layout before fading the cover.
        DispatchQueue.main.async { [weak self] in self?.finishShellPreparation() }
    }
    private func activateLibrary() {
        let id = account.session?.accountID ?? "guest"
        let isNew = !library.hasAccount(id)
        let oldGuest = companionStore.accountID == "guest"
        let canAdoptGuest = account.cloudSession == nil || account.cloudShouldImportLocal
        let adoptingGuest = canAdoptGuest && id != "guest" && isNew && oldGuest &&
            (companionStore.archive.guestImportedBy == nil || companionStore.archive.guestImportedBy == id)
        if canAdoptGuest, id != "guest", isNew, oldGuest { companionStore.importGuest(into:id) }
        companionStore.activateAccount(id)
        library.activate(id,existing:companionStore.currentRecords,adoptingGuest:adoptingGuest)
        if platformSync == nil {
            platformSync = AccountSync(account:account,store:companionStore,library:library)
            account.onFirstSync = { [weak self] in
                guard let self,self.selectedTab == .home,
                      let id=self.library.lastCharacter,id != self.selectedModel.id else{return}
                self.openCharacter(id,greetingReason:.conversationReturn)
            }
        }
        platformSync?.activate()
        if ProcessInfo.processInfo.arguments.contains("--companion-testing"), !ProcessInfo.processInfo.arguments.contains("--keep-companion-data") { predictionDefaults.removeObject(forKey:predictionKey) }
        prediction.visits = predictionDefaults.data(forKey:predictionKey).flatMap { try? JSONDecoder().decode([CharacterPrediction.Visit].self,from:$0) } ?? []
    }
    func accountChanged() {
        loginPresented = false; pendingLogin = false
        pendingCharacter = nil; pendingMessage = nil; needsAccountActivation = true
        if page == .home { finishAccountActivation() }
        else { closeViewer() }
    }
    private func finishAccountActivation() {
        cancelPrewarm(); discardConversation()
        needsAccountActivation = false; portraitRequests.removeAll()
        activateLibrary()
        selectedTab = .home; resumeLastCharacter()
    }
    func requestLogin() {
        guard !account.isSignedIn else { return }
        selectedTab = .mine
        if page == .home { loginPresented = true }
        else { pendingLogin = true; closeViewer() }
    }
    func navigate(_ tab:AppTab) {
        guard page != .closing else { return }
        transitionSourceTab = tab == .home && selectedTab != .home ? selectedTab : nil
        selectedTab = tab; pendingCharacter = nil; pendingMessage = nil; pendingCustomizationID = nil
        if tab == .home {
            if page == .home { resumeLastCharacter() }
            else if !library.subscriptions.contains(selectedModel.id) {
                pendingCharacter = library.lastCharacter.flatMap(library.model).map { ($0,.conversationReturn) }
                closeViewer()
            }
        } else if page != .home { closeViewer() }
        else { schedulePrewarm() }
    }
    func openCharacter(_ id:String, messageID:UUID? = nil, customize:Bool = false, greetingReason:ConversationEntryReason? = nil, showInMessages:Bool = true) {
        guard let model = library.model(id), library.select(id,showInMessages:showInMessages) else { return }
        // A message-list selection is a switch too. Merely returning to the
        // retained role is not, regardless of the tab used to get there.
        let reason = greetingReason ?? (companion?.model.id != id ? .characterSelection : .conversationReturn)
        if !companionStore.contains(id) {
            companionStore.saveProfile(model.conversationProfile(preserving:nil),id:id)
            guard companionStore.error == nil else { return }
        }
        pendingCustomizationID = customize ? id : nil
        transitionSourceTab = selectedTab == .home ? nil : selectedTab
        selectedTab = .home
        pendingMessage = messageID.map { (id,$0) }
        if page == .viewer, selectedModel.id == id { applyPendingMessage(); presentPendingCustomization(); return }
        if page == .home { openCompanion(model,greetingReason:reason) }
        else { pendingCharacter = (model,reason); closeViewer() }
    }
    private func applyPendingMessage() {
        guard let pendingMessage, let companion, companion.model.id == pendingMessage.characterID else { return }
        companion.focusMessage(pendingMessage.messageID); self.pendingMessage = nil
    }
    func resumeLastCharacter(reason:ConversationEntryReason = .conversationReturn) {
        guard page == .home else { return }
        guard let id = library.lastCharacter else { transitionSourceTab = nil; return }
        let source = transitionSourceTab
        openCharacter(id,greetingReason:reason,showInMessages:false)
        if page == .viewer || page == .loading { transitionSourceTab = source }
    }
    func profile(for model:ModelDescriptor) -> CharacterProfile {
        model.conversationProfile(preserving:companionStore.contains(model.id) ? companionStore.record(model.id).profile : nil)
    }

    let companionStore = CompanionStore()
    let soundscape = CompanionSoundscape()
    let portraits = CharacterPortraitStore()
    let characterPerformance = CharacterPerformanceState()
    @ObservationIgnored private var portraitTask: Task<Void,Never>?
    @ObservationIgnored private var portraitRequests: [String:(model:ModelDescriptor,key:String)] = [:]
    private var companion: CompanionSession?
    @ObservationIgnored private var postureRequests: [String:CheckedContinuation<String?,Never>] = [:]
    private(set) var page: Page = .home
    private(set) var stageLoadingVisible = false
    var showsLoadingIndicator: Bool { page == .error } // Legacy gallery error surface only.
    private(set) var errorMessage = ""
    private(set) var selectedModel = ModelDescriptor.defaultCharacter
    @ObservationIgnored private let bridge = UnityRuntimeBridge()
    @ObservationIgnored private let windowHandoff = NativeWindowHandoff()
    @ObservationIgnored private weak var window: UIWindow?
    @ObservationIgnored private weak var scene: UIWindowScene?
    @ObservationIgnored private var overlay: ViewerOverlayController?
    @ObservationIgnored private var active = false
    @ObservationIgnored private var conversationVisible = false
    @ObservationIgnored private var pendingGreeting: ConversationEntry?
    @ObservationIgnored private var backgroundConversation = false
    @ObservationIgnored private var desiredVisible = false
    @ObservationIgnored private var ready = false
    @ObservationIgnored private var presentation = 0
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var pendingReset = ""
    @ObservationIgnored private var pendingReveal = ""
    @ObservationIgnored private var frameReady = false
    @ObservationIgnored private var revealTask: Task<Void,Never>?
    @ObservationIgnored private var loadingPresentation = ModelLoadingPresentation()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var foregroundWait = 0.0
    @ObservationIgnored private var openTime = Date()
    @ObservationIgnored private var targetFPS = 120
    @ObservationIgnored private var openStudioWhenReady = false
    @ObservationIgnored private var pendingCustomizationID:String?
    private func presentPendingCustomization() {
        guard pendingCustomizationID == selectedModel.id, page == .viewer else { return }
        pendingCustomizationID = nil
        overlay?.openDetailsCustomization()
    }
    @ObservationIgnored private var didStartCapture = false
    @ObservationIgnored private var captureTask: Task<Void,Never>?
    @ObservationIgnored private var launchTask: Task<Void,Never>?
    private var captureEnabled: Bool { ProcessInfo.processInfo.arguments.contains("--capture-performance") }
    private var previewEnabled: Bool { captureEnabled || ProcessInfo.processInfo.arguments.contains("--preview-miku") }
#if DEBUG
    @ObservationIgnored private var didDeferTestReady = false
    @ObservationIgnored private var testEventFile = "viewer-events.jsonl"
#endif
    @ObservationIgnored private let logger = Logger(subsystem:"com.modelspace.viewer",category:"Viewer")

    init(window: UIWindow, scene: UIWindowScene) {
        self.window = window; self.scene = scene
        super.init()
        bridge.delegate = self
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--window-handoff-review") {
            windowHandoff.onSample = { [weak self] event in
                guard let data = try? JSONSerialization.data(withJSONObject:event), let json = String(data:data,encoding:.utf8) else { return }
                self?.recordTestEvent(json)
            }
        }
#endif
        NotificationCenter.default.addObserver(self,selector:#selector(themeChanged),name:.themeChanged,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(memoryPressure),name:UIApplication.didReceiveMemoryWarningNotification,object:nil)
        if captureEnabled, let directory = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first {
            try? FileManager.default.removeItem(at:directory.appendingPathComponent("performance-capture.jsonl"))
        }
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--test-character-switch") {
            testEventFile = "character-switch-events.jsonl"
        }
        if ProcessInfo.processInfo.arguments.contains("--test-miku-head") { testEventFile = "miku-head-events.jsonl" }
        if ProcessInfo.processInfo.arguments.contains("--test-ipad") { testEventFile = "ipad-events.jsonl" }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           let directory = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first {
            try? FileManager.default.removeItem(at:directory.appendingPathComponent(testEventFile))
            try? FileManager.default.removeItem(at:directory.appendingPathComponent("layout-motion.jsonl"))
        }
#endif
    }
    @objc private func memoryPressure() {
        cancelPrewarm(); warmedKeys.removeAll()
        if !desiredVisible { bridge.setPaused(true) }
    }
    @objc private func themeChanged() {
        window?.backgroundColor = .clear
        window?.rootViewController?.view.backgroundColor = UIColor(Theme.background)
        overlay?.refreshTheme()
    }
    func openCompanion(_ model: ModelDescriptor, greetingReason:ConversationEntryReason = .characterSelection) {
        guard page == .home else { return }
        cancelPrewarm(preservingEntryFor:model.id)
        pendingGreeting = ConversationEntry(reason:greetingReason,characterID:model.id,accountID:companionStore.accountID)
        conversationVisible = false
        if let session = companion, session.model.id == model.id, retainedAccount == companionStore.accountID, ready, retainedReady {
            applyPendingMessage(); resumeRetainedConversation(); return
        }
        discardConversation(); recordVisit(model.id)
        retainedAccount = companionStore.accountID
        let session = CompanionSession(store:companionStore,model:model,soundscape:soundscape)
        session.onLoginRequested = { [weak self] in self?.requestLogin() }
        session.onIntent = { [weak self] intent in self?.signal(intent) }
        session.onAIVisual = { [weak self] visuals in self?.applyAIVisuals(visuals) }
        session.onAdditionalAIVisual = { [weak self] visuals in self?.applyAIVisuals(visuals,replacingAll:false) }
        session.onEndAIVisual = { [weak self] in self?.endAIVisuals() }
        session.onAppearance = { [weak self] profile in self?.configureAppearance(profile) }
        session.onPosture = { [weak self] value in
            guard let self else { return "角色暂时无法调整姿势，请重新打开后再试。" }
            return await self.applyPosture(value)
        }
        companion = session
        // Network preparation overlaps the 3D load, but never delays showing it.
        prepareEntry(model,trigger:greetingReason == .appLaunch ? "appLaunch" : "characterSwitch",delay:0)
        applyPendingMessage()
        openViewer(model,asCompanion:true)
    }
    private func configureAppearance(_ profile: CharacterProfile, immediate: Bool = false) {
        send("configureCompanion",payload:["accent":profile.accent,"ambience":profile.ambience])
        previewStudio(profile.resolvedStudio,immediate:immediate)
        overlay?.setCompanionTitle(profile.name)
        schedulePortrait()
    }
    func openDesigner(_ model: ModelDescriptor = .defaultCharacter) {
        guard page == .home else { return }
        openStudioWhenReady = true
        openCompanion(model)
    }
    private let characterPort = CharacterSignalPort()
    private func signal(_ intent: CharacterIntent) { send("character.signal",payload:["signal":characterPort.payload(intent,actorId:selectedModel.runtimeID)]) }
    private func selectPerformance(_ option: String, enabled: Bool) {
        endAIVisuals()
        guard selectedModel.performance?.options.contains(where:{ $0.id == option }) == true else { return }
        sendPerformance(CharacterIntent(eventName:"performance.select",target:option,intensity:enabled ? 1 : 0))
    }
    private func resetPerformance(group: String) {
        endAIVisuals()
        guard group.isEmpty || selectedModel.performance?.groups.contains(where:{ $0.id == group }) == true else { return }
        sendPerformance(CharacterIntent(eventName:"performance.reset",target:group))
    }
    private var aiVisualBaseline: [String:Set<String>] = [:]
    private var aiVisualTasks: [String:Task<Void,Never>] = [:]
    private var aiVisualSequences:[String:Task<Void,Never>]=[:]
    private func applyAIVisuals(_ visuals: [AIVisual],replacingAll:Bool = true) {
        if replacingAll {
            aiVisualSequences.values.forEach { $0.cancel() };aiVisualSequences.removeAll()
        }
        let actor=selectedModel.id
        // A late ear/hand update must not cancel the other groups' next phase.
        let groups=Dictionary(grouping:visuals.prefix(24),by: { $0.group })
        for (group,cues) in groups {
            aiVisualSequences[group]?.cancel()
            aiVisualSequences[group]=Task { @MainActor [weak self] in
                var previous=0
                for visual in cues.sorted(by:{($0.offsetMs ?? 0)<($1.offsetMs ?? 0)}) {
                    let offset=min(12000,max(0,visual.offsetMs ?? 0))
                    if offset>previous {try? await Task.sleep(for:.milliseconds(offset-previous))}
                    guard !Task.isCancelled,let self,self.selectedModel.id==actor else {return}
                    previous=offset;self.applyAIVisual(visual)
                }
            }
        }
    }
    private func applyAIVisual(_ visual:AIVisual) {
        guard page == .viewer, desiredVisible, characterPerformance.ready,
              let profile = selectedModel.performance else { return }
            guard let option = profile.options.first(where:{ $0.id == visual.assetId && $0.group == visual.group }),
                  profile.groups.contains(where:{$0.id==option.group}) else {return}
            let group = option.group
            if aiVisualBaseline[group] == nil {
                aiVisualBaseline[group] = characterPerformance.selections.intersection(Set(profile.options.filter { $0.group == group }.map(\.id)))
            }
            aiVisualTasks[group]?.cancel()
            signal(CharacterIntent(eventName:"performance.select",target:option.id,intensity:visual.active == false ? 0 : 1))
            let actor = selectedModel.id
            aiVisualTasks[group] = Task { @MainActor [weak self] in
                try? await Task.sleep(for:.milliseconds(min(20000,max(1200,visual.durationMs))))
                guard !Task.isCancelled, let self, self.selectedModel.id == actor else { return }
                self.restoreAIGroup(group)
            }
    }
    private func restoreAIGroup(_ group: String) {
        guard let original = aiVisualBaseline.removeValue(forKey:group) else { return }
        aiVisualTasks.removeValue(forKey:group)
        signal(CharacterIntent(eventName:"performance.reset",target:group))
        for option in selectedModel.performance?.restoring(group,baseline:original) ?? [] {
            // Portable enum choices share a parameter. Writing every unselected
            // choice as OFF would overwrite the restored selected expression.
            signal(CharacterIntent(eventName:"performance.select",target:option.id,intensity:original.contains(option.id) ? 1 : 0))
        }
    }
    private func endAIVisuals() {
        aiVisualSequences.values.forEach { $0.cancel() };aiVisualSequences.removeAll()
        aiVisualTasks.values.forEach { $0.cancel() }; aiVisualTasks.removeAll()
        for group in Array(aiVisualBaseline.keys) { restoreAIGroup(group) }
        aiVisualBaseline.removeAll()
    }
    private func sendPerformance(_ intent: CharacterIntent) {
        guard page == .viewer, desiredVisible, selectedModel.performance != nil,
              characterPerformance.ready, characterPerformance.pendingID == nil else { return }
        let id = UUID().uuidString
        characterPerformance.request(id:id,option:intent.target)
        send("character.signal",payload:["signal":characterPort.payload(intent,actorId:selectedModel.runtimeID,eventId:id)])
        Task { @MainActor [weak self] in
            try? await Task.sleep(for:.seconds(5))
            self?.characterPerformance.timeout(id)
        }
    }
    private func applyPosture(_ value: PosturePreferences) async -> String? {
        let actor = selectedModel.runtimeID, recordID = selectedModel.id, currentPresentation = presentation
        let clean = value.normalized(selectedModel), eventId = UUID().uuidString
        let result: String? = await withCheckedContinuation { continuation in
            postureRequests[eventId] = continuation
            let intent = CharacterIntent(eventName:"posture.set",posture:clean.payload(selectedModel))
            send("character.signal",payload:["signal":characterPort.payload(intent,actorId:actor,eventId:eventId)])
            Task { @MainActor [weak self] in
                try? await Task.sleep(for:.seconds(5))
                self?.postureRequests.removeValue(forKey:eventId)?.resume(returning:"姿势设置暂时没有收到确认，请稍后再试。")
            }
        }
        // Stopping text generation does not undo an already accepted explicit setting.
        guard currentPresentation == presentation, desiredVisible, actor == selectedModel.runtimeID else { return "这次姿势设置已取消。" }
        if let result { return result }
        companionStore.update(recordID) { record in
            var studio = record.profile.resolvedStudio; studio.posture = clean; record.profile.studio = studio
        }
        overlay?.setStudio(companionStore.record(recordID).profile.resolvedStudio)
        return companionStore.error
    }
    private func previewStudio(_ input: CharacterStudio, immediate: Bool = false) {
        let value = selectedModel.collection.normalize(input)
        send("configureStudio",payload:["studio":value.payload,"immediate":immediate])
        let values = (value.parameters ?? [:]).map { ["id":$0.key,"value":$0.value] as [String:Any] }
        send("character.parameters",payload:["parameters":values])
        let posture = (value.posture ?? PosturePreferences()).normalized(selectedModel)
        signal(CharacterIntent(eventName:"posture.set",posture:posture.payload(selectedModel)))
    }
    private func saveStudio(_ value: CharacterStudio) -> String? {
        guard companion == nil else { return "角色的出场设定已固定。" }
        let clean = selectedModel.collection.normalize(value)
        guard clean != companionStore.record(selectedModel.id).profile.resolvedStudio else { return nil }
        companionStore.update(selectedModel.id) { $0.profile.studio = clean }
        if companionStore.error == nil { previewStudio(value); schedulePortrait() }
        return companionStore.error
    }
    func openViewer(_ model: ModelDescriptor = .defaultCharacter, asCompanion: Bool = false) {
        guard page == .home, scene != nil else { return }
        if !asCompanion { companion?.stop(); companion = nil }
        cancelOpeningTasks()
        selectedModel = model; characterPort.reset()
        bundledBackdropVisible = false
        pendingReset = ""; pendingReveal = ""; frameReady = false
        stageLoadingVisible = true
        presentation += 1; desiredVisible = true; page = .loading
        characterPerformance.begin(modelID:model.runtimeID,presentation:presentation)
        // Keep a fully opaque native canvas above Unity even if its startup makes a
        // new window key. Unity can render normally underneath until its frame fence.
        if let window { windowHandoff.cover(window) }
        window?.rootViewController?.view.accessibilityElementsHidden = false
        window?.makeKeyAndVisible()
        foregroundWait = 0; openTime = Date()
        loadingPresentation.begin(now:ProcessInfo.processInfo.systemUptime)
        logger.info("viewer_open presentation=\(self.presentation) warm=\(self.ready)")
        startTimeout()
        scheduleRuntimeStart()
    }
    private func scheduleRuntimeStart() {
        guard !startupInProgress, active, desiredVisible, page == .loading, let scene else { return }
        launchTask?.cancel()
        let openingPresentation = presentation
        // First commit the usable native page. Unity requires the main thread;
        // do not start it underneath the full-screen brand transition.
        launchTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for:.milliseconds(80)) } catch { return }
            guard let self, self.active, !self.startupInProgress, self.desiredVisible,
                  self.page == .loading, self.presentation == openingPresentation else { return }
            if !self.bridge.started {
                LaunchTrace.mark("unityStartBegin")
                self.bridge.start(in:scene)
                LaunchTrace.mark("unityStartReturned")
                self.window?.makeKeyAndVisible()
            } else {
                self.bridge.setPaused(false)
                if self.ready { self.preparePresentation() }
            }
            let runtime = self.bridge.rootController()?.view.window
            runtime?.backgroundColor = UIColor(Theme.background)
            runtime?.isHidden = false
            runtime?.alpha = 1
        }
    }
    private func cancelOpeningTasks() {
        launchTask?.cancel(); launchTask = nil
        revealTask?.cancel(); revealTask = nil
    }
    private func scheduleReveal() {
        guard ready, frameReady, desiredVisible, active, page == .loading else { return }
        revealTask?.cancel()
        let openingPresentation = presentation
        // A fast cached role still gets one readable breath, never a one-frame flash.
        let remaining = loadingPresentation.remainingDisplayTime(now:ProcessInfo.processInfo.systemUptime)
        revealTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for:.seconds(remaining)) } catch { return }
            guard let self, self.presentation == openingPresentation, self.active else { return }
            self.reveal()
        }
    }
    private func resumeRetainedConversation() {
        guard let scene, let window, let runtime = bridge.rootController()?.view.window else { return }
        desiredVisible = true; page = .viewer
        bridge.setPaused(false)
        overlay?.view.accessibilityElementsHidden = true
        overlay?.view.isUserInteractionEnabled = false
        overlay?.view.setNeedsLayout(); overlay?.view.layoutIfNeeded()
        window.rootViewController?.view.accessibilityElementsHidden = true
        windowHandoff.transition(to:.conversation,shell:window,runtime:runtime,
            duration:UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.36,
            activateRuntime:{ self.bridge.show(in:scene) }) { [weak self] in
            guard let self, self.page == .viewer else { return }
            self.transitionSourceTab = nil
            self.overlay?.view.accessibilityElementsHidden = self.startupInProgress
            self.overlay?.view.isUserInteractionEnabled = true
            self.presentPendingCustomization()
            self.conversationVisible = true
            // Sample input readiness after the handoff has restored the overlay;
            // querying during the fade reports UnityView beneath disabled controls.
            self.send("getState")
            self.greetVisibleConversation()
        }
        setConversationAudioActive(true)
        recordTestEvent("{\"name\":\"conversationResumed\",\"presentationId\":\(presentation),\"modelId\":\"\(selectedModel.runtimeID)\"}")
    }
    func closeViewer() {
        guard page != .closing, page != .home else { return }
        overlay?.cancelInspection()
        conversationVisible = false; pendingGreeting = nil; backgroundConversation = false
        bundledBackdropVisible = false
        if pendingCharacter == nil { transitionSourceTab = nil }
        cancelPrewarm()
        let wasVisible = page == .viewer
        if wasVisible { requestPortrait() }
        cancelOpeningTasks()
        portraitTask?.cancel(); portraitTask = nil
        openStudioWhenReady = false
        companion?.dismissKeyboardRequest += 1
        setConversationAudioActive(false)
        captureTask?.cancel(); captureTask = nil
        UIApplication.shared.isIdleTimerDisabled = false
        desiredVisible = false; pendingReset = ""; pendingReveal = ""; frameReady = false
        stageLoadingVisible = false
        timer?.invalidate(); timer = nil
        send("clearInput")
        // Both directions fade only the native shell. Metal stays fully opaque
        // underneath until the native page has completely covered it.
        if wasVisible, let home = window, let runtime = bridge.rootController()?.view.window, runtime !== home {
            page = .closing
            overlay?.view.isUserInteractionEnabled = false
            home.rootViewController?.view.accessibilityElementsHidden = false
            home.rootViewController?.view.layoutIfNeeded()
            windowHandoff.transition(to:.shell,shell:home,runtime:runtime,
                duration:UIAccessibility.isReduceMotionEnabled ? 0.18 : 0.38,
                activateRuntime:{}) { [weak self] in
                guard let self else { return }
                self.finishClosing()
            }
        } else {
            bridge.rootController()?.view.window?.isHidden = true
            window?.rootViewController?.view.accessibilityElementsHidden = false
            if let window { windowHandoff.showShellImmediately(window) }
            finishClosing()
        }
    }
    private func finishClosing() {
        companion?.stop()
        overlay?.view.accessibilityElementsHidden = true
        overlay?.view.isUserInteractionEnabled = true
        bridge.setPaused(true); page = .home
        // Account changes, errors and actual role switches recreate the session. A tab
        // visit preserves the hosting controller, scroll offset, draft and camera pose.
        if needsAccountActivation || !retainedReady || companion == nil { discardConversation() }
        if pendingLogin { pendingLogin = false; loginPresented = true }
        else if needsAccountActivation { finishAccountActivation() }
        else if let next = pendingCharacter, selectedTab == .home {
            pendingCharacter = nil; openCompanion(next.model,greetingReason:next.reason)
        }
        if page == .home && !pendingLogin { schedulePrewarm() }
        logger.info("viewer_close presentation=\(self.presentation) live_window_fade=true")
    }
    private func schedulePortrait() {
        portraitTask?.cancel()
        guard !portraits.clearing else { return }
        let model = selectedModel, profile = profile(for:selectedModel)
        guard !portraits.hasCurrent(model,profile:profile) else { return }
        let current = presentation
        portraitTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for:.milliseconds(650)) } catch { return }
            guard let self, self.presentation == current, self.desiredVisible, self.page == .viewer else { return }
            self.requestPortrait()
        }
    }
    private func requestPortrait() {
        guard !portraits.clearing else { return }
        let model = selectedModel, profile = profile(for:selectedModel)
        let key = CharacterPortraitStore.key(model:model,profile:profile)
        guard !portraits.hasCurrent(model,profile:profile), !portraitRequests.values.contains(where:{ $0.key == key }) else { return }
        let request = nextRequest()
        portraitRequests[request] = (model,key)
        send("capturePortrait",payload:["portraitKey":key,"studio":profile.resolvedStudio.payload,
            "accent":profile.accent,"parameters":(profile.resolvedStudio.parameters ?? [:]).map { ["id":$0.key,"value":$0.value] as [String:Any] }],request:request)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for:.seconds(10))
            self?.portraitRequests.removeValue(forKey:request)
        }

    }
    func beginCacheClear(_ categories: Set<CacheCategory>) {
        if categories.contains(.speech) { SpeechClipCache.shared.beginClearing() }
        if categories.contains(.portraits) {
            portraitTask?.cancel(); portraitTask = nil; portraitRequests.removeAll()
            portraits.beginClearing()
        }
    }
    func endCacheClear(_ categories: Set<CacheCategory>) {
        if categories.contains(.speech) { SpeechClipCache.shared.endClearing() }
        if categories.contains(.portraits) {
            portraits.endClearing()
            if desiredVisible && page == .viewer { schedulePortrait() }
        }
    }
    private func previewFraming(_ value: CharacterFraming, immediate: Bool = false) {
        let clean = value.normalized
        send("configureFraming",payload:["framingShot":clean.shot,"framingSize":clean.size,
            "framingAngle":clean.angle,"immediate":immediate || UIAccessibility.isReduceMotionEnabled])
    }
    private func saveFraming(_ value: CharacterFraming) -> String? {
        guard companion == nil else { return "角色的出场设定已固定。" }
        // Update only framing: do not overwrite edits to memory, history, or character settings.
        guard value.normalized != companionStore.record(selectedModel.id).profile.resolvedFraming else { return nil }
        companionStore.update(selectedModel.id) { $0.profile.framing = value.normalized }
        if companionStore.error == nil { previewFraming(value) }
        return companionStore.error
    }
    func playAction(_ action: String) {
        guard ready, desiredVisible, page == .viewer else { return }
        guard companion?.availableActions.contains(where:{ $0.id == action }) ?? selectedModel.collection.actions.contains(action) else { return }
        signal(CharacterIntent(eventName:"action.request",target:action))
    }
    func activate() {
        let returning = !active && backgroundConversation
        active = true
        backgroundConversation = false
        if page == .loading, !bridge.started { scheduleRuntimeStart() }
        if ProcessInfo.processInfo.arguments.contains("--preview-companion"), page == .home, !bridge.started {
            openCompanion(.defaultCharacter)
        } else if previewEnabled, page == .home, !bridge.started { openViewer(.defaultCharacter) }
        if bridge.started, desiredVisible {
            bridge.setPaused(false)
            if page == .viewer {
                // Returning from permissions, Control Centre or the background preserves the live
                // camera and any unsaved sheet preview. Only a new presentation applies a profile.
                if let scene { bridge.show(in:scene) }
                overlay?.view.setNeedsLayout()
                setConversationAudioActive(companion != nil)
                send("configureViewport")
                if returning, pendingGreeting == nil, let companion, conversationVisible {
                    pendingGreeting = ConversationEntry(reason:.foregroundReturn,characterID:companion.model.id,accountID:companionStore.accountID)
                }
                greetVisibleConversation()
            }
            else if page == .loading {
                if frameReady { scheduleReveal() } else { preparePresentation() }
            }
        }
    }
    @ObservationIgnored private var deviceMotion=ConversationDeviceMotion()
    private func setConversationAudioActive(_ enabled:Bool) {
        soundscape.setActive(enabled)
        overlay?.setAtmosphereActive(enabled)
        deviceMotion.onShake = { [weak self] intensity in
            guard let self,self.active,self.conversationVisible,self.page == .viewer,
                  !self.startupInProgress,let session=self.companion,
                  !session.characterEditorPresented,!session.inspectionActive,!session.voiceInput.active else {return}
            session.reactToShake(intensity:intensity)
        }
        deviceMotion.setActive(enabled && companion != nil)
    }
    func deactivate() {
        // Settle may invoke a transition completion synchronously. Mark inactive
        // first so that a backgrounding app cannot greet behind a hidden window.
        overlay?.cancelInspection()
        active = false
        windowHandoff.settle()
        setConversationAudioActive(false)
        companion?.stop()
        cancelPrewarm()
        captureTask?.cancel(); captureTask = nil
        UIApplication.shared.isIdleTimerDisabled = false
        signal(CharacterIntent(eventName:"session.leave"))
        send("clearInput")
        bridge.setPaused(true)
    }
    func enteredBackground() {
        backgroundConversation = page == .viewer && conversationVisible && !startupInProgress
        deactivate()
        let task=UIApplication.shared.beginBackgroundTask(withName:"Save conversation")
        Task { @MainActor in
            await CompanionPersistence.flush()
            if task != .invalid {UIApplication.shared.endBackgroundTask(task)}
        }
    }
    private func greetVisibleConversation() {
        guard active, !startupInProgress, conversationVisible, desiredVisible, page == .viewer,
              let entry = pendingGreeting, let companion,
              entry.characterID == companion.model.id, entry.accountID == companionStore.accountID else { return }
        pendingGreeting = nil
        if let preparation=entryPreparation,preparation.api.characterID==companion.model.id {
            companion.adoptPreparationLease(preparation.body["request_id"] as? String)
        }
        cancelEntryPreparation(preserveGeneration:true)
        companion.enterConversation(entry)
    }
    private func preparePresentation() {
        guard ready, desiredVisible, active, page == .loading,
              pendingReset.isEmpty, pendingReveal.isEmpty, !frameReady else { return }
        bridge.setPaused(false)
        pendingReset = nextRequest()
        send("selectModel", payload:["modelId":selectedModel.runtimeID], request:pendingReset)
    }
    private func prepareSceneForReveal() {
        guard ready, desiredVisible, page == .loading else { return }
        if overlay == nil, let root = bridge.rootController() {
            let overlay = ViewerOverlayController()
            overlay.portraits = portraits; overlay.library = library
            overlay.characterPerformance = characterPerformance
            overlay.onSelectPerformance = { [weak self] option,enabled in self?.selectPerformance(option,enabled:enabled) }
            overlay.onAdjustPerformance = { [weak self] option,value in
                guard let self, self.selectedModel.performance?.options.contains(where:{$0.id==option && $0.control?.kind=="slider"}) == true else {return}
                self.endAIVisuals()
                self.signal(CharacterIntent(eventName:"performance.select",target:option,intensity:min(1,max(0,value))))
            }
            overlay.onResetPerformance = { [weak self] group in self?.resetPerformance(group:group) }
            overlay.onOpenCharacterFromDetails = { [weak self] id,customize in self?.openCharacter(id,customize:customize) }
            overlay.onDetailsClosed = { [weak self] in
                guard let self, !self.library.subscriptions.contains(self.selectedModel.id) else { return }
                self.navigate(.home)
            }
            overlay.onBack = { [weak self] in self?.navigate(.discover) }
            overlay.onTabSelected = { [weak self] tab in self?.navigate(tab) }
            overlay.onPreviewStudio = { [weak self] value in self?.previewStudio(value) }
            overlay.onSaveStudio = { [weak self] value in
                guard let self else { return "角色暂时无法保存，请重新打开后重试。" }
                return self.saveStudio(value)
            }
            overlay.onPreviewFraming = { [weak self] value in self?.previewFraming(value) }
            overlay.onSaveFraming = { [weak self] value in
                guard let self else { return "取景暂时无法保存，请重新打开后重试。" }
                return self.saveFraming(value)
            }
            overlay.onAction = { [weak self] action in self?.playAction(action) }
            overlay.onFrameRate = { [weak self] fps in
                guard let self else { return }
                self.targetFPS = fps
                self.send("configurePerformance",payload:["targetFPS":fps])
            }
            overlay.onResize = { [weak self] in self?.send("configureViewport") }
            overlay.onLoadCharacterView = { [weak self] pose,immediate in
                self?.send("loadCharacterView",payload:["inspectionPose":pose.payload,"immediate":immediate])
            }
            overlay.onNativeGesture = { [weak self] payload in
                guard let self, self.page == .viewer, self.desiredVisible else { return }
                self.send("nativeGesture",payload:payload)
            }
            overlay.onGestureInputChanged = { [weak self] enabled, framingEnabled in
                self?.send("configureGestures",payload:["gesturesEnabled":enabled,"framingGesturesEnabled":framingEnabled,"nativeGestures":true])
            }
            overlay.onConversationViewport = { [weak self] rect, safeFrame in
                self?.send("conversationViewport",payload:["viewportX":rect.minX,"viewportY":rect.minY,"viewportWidth":rect.width,"viewportHeight":rect.height,
                    "safeFrameX":safeFrame.minX,"safeFrameY":safeFrame.minY,"safeFrameWidth":safeFrame.width,"safeFrameHeight":safeFrame.height,
                    "immersive":rect == CGRect(x:0,y:0,width:1,height:1)])
            }
            root.addChild(overlay); root.view.addSubview(overlay.view)
            overlay.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                overlay.view.leadingAnchor.constraint(equalTo:root.view.leadingAnchor),
                overlay.view.trailingAnchor.constraint(equalTo:root.view.trailingAnchor),
                overlay.view.topAnchor.constraint(equalTo:root.view.topAnchor),
                overlay.view.bottomAnchor.constraint(equalTo:root.view.bottomAnchor)])
            overlay.didMove(toParent:root)
            self.overlay = overlay
        }
        overlay?.view.accessibilityElementsHidden = true
        overlay?.setModel(selectedModel)
        overlay?.setCompanion(companion)
        let profile = profile(for:selectedModel)
        configureAppearance(profile,immediate:true)
        overlay?.setFraming(profile.resolvedFraming)
        overlay?.setStudio(profile.resolvedStudio)
        // Configure everything underneath the loading canvas. The final command is a
        // render fence; modelSelected alone says nothing about these subsequent changes.
        overlay?.view.setNeedsLayout(); overlay?.view.layoutIfNeeded()
        previewFraming(profile.resolvedFraming,immediate:true)
        overlay?.loadSavedCharacterView(immediate:true)
        send("configureGestures",payload:["gesturesEnabled":overlay?.gestureInputAvailable ?? false,
            "framingGesturesEnabled":!(overlay?.modelControlsLocked ?? true),"nativeGestures":true])
        send("configurePerformance",payload:["targetFPS":targetFPS])
        pendingReveal = nextRequest()
        send("prepareReveal",request:pendingReveal)
    }
    private func reveal() {
        guard ready, frameReady, desiredVisible, active, page == .loading, let scene,
              let window, let runtime = bridge.rootController()?.view.window else { return }
        cancelOpeningTasks()
        overlay?.view.accessibilityElementsHidden = true
        overlay?.view.isUserInteractionEnabled = false
        let profile = profile(for:selectedModel)
        let shownPresentation = presentation
        windowHandoff.transition(to:.conversation,shell:window,runtime:runtime,
            duration:UIAccessibility.isReduceMotionEnabled ? 0.18 : 0.46,
            activateRuntime:{ self.bridge.show(in:scene) }) { [weak self] in
            guard let self, self.presentation == shownPresentation, self.page == .viewer else { return }
            self.transitionSourceTab = nil
            self.bundledBackdropVisible = false
            self.stageLoadingVisible = false
            self.overlay?.view.accessibilityElementsHidden = self.startupInProgress
            self.overlay?.view.isUserInteractionEnabled = true
            self.presentPendingCustomization()
            self.conversationVisible = true
            self.send("getState")
            LaunchTrace.mark("conversationVisible")
            self.greetVisibleConversation()
        }
        window.rootViewController?.view.accessibilityElementsHidden = true
        page = .viewer; retainedReady = true
        schedulePortrait()
        warmedKeys.insert(CharacterPortraitStore.key(model:selectedModel,profile:profile))
        // The prepared conversational framing is the first visible framing. An
        // automatic session.enter body cue would pull back for a greeting, then
        // zoom back in. Keep the natural idle; explicit chat actions still work.
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--layout-motion-review") { send("captureLayoutMotion") }
#endif
        if openStudioWhenReady {
            openStudioWhenReady = false
            DispatchQueue.main.async { [weak self] in self?.overlay?.openStudio() }
        }
        setConversationAudioActive(companion != nil)
        timer?.invalidate(); timer = nil
        send("configureViewport")
        send("configurePerformance",payload:["targetFPS":targetFPS])
        if captureEnabled, !didStartCapture {
            didStartCapture = true
            captureTask = Task { @MainActor [weak self] in await self?.capturePerformance() }
        }
        logger.info("viewer_visible elapsed=\(Date().timeIntervalSince(self.openTime)) presentation=\(self.presentation)")
        recordTestEvent("{\"name\":\"conversationPresented\",\"presentationId\":\(presentation),\"elapsed\":\(Date().timeIntervalSince(openTime)),\"modelId\":\"\(selectedModel.runtimeID)\"}")
    }
    nonisolated func runtimeDidReceive(_ json: String) {
        Task { @MainActor [weak self] in self?.receive(json) }
    }
    private func receive(_ json: String) {
        guard let data = json.data(using:.utf8),
              let event = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              event["schemaVersion"] as? Int == 1,
              let name = event["name"] as? String else { return }
        if name == "modelPrewarmed" || name == "modelPrewarmFailed" {
            recordTestEvent(json)
            if let request = prewarmRequest, event["requestId"] as? String == request.id {
                if name == "modelPrewarmed" { warmedKeys.insert(request.key) }
                prewarmRequest = nil
                if !desiredVisible { bridge.setPaused(true) }
            }
            return
        }
        if name == "portraitReady" || name == "portraitFailed" {
            guard let id = event["requestId"] as? String, let request = portraitRequests.removeValue(forKey:id),
                  event["modelId"] as? String == request.model.runtimeID else { return }
            let current = CharacterPortraitStore.key(model:request.model,profile:profile(for:request.model))
            if name == "portraitReady", current == request.key, portraits.accept(model:request.model,key:request.key) {
                logger.info("portrait_saved model=\(request.model.id)")
            } else { logger.info("portrait_deferred model=\(request.model.id)") }
            return
        }
        if name == "layoutMotionSample" {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--layout-motion-review"),
               let directory = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first {
                let url = directory.appendingPathComponent("layout-motion.jsonl")
                if !FileManager.default.fileExists(atPath:url.path) { FileManager.default.createFile(atPath:url.path,contents:nil) }
                if let handle = try? FileHandle(forWritingTo:url) {
                    defer { try? handle.close() }; _ = try? handle.seekToEnd(); try? handle.write(contentsOf:Data((json+"\n").utf8))
                }
            }
#endif
            return
        }
#if DEBUG
        // Deterministically exercise cancellation and timeout with the real engine.
        // Only the delivery of the first ready event is delayed, never scene content.
        if name == "sceneReady", !didDeferTestReady,
           ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--test-ready-delay=") }),
           let seconds = Double(argument.split(separator:"=").last ?? ""), seconds > 0 {
            didDeferTestReady = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(for:.seconds(min(seconds,40)))
                self?.receive(json)
            }
            return
        }
#endif
        logger.info("unity_event \(json, privacy:.public)")
        recordTestEvent(json)
        characterPerformance.receive(event)
        if name == "characterReceipt", let receipt = event["receipt"] as? [String:Any],
           receipt["eventName"] as? String == "action.request",
           receipt["code"] as? String == "POSTURE_ACTION_UNAVAILABLE_OR_TRANSITIONING" {
            companion?.notice = "当前姿势还没有这个动作，或正在换姿势。可以稍后再试，或先说“站起来”。"
        }
        if name == "characterReceipt", event["presentationId"] as? Int == presentation,
           event["modelId"] as? String == selectedModel.runtimeID, let receipt = event["receipt"] as? [String:Any],
           let id = receipt["eventId"] as? String, let continuation = postureRequests.removeValue(forKey:id) {
            continuation.resume(returning:receipt["status"] as? String == "accepted" ? nil : "这个姿势或参数暂时无法执行，已保持原来的设置。")
        }
        // The overlay correlates token + character to the owning session. Final
        // auto-save replies must survive a tab change/background transition.
        overlay?.receiveInspectionEvent(event)
        if event["presentationId"] as? Int == presentation,event["modelId"] as? String == selectedModel.runtimeID,
           ["previewPinchBegan","previewPinchEnded","previewPinchReturned","previewPinchRejected"].contains(name) {
            overlay?.setRuntimeFraming(event)
        }
        if event["presentationId"] as? Int == presentation, event["modelId"] as? String == selectedModel.runtimeID,
           ["state","studioConfigured","environmentConfigured","framingConfigured","companionViewport","actionStarted","actionCompleted","headTapped","characterReceipt","parametersConfigured","postureConfigured","postureSettled","performanceConfigured","inspectionPrepared","inspectionBegan","inspectionEnded","inspectionReturned","inspectionRejected","inspectionAdjusting","inspectionChanged","inspectionCaptured","inspectionClosed","inspectionLoaded","previewRotationBegan","previewRotationEnded","previewRotationReturned","previewRotationRejected"].contains(name) {
            overlay?.setRuntimeFraming(event)
        }
        switch name {
        case "characterShaken","characterPinched":
            guard page == .viewer,desiredVisible,event["presentationId"] as? Int==presentation,
                  event["modelId"] as? String==selectedModel.runtimeID else {return}
            if name=="characterShaken" {companion?.reactToShake(intensity:event["previewShakeIntensity"] as? Double ?? 0.7)}
            else if let kind=event["previewReactionKind"] as? String,["pinch_out","pinch_in"].contains(kind) {
                companion?.reactToModelInteraction(kind:kind,intensity:event["previewReactionIntensity"] as? Double ?? 0.7)
            }
            overlay?.setRuntimeFraming(event)
        case "framingGestureEnded":
            guard companion == nil else { return }
            guard event["presentationId"] as? Int == presentation,
                  event["modelId"] as? String == selectedModel.runtimeID,
                  let size = event["framingSize"] as? Double, let angle = event["framingAngle"] as? Double,
                  let shot = event["framingShot"] as? String, size.isFinite, angle.isFinite else { return }
            let framing = CharacterFraming(shot:shot,size:size,angle:angle).normalized
            companionStore.update(selectedModel.id) { $0.profile.framing = framing }
            // The engine already applied this value. Echoing configureFraming would interrupt input.
            overlay?.setFraming(framing); overlay?.setRuntimeFraming(event)
        case "sceneReady":
            LaunchTrace.mark("unitySceneReadyReceived")
            ready = true
            if desiredVisible && active { preparePresentation() }
            else { bridge.setPaused(true); window?.makeKeyAndVisible() }
        case "modelSelected":
            guard event["presentationId"] as? Int == presentation,
                  event["modelId"] as? String == selectedModel.runtimeID else { return }
            if page == .loading, event["requestId"] as? String == pendingReset { pendingReset = ""; prepareSceneForReveal() }
        case "presentationReady":
            guard page == .loading, desiredVisible,
                  event["presentationId"] as? Int == presentation,
                  event["modelId"] as? String == selectedModel.runtimeID,
                  event["requestId"] as? String == pendingReveal,
                  (event["stableRenderedFrames"] as? Int ?? 0) >= 3 else { return }
            pendingReveal = ""; frameReady = true
            LaunchTrace.mark("characterFrameReady")
            scheduleReveal()
        case "actionStarted", "actionCompleted", "actionIdle":
            guard event["presentationId"] as? Int == presentation,
                  event["modelId"] as? String == selectedModel.runtimeID else { return }
            overlay?.setAction(name == "actionStarted" ? event["action"] as? String ?? "" : "")
        case "headTapped":
            guard desiredVisible, event["presentationId"] as? Int == presentation else { return }
            UIImpactFeedbackGenerator(style:.light).impactOccurred()
        case "performance":
            guard desiredVisible, event["presentationId"] as? Int == presentation,
                  event["modelId"] as? String == selectedModel.runtimeID else { return }
            overlay?.setPerformance(fps:event["fps"] as? Double ?? 0,
                target:event["targetFPS"] as? Int ?? targetFPS,
                screenMaximum:scene?.screen.maximumFramesPerSecond ?? 60)
        case "error":
            guard desiredVisible else { return }
            cancelOpeningTasks()
            setConversationAudioActive(false)
            companion?.stop(); overlay?.view.accessibilityElementsHidden = true
            errorMessage = "请返回首页后重新尝试。如果仍无法打开，请关闭并重新打开 App。"
            page = .error; desiredVisible = false; retainedReady = false; transitionSourceTab = nil
            stageLoadingVisible = false
            bridge.rootController()?.view.window?.isHidden = true
            window?.rootViewController?.view.accessibilityElementsHidden = false
            timer?.invalidate(); bridge.setPaused(true)
            if let window { windowHandoff.showShellImmediately(window) }
        default: break
        }
    }
    // Explicit local launch flag only. No telemetry is uploaded; normal launches do not write events.
    private func capturePerformance() async {
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        do {
            try await Task.sleep(for:.seconds(6))
            for fps in [120,60] {
                guard active, desiredVisible else { return }
                targetFPS = fps
                send("configurePerformance",payload:["targetFPS":fps])
                for action in selectedModel.actions {
                    try Task.checkCancellation()
                    guard active, desiredVisible else { return }
                    playAction(action.id)
                    try await Task.sleep(for:.seconds(6))
                }
            }
            targetFPS = 120
            send("configurePerformance",payload:["targetFPS":120])
            try await Task.sleep(for:.seconds(15))
        } catch { return }
    }
    private func recordTestEvent(_ json: String) {
        var filename: String?
        if captureEnabled { filename = "performance-capture.jsonl" }
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { filename = testEventFile }
#endif
        guard let filename,
              let directory = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first,
              let data = (json + "\n").data(using:.utf8) else { return }
        let url = directory.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath:url.path) { FileManager.default.createFile(atPath:url.path,contents:nil) }
        if let handle = try? FileHandle(forWritingTo:url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd(); try? handle.write(contentsOf:data)
        }
    }
    private func nextRequest() -> String { sequence += 1; return "view-\(presentation)-\(sequence)" }
    private func send(_ name: String, payload: [String:Any] = [:], request: String? = nil) {
        guard bridge.started else { return }
        let value: [String:Any] = ["schemaVersion":1,"kind":"command","name":name,
            "requestId":request ?? nextRequest(),"presentationId":presentation,"payload":payload]
        guard let data = try? JSONSerialization.data(withJSONObject:value), let json = String(data:data,encoding:.utf8) else { return }
        bridge.send(json)
    }
    private func startTimeout() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.active, self.page == .loading else { return }
                self.foregroundWait += 1
                if self.foregroundWait >= 30 {
                    self.cancelOpeningTasks()
                    self.setConversationAudioActive(false)
                    self.errorMessage = "准备模型所需时间较长，请返回后重试。"
                    self.page = .error; self.desiredVisible = false; self.retainedReady = false; self.transitionSourceTab = nil
                    self.stageLoadingVisible = false
                    self.bridge.rootController()?.view.window?.isHidden = true
                    self.window?.rootViewController?.view.accessibilityElementsHidden = false
                    self.timer?.invalidate(); self.bridge.setPaused(true)
                    if let window = self.window { self.windowHandoff.showShellImmediately(window) }
                }
            }
        }
    }
}
