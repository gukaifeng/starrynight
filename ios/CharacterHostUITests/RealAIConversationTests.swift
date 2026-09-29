import XCTest

final class RealAIConversationTests: XCTestCase {
    @MainActor func testAudioThreadPlaybackAndCachedVocalBeat() {
        let app = XCUIApplication(); app.launchArguments = ["--speech-playback-check"]
        app.launch()
        let result = app.staticTexts["speechPlaybackResult"]
        XCTAssertTrue(result.waitForExistence(timeout:10))
        let completed = NSPredicate { _,_ in result.label.hasPrefix("PASS:") || result.label.hasPrefix("FAIL:") }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:completed,object:nil)],timeout:20),.completed)
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
        app.launchArguments = ["--ui-testing","--companion-testing","--auth-testing","--live-ai"]
        app.launch()
        dismissLocalNetworkAlert()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:65))
        waitForRealVoice(app)
        capture("real-ai-kipfel-greeting",app)
        let field = app.textFields["chatInput"].exists ? app.textFields["chatInput"] : app.textViews["chatInput"]
        XCTAssertTrue(field.waitForExistence(timeout:10));field.tap();field.typeText("我今天画好了一朵小花，用一句话夸夸我吧。")
        app.buttons["sendMessageButton"].tap()
        let reply = app.staticTexts.matching(identifier:"assistantMessage")
        let ready = NSPredicate { _,_ in reply.count >= 2 }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:ready,object:nil)],timeout:70),.completed)
        waitForRealVoice(app)
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
        app.terminate() // No unattended paid idle generation after the test.
    }
    @MainActor func testMissingAIShowsErrorWithoutFabricatedReply() {
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:65))
        XCTAssertTrue(app.staticTexts["自动测试已关闭付费 AI 调用。"].waitForExistence(timeout:10))
        XCTAssertEqual(app.staticTexts.matching(identifier:"assistantMessage").count,0)
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
    @MainActor private func dismissLocalNetworkAlert() {
        let springboard=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout:3) {
            for title in ["Allow","允许","好","OK"] where springboard.alerts.buttons[title].exists { springboard.alerts.buttons[title].tap();break }
        }
    }
    @MainActor private func capture(_ name:String,_ app:XCUIApplication) {
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
        let tree=XCTAttachment(string:app.debugDescription);tree.name=name+"-elements";tree.lifetime = .keepAlways;add(tree)
    }
}
