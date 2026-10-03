import XCTest
final class DeveloperFloatingTests:XCTestCase {
    @MainActor func testFloatingEntryMovesAndOpensTheCurrentCharacter() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--inspector-layout-fixture","--developer-float-check"]
        app.launch();defer {app.terminate()}
        let button=app.buttons["openCharacterDeveloper"]
        XCTAssertTrue(button.waitForExistence(timeout:75))
        let start=button.frame.midY
        let destination=button.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).withOffset(CGVector(dx:-80,dy:110))
        button.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).press(forDuration:0.1,thenDragTo:destination)
        XCTAssertGreaterThan(button.frame.midY,start+40)
        button.tap()
        XCTAssertTrue(app.buttons["openCharacterVoiceTimings"].waitForExistence(timeout:5))
        app.buttons["closeCharacterDeveloper"].tap()
        XCTAssertTrue(button.waitForExistence(timeout:5))
    }
}
