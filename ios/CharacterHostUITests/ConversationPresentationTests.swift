import XCTest

final class ConversationPresentationTests: XCTestCase {
    @MainActor func testNewMessagesAndLateNarrationReturnFromHistory() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--conversation-presentation-check"]
        app.launch();defer {app.terminate()}
        let scroll=app.scrollViews["chatMessages"]
        XCTAssertTrue(scroll.waitForExistence(timeout:20))
        XCTAssertTrue(app.staticTexts["你回来啦。"].waitForExistence(timeout:5))
        XCTAssertFalse(app.descendants(matching:.any)["aiThought"].exists,"Old planning text must be hidden while its genuine dialogue stays visible")
        func awaitPosition(_ text:String) {
            let ready=NSPredicate { _,_ in (scroll.value as? String)==text }
            XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:ready,object:nil)],timeout:8),.completed)
        }
        func history() {app.buttons["fixtureHistory"].tap();awaitPosition("历史消息")}
        history();app.buttons["fixtureUser"].tap();awaitPosition("最新消息")
        XCTAssertTrue(app.staticTexts["新发送的消息"].isHittable)
        history();app.buttons["fixtureAI"].tap();awaitPosition("最新消息")
        XCTAssertTrue(app.staticTexts["后来发生了什么？"].isHittable)
        XCTAssertTrue(app.descendants(matching:.any)["aiThought"].exists)
        history();app.buttons["fixtureNarration"].tap();awaitPosition("最新消息")
        XCTAssertTrue(app.staticTexts["aiNarration"].isHittable)
        XCTAssertTrue(app.staticTexts["presentationContentResult"].label.hasPrefix("PASS:"))
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="narration-thought-dialogue";shot.lifetime = .keepAlways;add(shot)
    }
}
