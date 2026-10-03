import XCTest

final class QuietChatTests:XCTestCase {
    @MainActor private func wait(_ condition:@escaping ()->Bool,timeout:TimeInterval = 20) {
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in MainActor.assumeIsolated { condition() } },object:nil)],timeout:timeout),.completed)
    }
    @MainActor private func capture(_ name:String) {
        let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)
    }
    @MainActor func testLocalSearchFocusAndStatisticNavigation() {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing"]
        app.launch();XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        XCTAssertFalse(app.buttons["viewerBackButton"].exists)
        XCTAssertFalse(app.buttons["characterActionsMenu"].exists)
        XCTAssertFalse(app.buttons["tab-create"].staticTexts["创建"].exists)
        XCTAssertFalse(app.buttons["voiceMuteButton"].exists)
        let title=app.buttons["customizationButton"]
        XCTAssertEqual(title.frame.midX,app.frame.midX,accuracy:2)
        XCTAssertTrue(title.label.contains("初音未来"))
        app.openCustomization()
        let mute=app.switches["characterMuteToggle"]
        XCTAssertTrue(mute.waitForExistence(timeout:8));mute.tap()
        XCTAssertEqual(mute.value as? String,"1")
        app.buttons["closeCustomizationButton"].tap()
        XCTAssertTrue(app.buttons["closeCharacterDetails"].waitForExistence(timeout:5))
        app.buttons["closeCharacterDetails"].tap()
        let input=app.textViews["chatInput"]
        input.tap();input.typeText("今晚一起看月亮")
        app.buttons["sendMessageButton"].tap()
        wait { app.staticTexts.matching(identifier:"assistantMessage").count == 1 && !app.buttons["stopReplyButton"].exists }
        let voice=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","messageVoice-")).firstMatch
        XCTAssertTrue(voice.exists)
        let reply=app.staticTexts.matching(identifier:"assistantMessage").firstMatch
        XCTAssertLessThan(voice.frame.width,100)
        XCTAssertGreaterThanOrEqual(voice.frame.height,44,"Compact visuals keep a usable touch target")
        XCTAssertLessThanOrEqual(voice.frame.maxY,reply.frame.minY+1,"Voice occupies the bubble's own raised corner above its text")
        XCTAssertTrue((voice.value as? String ?? "").contains("″"))
        XCTAssertFalse((voice.value as? String ?? "").contains("约"))
        XCTAssertTrue((voice.value as? String ?? "").contains("durationSource:estimated"))
        XCTAssertTrue((voice.value as? String ?? "").contains("voiceMotion:static"))
        XCTAssertFalse(app.staticTexts["speechStatus"].exists)
        XCTAssertFalse(app.staticTexts["companionPresence"].exists)
        let composerFrame = input.frame
        let viewportFrame = app.scrollViews["chatMessages"].frame
        capture("minimal-chat-pendant")
        app.buttons["tab-messages"].tap()
        let search=app.textFields["conversationSearchField"]
        XCTAssertTrue(search.waitForExistence(timeout:8));search.tap();search.typeText("月亮")
        let hit=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","conversationHit-")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout:8));XCTAssertTrue(hit.label.contains("月亮"))
        capture("local-search-results")
        hit.tap();XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:10))
        let found=app.staticTexts.matching(identifier:"userMessage").matching(NSPredicate(format:"label == %@","今晚一起看月亮")).firstMatch
        wait { found.isHittable }
        XCTAssertTrue(app.buttons["returnLatestButton"].exists)
        let arrow = app.buttons["returnLatestButton"]
        XCTAssertLessThanOrEqual(arrow.frame.maxY,app.scrollViews["chatMessages"].frame.maxY+1,"Arrow stays above the composer instead of extending into it")
        XCTAssertEqual(input.frame.minY,composerFrame.minY,accuracy:1,"Arrow overlay does not move the composer")
        XCTAssertEqual(app.scrollViews["chatMessages"].frame.height,viewportFrame.height,accuracy:1,"Arrow does not resize history")
        capture("minimal-double-chevron")
        app.buttons["returnLatestButton"].tap()
        wait { !app.buttons["returnLatestButton"].exists }
        app.buttons["tab-mine"].tap()
        XCTAssertTrue(app.buttons["myConversationsButton"].waitForExistence(timeout:8))
        XCTAssertEqual(app.buttons["tab-mine"].label,"我的","The text-only dock exposes My as its button label")
        XCTAssertFalse(app.staticTexts["我的关注"].exists)
        XCTAssertFalse(app.staticTexts["我创建的角色"].exists)
        XCTAssertLessThan(app.buttons["mySubscriptionsButton"].frame.width,100)
        capture("quiet-profile-statistics")
        app.buttons["myConversationsButton"].tap()
        XCTAssertTrue(app.buttons["chatted-hatsune-miku"].waitForExistence(timeout:8));capture("chatted-character-list")
        app.buttons["closeConversationsButton"].tap()
        app.buttons["mySubscriptionsButton"].tap()
        XCTAssertTrue(app.buttons["unsubscribe-hatsune-miku"].waitForExistence(timeout:8))
        app.buttons["closeSubscriptionsButton"].tap()
        app.buttons["myCreationsButton"].tap()
        XCTAssertTrue(app.navigationBars["我创建的角色"].waitForExistence(timeout:8))
        app.buttons["closeCreationsButton"].tap()
        app.buttons["profileSettingsButton"].tap();app.buttons["themeSettingsButton"].tap()
        XCTAssertEqual(app.buttons["theme-silver"].value as? String,"已选择")
        XCTAssertLessThan(app.buttons["theme-silver"].frame.minY,app.buttons["theme-aurora"].frame.minY)
        capture("moonwhite-first-default")
    }
}
