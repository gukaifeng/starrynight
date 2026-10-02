import XCTest

final class ConversationInfoCardTests:XCTestCase {
    @MainActor func testRelationshipCardAndResetConfirmationPreserveThenClearRecords() {
        let app=launch()
        let row=app.buttons["message-anime-kipfel"]
        XCTAssertTrue(row.waitForExistence(timeout:15));row.tap()
        assertSummary(app,turns:"8 轮",memories:"2 件")
        XCTAssertEqual(app.staticTexts["conversationActiveDays"].label,"3 天")
        XCTAssertTrue(app.staticTexts["conversationLatestMessage"].label.contains("风铃"))
        XCTAssertFalse(app.buttons["resetConversation-anime-kipfel"].exists)
        capture("relationship-overview")
        app.buttons["moreConversationActions-anime-kipfel"].tap()
        let reset=app.buttons["resetConversation-anime-kipfel"]
        XCTAssertTrue(reset.waitForExistence(timeout:3));reset.tap()
        XCTAssertTrue(app.buttons["confirmConversationReset"].waitForExistence(timeout:3))
        capture("relationship-reset-confirmation")
        app.buttons["cancelConversationReset"].tap()
        XCTAssertTrue(reset.waitForExistence(timeout:3))
        app.buttons["backConversationDetail"].tap()
        assertSummary(app,turns:"8 轮",memories:"2 件")
        app.buttons["moreConversationActions-anime-kipfel"].tap();reset.tap()
        app.buttons["confirmConversationReset"].tap()
        XCTAssertTrue(app.staticTexts["conversationResetSuccess"].waitForExistence(timeout:6))
        assertSummary(app,turns:"0 轮",memories:"0 件")
        app.buttons["closeConversationDetail"].tap()
        XCTAssertTrue(row.waitForExistence(timeout:4),"Reset retains the message-list entry")
        app.terminate();app.launchArguments += ["--keep-companion-data","--keep-auth-data"];app.launch()
        XCTAssertTrue(row.waitForExistence(timeout:15));row.tap()
        assertSummary(app,turns:"0 轮",memories:"0 件")
        app.buttons["enterConversation-anime-kipfel"].tap()
        // The native fixture deliberately has no Unity frame fence. Reaching
        // its real preparing page verifies routing, not model readiness.
        XCTAssertTrue(app.otherElements["conversationPreparingArtwork"].waitForExistence(timeout:6))
        app.terminate()
    }
    @MainActor func testHideKeepsBondAndMemoriesAndSwipeCanClose() {
        let app=launch(["--message-scroll-fixture"]);defer {app.terminate()}
        let row=app.buttons["message-anime-kipfel"]
        XCTAssertTrue(row.waitForExistence(timeout:15))
        row.swipeLeft()
        let remove=app.buttons["deleteConversation-anime-kipfel"]
        XCTAssertTrue(remove.waitForExistence(timeout:4))
        capture("relationship-swipe-blend")
        row.swipeRight()
        let closed=NSPredicate {_,_ in !remove.exists}
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:closed,object:nil)],timeout:4),.completed)
        row.tap();assertSummary(app,turns:"8 轮",memories:"2 件")
        app.buttons["detailHideConversation-anime-kipfel"].tap()
        XCTAssertTrue(app.buttons["undoHideConversation"].waitForExistence(timeout:4))
        XCTAssertFalse(row.exists)
        app.buttons["undoHideConversation"].tap()
        XCTAssertTrue(row.waitForExistence(timeout:3));row.tap()
        assertSummary(app,turns:"8 轮",memories:"2 件")
    }
    @MainActor func testFailedResetKeepsRecordsAndOffersRetry() {
        let app=launch(["--conversation-reset-failure"]);defer {app.terminate()}
        let row=app.buttons["message-anime-kipfel"]
        XCTAssertTrue(row.waitForExistence(timeout:15));row.tap()
        app.buttons["moreConversationActions-anime-kipfel"].tap()
        app.buttons["resetConversation-anime-kipfel"].tap()
        app.buttons["confirmConversationReset"].tap()
        XCTAssertTrue(app.staticTexts["conversationResetError"].waitForExistence(timeout:6))
        app.buttons["backConversationDetail"].tap()
        assertSummary(app,turns:"8 轮",memories:"2 件")
        XCTAssertFalse(app.buttons["enterConversation-anime-kipfel"].isEnabled)
    }
    @MainActor func testEnglishCardKeepsTranscriptAndLocalizesControls() {
        let app=launch(language:"en");defer {app.terminate()}
        let row=app.buttons["message-anime-kipfel"]
        XCTAssertTrue(row.waitForExistence(timeout:15));row.tap()
        assertSummary(app,turns:"8 exchanges",memories:"2 memories")
        XCTAssertTrue(app.staticTexts["Your story"].exists)
        XCTAssertTrue(app.staticTexts["conversationLatestMessage"].label.contains("风铃"),"User/character text stays verbatim")
        app.buttons["moreConversationActions-anime-kipfel"].tap()
        app.buttons["resetConversation-anime-kipfel"].tap()
        XCTAssertEqual(app.buttons["confirmConversationReset"].label,"Confirm reset")
        app.buttons["cancelConversationReset"].tap()
    }
    @MainActor private func assertSummary(_ app:XCUIApplication,turns:String,memories:String) {
        XCTAssertTrue(app.staticTexts["conversationTurnCount"].waitForExistence(timeout:4))
        XCTAssertEqual(app.staticTexts["conversationTurnCount"].label,turns)
        XCTAssertEqual(app.staticTexts["conversationMemoryCount"].label,memories)
    }
    @MainActor private func launch(_ extra:[String]=[],language:String="zh-Hans") -> XCUIApplication {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--conversation-card-fixture","-starry.app.language.v1",language]+extra
        app.launch();return app
    }
    @MainActor private func capture(_ name:String) {
        let image=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        image.name=name;image.lifetime = .keepAlways;add(image)
    }
}
