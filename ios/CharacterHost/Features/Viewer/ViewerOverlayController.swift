import UIKit
import SwiftUI

private final class TouchThroughView: UIView {
    weak var chatView:UIView?
    weak var characterTouchView:UIView?
    var messageFrame = CGRect.zero
    var messageRegions: [String:ConversationHitRegion] = [:]
    var capturesInspection = false
    weak var inspectionReset:UIView?
    weak var inspectionEntry:UIView?
    weak var inspectionDock:UIView?
    private let bottomScrim = CAGradientLayer()
    private let sideScrim = CAGradientLayer()
    private let fadeStops = (0...16).map { CGFloat($0) / 16 }
    override init(frame: CGRect) {
        super.init(frame:frame)
        isMultipleTouchEnabled = true
        for scrim in [bottomScrim,sideScrim] { layer.addSublayer(scrim) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func conversationHit(at point:CGPoint)->ConversationHitKind? {
        // Controls remain usable even where their 44pt target extends beyond a
        // bubble's raised corner. Completely faded messages count as whitespace.
        if messageRegions.values.contains(where:{$0.kind == .control && $0.frame.contains(point)}) {return .control}
        if !UIAccessibility.isReduceTransparencyEnabled,
           point.y-messageFrame.minY < ConversationContentMask.touchThroughHeight(in:messageFrame.height) {return nil}
        return messageRegions.values.contains(where:{$0.kind == .message && $0.frame.contains(point)}) ? .message : nil
    }
    func previewOrigin(at point:CGPoint,target:UIView?)->CharacterPreviewOrigin? {
        if let chatView,messageFrame.contains(chatView.convert(point,from:self)) {
            switch conversationHit(at:chatView.convert(point,from:self)) {
            case .control:return nil
            case .message:return .conversationMessage
            case nil:return .conversationBlank
            }
        }
        if let characterTouchView,let target,
           target === characterTouchView || target.isDescendant(of:characterTouchView) {return .character}
        return nil
    }
    func updateScrims(chat: CGRect?, stage: CGRect, editing: Bool, duration: TimeInterval) {
        let color = UIColor(Theme.background)
        let solid = UIAccessibility.isReduceTransparencyEnabled || ThemeSettings.shared.solid
        let sideChat = AdaptiveViewerLayout.sideBySide(bounds.size) && chat != nil
        // Spread the veil across the whole conversation, with a gentle slope at both ends.
        // The landscape keyboard keeps its side column without whitening the character's face.
        let start = chat.map { sideChat ? max(0,$0.maxY-90) : max(0,$0.minY-16) } ?? max(0,stage.maxY-48)
        let opacity: CGFloat = solid ? 1 : (editing ? 0.36 : 0.80)
        sideScrim.startPoint = CGPoint(x:0,y:0.5); sideScrim.endPoint = CGPoint(x:1,y:0.5)
        let sideStart = max(0,(chat?.minX ?? bounds.width)-80)
        update(sideScrim,frame:CGRect(x:sideStart,y:0,width:max(1,bounds.width-sideStart),height:bounds.height),
            colors:fadeStops.map { t in color.withAlphaComponent(sideChat ? opacity * t * t * (3-2*t) : 0).cgColor },
            locations:fadeStops.map { NSNumber(value:Double($0)) },duration:duration)
        update(bottomScrim,frame:CGRect(x:0,y:start,width:bounds.width,height:max(1,bounds.height-start)),
            colors:fadeStops.map { t in color.withAlphaComponent((sideChat ? 0 : opacity) * t * t * (3-2*t)).cgColor },
            locations:fadeStops.map { NSNumber(value:Double($0)) },duration:duration)
    }
    private func update(_ scrim:CAGradientLayer,frame:CGRect,colors:[CGColor],locations:[NSNumber],duration:TimeInterval) {
        let keys = ["position","bounds","colors","locations"]
        let previous = keys.map { scrim.value(forKeyPath:$0) }
        let displayed = keys.map { scrim.presentation()?.value(forKeyPath:$0) ?? scrim.value(forKeyPath:$0) }
        let initialized = scrim.bounds.width > 0
        CATransaction.begin(); CATransaction.setDisableActions(true)
        scrim.frame = frame; scrim.colors = colors; scrim.locations = locations
        CATransaction.commit()
        guard initialized, duration > 0 else { return }
        for (index,key) in keys.enumerated() {
            let target = scrim.value(forKeyPath:key)
            if let old = previous[index] as? NSObject, old.isEqual(target) { continue }
            let animation = CABasicAnimation(keyPath:key)
            animation.fromValue = displayed[index]; animation.toValue = target
            animation.duration = duration; animation.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut)
            scrim.add(animation,forKey:key)
        }
    }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if capturesInspection, let characterTouchView {
            for panel in [inspectionReset,inspectionEntry,inspectionDock].compactMap({$0}) where !panel.isHidden && panel.alpha>0.01 {
                let local=panel.convert(point,from:self)
                if panel.bounds.contains(local),let hit=panel.hitTest(local,with:event) { return hit }
            }
            return characterTouchView.hitTest(characterTouchView.convert(point,from:self),with:event)
        }
        guard let hit = super.hitTest(point,with:event), hit !== self else { return nil }
        if let chatView,
           hit.isDescendant(of:chatView), let characterTouchView, characterTouchView.isUserInteractionEnabled {
            let local = chatView.convert(point,from:self)
            if messageFrame.contains(local),conversationHit(at:local) == nil {
                return characterTouchView.hitTest(characterTouchView.convert(point,from:self),with:event)
            }
        }
        return hit
    }
}

// Sheet geometry becomes available during presentation, not just after its completion.
private final class PreviewSheet<Content: View>: UIHostingController<Content> {
    var onLayout: (() -> Void)?
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); onLayout?() }
}

final class ViewerOverlayController: UIViewController, UISheetPresentationControllerDelegate, UIGestureRecognizerDelegate {
    func refreshTheme() {
        guard isViewLoaded else { return }
        func update(_ view:UIView) {
            if let button = view as? UIButton, ["viewerBackButton"].contains(button.accessibilityIdentifier ?? "") {
                button.configuration?.background.backgroundColor = UIColor(Theme.background).withAlphaComponent(UIAccessibility.isReduceTransparencyEnabled ? 1 : 0.14)
                button.configuration?.background.strokeColor = UIColor.white.withAlphaComponent(0.14)
            }
            view.subviews.forEach(update)
        }
        update(view); updatePositionButton(); view.setNeedsLayout()
    }
    var onTabSelected: ((AppTab)->Void)?
    private var dockBottomInset:CGFloat = -1
    private var dockHost: UIHostingController<AppDock>?
    var onBack: (() -> Void)?
    var onPreviewFraming: ((CharacterFraming) -> Void)?
    var onSaveFraming: ((CharacterFraming) -> String?)?
    private let touchSurface = CharacterTouchSurface()
    private let viewEditor = CharacterViewEditor()
    private var viewEditorHost:UIHostingController<CharacterViewEditorPanel>?
    private let positionButton=UIButton(type:.system)
    private let resetPositionButton=UIButton(type:.system)
    private var positionSessions:[Int:(session:CompanionSession,account:String)]=[:]
    var onLoadCharacterView:((CharacterViewPose,Bool)->Void)?
    func loadSavedCharacterView(immediate:Bool) {
        guard let session=chatSession else {return}
        viewEditor.pose=session.record.lastViewPose
        if session.record.viewLibrary != nil {
            let pose=viewEditor.pose
            session.store.update(session.model.id) {$0.viewPose=pose;$0.viewLibrary=nil}
        }
        onLoadCharacterView?(viewEditor.pose,immediate)
    }
    private func viewCommand(_ state:String) {
        onNativeGesture?(["action":"inspect","state":state,"inspectionToken":touchSurface.inspectionToken])
    }
    private func rememberView(_ pose:CharacterViewPose,session:CompanionSession) {
        guard session.record.viewPose != pose || session.record.viewLibrary != nil else {return}
        session.store.update(session.model.id) {$0.viewPose=pose;$0.viewLibrary=nil}
        if let error=session.store.error {viewEditor.status=error} else {viewEditor.status=""}
    }
    private func updatePositionButton() {
        let editing=viewEditor.isOpen
        positionButton.setImage(UIImage(systemName:editing ? "checkmark" : "move.3d",withConfiguration:UIImage.SymbolConfiguration(pointSize:15,weight:.regular)),for:.normal)
        positionButton.tintColor=UIColor(Theme.ink).withAlphaComponent(editing ? 0.84:0.56)
        positionButton.accessibilityLabel=editing ? "结束位置调整" : "修改角色位置"
        positionButton.accessibilityValue=editing ? "编辑中" : "已记住最后位置"
        positionButton.accessibilityIdentifier=editing ? "closeCharacterViewEditor" : "characterPositionButton"
        positionButton.isHidden=chatSession == nil
    }
    @objc private func togglePositionEditor() {
        guard gestureInputAvailable,chatSession != nil else {return}
        UIImpactFeedbackGenerator(style:.light).impactOccurred(intensity:0.65)
#if DEBUG
        inspectionHapticCount += 1
#endif
        if viewEditor.isOpen {closeViewEditor();return}
        touchSurface.beginEditing()
        if let session=chatSession {positionSessions[touchSurface.inspectionToken]=(session,session.store.accountID)}
        viewCommand("open")
        showViewEditor();setInspectionCapture(true)
    }
    @objc private func resetPosition() {
        guard viewEditor.isOpen,let session=chatSession else {return}
        touchSurface.cancelCurrentAdjustment()
        viewEditor.pose = .original;viewEditor.status=""
        rememberView(.original,session:session)
        viewCommand("reset")
    }
    private func showViewEditor() {
        guard viewEditorHost == nil,chatSession != nil else {return}
        viewEditor.isOpen=true;viewEditor.status="";viewEditor.moving=false
        let host=UIHostingController(rootView:CharacterViewEditorPanel(editor:viewEditor))
        host.view.backgroundColor = .clear;host.view.isOpaque=false;host.safeAreaRegions=[]
        host.view.alpha=0
        addChild(host);view.addSubview(host.view);host.didMove(toParent:self);viewEditorHost=host
        host.view.addSubview(resetPositionButton)
        (view as? TouchThroughView)?.inspectionReset=resetPositionButton
        chatSession?.dismissKeyboardRequest += 1;view.endEditing(true)
        customizationButton.isUserInteractionEnabled=false;updatePositionButton()
        // Resolve the final chat-centred frame while invisible, outside an animation.
        // Animating a newly mounted zero frame caused a flight from the top-left.
        UIView.performWithoutAnimation { self.view.setNeedsLayout();self.view.layoutIfNeeded() }
        host.view.transform=UIAccessibility.isReduceMotionEnabled ? .identity : CGAffineTransform(translationX:0,y:18)
        UIView.animate(withDuration:motionDuration,delay:0,usingSpringWithDamping:0.9,initialSpringVelocity:0,options:[.beginFromCurrentState,.allowUserInteraction]) {
            host.view.alpha=1;host.view.transform = .identity
        }
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            positionAnimationSamples=[]
            for delay in [0.03,0.10,0.20,0.40,0.75] {
                DispatchQueue.main.asyncAfter(deadline:.now()+delay) { [weak self,weak host] in
                    guard let self,let host,self.viewEditorHost === host else {return}
                    let layer=host.view.layer.presentation() ?? host.view.layer
                    self.positionAnimationSamples.append(["x":layer.frame.minX,"y":layer.frame.minY,"opacity":Double(layer.opacity)])
                }
            }
        }
#endif
    }
    private func closeViewEditor() {
        guard viewEditor.isOpen else {return}
        touchSurface.endEditing()
        // Keep the latest received target now; the ordered close reply commits
        // the final engine target even if its last changed event was in flight.
        if let session=chatSession {rememberView(viewEditor.pose,session:session)}
        viewCommand("close")
        viewEditor.isOpen=false;viewEditor.moving=false;setInspectionCapture(false)
        customizationButton.isUserInteractionEnabled=true;updatePositionButton()
        guard let host=viewEditorHost else {return}
        viewEditorHost=nil;(view as? TouchThroughView)?.inspectionReset=nil
        host.willMove(toParent:nil);host.view.isUserInteractionEnabled=false
        UIView.animate(withDuration:motionDuration,delay:0,options:[.beginFromCurrentState,.allowUserInteraction]) {
            host.view.alpha=0;host.view.transform=UIAccessibility.isReduceMotionEnabled ? .identity : CGAffineTransform(translationX:0,y:12)
        } completion:{ _ in host.view.removeFromSuperview();host.removeFromParent() }
        animateLayout()
    }
#if DEBUG
    private var inspectionFeedbackShowCount = 0
    private var inspectionHapticCount = 0
    private var positionAnimationSamples:[[String:Double]] = []
#endif
    var onNativeGesture: (([String:Any])->Void)?
    var onGestureInputChanged: ((Bool, Bool) -> Void)?
    var gestureInputAvailable: Bool { studioOriginal == nil && framingOriginal == nil }
    private(set) var modelControlsLocked = true
    private let gestureHint = UILabel()
    private func syncGestureInput() {
        if !gestureInputAvailable { cancelInspection() }
        touchSurface.configure(available:gestureInputAvailable,framingEnabled:false)
        onGestureInputChanged?(gestureInputAvailable, false)
    }
    func receiveInspectionEvent(_ event:[String:Any]) {
        let name=event["name"] as? String ?? ""
        guard let token=event["inspectionToken"] as? Int,
              let owner=positionSessions[token],event["modelId"] as? String == owner.session.model.runtimeID else {return}
        let session=owner.session
        guard session.store.accountID==owner.account else {positionSessions.removeValue(forKey:token);return}
        if let pose=CharacterViewPose(event:event) {
            if token==touchSurface.inspectionToken,viewEditor.isOpen {
                viewEditor.pose=pose;viewEditor.moving=event["inspectionMoving"] as? Bool ?? false
            }
            if ["inspectionEnded","inspectionClosed","inspectionChanged"].contains(name) {rememberView(pose,session:session)}
        }
        if name=="inspectionClosed" {positionSessions.removeValue(forKey:token)}
        if name=="inspectionRejected",token==touchSurface.inspectionToken {closeViewEditor()}
    }
    func cancelInspection() {closeViewEditor();touchSurface.cancelInspection();setInspectionCapture(false)}
    private func setInspectionCapture(_ value:Bool) {
        chatSession?.inspectionActive = value
        (view as? TouchThroughView)?.capturesInspection = value
        func setScrolling(_ node:UIView) {
            if let scroll = node as? UIScrollView { scroll.isScrollEnabled = !value }
            node.subviews.forEach(setScrolling)
        }
        if let host = chatHost { setScrolling(host.view) }
    }
    private func setModelControlsLocked(_ locked: Bool) {
        modelControlsLocked = true
        gestureHint.text = "单指轻转，松手复位；右上角修改位置"
        stageProbe.accessibilityLabel = "角色互动区域，单指小范围旋转，松手恢复；右上角修改位置"
        syncGestureInput()
    }
    private var framing = CharacterFraming.recommended
    private var framingOriginal: CharacterFraming?
    private var editorDismissing = false
    private let softSheetTransition = SoftSheetTransition()
    private var motionDuration: TimeInterval { UIAccessibility.isReduceMotionEnabled ? 0.18 : 0.42 }
    private func animateLayout() {
        view.setNeedsLayout()
        UIView.animate(withDuration:motionDuration,delay:0,options:[.beginFromCurrentState,.allowUserInteraction,.curveEaseInOut]) {
            self.view.layoutIfNeeded()
        }
    }
    private func prepareEditor() {
        editorDismissing = false
        chatSession?.characterEditorPresented = true
        chatSession?.dismissKeyboardRequest += 1
        view.endEditing(true); chatEditing = false
        animateLayout()
    }
    private func editorDidClose() {
        view.endEditing(true); chatEditing = false
        chatSession?.dismissKeyboardRequest += 1
        chatSession?.characterEditorPresented = false
        animateLayout()
    }
    private func prepareSheet<Content:View>(_ host: PreviewSheet<Content>) {
        host.onLayout = { [weak self] in self?.animateLayout() }
    }

    var portraits:CharacterPortraitStore!
    var library:CharacterLibrary!
    var characterPerformance:CharacterPerformanceState!
    var onSelectPerformance:((String,Bool)->Void)?
    var onResetPerformance:((String)->Void)?
    var onOpenCharacterFromDetails: ((String,Bool) -> Void)?
    var onDetailsClosed: (() -> Void)?
    private var nextCharacterAfterDetails: (String,Bool)?
    private var identityHost:UIHostingController<CharacterConversationIdentity>?
    private let customizationButton = UIButton(type:.system)
    private var identityLeading:NSLayoutConstraint?
    private var identityContentWidth:NSLayoutConstraint?
    private var identityCentered:NSLayoutConstraint?
    private var identityExplorerWidth:NSLayoutConstraint?
    private let backButton = UIButton(type:.system)
    var onPreviewStudio: ((CharacterStudio) -> Void)?
    var onSaveStudio: ((CharacterStudio) -> String?)?
    private var studio = CharacterStudio.recommended
    private var studioOriginal: CharacterStudio?
    func setStudio(_ value: CharacterStudio) { studio = value.normalized }
    func openStudio() { openCustomization() }
    func openDetailsCustomization() { openCustomization(showDetails:false) }
    private func openCustomization(_ destination: CustomizationDestination? = nil, showDetails:Bool = true) {
        guard presentedViewController == nil else { return }
        studioOriginal = studio; framingOriginal = framing
        prepareEditor(); syncGestureInput()
        let panel = CompanionCustomizationPanel(model:model,session:chatSession,destination:destination,portraits:portraits)
        let close = SoftPanelCloseRequest()
        close.begin { [weak self] in self?.finishCustomization() }
        softSheetTransition.onDismissRequested = { close.request() }
        let content:AnyView
        if let session = chatSession, let portraits, let library, destination == nil, showDetails {
            content = AnyView(CharacterDetailsPanel(model:model,store:session.store,library:library,portraits:portraits,showsLiveCharacter:true,
                onChat:{ close.request() },customization:{ AnyView(panel) },session:session,
                performanceState:characterPerformance,
                onSelectPerformance:{ [weak self] id,enabled in self?.onSelectPerformance?(id,enabled) },
                onResetPerformance:{ [weak self] group in self?.onResetPerformance?(group) },
                onPerformanceVisibility:{ [weak self] visible in self?.resizePerformancePanel(visible) },
                onOpenCharacter:{ [weak self] id,customize in
                    self?.nextCharacterAfterDetails = (id,customize); close.request()
                }))
        } else { content = AnyView(panel) }
        let host = PreviewSheet(rootView:content.environment(\.softPanelCloseRequest,close)
            .environment(\.softPanelDismiss,{ close.request() }))
        prepareSheet(host)
        host.modalPresentationStyle = .custom; host.transitioningDelegate = softSheetTransition
        host.view.backgroundColor = .clear; host.view.isOpaque = false; host.safeAreaRegions = []
        host.preferredContentSize = CGSize(width:520,height:560)
        host.presentationController?.delegate = self
        view.isUserInteractionEnabled = false
        present(host,animated:true) { [weak self] in self?.animateLayout() }
    }
    private func presentConversationPanel<Content:View>(height:CGFloat,@ViewBuilder content:() -> Content) {
        guard presentedViewController == nil else { return }
        studioOriginal = studio; framingOriginal = framing
        prepareEditor(); syncGestureInput()
        let close = SoftPanelCloseRequest()
        close.begin { [weak self] in self?.finishCustomization() }
        softSheetTransition.onDismissRequested = { close.request() }
        let host = PreviewSheet(rootView:content().environment(\.softPanelCloseRequest,close)
            .environment(\.softPanelDismiss,{ close.request() }))
        prepareSheet(host)
        host.modalPresentationStyle = .custom; host.transitioningDelegate = softSheetTransition
        host.view.backgroundColor = .clear; host.view.isOpaque = false; host.safeAreaRegions = []
        host.preferredContentSize = CGSize(width:520,height:height)
        host.presentationController?.delegate = self
        view.isUserInteractionEnabled = false
        present(host,animated:true) { [weak self] in self?.animateLayout() }
    }
    private func openConversationPerformance() {
        guard let profile = model.performance, let characterPerformance else { return }
        presentConversationPanel(height:302) {
            CharacterPerformancePanel(model:model,profile:profile,state:characterPerformance,
                onSelect:{ [weak self] id,on in self?.onSelectPerformance?(id,on) },
                onReset:{ [weak self] group in self?.onResetPerformance?(group) })
        }
    }
    private func openConversationSound() {
        guard let session = chatSession else { return }
        presentConversationPanel(height:258) { ConversationSoundPanel(session:session) }
    }
    private func resizePerformancePanel(_ visible:Bool) {
        guard let host = presentedViewController, !host.isBeingDismissed else { return }
        // Make room to see the character's performance, without touching Unity's camera.
        host.preferredContentSize = CGSize(width:520,height:visible ? 302 : 560)
        let container = host.presentationController?.containerView
        container?.setNeedsLayout()
        UIView.animate(withDuration:motionDuration,delay:0,options:[.beginFromCurrentState,.allowUserInteraction,.curveEaseInOut]) {
            container?.layoutIfNeeded()
        }
    }
    private func finishCustomization() {
        studioOriginal = nil; framingOriginal = nil
        view.isUserInteractionEnabled = true
        syncGestureInput(); animateLayout()
        dismiss(animated:true) { [weak self] in
            guard let self else { return }
            self.editorDidClose()
            if let next = self.nextCharacterAfterDetails {
                self.nextCharacterAfterDetails = nil
                self.onOpenCharacterFromDetails?(next.0,next.1)
            } else { self.onDetailsClosed?() }
        }
    }
    private let stageProbe = UIView()
#if DEBUG
    private let gestureProbe = UIView()
#endif
    private var headTapCount = 0
    private var actionCount = 0
    private var gestureCount = 0
    func setFraming(_ value: CharacterFraming) {
        framing = value.normalized
#if DEBUG
        // The QA probe owns its value while testing. A no-op save no longer sends
        // camera commands, so there may be no subsequent event to restore its JSON.
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return }
#endif
        customizationButton.accessibilityValue = framing.summary
    }
    func setRuntimeFraming(_ event: [String:Any]) {
#if DEBUG
        if event["name"] as? String == "headTapped" { headTapCount += 1 }
        if event["name"] as? String == "actionStarted" { actionCount += 1 }
        if event["name"] as? String == "framingGestureEnded" { gestureCount += 1 }
        var values = event; values["headTapCount"] = headTapCount; values["actionCount"] = actionCount; values["gestureCount"] = gestureCount
        values["modelControlsLocked"] = modelControlsLocked
        if let window = view.window {
            let safe = view.convert(window.safeAreaLayoutGuide.layoutFrame,from:window)
            values["nativeWindowGeometry"] = ["width":view.bounds.width,"height":view.bounds.height,
                "safeTop":safe.minY,"safeLeft":safe.minX,"safeRight":view.bounds.width-safe.maxX]
        }
        values["soundscape"] = chatSession?.soundscape.accessibilityEvidence
        if let x = event["headX"] as? Double, let y = event["headY"] as? Double, let window = view.window {
            let point = CGPoint(x:x*window.bounds.width,y:y*window.bounds.height)
            values["nativeHeadHit"] = window.hitTest(point,with:nil).map { String(describing:type(of:$0)) } ?? "none"
            values["runtimeIsKeyWindow"] = window.isKeyWindow
            values["runtimeTouchEnabled"] = window.isUserInteractionEnabled
        }
        values["nativeHoldAvailable"] = touchSurface.inputAvailable && view.isUserInteractionEnabled && gestureInputAvailable
        values["nativeTouchSequences"] = touchSurface.touchSequences
        values["nativeRecognizedGestures"] = touchSurface.recognizedGestures
        values["chatEditing"] = chatEditing
        values["chatComposerFrame"] = String(describing:chatComposerFrame)
        values["keyboardPresent"] = keyboardFrame != nil
        values["outsideKeyboardTouches"] = outsideKeyboardTouches
        values["inspectionChatLocked"] = chatSession?.inspectionActive ?? false
        values["viewEditorOpen"] = viewEditor.isOpen
        values["positionAnimationSamples"] = positionAnimationSamples
        values["viewPoseSaved"] = chatSession?.record.lastViewPose.payload
        if let host=viewEditorHost {
            values["viewEditorFrame"] = ["x":host.view.frame.minX,"y":host.view.frame.minY,"width":host.view.frame.width,"height":host.view.frame.height]
        }
        values["inspectionFeedbackActive"] = false
        values["inspectionFeedbackShowCount"] = inspectionFeedbackShowCount
        values["inspectionHapticCount"] = inspectionHapticCount
        values["inspectionFeedbackAnimated"] = false
        values["avatarVoicePlaying"] = chatSession?.speech.isSpeaking ?? false
        values["greetingScene"] = chatSession?.record.messages.last(where:{ $0.proactiveScene != nil })?.proactiveScene
        values["greetingCount"] = chatSession?.record.greeting?.count ?? 0
        values["confirmedPerformanceCounts"] = characterPerformance?.confirmedCounts ?? [:]
        values["shakeReactions"] = chatSession?.shakeReactions ?? 0
        values["guestTurns"] = chatSession?.store.guestTurns ?? 0
        values["userMessageCount"] = chatSession?.record.messages.filter { $0.role == "user" }.count ?? 0
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           let data = try? JSONSerialization.data(withJSONObject:values,options:.sortedKeys) {
            customizationButton.accessibilityValue = String(data:data,encoding:.utf8)
        }
#endif
    }
    func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
        editorDismissing = true
        animateLayout()
        presentationController.presentedViewController.transitionCoordinator?.notifyWhenInteractionChanges { [weak self] context in
            guard let self, context.isCancelled else { return }
            self.editorDismissing = false; self.animateLayout()
        }
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        studioOriginal = nil
        framingOriginal = nil; editorDismissing = false
        view.isUserInteractionEnabled = true; editorDidClose()
        syncGestureInput()
    }
    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheetPresentationController: UISheetPresentationController) {
        animateLayout()
    }
    var onResize: (() -> Void)?
    var onAction: ((String) -> Void)?
    var onFrameRate: ((Int) -> Void)?
    var onConversationViewport: ((CGRect,CGRect) -> Void)?
    private var chatHost: UIHostingController<CompanionChatView>?
    private var chatSession: CompanionSession?
    private var explorerViews: [UIView] = []
    private var previousViewport = CGRect.zero
    private var previousCharacterSafeFrame = CGRect.zero
    private var outsideKeyboardTouches = 0
    private var chatEditing = false
    private var chatComposerFrame = CGRect.zero
    private lazy var dismissChatKeyboardTap = UITapGestureRecognizer(target:self,action:#selector(dismissChatKeyboardFromBlankTap(_:)))
    private var keyboardFrame: CGRect?
    func setCompanionTitle(_ title: String) {
        if chatSession != nil {
            titleLabel.text = title; subtitle.text = nil
            customizationButton.accessibilityLabel = title + "，查看角色资料"
            identityContentWidth?.constant = CharacterConversationIdentity.fittingWidth(for:title)
        }
    }
    func setCompanion(_ session: CompanionSession?) {
        loadViewIfNeeded()
        if let session, chatSession === session { return }
        cancelInspection()
        if let host = chatHost { host.willMove(toParent:nil); host.view.removeFromSuperview(); host.removeFromParent() }
        if let host = identityHost { host.willMove(toParent:nil); host.view.removeFromSuperview(); host.removeFromParent() }
        identityHost = nil
        backButton.isHidden = session != nil
        chatHost = nil; chatSession = session; chatEditing = false; chatComposerFrame = .zero
        (view as? TouchThroughView)?.messageRegions = [:]
        // Only the visible identity occupies the upper-left touch area. Keeping
        // the old wide centered hit target here would swallow model gestures.
        NSLayoutConstraint.deactivate([identityCentered,identityExplorerWidth,identityLeading,identityContentWidth].compactMap { $0 })
        NSLayoutConstraint.activate((session == nil ? [identityCentered,identityExplorerWidth] :
            [identityLeading,identityContentWidth]).compactMap { $0 })
        setModelControlsLocked(true);updatePositionButton()
        for item in explorerViews { item.isHidden = session != nil }
        performance.isHidden = session != nil; actionsScroll.isHidden = session != nil
        previousViewport = .zero
        if let session {
            let host = UIHostingController(rootView:CompanionChatView(session:session,onPerformance:{ [weak self] in self?.openConversationPerformance() },onSoundSettings:{ [weak self] in self?.openConversationSound() },onEditingChanged:{ [weak self] focused in
                guard let self else { return }; self.chatEditing = focused
                if !focused { self.view.endEditing(true) }; self.animateLayout()
            },onDisplayChanged:{ [weak self] in self?.animateLayout() },onMessageFrameChanged:{ [weak self] frame in
                (self?.view as? TouchThroughView)?.messageFrame = frame
            },onComposerFrameChanged:{ [weak self] frame in
                self?.chatComposerFrame = frame
            },onHitRegionsChanged:{ [weak self,weak session] regions in
                guard let self,let session,self.chatSession === session else {return}
                (self.view as? TouchThroughView)?.messageRegions = regions
            }))
            host.view.backgroundColor = .clear; host.view.isOpaque = false
            host.view.accessibilityIdentifier = "companionPanel"
            host.safeAreaRegions = []
            addChild(host); view.addSubview(host.view); host.didMove(toParent:self); chatHost = host
            (view as? TouchThroughView)?.chatView = host.view
            (view as? TouchThroughView)?.characterTouchView = touchSurface
            if let portraits {
                let identity = UIHostingController(rootView:CharacterConversationIdentity(session:session,portraits:portraits))
                identity.view.backgroundColor = .clear; identity.view.isOpaque = false
                identity.view.isUserInteractionEnabled = false; identity.view.accessibilityElementsHidden = true
                identity.safeAreaRegions = []
                addChild(identity); view.addSubview(identity.view); identity.didMove(toParent:self)
                identity.view.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    identity.view.leadingAnchor.constraint(equalTo:customizationButton.leadingAnchor),
                    identity.view.trailingAnchor.constraint(equalTo:customizationButton.trailingAnchor),
                    identity.view.topAnchor.constraint(equalTo:customizationButton.topAnchor),
                    identity.view.bottomAnchor.constraint(equalTo:customizationButton.bottomAnchor)])
                identityHost = identity
            }
            setCompanionTitle(session.record.profile.name)
        } else { titleLabel.text = model.name; setAction("") }
        view.setNeedsLayout()
    }
    private let performance = UIButton(type:.system)
    private var performanceTop:NSLayoutConstraint?
    private var previousSize: CGSize = .zero
    private let subtitle = UILabel()
    private let titleLabel = UILabel()
    private let actionStrip = UIStackView()
    private let actionsScroll = UIScrollView()
    private var model = ModelDescriptor.defaultCharacter
    private var actionButtons: [String:UIButton] = [:]

    func setModel(_ model: ModelDescriptor) {
        let changed = self.model.id != model.id
        self.model = model
        if changed { cancelInspection(); setModelControlsLocked(true) }
        guard isViewLoaded else { return }
        guard changed || actionButtons.isEmpty else { return }
        titleLabel.text = model.name
        customizationButton.accessibilityLabel = model.name + "，查看角色资料"
        for item in actionStrip.arrangedSubviews { actionStrip.removeArrangedSubview(item); item.removeFromSuperview() }
        actionButtons.removeAll()
        for action in model.actions {
            let button = UIButton(type:.system)
            var config = UIButton.Configuration.filled()
            config.title = action.name; config.image = UIImage(systemName:action.symbol)
            config.imagePlacement = .top; config.imagePadding = 6; config.cornerStyle = .large
            config.baseBackgroundColor = UIColor(Theme.surface).withAlphaComponent(0.95)
            config.baseForegroundColor = UIColor(Theme.accent)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming; outgoing.font = .preferredFont(forTextStyle:.subheadline); return outgoing
            }
            button.configuration = config
            button.accessibilityIdentifier = "action" + action.id + "Button"
            button.accessibilityLabel = "让" + model.name + action.name
            button.addAction(UIAction { [weak self] _ in self?.onAction?(action.id) },for:.touchUpInside)
            button.widthAnchor.constraint(equalToConstant:100).isActive = true
            actionStrip.addArrangedSubview(button); actionButtons[action.id] = button
        }
        setAction("")
        actionsScroll.setContentOffset(.zero,animated:false)
        performance.configuration?.title = "帧率测量中"
        performance.configuration?.subtitle = nil
    }

    func setAction(_ action: String) {
        let name = action == "No" ? "摇头" : model.actions.first(where: { $0.id == action })?.name
        if let chatSession { chatSession.currentAction = action; return }
        subtitle.text = name.map { "正在" + $0 } ?? model.originalName.uppercased()
        for (name,button) in actionButtons {
            button.isSelected = name == action
            button.accessibilityValue = name == action ? "正在播放" : "轻点播放"
            button.configuration?.baseBackgroundColor = name == action
                ? UIColor(Theme.jade) : UIColor(Theme.surface).withAlphaComponent(0.95)
        }
    }
    func setPerformance(fps:Double,target:Int,screenMaximum:Int) {
        performance.configuration?.title = String(format:"%.0f FPS  ·  目标 %d",fps,target)
        performance.configuration?.subtitle = "当前屏幕上限 \(screenMaximum) Hz"
        performance.accessibilityValue = String(format:"实测渲染循环 %.1f 帧，目标 %d 帧，屏幕上限 %d 赫兹",fps,target,screenMaximum)
    }

    override func loadView() { view = TouchThroughView(); view.backgroundColor = .clear }
    override func viewDidLoad() {
        super.viewDidLoad()
        positionButton.addTarget(self,action:#selector(togglePositionEditor),for:.touchUpInside)
        positionButton.accessibilityHint="打开后单指旋转，双指缩放和移动；自动记住最后状态"
        view.addSubview(positionButton)
        (view as? TouchThroughView)?.inspectionEntry=positionButton
        var resetConfig=UIButton.Configuration.plain()
        resetConfig.title="恢复默认";resetConfig.image=UIImage(systemName:"arrow.counterclockwise",withConfiguration:UIImage.SymbolConfiguration(pointSize:11))
        resetConfig.imagePadding=4;resetConfig.baseForegroundColor=UIColor(Theme.ink).withAlphaComponent(0.82)
        resetConfig.titleTextAttributesTransformer=UIConfigurationTextAttributesTransformer { attributes in
            var result=attributes;result.font=UIFont.systemFont(ofSize:11,weight:.medium);return result
        }
        resetPositionButton.configuration=resetConfig;resetPositionButton.accessibilityIdentifier="resetCharacterView"
        resetPositionButton.addTarget(self,action:#selector(resetPosition),for:.touchUpInside)
        touchSurface.onGesture = { [weak self] value in self?.onNativeGesture?(value) }
        touchSurface.frame=view.bounds;touchSurface.autoresizingMask=[.flexibleWidth,.flexibleHeight]
        view.insertSubview(touchSurface,at:0)
        touchSurface.observePreview(in:view,origin:{ [weak self] point,target in
            (self?.view as? TouchThroughView)?.previewOrigin(at:point,target:target)
        },conversationScroll:{ [weak self] scroll in
            guard let chat=self?.chatHost?.view,!(scroll is UITextView) else {return false}
            return scroll.isDescendant(of:chat)
        })
        touchSurface.observeEditing(in:view) { [weak self] point,target in
            guard let self,self.viewEditor.isOpen,self.gestureInputAvailable,self.view.isUserInteractionEnabled else {return false}
            for excluded in [self.resetPositionButton,self.positionButton,self.dockHost?.view].compactMap({$0}) where !excluded.isHidden && excluded.alpha>0.01 {
                if excluded.bounds.contains(excluded.convert(point,from:self.view)) {return false}
            }
            return true
        }
        // Observe a background tap alongside Unity's head interaction. This
        // recognizer never cancels or delays the touch delivered to its target.
        dismissChatKeyboardTap.cancelsTouchesInView = false
        dismissChatKeyboardTap.delaysTouchesBegan = false
        dismissChatKeyboardTap.delaysTouchesEnded = false
        dismissChatKeyboardTap.delegate = self
        view.addGestureRecognizer(dismissChatKeyboardTap)
        overrideUserInterfaceStyle = .dark
        let dock = UIHostingController(rootView:AppDock(selection:.home) { [weak self] tab in
            self?.view.endEditing(true); self?.onTabSelected?(tab)
        })
        dock.view.backgroundColor = .clear; dock.safeAreaRegions = []
        addChild(dock); view.addSubview(dock.view); dock.didMove(toParent:self); dockHost = dock
        NotificationCenter.default.addObserver(self,selector:#selector(keyboardChanged),name:UIResponder.keyboardWillChangeFrameNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(keyboardChanged),name:UIResponder.keyboardDidHideNotification,object:nil)
        stageProbe.backgroundColor = .clear; stageProbe.isUserInteractionEnabled = false
        stageProbe.isAccessibilityElement = true; stageProbe.accessibilityIdentifier = "characterStage"
        stageProbe.accessibilityLabel = "角色互动区域，单指小范围旋转，松手恢复；右上角修改位置"
        stageProbe.accessibilityTraits = .image; view.addSubview(stageProbe)
        updatePositionButton()
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            // Expose the genuinely uncovered touch region so UI tests can place both pinch fingers
            // on the 3D view. This adds no recognizer or alternative runtime input path.
            gestureProbe.isUserInteractionEnabled = false; gestureProbe.isAccessibilityElement = true
            gestureProbe.accessibilityIdentifier = "characterGestureRegion"; gestureProbe.accessibilityTraits = .image
            gestureProbe.accessibilityLabel = "当前未被聊天遮挡的模型区域"
            view.addSubview(gestureProbe)
        }
#endif
        let ink = UIColor(Theme.ink)
        let back = backButton
        func quietControl(_ symbol:String) -> UIButton.Configuration {
            var config = UIButton.Configuration.plain()
            config.image = UIImage(systemName:symbol,withConfiguration:UIImage.SymbolConfiguration(pointSize:16,weight:.regular))
            config.baseForegroundColor = ink.withAlphaComponent(0.86)
            config.contentInsets = .zero
            config.background.backgroundColor = UIColor(Theme.background).withAlphaComponent(UIAccessibility.isReduceTransparencyEnabled ? 1 : 0.14)
            config.background.backgroundInsets = NSDirectionalEdgeInsets(top:5,leading:5,bottom:5,trailing:5)
            config.background.cornerRadius = 17
            config.background.strokeColor = UIColor.white.withAlphaComponent(0.14)
            config.background.strokeWidth = 0.5
            return config
        }
        back.configuration = quietControl("chevron.left")
        back.accessibilityLabel = "返回发现"; back.accessibilityIdentifier = "viewerBackButton"
        back.addAction(UIAction { [weak self] _ in self?.onBack?() },for:.touchUpInside)
        setModelControlsLocked(modelControlsLocked)

        let reset = customizationButton
        // The SwiftUI avatar/name capsule supplies the visuals; this transparent
        // native button keeps a generous tap target without intercepting model gestures below.
        reset.configuration = .plain()
        reset.configuration?.contentInsets = .zero
        reset.accessibilityHint = "查看介绍，或从资料卡进入定制"
        reset.accessibilityIdentifier = "customizationButton"
        reset.accessibilityLabel = "查看角色资料"
        reset.addAction(UIAction { [weak self] _ in self?.openCustomization() },for:.touchUpInside)
        let title = titleLabel; title.text = model.name; title.textColor = ink
        title.font = UIFontMetrics(forTextStyle:.subheadline).scaledFont(for:.systemFont(ofSize:16,weight:.medium)); title.adjustsFontForContentSizeCategory = true
        title.textAlignment = .center
        title.isAccessibilityElement = false; subtitle.isAccessibilityElement = false
        // Local text shadows retain legibility on bright rooms without veiling the scene.
        for label in [title,subtitle] {
            label.layer.shadowColor = UIColor.black.cgColor; label.layer.shadowOpacity = 0.6
            label.layer.shadowRadius = 3; label.layer.shadowOffset = CGSize(width:0,height:1)
        }
        title.adjustsFontSizeToFitWidth = true; title.minimumScaleFactor = 0.8
        subtitle.text = "LUMA · STUDIO ROBOT"; subtitle.textAlignment = .center
        subtitle.font = .monospacedSystemFont(ofSize:9,weight:.medium); subtitle.textColor = ink.withAlphaComponent(0.48)
        let hint = gestureHint
        hint.font = .preferredFont(forTextStyle:.caption1); hint.textColor = ink.withAlphaComponent(0.66)
        hint.adjustsFontForContentSizeCategory = true; hint.textAlignment = .center
        let hintBackground = UIVisualEffectView(effect:UIBlurEffect(style:.systemUltraThinMaterialDark))
        hintBackground.layer.cornerRadius = 23; hintBackground.clipsToBounds = true
        explorerViews = [hint,hintBackground]
        let actions = actionsScroll; actions.showsHorizontalScrollIndicator = false
        actions.accessibilityIdentifier = "characterActionsScroll"
        actions.alwaysBounceHorizontal = false
        actionStrip.axis = .horizontal; actionStrip.spacing = 10
        actions.addSubview(actionStrip); actionStrip.translatesAutoresizingMaskIntoConstraints = false
        for item in [back,reset,title,subtitle,hintBackground,hint,actions] {
            view.addSubview(item); item.translatesAutoresizingMaskIntoConstraints = false
        }
        let safe = view.safeAreaLayoutGuide
        let titleArea = UILayoutGuide(); view.addLayoutGuide(titleArea)
        var fpsConfig = UIButton.Configuration.tinted()
        fpsConfig.title = "目标 120 FPS · 测量中"; fpsConfig.cornerStyle = .capsule
        fpsConfig.baseForegroundColor = ink; fpsConfig.baseBackgroundColor = UIColor(Theme.surface)
        fpsConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming; outgoing.font = .monospacedDigitSystemFont(ofSize:11,weight:.medium); return outgoing
        }
        fpsConfig.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming; outgoing.font = .systemFont(ofSize:9); return outgoing
        }
        performance.configuration = fpsConfig
        performance.accessibilityIdentifier = "frameRateButton"
        performance.accessibilityLabel = "帧率设置与实测"
        performance.menu = UIMenu(title:"渲染目标（实际帧率由设备与系统决定）",children:[
            UIAction(title:"120 FPS · 高刷新率") { [weak self] _ in self?.onFrameRate?(120) },
            UIAction(title:"60 FPS · 标准") { [weak self] _ in self?.onFrameRate?(60) }])
        performance.showsMenuAsPrimaryAction = true
        view.addSubview(performance); performance.translatesAutoresizingMaskIntoConstraints = false
        performanceTop = performance.topAnchor.constraint(equalTo:back.bottomAnchor,constant:18)
        identityCentered = reset.centerXAnchor.constraint(equalTo:safe.centerXAnchor)
        identityExplorerWidth = reset.widthAnchor.constraint(equalTo:titleArea.widthAnchor)
        identityLeading = reset.leadingAnchor.constraint(equalTo:safe.leadingAnchor,constant:16)
        identityContentWidth = reset.widthAnchor.constraint(equalToConstant:CharacterConversationIdentity.fittingWidth(for:model.name))
        identityContentWidth?.priority = .defaultHigh
        NSLayoutConstraint.activate([
            performanceTop!,
            performance.centerXAnchor.constraint(equalTo:view.centerXAnchor),performance.heightAnchor.constraint(equalToConstant:44),
            back.leadingAnchor.constraint(equalTo:safe.leadingAnchor,constant:20),
            back.topAnchor.constraint(equalTo:safe.topAnchor,constant:8),
            back.widthAnchor.constraint(equalToConstant:44),back.heightAnchor.constraint(equalToConstant:44),
            identityCentered!,
            reset.centerYAnchor.constraint(equalTo:back.centerYAnchor),reset.heightAnchor.constraint(equalToConstant:48),
            identityExplorerWidth!,
            reset.trailingAnchor.constraint(lessThanOrEqualTo:safe.trailingAnchor,constant:-16),
            titleArea.leadingAnchor.constraint(equalTo:safe.leadingAnchor,constant:76),
            titleArea.trailingAnchor.constraint(equalTo:safe.trailingAnchor,constant:-76),
            titleArea.topAnchor.constraint(equalTo:back.topAnchor),titleArea.heightAnchor.constraint(equalToConstant:46),
            title.centerXAnchor.constraint(equalTo:titleArea.centerXAnchor),title.topAnchor.constraint(equalTo:back.topAnchor,constant:3),
            title.widthAnchor.constraint(lessThanOrEqualTo:titleArea.widthAnchor),
            subtitle.centerXAnchor.constraint(equalTo:titleArea.centerXAnchor),subtitle.topAnchor.constraint(equalTo:title.bottomAnchor,constant:5),
            subtitle.widthAnchor.constraint(lessThanOrEqualTo:titleArea.widthAnchor),
            actions.centerXAnchor.constraint(equalTo:view.centerXAnchor),actions.bottomAnchor.constraint(equalTo:safe.bottomAnchor,constant:-20),
            actions.widthAnchor.constraint(equalTo:safe.widthAnchor,constant:-40),actions.heightAnchor.constraint(equalToConstant:78),
            actionStrip.leadingAnchor.constraint(equalTo:actions.contentLayoutGuide.leadingAnchor),
            actionStrip.trailingAnchor.constraint(equalTo:actions.contentLayoutGuide.trailingAnchor),
            actionStrip.topAnchor.constraint(equalTo:actions.contentLayoutGuide.topAnchor),
            actionStrip.bottomAnchor.constraint(equalTo:actions.contentLayoutGuide.bottomAnchor),
            actionStrip.heightAnchor.constraint(equalTo:actions.frameLayoutGuide.heightAnchor),
            hint.centerXAnchor.constraint(equalTo:view.centerXAnchor),hint.bottomAnchor.constraint(equalTo:actions.topAnchor,constant:-24),
            hintBackground.centerXAnchor.constraint(equalTo:hint.centerXAnchor),hintBackground.centerYAnchor.constraint(equalTo:hint.centerYAnchor),
            hintBackground.widthAnchor.constraint(equalTo:hint.widthAnchor,constant:40),hintBackground.heightAnchor.constraint(equalTo:hint.heightAnchor,constant:26)])
        setModel(model)
    }
    func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldReceive touch:UITouch) -> Bool {
        guard gestureRecognizer === dismissChatKeyboardTap else { return true }
        guard chatSession != nil, (chatEditing || keyboardFrame != nil), gestureInputAvailable, presentedViewController == nil else { return false }
        outsideKeyboardTouches += 1
        if let host = chatHost {
            let point = touch.location(in:host.view)
            // Keep text selection, caret placement, voice and send inside the
            // composer entirely on their original input paths.
            if chatComposerFrame != .zero && chatComposerFrame.insetBy(dx:-4,dy:-4).contains(point) { return false }
            if chatComposerFrame == .zero && host.view.bounds.contains(point) && point.y > host.view.bounds.height-62 { return false }
        }
        // Dismiss on the outside touch itself: the model's hold recognizer may
        // win/cancel a tap, but must never keep the keyboard open. Focus change
        // is deferred beyond hit testing and never clears the bound draft.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.chatSession?.dismissKeyboardRequest += 1; self.view.endEditing(true)
        }
        return true
    }
    func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldRecognizeSimultaneouslyWith other:UIGestureRecognizer) -> Bool {
        gestureRecognizer === dismissChatKeyboardTap || other === dismissChatKeyboardTap
    }
    @objc private func dismissChatKeyboardFromBlankTap(_ recognizer:UITapGestureRecognizer) {
        guard recognizer.state == .ended, chatEditing else { return }
        chatSession?.dismissKeyboardRequest += 1
        view.endEditing(true)
    }
    @objc private func keyboardChanged(_ notification: Notification) {
        if notification.name == UIResponder.keyboardDidHideNotification { keyboardFrame = nil }
        else if let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
                let window = view.window {
            let inWindow = window.convert(frame,from:window.screen.coordinateSpace)
            let local = view.convert(inWindow,from:window)
            keyboardFrame = local.minY < view.bounds.height-1 ? frame : nil
        }
        view.setNeedsLayout()
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? motionDuration
        let curve = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 0
        UIView.animate(withDuration:max(0.01,duration),delay:0,
            options:[UIView.AnimationOptions(rawValue:curve << 16),.beginFromCurrentState,.allowUserInteraction]) {
            self.view.layoutIfNeeded()
        }
    }
    override func viewWillTransition(to size:CGSize,with coordinator:UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to:size,with:coordinator)
        coordinator.animate(alongsideTransition:{ _ in self.view.setNeedsLayout(); self.view.layoutIfNeeded() })
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if previousSize != view.bounds.size { previousSize = view.bounds.size; onResize?() }
        let size = view.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let editingPanel = (studioOriginal != nil || framingOriginal != nil) && !editorDismissing
        var viewport = CGRect(x:0,y:0,width:1,height:1)
        let duration = UIView.inheritedAnimationDuration > 0 ? UIView.inheritedAnimationDuration : motionDuration
        var chatRect: CGRect?
        let safe = view.safeAreaInsets
        // Match the capsule's actual centre, including its safe-area constraints.
        positionButton.frame=CGRect(x:size.width-safe.right-54,y:customizationButton.frame.midY-22,width:44,height:44)
        view.bringSubviewToFront(positionButton)
        var insets = AdaptiveViewerLayout.Insets(top:safe.top,left:safe.left,bottom:safe.bottom,right:safe.right)
        // Composition belongs to the character, not to the current sheet, keyboard
        // or chat height. The window safe area also handles notch/island rotation.
        var stageInsets = insets
        if chatHost != nil { stageInsets.bottom += 62 }
        let side = AdaptiveViewerLayout.sideBySide(size)
        let compactExplorer = side && chatHost == nil
        performanceTop?.constant = compactExplorer ? -46 : 18
        titleLabel.isHidden = compactExplorer || chatSession != nil
        subtitle.isHidden = side || chatSession != nil
        for item in explorerViews { item.isHidden = chatHost != nil || side }
        var keyboard: CGRect?
        if let keyboardFrame, let window = view.window {
            let local = view.convert(window.convert(keyboardFrame,from:window.screen.coordinateSpace),from:window)
            let intersection = local.intersection(view.bounds)
            if !intersection.isNull && intersection.height > 35 { keyboard = intersection }
        }
        let dockVisible = chatHost != nil && keyboard == nil && !editingPanel
        if let dock = dockHost {
            dock.view.frame = CGRect(x:0,y:size.height-safe.bottom-62,width:size.width,height:62+safe.bottom)
            if dockBottomInset != safe.bottom {
                dockBottomInset = safe.bottom
                dock.rootView = AppDock(selection:.home,bottomInset:safe.bottom) { [weak self] tab in
                    self?.view.endEditing(true); self?.onTabSelected?(tab)
                }
            }
            dock.view.alpha = dockVisible ? 1 : 0
            dock.view.isUserInteractionEnabled = dockVisible
            dock.view.accessibilityElementsHidden = !dockVisible
            view.bringSubviewToFront(dock.view)
        }
        if dockVisible { insets.bottom += 62 }
        if let host = chatHost {
            let layout = AdaptiveViewerLayout.conversation(size,inset:insets,keyboard:keyboard,heightFraction:CGFloat(chatSession?.store.chatDisplay.normalized.heightFraction ?? 0.6))
            let frame = layout.chat
            let stableStage = AdaptiveViewerLayout.conversation(size,inset:stageInsets,keyboard:nil).stage
            viewport = AdaptiveViewerLayout.normalized(stableStage,in:size)
            let obscured = editingPanel || viewEditor.isOpen
            let alpha: CGFloat = obscured ? 0 : 1
            if host.view.frame != frame || host.view.alpha != alpha {
                let changes = { host.view.frame = frame; host.view.alpha = alpha }
                if host.view.frame == .zero || UIView.inheritedAnimationDuration > 0 { changes() }
                else { UIView.animate(withDuration:duration,delay:0,options:[.beginFromCurrentState,.allowUserInteraction,.curveEaseInOut],animations:changes) }
            }
            host.view.isUserInteractionEnabled = !obscured
            host.view.accessibilityElementsHidden = obscured
            if !obscured { chatRect = frame }
        } else {
            let top = view.safeAreaInsets.top + (side ? 68 : 130)
            let bottom = size.height - view.safeAreaInsets.bottom - (side ? 108 : 156)
            viewport = CGRect(x:0,y:(size.height-bottom)/size.height,width:1,height:max(70,bottom-top)/size.height)
        }
        if let host=viewEditorHost,let chat=chatHost?.view.frame {
            let width=min(CGFloat(268),chat.width-32)
            let height:CGFloat=90
            let bottom=size.height-safe.bottom-70
            host.view.bounds=CGRect(x:0,y:0,width:width,height:height)
            host.view.center=CGPoint(x:chat.midX,y:max(safe.top+height/2+8,min(bottom-height/2,chat.midY)))
            resetPositionButton.frame=CGRect(x:width-102,y:1,width:94,height:44)
            view.bringSubviewToFront(host.view)
            view.bringSubviewToFront(positionButton)
        }
        (view as? TouchThroughView)?.inspectionDock=dockHost?.view
        let stage = CGRect(x:viewport.minX*size.width,y:(1-viewport.maxY)*size.height,width:viewport.width*size.width,height:viewport.height*size.height)
        (view as? TouchThroughView)?.updateScrims(chat:chatRect ?? (viewEditor.isOpen ? chatHost?.view.frame : nil),stage:stage,editing:editingPanel || viewEditor.isOpen,duration:duration)
        stageProbe.frame = stage
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            stageProbe.accessibilityValue = side ? "sideBySide" : "portrait"
        }
#endif
#if DEBUG
        let touchTop = max(stage.minY,view.safeAreaInsets.top + 76)
        let touchBottom = min(stage.maxY,editingPanel || side ? stage.maxY : (chatHost?.view.frame.minY ?? stage.maxY))
        gestureProbe.frame = CGRect(x:stage.minX+12,y:touchTop,width:max(0,stage.width-24),height:max(0,touchBottom-touchTop-12))
#endif
        // Use the window's system safe area rather than any child-controller inset
        // that a presentation/container may add. Coordinates remain local to Unity's
        // full-window surface; there is no device-name or screen-scale lookup.
        let windowSafe = view.window.map { view.convert($0.safeAreaLayoutGuide.layoutFrame,from:$0) }
        let stableInsets = windowSafe.map { frame in AdaptiveViewerLayout.Insets(
            top:max(0,frame.minY),left:max(0,frame.minX),
            bottom:max(0,size.height-frame.maxY),right:max(0,size.width-frame.maxX)) } ?? stageInsets
        let characterSafeFrame = AdaptiveViewerLayout.characterSafeFrame(size,inset:stableInsets)
        if viewport != previousViewport || characterSafeFrame != previousCharacterSafeFrame {
            previousViewport = viewport; previousCharacterSafeFrame = characterSafeFrame
            onConversationViewport?(viewport,characterSafeFrame)
        }
    }
}
