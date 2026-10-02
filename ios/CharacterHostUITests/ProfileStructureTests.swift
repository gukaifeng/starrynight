import XCTest

final class ProfileStructureTests:XCTestCase {
    @MainActor func testAccountIdentityEditorAndProfileTools() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--profile-page-fixture","-starry.app.language.v1","zh-Hans"]
        app.launch();defer {app.terminate()}
        XCTAssertTrue(app.buttons["tab-mine"].waitForExistence(timeout:15));app.buttons["tab-mine"].tap()
        XCTAssertTrue(app.otherElements["myPage"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["profileAccountID"].label.contains("01993629-8410-7000-8000-000000000001"))
        XCTAssertTrue(app.buttons["profileTool-privacy"].exists);XCTAssertTrue(app.buttons["profileTool-help"].exists)
        app.buttons["accountCenterButton"].tap()
        XCTAssertTrue(app.buttons["editAccountProfile"].waitForExistence(timeout:5));app.buttons["editAccountProfile"].tap()
        XCTAssertTrue(app.textFields["profileNameInput"].waitForExistence(timeout:5))
        XCTAssertEqual(app.textFields["profileNameInput"].value as? String,"小星")
        XCTAssertFalse(app.textFields["immutableAccountID"].exists)
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name="account-profile-editor";shot.lifetime = .keepAlways;add(shot)
    }
    @MainActor func testDiscoveryHasNoFeaturedShelfOrCardAuthor() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","-starry.app.language.v1","zh-Hans"]
        app.launch();defer {app.terminate()}
        XCTAssertTrue(app.buttons["tab-discover"].waitForExistence(timeout:15));app.buttons["tab-discover"].tap()
        XCTAssertTrue(app.otherElements["discoverPage"].waitForExistence(timeout:5))
        XCTAssertFalse(app.otherElements["marketFeaturedShelf"].exists)
        XCTAssertFalse(app.buttons["marketShelf-精选"].exists)
        XCTAssertTrue(app.buttons["marketShelf-全部"].exists)
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name="simplified-discovery";shot.lifetime = .keepAlways;add(shot)
    }
}
