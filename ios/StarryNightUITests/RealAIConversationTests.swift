import XCTest

final class RealAIConversationTests: XCTestCase {
    override func tearDown() async throws {
        // Also cancel paid idle timers after assertions fail. XCTest's override
        // is nonisolated; explicitly hop to the UI actor for app interaction.
        await MainActor.run { XCUIApplication().terminate() }
        try await super.tearDown()
    }
    @MainActor func testAudioThreadPlaybackAndCachedVocalBeat() {
        let app = XCUIApplication(); app.launchArguments = ["--speech-playback-check","--ui-testing","--conversation-continuity-fixture","--automatic-audio-recovery-check"]
        app.launch()
        let result = app.staticTexts["speechPlaybackResult"]
        XCTAssertTrue(result.waitForExistence(timeout:10))
        let completed = NSPredicate { _,_ in result.label.hasPrefix("PASS:") || result.label.hasPrefix("FAIL:") }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:completed,object:nil)],timeout:45),.completed)
        XCTAssertTrue(result.label.hasPrefix("PASS:"),result.label)
        let evidence = XCTAttachment(string:result.label); evidence.name = "audio-thread-playback"; evidence.lifetime = .keepAlways; add(evidence)
        app.terminate()
    }
    @MainActor func testGreetingPolicyContract() {
        let app = XCUIApplication(); app.launchArguments = ["--greeting-core-check"]
        app.launch()
        let result = app.staticTexts["greetingCoreResult"]
        XCTAssertTrue(result.waitForExistence(timeout:25)); XCTAssertTrue(result.label.hasPrefix("PASS:"),result.label)
        let evidence = XCTAttachment(string:result.label); evidence.name = "greeting-policy-result"; evidence.lifetime = .keepAlways; add(evidence)
        app.terminate()
    }
    @MainActor func testPaidConversationVoiceAndRoleSwitch() throws {
        guard ProcessInfo.processInfo.environment["STARRY_LIVE_AI_TESTS"] == "1" else {
            throw XCTSkip("Paid AI is opt-in: STARRY_LIVE_AI_TESTS=1. Ordinary test runs are free.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--auth-testing","--live-ai","--layout-motion-review"]
        app.launch()
        dismissLocalNetworkAlert()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:65))
        waitForRealVoice(app)
        capture("real-ai-kipfel-greeting",app)
        let beforePerformance=app.characterRuntime["confirmedPerformanceCounts"] as? [String:Int] ?? [:]
        let field = app.textViews["chatInput"]
        XCTAssertTrue(field.waitForExistence(timeout:10));field.tap();field.typeText("请笑一笑，再动动耳朵和我打招呼，用一句话就好。")
        app.buttons["sendMessageButton"].tap()
        let reply = app.staticTexts.matching(identifier:"assistantMessage")
        let ready = NSPredicate { _,_ in reply.count >= 2 }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:ready,object:nil)],timeout:70),.completed)
        app.waitForCharacter({ state in
            let counts=state["confirmedPerformanceCounts"] as? [String:Int] ?? [:]
            let changed=counts.keys.filter { counts[$0,default:0]>beforePerformance[$0,default:0] }
            return changed.contains { ["kipfel-catear-pyoko-loop","kipfel-catear-pyoko-left","kipfel-catear-pyoko-right","kipfel-catear-up"].contains($0) } && changed.contains { $0.hasPrefix("kipfel-facial-") }
        },timeout:45)
        capture("real-ai-original-expression-and-ears",app)
        waitForRealVoice(app)
        app.waitForCharacter({ state in
            guard let selected=(state["characterPlatform"] as? [String:Any])?["performanceSelections"] as? [String] else {return false}
            return !selected.contains { $0.hasPrefix("kipfel-catear-") || $0.hasPrefix("kipfel-facial-") }
        },timeout:12)
        capture("real-ai-user-turn",app)
        app.buttons["tab-messages"].tap(); app.buttons["tab-home"].tap()
        XCTAssertEqual(app.characterRuntime["greetingCount"] as? Int,1,"Retained tab return must not issue another paid greeting")
        app.buttons["tab-discover"].tap()
        let second = app.buttons["discover-open-anime-mamehinata"]
        XCTAssertTrue(second.waitForExistence(timeout:15));second.tap()
        XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:10));app.buttons["profileChatButton"].tap()
        waitForRealVoice(app)
        capture("real-ai-mamehinata-greeting",app)
        XCTAssertEqual(app.characterRuntime["modelId"] as? String,"anime-mamehinata")
        app.openConversationSettings("sound")
        XCTAssertTrue(app.sliders["speechSoundVolume"].waitForExistence(timeout:8))
        app.sliders["speechSoundVolume"].adjust(toNormalizedSliderPosition:0)
        app.buttons["closeCharacterViewEditor"].tap()
        let beforeMutedPerformance=app.characterRuntime["confirmedPerformanceCounts"] as? [String:Int] ?? [:]
        field.tap();field.typeText("开心地笑一笑，摇摇尾巴吧。只说一句话就好。")
        app.buttons["sendMessageButton"].tap()
        app.waitForCharacter({ state in
            let counts=state["confirmedPerformanceCounts"] as? [String:Int] ?? [:]
            let changed=counts.keys.filter { counts[$0,default:0]>beforeMutedPerformance[$0,default:0] }
            return changed.contains { ["dogtail-upwag","dogtail-updown"].contains($0) } && changed.contains { $0.hasPrefix("f-") }
        },timeout:70)
        capture("real-ai-muted-original-expression-and-tail",app)
        app.openConversationSettings("sound")
        app.sliders["speechSoundVolume"].adjust(toNormalizedSliderPosition:0.45)
        app.buttons["closeCharacterViewEditor"].tap()
        let previous=app.staticTexts.matching(identifier:"assistantMessage").allElementsBoundByIndex.map(\.label)
        let previousGreetings=app.characterRuntime["greetingCount"] as? Int ?? 0
        app.terminate()
        app.launchArguments.append("--keep-companion-data");app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.waitForCharacter({ ($0["greetingCount"] as? Int ?? 0)>previousGreetings },timeout:70)
        waitForRealVoice(app)
        let fresh=app.staticTexts.matching(identifier:"assistantMessage").allElementsBoundByIndex.last?.label ?? ""
        XCTAssertFalse(fresh.isEmpty)
        XCTAssertFalse(previous.contains(fresh),"Reentry must generate a fresh contextual greeting")
        capture("real-ai-fresh-contextual-reentry",app)
        app.terminate() // No unattended paid idle generation after the test.
    }
    @MainActor func testMissingAIShowsErrorWithoutFabricatedReply() {
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:65))
        XCTAssertTrue(app.staticTexts["自动测试已关闭付费 AI 调用。"].waitForExistence(timeout:10))
        XCTAssertEqual(app.staticTexts.matching(identifier:"assistantMessage").count,0)
        capture("compact-error-in-tools-row",app)
        let inputY=app.textViews["chatInput"].frame.minY
        let chatHeight=app.scrollViews["chatMessages"].frame.height
        app.buttons["关闭提示"].tap()
        XCTAssertTrue(app.staticTexts["自动测试已关闭付费 AI 调用。"].waitForNonExistence(timeout:3))
        XCTAssertEqual(app.textViews["chatInput"].frame.minY,inputY,accuracy:1)
        XCTAssertEqual(app.scrollViews["chatMessages"].frame.height,chatHeight,accuracy:1)
        app.terminate()
    }
    @MainActor func testSmartRepliesStayAboveInputAndTabBar() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--smart-reply-layout-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["smartReplyButton"].waitForExistence(timeout:65))
        XCTAssertTrue(app.staticTexts["自动测试已关闭付费 AI 调用。"].waitForExistence(timeout:10))
        app.buttons["smartReplyButton"].tap()
        let input=app.textViews["chatInput"]
        for index in 0..<3 {
            let choice=app.buttons["smartReplyOption-\(index)"]
            XCTAssertTrue(choice.waitForExistence(timeout:5))
            XCTAssertTrue(choice.isHittable)
            XCTAssertLessThan(choice.frame.maxY,input.frame.minY-4,"Every choice must remain above the input and tab bar")
            XCTAssertGreaterThan(choice.frame.minY,app.buttons["customizationButton"].frame.maxY)
        }
        capture("smart-replies-fully-visible-above-input",app)
        app.buttons["closeSmartReplies"].tap()
        XCTAssertTrue(app.buttons["smartReplyOption-0"].waitForNonExistence(timeout:3))
        XCTAssertTrue(input.isHittable)
    }
    @MainActor func testPreparedPinchUsesRealAIAndReadyAudio() throws {
        guard ProcessInfo.processInfo.environment["STARRY_LIVE_AI_TESTS"]=="1" else {
            throw XCTSkip("Paid reaction preparation is explicitly opt-in.")
        }
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--live-ai","--live-reaction-prewarm"]
        app.launch();dismissLocalNetworkAlert()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:65))
        waitForRealVoice(app)
        app.waitForCharacter({state in
            let ready=state["preparedReactionReady"] as? [String:Int] ?? [:]
            return ["shake","pinch_in","pinch_out","idle","app_launch","return"].allSatisfy {ready[$0,default:0]==1}
        },timeout:120)
        capture("prepared-real-ai-all-gesture-pools",app)
        let before=app.characterRuntime
        let center=CGPoint(x:(before["headX"] as? Double ?? 0.5)*app.frame.width,
                           y:(before["headY"] as? Double ?? 0.3)*app.frame.height)
        let done=expectation(description:"outward pinch from current portrait")
        SNSynthesizePreviewPinch(center,1.8) {error in XCTAssertNil(error);done.fulfill()}
        wait(for:[done],timeout:8)
        app.waitForCharacter({($0["preparedReactionHits"] as? Int ?? 0)>(before["preparedReactionHits"] as? Int ?? 0)},timeout:5)
        XCTAssertEqual(app.characterRuntime["lastModelInteraction"] as? String,"pinch_out")
        XCTAssertEqual(app.characterRuntime["userMessageCount"] as? Int,0,"A physical gesture must not invent a user message")
        waitForRealVoice(app)
        capture("prepared-pinch-consumed-with-real-pcm",app)
        let greetings=app.characterRuntime["greetingCount"] as? Int ?? 0
        app.terminate()
        app.launchArguments.append("--keep-companion-data");app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:65))
        app.waitForCharacter({($0["greetingCount"] as? Int ?? 0)>greetings && ($0["preparedReactionHits"] as? Int ?? 0)>0},timeout:10)
        waitForRealVoice(app)
        capture("prepared-app-return-with-real-pcm",app)
        app.terminate()
    }
    @MainActor private func waitForRealVoice(_ app:XCUIApplication) {
        let controls=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","messageVoice-"))
        let ready=NSPredicate { _,_ in
            (controls.allElementsBoundByIndex.last?.value as? String ?? "").contains("durationSource:measured")
        }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:ready,object:nil)],timeout:85),.completed,
            "A completed native PCM playback must report measured duration")
        XCTAssertGreaterThan(controls.count,0)
    }
    @MainActor func testSmartReplyChoiceUsesPreparedRealAnswer() throws {
        guard ProcessInfo.processInfo.environment["STARRY_LIVE_AI_TESTS"]=="1" else {throw XCTSkip("Paid AI is opt-in.")}
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--live-ai","--live-smart-replies","--live-reaction-prewarm","--keep-companion-data"]
        app.launch();dismissLocalNetworkAlert()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:65))
        app.waitForCharacter({($0["quickReplyCount"] as? Int ?? 0)==3},timeout:50)
        waitForRealVoice(app)
        app.buttons["smartReplyButton"].tap()
        for index in 0..<3 {XCTAssertTrue(app.buttons["smartReplyOption-\(index)"].waitForExistence(timeout:5))}
        capture("smart-replies-ranked-options",app)
        let choice=app.buttons["smartReplyOption-0"].label
        let before=app.characterRuntime
        app.buttons["smartReplyOption-0"].tap()
        app.waitForCharacter({($0["preparedReactionHits"] as? Int ?? 0)>(before["preparedReactionHits"] as? Int ?? 0)},timeout:25)
        XCTAssertEqual(app.characterRuntime["userMessageCount"] as? Int,(before["userMessageCount"] as? Int ?? 0)+1)
        XCTAssertTrue(app.staticTexts.matching(identifier:"userMessage").allElementsBoundByIndex.contains {$0.label==choice})
        waitForRealVoice(app)
        capture("smart-reply-selected-pair-and-pcm",app)
        app.terminate()
    }
    @MainActor private func dismissLocalNetworkAlert() {
        let springboard=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout:3) {
            for title in ["Allow","允许","好","OK"] where springboard.alerts.buttons[title].exists { springboard.alerts.buttons[title].tap();break }
        }
    }
    @MainActor private func capture(_ name:String,_ app:XCUIApplication) {
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
        let tree=XCTAttachment(string:app.debugDescription);tree.name=name+"-elements";tree.lifetime = .keepAlways;add(tree)
        if let data=try? JSONSerialization.data(withJSONObject:app.characterRuntime,options:[.prettyPrinted,.sortedKeys]) {
            let runtime=XCTAttachment(data:data,uniformTypeIdentifier:"public.json");runtime.name=name+"-runtime";runtime.lifetime = .keepAlways;add(runtime)
        }
    }
}
