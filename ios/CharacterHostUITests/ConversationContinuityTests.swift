import XCTest

final class ConversationContinuityTests:XCTestCase {
    @MainActor private func launch()->XCUIApplication {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--conversation-continuity-fixture","--smart-reply-layout-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        return app
    }
    @MainActor func testThinkingSurvivesTabReturnAndReplyFinishesOnce() {
        let app=launch();defer {app.terminate()}
        let input=app.textViews["chatInput"]
        input.tap();input.typeText("Wait\n")
        XCTAssertTrue(app.images["streamingReply"].waitForExistence(timeout:5))
        app.buttons["tab-discover"].tap()
        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout:5));app.buttons["tab-home"].tap()
        XCTAssertTrue(app.images["streamingReply"].waitForExistence(timeout:5),"Tab return must retain the same pending turn")
        let reply=app.staticTexts["切页之后，我把刚才的话接着说完了。"]
        XCTAssertTrue(reply.waitForExistence(timeout:20))
        XCTAssertFalse(app.images["streamingReply"].exists)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format:"label == %@",reply.label)).count,1)
        capture("reply-completes-after-tab-return")
    }
    @MainActor func testHiddenReplyPersistsAndSuggestedSendAnimates() {
        let app=launch();defer {app.terminate()}
        let input=app.textViews["chatInput"]
        input.tap();input.typeText("Wait\n")
        XCTAssertTrue(app.images["streamingReply"].waitForExistence(timeout:5))
        app.buttons["tab-messages"].tap()
        // A new message arrives while the conversation view is hidden. The
        // message-list preview observes the real store, not a UI fixture flag.
        let row=app.buttons["message-anime-kipfel"]
        wait(22) {row.label.contains("切页之后，我把刚才的话接着说完了。")}
        row.tap()
        XCTAssertTrue(app.staticTexts["切页之后，我把刚才的话接着说完了。"].waitForExistence(timeout:5))
        XCTAssertFalse(app.images["streamingReply"].exists)
        XCTAssertFalse(app.otherElements["chatNotice"].exists)
        let open=app.buttons["smartReplyButton"],panel=app.otherElements["smartRepliesPanel"]
        XCTAssertEqual(open.label,"灵感接话")
        open.tap();XCTAssertTrue(panel.waitForExistence(timeout:4))
        capture("inspiration-replies-presented")
        app.buttons["closeSmartReplies"].tap();wait(3) {!panel.exists}
        open.tap();XCTAssertTrue(panel.waitForExistence(timeout:4))
        let choice=app.buttons["smartReplyOption-0"],text=choice.label
        choice.tap();wait(4) {!panel.exists}
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout:4))
        XCTAssertTrue(app.staticTexts["这份接话已经收到，我们继续聊。"].waitForExistence(timeout:8))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format:"identifier == %@ AND label == %@","userMessage",text)).count,1)
        capture("suggestion-sent-once")
    }
    @MainActor private func wait(_ timeout:Double,_ predicate:@escaping @MainActor ()->Bool) {
        let check=XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in MainActor.assumeIsolated {predicate()}},object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[check],timeout:timeout),.completed)
    }
    @MainActor private func capture(_ name:String) {
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
    }
}
