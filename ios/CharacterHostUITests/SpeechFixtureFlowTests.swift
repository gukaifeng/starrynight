import XCTest

final class SpeechFixtureFlowTests: XCTestCase {
    @MainActor func testActualASRToEditableDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--preview-companion","--voice-fixture"]
        app.launch()
        let fixture = app.buttons["recognizeFixtureButton"]
        XCTAssertTrue(fixture.waitForExistence(timeout:45)); fixture.tap()
        let input = app.textFields["chatInput"]
        expectation(for:NSPredicate(format:"value CONTAINS %@","时间"),evaluatedWith:input)
        waitForExpectations(timeout:45)
        XCTAssertFalse(app.staticTexts.matching(identifier:"assistantMessage").firstMatch.exists,"Recognition must not auto-send")
        capture("11-real-asr-editable-draft")
        let original = input.value as? String ?? ""
        input.tap(); input.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:original.count)+"你好")
        app.buttons["sendMessageButton"].tap()
        XCTAssertTrue(app.staticTexts.matching(identifier:"assistantMessage").firstMatch.waitForExistence(timeout:15))
        if app.buttons["stopSpeechButton"].exists { app.buttons["stopSpeechButton"].tap() }
        capture("12-asr-user-confirmed")
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
