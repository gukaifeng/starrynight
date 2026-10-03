import XCTest

final class ConversationPresentationTests: XCTestCase {
    @MainActor func testLoadingAndGrowingReplyStayAtMeasuredBottom() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--conversation-presentation-check","-starry.app.language.v1","zh-Hans"]
        app.launch();defer {app.terminate()}
        let scroll=app.scrollViews["chatMessages"]
        XCTAssertTrue(scroll.waitForExistence(timeout:20))
        func wait(_ condition:@escaping ()->Bool) {
            let outcome=XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in condition() },object:nil)],timeout:8)
            if outcome != .completed {
                let shot=XCTAttachment(screenshot:app.screenshot());shot.name="bottom-follow-failure";shot.lifetime = .keepAlways;add(shot)
                print("SCROLL",scroll.frame,scroll.value ?? "nil")
                print("LAST",app.staticTexts.matching(NSPredicate(format:"identifier == 'assistantMessage' AND label CONTAINS '第8段'")).firstMatch.frame)
            }
            XCTAssertEqual(outcome,.completed)
        }
        app.buttons["fixtureHistory"].tap()
        wait {(scroll.value as? String)=="历史消息"}
        // Loading alone, without inserting a user or assistant message, must
        // switch out of the old search window and reveal the actual spinner.
        app.buttons["fixtureLoading"].tap()
        let spinner=app.images["streamingReply"]
        wait {spinner.isHittable && (scroll.value as? String)=="最新消息"}
        XCTAssertLessThanOrEqual(spinner.frame.maxY,scroll.frame.maxY)
        XCTAssertLessThan(scroll.frame.maxY-spinner.frame.maxY,40)
        app.buttons["fixtureGrowth"].tap()
        wait {app.staticTexts["presentationContentResult"].label=="growth-complete"}
        let last=app.staticTexts.matching(NSPredicate(format:"identifier == 'assistantMessage' AND label CONTAINS '第8段'")).firstMatch
        // The last text has 12pt of bubble padding plus the 28pt bottom target.
        wait {last.exists && abs(scroll.frame.maxY-last.frame.maxY)<=42 && (scroll.value as? String)=="最新消息"}
        XCTAssertFalse(app.buttons["returnLatestButton"].exists)
        // Manual history reading still works until another content event.
        scroll.swipeDown()
        wait {(scroll.value as? String)=="历史消息"}
        app.buttons["fixtureLoading"].tap()
        wait {spinner.isHittable && (scroll.value as? String)=="最新消息"}
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="loading-follows-measured-bottom";shot.lifetime = .keepAlways;add(shot)
    }
    @MainActor func testNewMessagesAndLateNarrationReturnFromHistory() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--conversation-presentation-check","-starry.app.language.v1","zh-Hans"]
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
