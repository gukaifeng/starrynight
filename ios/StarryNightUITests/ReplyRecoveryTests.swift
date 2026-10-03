import XCTest

/// Uses delayed synthetic SSE and real session/persistence/playback. No AI calls.
final class ReplyRecoveryTests:XCTestCase {
    @MainActor func testBoundedRetryAndResendReuseBubbleWhilePreservingNewDraft() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--resilient-reply-fixture","-starry.app.language.v1","zh-Hans"]
        app.launch();defer{app.terminate()}
        let field=app.textViews["chatInput"]
        XCTAssertTrue(field.waitForExistence(timeout:65))
        func send(_ text:String) {
            field.tap();field.typeText(text)
            XCTAssertEqual(field.value as? String,text,"Verify the fixture input before sending; keyboard corrections must not select a different failure scenario")
            let key=app.keyboards.buttons.matching(NSPredicate(format:"label IN %@",["发送","Send","send"])).firstMatch
            XCTAssertTrue(key.waitForExistence(timeout:5));key.tap()
        }
        send("111")
        let reply=app.staticTexts.matching(identifier:"assistantMessage").matching(NSPredicate(format:"label == %@","这份接话已经收到，我们继续聊。")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout:12),"A transient busy response must recover privately")
        let playing=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'messageVoice-' AND value CONTAINS 'voiceMotion:playing'")).firstMatch
        XCTAssertTrue(playing.waitForExistence(timeout:3),"Validated speech must already be readable while its decoration-only patch is playing")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'resend-'")).firstMatch.exists)
        send("222")
        let retry=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'resend-'")).firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout:8),"Only exhausted bounded retries mark failure")
        field.tap();field.typeText("333")
        XCTAssertEqual(field.value as? String,"333")
        app.buttons["customizationButton"].tap();app.buttons["closeCharacterDetails"].tap()
        retry.tap();XCTAssertTrue(app.alerts["重新发送这条消息？"].waitForExistence(timeout:5))
        app.alerts.buttons["重新发送"].tap()
        let recovered=NSPredicate {_,_ in !retry.exists}
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:recovered,object:nil)],timeout:10),.completed)
        XCTAssertEqual(app.staticTexts.matching(identifier:"userMessage").matching(NSPredicate(format:"label == %@","222")).count,1)
        XCTAssertEqual(field.value as? String,"333")
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="recovered-message-draft-retained";shot.lifetime = .keepAlways;add(shot)
    }
}
