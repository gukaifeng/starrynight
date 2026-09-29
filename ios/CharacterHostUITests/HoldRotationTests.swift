import XCTest

// Revision 4 opens a saved-view editor; release-to-restore was removed by design.
final class HoldRotationTests:XCTestCase {
    @MainActor func testShortSwipeAndEmptyBackgroundDoNotOpenEditor() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch();XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.waitForCharacter {$0["nativeHoldAvailable"] as? Bool == true}
        let before=app.characterRuntime
        let x=(before["headX"] as? NSNumber)?.doubleValue ?? 0.5
        let y=(before["headY"] as? NSNumber)?.doubleValue ?? 0.3
        app.coordinate(withNormalizedOffset:CGVector(dx:x,dy:y)).press(forDuration:0.2,
            thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.84,dy:y)),withVelocity:.slow,thenHoldForDuration:0.1)
        XCTAssertFalse(app.buttons["closeCharacterViewEditor"].exists)
        app.coordinate(withNormalizedOffset:CGVector(dx:0.98,dy:0.16)).press(forDuration:1.4)
        app.waitForCharacter { ($0["inspectionRejectedCount"] as? NSNumber)?.intValue ?? 0 > 0 }
        XCTAssertFalse(app.buttons["closeCharacterViewEditor"].exists)
        XCTAssertEqual(app.characterRuntime["inspectionHapticCount"] as? Int,before["inspectionHapticCount"] as? Int)
        XCTAssertEqual(app.characterRuntime["inspectionActive"] as? Bool,false)
    }
}
