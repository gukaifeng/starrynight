import XCTest
final class SpeechPlaybackTests: XCTestCase {
    @MainActor func testActualSpeechPlaybackAndStop() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing","--companion-testing","--preview-companion","--preview-miku"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:45))
        expectation(for:NSPredicate(format:"label CONTAINS %@","已就绪"),evaluatedWith:app.staticTexts["speechStatus"])
        waitForExpectations(timeout:20)
        app.buttons["你好"].tap()
        expectation(for:NSPredicate(format:"value MATCHES %@","audioSegments:[1-9][0-9]*"),evaluatedWith:app.staticTexts["speechStatus"])
        waitForExpectations(timeout:80)
        let capture = XCTAttachment(screenshot:XCUIScreen.main.screenshot());capture.name="real-audio-playback";capture.lifetime = .keepAlways;add(capture)
        if !app.buttons["stopSpeechButton"].exists { app.messageAction("readMessageButton") }
        app.buttons["stopSpeechButton"].tap()
        XCTAssertFalse(app.buttons["stopSpeechButton"].exists)
    }
}
