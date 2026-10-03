import XCTest

final class ReplyFlowTests:XCTestCase {
    @MainActor func testAsidesArriveBetweenLinesWhileVoiceIsPlaying() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--reply-flow-check","-starry.app.language.v1","zh-Hans"]
        app.launch();defer {app.terminate()}
        XCTAssertTrue(app.buttons["startReplyFlow"].waitForExistence(timeout:20))
        app.buttons["startReplyFlow"].tap()
        let first=app.staticTexts["我在听。"],middle=app.staticTexts["你愿意接着讲吗？"],last=app.staticTexts["慢慢说就好。"]
        XCTAssertTrue(first.waitForExistence(timeout:2))
        XCTAssertTrue(last.exists,"Received dialogue stays readable; only nonspoken directions follow the audio clock")
        XCTAssertFalse(app.staticTexts["aiNarration"].exists,"Future directions must not appear before their audio phase")
        let thought=app.staticTexts["aiThought"]
        XCTAssertTrue(thought.waitForExistence(timeout:4))
        XCTAssertTrue(middle.exists)
        XCTAssertGreaterThan(thought.frame.minY,first.frame.minY,"Thought belongs after the first line")
        XCTAssertGreaterThan(middle.frame.minY,thought.frame.minY)
        XCTAssertFalse(app.staticTexts["replyFlowResult"].label.hasPrefix("PASS:"),"Middle phase must arrive before speech finishes")
        let midShot=XCTAttachment(screenshot:app.screenshot());midShot.name="reply-flow-during-voice";midShot.lifetime = .keepAlways;add(midShot)
        XCTAssertTrue(last.waitForExistence(timeout:4))
        let result=app.staticTexts["replyFlowResult"]
        let finished=NSPredicate {_,_ in result.label.hasPrefix("PASS:") || result.label.hasPrefix("FAIL:")}
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:finished,object:nil)],timeout:5),.completed)
        XCTAssertTrue(result.label.hasPrefix("PASS:"),result.label)
        XCTAssertGreaterThan(app.staticTexts["aiNarration"].frame.minY,middle.frame.minY)
        let final=XCTAttachment(screenshot:app.screenshot());final.name="reply-flow-complete";final.lifetime = .keepAlways;add(final)
    }
}
