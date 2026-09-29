import XCTest

final class StarryImmersionTests:XCTestCase {
    @MainActor private func start(_ extra:[String] = []) -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing","--companion-testing"] + extra
        app.launch(); return app
    }
    @MainActor private func wait(_ condition:@escaping ()->Bool,timeout:TimeInterval = 20) {
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in MainActor.assumeIsolated { condition() } },object:nil)],timeout:timeout),.completed)
    }
    @MainActor private func ready(_ app:XCUIApplication) { XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60)) }
    @MainActor private func tab(_ app:XCUIApplication,_ id:String) { let b=app.buttons["tab-"+id]; wait { b.isHittable }; b.tap() }
    @MainActor private func state(_ app:XCUIApplication) -> [String:Any] {
        let data = Data((app.buttons["customizationButton"].value as? String ?? "{}").utf8)
        return (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] ?? [:]
    }
    @MainActor private func capture(_ name:String) {
        RunLoop.current.run(until:Date().addingTimeInterval(0.6))
        let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)
    }
    @MainActor func testRetainedHomeCompactMessagesAndProfileRoutes() {
        let app=start();ready(app)
        wait { self.state(app)["cameraSnapCount"] != nil }
        let first=state(app);capture("starry-immersive-home")
        XCTAssertFalse(app.staticTexts["正在准备模型"].exists)
        let draft = app.textFields["chatInput"].exists ? app.textFields["chatInput"] : app.textViews["chatInput"]
        draft.tap(); draft.typeText("明晚继续聊")
        app.buttons["dismissChatKeyboardButton"].tap()
        for destination in ["messages","discover","mine"] {
            tab(app,destination)
            if destination == "messages" {
                let row=app.buttons["message-hatsune-miku"];XCTAssertTrue(row.waitForExistence(timeout:8));XCTAssertLessThan(row.frame.height,80)
                capture("starry-compact-messages");row.tap()
            } else { tab(app,"home") }
            ready(app)
            wait { self.state(app)["name"] as? String == "state" }
            XCTAssertEqual(state(app)["presentationId"] as? Int,first["presentationId"] as? Int)
            XCTAssertEqual(state(app)["cameraSnapCount"] as? Int,first["cameraSnapCount"] as? Int)
            XCTAssertEqual(draft.value as? String,"明晚继续聊")
        }
        tab(app,"mine");capture("starry-profile")
        XCTAssertFalse(app.buttons["unsubscribe-hatsune-miku"].exists)
        app.buttons["accountCenterButton"].tap()
        XCTAssertTrue(app.navigationBars["账户"].waitForExistence(timeout:8));capture("starry-account")
        app.buttons["closeAccountButton"].tap()
        app.buttons["mySubscriptionsButton"].tap()
        XCTAssertTrue(app.buttons["unsubscribe-hatsune-miku"].waitForExistence(timeout:8));capture("starry-follows")
        app.buttons["closeSubscriptionsButton"].tap()
        app.buttons["myCreationsButton"].tap()
        XCTAssertTrue(app.navigationBars["我创建的角色"].waitForExistence(timeout:8));capture("starry-creations")
        app.buttons["closeCreationsButton"].tap()
        app.buttons["profileSettingsButton"].tap();app.buttons["themeSettingsButton"].tap()
        XCTAssertEqual(app.buttons["theme-silver"].value as? String,"已选择");capture("starry-theme")
    }
    @MainActor func testBubbleVoicePlaybackDurationAndNoMessageMenu() {
        let app=start(["--auth-testing"]);ready(app)
        app.buttons["starter-hello"].tap()
        let voice=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","messageVoice-")).firstMatch
        XCTAssertTrue(voice.waitForExistence(timeout:25))
        wait({ (voice.value as? String ?? "").contains("播放中") },timeout:100)
        wait({ (voice.value as? String ?? "").range(of:"audioSegments:[1-9]",options:.regularExpression) != nil },timeout:60)
        XCTAssertLessThan(voice.frame.width,100)
        XCTAssertTrue((voice.value as? String ?? "").contains("″"))
        XCTAssertTrue((voice.value as? String ?? "").contains("voiceMotion:playing"))
        capture("starry-bubble-playing")
        wait({ !(voice.value as? String ?? "").contains("播放中") && !(voice.value as? String ?? "").contains("准备中") },timeout:100)
        XCTAssertTrue((voice.value as? String ?? "").contains("durationSource:measured"),"Measured audio duration replaces estimate")
        XCTAssertTrue((voice.value as? String ?? "").contains("voiceMotion:static"))
        capture("starry-bubble-duration")
        app.openCustomization()
        app.switches["characterMuteToggle"].tap()
        app.buttons["closeCustomizationButton"].tap()
        voice.tap();wait({ (voice.value as? String ?? "").contains("播放中") },timeout:10)
        voice.tap();wait { (voice.value as? String ?? "").contains("未播放") }
        XCTAssertTrue((voice.value as? String ?? "").contains("voiceMotion:static"))
        let stoppedFrame = voice.frame
        RunLoop.current.run(until:Date().addingTimeInterval(1.1))
        XCTAssertEqual(voice.frame,stoppedFrame,"Stopping playback must not keep moving the voice label")
        capture("voice-stopped-static")
        app.openCustomization()
        XCTAssertEqual(app.switches["characterMuteToggle"].value as? String,"1","Explicit replay doesn't change auto-read preference")
        app.buttons["closeCustomizationButton"].tap()
        app.staticTexts.matching(identifier:"assistantMessage").firstMatch.press(forDuration:0.8)
        XCTAssertFalse(app.menuItems["复制"].exists);XCTAssertFalse(app.buttons["rememberMessageButton"].exists)
        tab(app,"messages");app.buttons["message-hatsune-miku"].tap();ready(app)
        XCTAssertTrue(voice.exists);XCTAssertFalse((voice.value as? String ?? "").contains("约"))
        capture("starry-chat-retained")
        app.terminate(); app.launchArguments = ["--ui-testing","--companion-testing","--auth-testing","--keep-companion-data","--keep-auth-data"]; app.launch();ready(app)
        XCTAssertTrue((voice.value as? String ?? "").contains("durationSource:measured"),"Measured durations survive a fresh process")
    }
    @MainActor func testCancelColdOpeningThenSwitchRoles() {
        let app=start(["--shell-discover","--test-ready-delay=3"])
        XCTAssertTrue(app.buttons["discover-open-hatsune-miku"].waitForExistence(timeout:15))
        app.buttons["discover-open-hatsune-miku"].tap()
        tab(app,"mine")
        XCTAssertTrue(app.buttons["mySubscriptionsButton"].waitForExistence(timeout:10))
        tab(app,"home");ready(app)
        XCTAssertTrue(app.buttons["customizationButton"].label.hasPrefix("初音未来"))
        tab(app,"discover");app.buttons["discover-open-studio-robot"].tap();ready(app)
        XCTAssertEqual(state(app)["modelId"] as? String,"studio-robot")
        capture("starry-luma-closeup")
        tab(app,"messages");app.buttons["message-hatsune-miku"].tap();ready(app)
        XCTAssertTrue(app.buttons["customizationButton"].label.hasPrefix("初音未来"))
        capture("starry-final-closeup")
    }

    @MainActor func testStarArrivalFadesToLivingCharacter() {
        let app=start(["--auth-testing","--shell-discover","--test-ready-delay=4"])
        let entry=app.buttons["discover-open-hatsune-miku"]
        XCTAssertTrue(entry.waitForExistence(timeout:15));entry.tap()
        XCTAssertFalse(app.otherElements["appStartupScreen"].exists,"Role arrival must not replay the brand opening")
        let arrival=app.descendants(matching:.any).matching(identifier:"characterArrival").firstMatch
        XCTAssertTrue(arrival.waitForExistence(timeout:8))
        XCTAssertFalse(app.staticTexts["正在准备模型"].exists)
        capture("starry-arrival")
        ready(app)
        wait { !arrival.exists }
        // Check that the first conversational framing remains stable after entry.
        RunLoop.current.run(until:Date().addingTimeInterval(3))
        capture("starry-settled-closeup")
        XCTAssertTrue(app.buttons["customizationButton"].label.hasPrefix("初音未来"))
        XCTAssertTrue(app.textFields["chatInput"].exists || app.textViews["chatInput"].exists)
    }

}
