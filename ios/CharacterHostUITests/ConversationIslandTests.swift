import XCTest

final class ConversationIslandTests:XCTestCase {
    @MainActor func testRealActivityKitLifecycleAndSystemPresentation() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--live-activity-fixture","--island-system-preview","-starry.app.language.v1","zh-Hans"]
        app.launch();defer {app.terminate()}
        let result=app.staticTexts["islandCoreResult"]
        XCTAssertTrue(result.waitForExistence(timeout:15))
        let checked=NSPredicate {_,_ in result.label.hasPrefix("PASS:")}
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:checked,object:nil)],timeout:10),.completed,result.label)
        app.buttons["islandStartThinking"].tap()
        let thinking=NSPredicate {_,_ in app.staticTexts["islandSystemState"].label=="thinking"}
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:thinking,object:nil)],timeout:10),.completed,app.debugDescription)
        let started=NSPredicate {_,_ in app.staticTexts["islandSystemCount"].label=="ActivityKit: 1"}
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:started,object:nil)],timeout:5),.completed)
        app.buttons["islandStartSpeaking"].tap()
        XCUIDevice.shared.press(.home)
        let springboard=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        XCTAssertTrue(springboard.wait(for:.runningForeground,timeout:5))
        Thread.sleep(forTimeInterval:1.3) // Let the system collapse its launch animation.
        let compact=XCTAttachment(screenshot:springboard.screenshot());compact.name="starry-island-compact";compact.lifetime = .keepAlways;add(compact)
        springboard.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.035)).press(forDuration:1.2)
        let expanded=XCTAttachment(screenshot:springboard.screenshot());expanded.name="starry-island-expanded";expanded.lifetime = .keepAlways;add(expanded)
        // Dismiss the system's expanded surface before returning. Otherwise
        // XCTest can report a foreground app while its buttons remain covered.
        springboard.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.65)).tap()
        app.activate()
        let endButton=app.buttons["islandEnd"]
        let visible=NSPredicate {_,_ in endButton.isHittable}
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:visible,object:nil)],timeout:5),.completed)
        endButton.tap()
        let ended=NSPredicate {_,_ in app.staticTexts["islandSystemCount"].label=="ActivityKit: 0"}
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:ended,object:nil)],timeout:10),.completed)
    }
    @MainActor func testPendingReplyFinishesAfterLeavingApp() async throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--conversation-continuity-fixture","--live-activity-fixture","-starry.app.language.v1","zh-Hans"]
        app.launch();defer {app.terminate()}
        let input=app.textViews["chatInput"]
        XCTAssertTrue(input.waitForExistence(timeout:65))
        input.tap();input.typeText("Wait")
        XCTAssertEqual(input.value as? String,"Wait")
        let key=app.keyboards.buttons.matching(NSPredicate(format:"label IN %@",["发送","Send","send"])).firstMatch
        XCTAssertTrue(key.waitForExistence(timeout:5));key.tap()
        let sent=app.staticTexts.matching(identifier:"userMessage").matching(NSPredicate(format:"label == %@","Wait")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout:5),"Verify a real pending turn before leaving the app")
        XCTAssertTrue(app.images["streamingReply"].waitForExistence(timeout:5))
        XCUIDevice.shared.press(.home)
        // The fixture replies after 14 seconds. iOS, not the app's foreground
        // tab, owns this interval. No paid endpoint is contacted.
        try await Task.sleep(for:.seconds(16))
        let springboard=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        springboard.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.035)).press(forDuration:1.2)
        let returned=springboard.staticTexts["回去接着聊"]
        XCTAssertTrue(returned.waitForExistence(timeout:3),"The real pending turn must still be on the island")
        let shot=XCTAttachment(screenshot:springboard.screenshot());shot.name="starry-real-background-reply";shot.lifetime = .keepAlways;add(shot)
        returned.tap()
        XCTAssertTrue(app.wait(for:.runningForeground,timeout:5),"Tapping the live activity must reopen StarryNight")
        let reply=app.staticTexts.matching(identifier:"assistantMessage").matching(NSPredicate(format:"label == %@","切页之后，我把刚才的话接着说完了。"))
        XCTAssertTrue(reply.firstMatch.waitForExistence(timeout:10));XCTAssertEqual(reply.count,1)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'resend-'")).firstMatch.exists)
    }
}
