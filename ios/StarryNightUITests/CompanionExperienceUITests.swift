import XCTest

final class CompanionExperienceUITests:XCTestCase {
    @MainActor func testCoreContractInIOSRuntime() {
        let app=XCUIApplication();app.launchArguments=["--experience-core-check"]
        app.launch()
        let result=app.staticTexts["experienceCoreResult"]
        XCTAssertTrue(result.waitForExistence(timeout:25))
        XCTAssertTrue(result.label.hasPrefix("PASS:"),result.label)
        let attachment=XCTAttachment(string:result.label);attachment.name="core-contract-result";attachment.lifetime = .keepAlways;add(attachment)
    }
}
