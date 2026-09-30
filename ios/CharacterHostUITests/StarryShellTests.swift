import XCTest

final class StarryShellTests: XCTestCase {
    @MainActor private func start(_ extra:[String] = []) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing","--companion-testing"] + extra
        app.launch(); return app
    }
    @MainActor private func tab(_ app:XCUIApplication,_ name:String) {
        let button = app.buttons["tab-"+name]
        XCTAssertTrue(button.waitForExistence(timeout:60)); XCTAssertTrue(button.isHittable); button.tap()
    }
    @MainActor private func wait(_ condition:@escaping ()->Bool,timeout:TimeInterval = 15) {
        let predicate = NSPredicate { _,_ in MainActor.assumeIsolated { condition() } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:nil)],timeout:timeout),.completed)
    }
    @MainActor private func capture(_ name:String) {
        RunLoop.current.run(until:Date().addingTimeInterval(0.5))
        let attachment = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func scrollTo(_ element:XCUIElement,in app:XCUIApplication) {
        for _ in 0..<9 { if element.isHittable { return }; app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor func testDefaultConversationMessagesAndResume() {
        let app = start()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:90))
        XCTAssertEqual(app.staticTexts["chatCharacterName"].label,"初音未来")
        for name in ["home","messages","create","discover","mine"] { XCTAssertTrue(app.buttons["tab-"+name].isHittable) }
        capture("starry-home-phone")
        app.buttons["starter-hello"].tap(); app.waitForReply()
        let input = app.textViews["chatInput"]
        input.tap()
        XCTAssertTrue(app.buttons["sendMessageButton"].isHittable)
        XCTAssertFalse(app.buttons["tab-messages"].isHittable)
        app.buttons["dismissChatKeyboardButton"].tap()
        wait { app.buttons["tab-messages"].isHittable }
        capture("starry-chat-phone")
        tab(app,"messages")
        XCTAssertTrue(app.buttons["message-hatsune-miku"].waitForExistence(timeout:12))
        capture("starry-messages-phone")
        tab(app,"discover")
        for id in ["real-woman","studio-robot","hatsune-miku","sample-robot"] { XCTAssertTrue(app.buttons["follow-"+id].exists) }
        capture("starry-discover-phone")
        app.buttons["discover-open-studio-robot"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        XCTAssertEqual(app.staticTexts["chatCharacterName"].label,"Luma")
        tab(app,"messages"); app.buttons["message-hatsune-miku"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        XCTAssertEqual(app.staticTexts["chatCharacterName"].label,"初音未来")
        XCTAssertTrue(app.staticTexts.matching(identifier:"assistantMessage").count > 0)
        app.terminate(); app.launchArguments = ["--ui-testing","--companion-testing","--keep-companion-data"]; app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:90))
        XCTAssertEqual(app.staticTexts["chatCharacterName"].label,"初音未来")
        XCTAssertTrue(app.staticTexts.matching(identifier:"assistantMessage").count > 0)
    }
    @MainActor func testUnfollowAllAndLandscape() {
        let app = start(["--shell-discover"])
        XCTAssertTrue(app.buttons["follow-hatsune-miku"].waitForExistence(timeout:20))
        XCTAssertEqual(app.buttons["follow-hatsune-miku"].value as? String,"已关注")
        app.buttons["follow-hatsune-miku"].tap(); tab(app,"home")
        XCTAssertTrue(app.buttons["emptyStateAction"].waitForExistence(timeout:8)); capture("starry-empty-home")
        app.terminate();app.launchArguments = ["--ui-testing","--companion-testing","--keep-companion-data"];app.launch()
        XCTAssertTrue(app.buttons["emptyStateAction"].waitForExistence(timeout:20))
        XCTAssertFalse(app.buttons["customizationButton"].exists)
        tab(app,"discover")
        XCUIDevice.shared.orientation = .landscapeLeft
        wait { app.frame.width > app.frame.height }
        XCTAssertTrue(app.buttons["tab-create"].isHittable)
        capture("starry-discover-landscape")
        app.buttons["discover-open-studio-robot"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:90))
        XCTAssertTrue(app.buttons["tab-mine"].isHittable)
        XCTAssertTrue(app.frame.contains(app.buttons["sendMessageButton"].frame))
        capture("starry-chat-landscape")
        tab(app,"mine")
        XCTAssertTrue(app.buttons["accountCenterButton"].waitForExistence(timeout:10));capture("starry-my-landscape")
        XCUIDevice.shared.orientation = .portrait
    }
    @MainActor func testCreationVisibilityAccountIsolationAndPersistence() {
        let app = start(["--shell-discover"])
        tab(app,"create");XCTAssertTrue(app.textFields["createName"].waitForExistence(timeout:10));capture("starry-create-phone")
        // First create a private human. The default name makes this reproducible without keyboard timing.
        scrollTo(app.buttons["createCharacterButton"],in:app)
        XCTAssertEqual(app.buttons["createPrivate"].value as? String,"已选择")
        app.buttons["createCharacterButton"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:90))
        XCTAssertEqual(app.staticTexts["chatCharacterName"].label,"小月")
        app.buttons["starter-hello"].tap();app.waitForReply()
        capture("starry-created-human")
        tab(app,"mine")
        let privateButton = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'publish-'")).firstMatch
        scrollTo(privateButton,in:app); let id = String(privateButton.identifier.dropFirst("publish-".count))
        capture("starry-my-phone")
        scrollTo(app.buttons["switchDemoIdentity"],in:app);app.buttons["switchDemoIdentity"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:90))
        tab(app,"discover");XCTAssertFalse(app.buttons["discover-open-"+id].exists)
        tab(app,"messages");XCTAssertFalse(app.buttons["message-"+id].exists)
        tab(app,"mine");scrollTo(app.buttons["switchDemoIdentity"],in:app);app.buttons["switchDemoIdentity"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:90))
        XCTAssertEqual(app.staticTexts["chatCharacterName"].label,"小月")
        XCTAssertTrue(app.staticTexts.matching(identifier:"assistantMessage").count > 0)
        tab(app,"mine");scrollTo(app.buttons["publish-"+id],in:app);app.buttons["publish-"+id].tap()
        scrollTo(app.buttons["switchDemoIdentity"],in:app);app.buttons["switchDemoIdentity"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:90))
        tab(app,"discover");scrollTo(app.buttons["discover-open-"+id],in:app);app.buttons["discover-open-"+id].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:90))
        XCTAssertEqual(app.staticTexts["chatCharacterName"].label,"小月")
        XCTAssertEqual(app.staticTexts.matching(identifier:"assistantMessage").count,0,"Public character must not leak owner's chat")
        app.terminate();app.launchArguments = ["--ui-testing","--companion-testing","--keep-companion-data"];app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:90))
        XCTAssertEqual(app.staticTexts["chatCharacterName"].label,"小月")
        tab(app,"mine")
        XCTAssertTrue(app.staticTexts["星夜体验者 B"].waitForExistence(timeout:10))
    }
    @MainActor func testGuestLoginFromMyPage() {
        let app = start(["--auth-testing","--shell-discover"])
        XCTAssertTrue(app.buttons["discover-open-hatsune-miku"].waitForExistence(timeout:20))
        app.buttons["discover-open-hatsune-miku"].tap()
        XCTAssertTrue(app.buttons["signInButton"].waitForExistence(timeout:10));capture("starry-login-phone")
        app.buttons["signInButton"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:90))
        XCTAssertEqual(app.staticTexts["chatCharacterName"].label,"初音未来")
    }
}
