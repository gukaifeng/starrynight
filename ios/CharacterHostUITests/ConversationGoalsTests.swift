import XCTest

final class ConversationGoalsTests: XCTestCase {
    @MainActor func testThreeDirectionsPauseAndExistingStoryNavigation() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--goal-page-fixture","-starry.app.language.v1","zh-Hans"]
        app.launch();defer{app.terminate()}
        XCTAssertTrue(app.buttons["goal-mode-relationship"].waitForExistence(timeout:6))
        XCTAssertTrue(app.buttons["goal-mode-task"].exists);XCTAssertTrue(app.buttons["goal-mode-sandbox"].exists)
        app.buttons["goal-mode-task"].tap();XCTAssertTrue(app.buttons["goalTask"].waitForExistence(timeout:4))
        app.buttons["goal-mode-sandbox"].tap();XCTAssertFalse(app.buttons["goalTask"].exists)
        let pause=app.switches["goalPause"]
        for _ in 0..<4 {if pause.isHittable{break};app.scrollViews["togetherContent"].swipeUp()}
        XCTAssertTrue(pause.exists);pause.tap();XCTAssertEqual(pause.value as? String,"1")
        let picture=XCTAttachment(screenshot:app.screenshot());picture.name="goal-sandbox-and-pause";picture.lifetime = .keepAlways;add(picture)
        app.segmentedControls["togetherTabs"].buttons["故事"].tap()
        XCTAssertTrue(app.buttons["start-story-ichigo-sweet-rival"].waitForExistence(timeout:4))
    }
}
