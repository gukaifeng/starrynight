import XCTest

final class ChatKeyboardTests: XCTestCase {
    @MainActor func testNativeInputContractWithoutAIOrUnity() {
        let app = XCUIApplication(); app.launchArguments = ["--chat-input-check"]
        app.launch(); defer { app.terminate() }
        let result = app.staticTexts["chatInputCoreResult"]
        XCTAssertTrue(result.waitForExistence(timeout:15))
        XCTAssertTrue(result.label.hasPrefix("PASS:"),result.label)
        let evidence = XCTAttachment(string:result.label)
        evidence.name = "native-chat-input-contract"; evidence.lifetime = .keepAlways; add(evidence)
    }
    @MainActor func testKeyboardSendAndOutsideDismissalPreserveDraft() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing","--companion-testing","--auth-testing","-starry.app.language.v1","zh-Hans"]
        app.launch(); defer { app.terminate() }
        let input = app.textViews["chatInput"]
        XCTAssertTrue(input.waitForExistence(timeout:65))
        let messages = app.staticTexts.matching(identifier:"userMessage")
        let originalCount = messages.count
        input.tap(); input.typeText("Keyboard send regression")
        let sendKey = app.keyboards.buttons.matching(NSPredicate(format:"label IN %@",["发送","Send","send"])).firstMatch
        XCTAssertTrue(sendKey.waitForExistence(timeout:5),"The software keyboard must show Send")
        sendKey.tap()
        let sent = messages.matching(NSPredicate(format:"label == %@","Keyboard send regression")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout:8))
        XCTAssertEqual(messages.count,originalCount+1)
        // A disabled paid transport exercises the real failed-bubble path.
        XCTAssertTrue(app.staticTexts["自动测试已关闭付费 AI 调用。"].waitForExistence(timeout:5))
        XCTAssertNotEqual(input.value as? String,"Keyboard send regression")
        let resend=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'resend-'")).firstMatch
        XCTAssertTrue(resend.waitForExistence(timeout:5))
        input.tap();input.typeText("New unsent draft")
        app.buttons["customizationButton"].tap()
        XCTAssertTrue(app.buttons["closeCharacterDetails"].waitForExistence(timeout:5));app.buttons["closeCharacterDetails"].tap()
        resend.tap();XCTAssertTrue(app.alerts["重新发送这条消息？"].waitForExistence(timeout:5))
        app.alerts.buttons["重新发送"].tap()
        XCTAssertTrue(resend.waitForExistence(timeout:5))
        XCTAssertEqual(messages.count,originalCount+1,"Resend must reuse the failed bubble")
        XCTAssertEqual(input.value as? String,"New unsent draft","Retry must preserve a newly typed draft")

        // A fresh isolated journal keeps the draft scenario independent of the
        // deliberately failed send and the insertion point of its restored text.
        app.terminate();app.launch();XCTAssertTrue(input.waitForExistence(timeout:65))
        let draftMessageCount=messages.count
        input.tap();input.typeText("Keep this draft")
        app.buttons["customizationButton"].tap()
        let keyboardHidden = NSPredicate { _,_ in !app.keyboards.firstMatch.exists }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:keyboardHidden,object:nil)],timeout:6),.completed)
        XCTAssertTrue(app.buttons["closeCharacterDetails"].waitForExistence(timeout:5))
        app.buttons["closeCharacterDetails"].tap()
        XCTAssertEqual(input.value as? String,"Keep this draft")
        input.tap(); input.typeText("\n")
        let second = messages.matching(NSPredicate(format:"label == %@","Keep this draft")).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout:8),"Return must use the same send path after reopening the keyboard")
        XCTAssertEqual(messages.count,draftMessageCount+1)
        XCTAssertNotEqual(input.value as? String,"Keep this draft","Sent text stays in its failed bubble instead of being restored into the composer")
    }
}
