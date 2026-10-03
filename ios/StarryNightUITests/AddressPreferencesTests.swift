import XCTest

final class AddressPreferencesTests:XCTestCase {
    @MainActor func testGlobalDefaultRoleOverrideAndInheritance() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--auth-testing","-starry.app.language.v1","zh-Hans"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["tab-mine"].waitForExistence(timeout:75))
        openDefault(app)
        let input = app.textFields["defaultNicknameInput"]
        XCTAssertTrue(input.waitForExistence(timeout:8));input.tap();input.typeText("Sky")
        app.buttons["closeDefaultNicknameButton"].tap()
        app.buttons["defaultNicknameSettingsButton"].tap()
        XCTAssertEqual(input.value as? String,"Sky")
        capture(app,"global-default-nickname")
        app.buttons["closeDefaultNicknameButton"].tap()
        app.buttons["closeSettingsButton"].tap()
        app.buttons["tab-home"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:65))
        app.buttons["customizationButton"].tap()
        openRelationship(app)
        XCTAssertTrue(app.staticTexts["roleNicknamePreview"].label.contains("Sky"))
        let role = app.textFields["togetherNickname"]
        XCTAssertTrue(role.waitForExistence(timeout:8));role.tap();role.typeText("Captain")
        app.buttons["closeTogetherButton"].tap()
        openRelationship(app)
        XCTAssertTrue(app.staticTexts["roleNicknamePreview"].label.contains("Captain"))
        capture(app,"character-specific-nickname")
        app.buttons["inheritDefaultNickname"].tap()
        XCTAssertTrue(app.staticTexts["roleNicknamePreview"].label.contains("Sky"))
        app.buttons["closeTogetherButton"].tap()
        app.buttons["closeCharacterDetails"].tap()
        app.terminate()
        app.launchArguments += ["--keep-companion-data","--keep-auth-data"]
        app.launch();openDefault(app)
        XCTAssertEqual(input.value as? String,"Sky")
        app.buttons["clearDefaultNickname"].tap()
        app.buttons["closeDefaultNicknameButton"].tap()
        app.buttons["defaultNicknameSettingsButton"].tap()
        XCTAssertTrue(app.staticTexts["defaultNicknamePreview"].label.contains("留空"))
    }
    @MainActor private func openDefault(_ app:XCUIApplication) {
        XCTAssertTrue(app.buttons["tab-mine"].waitForExistence(timeout:65));app.buttons["tab-mine"].tap()
        app.buttons["profileSettingsButton"].tap()
        XCTAssertTrue(app.buttons["defaultNicknameSettingsButton"].waitForExistence(timeout:8))
        app.buttons["defaultNicknameSettingsButton"].tap()
    }
    @MainActor private func openRelationship(_ app:XCUIApplication) {
        let open = app.buttons["profileTogetherButton"]
        XCTAssertTrue(open.waitForExistence(timeout:8))
        for _ in 0..<4 { if open.isHittable { break }; app.swipeUp() }
        open.tap()
        XCTAssertTrue(app.segmentedControls["togetherTabs"].waitForExistence(timeout:8))
        app.segmentedControls["togetherTabs"].buttons["相处"].tap()
        XCTAssertTrue(app.staticTexts["roleNicknamePreview"].waitForExistence(timeout:8))
    }
    @MainActor private func capture(_ app:XCUIApplication,_ name:String) {
        let item = XCTAttachment(screenshot:app.screenshot());item.name=name;item.lifetime = .keepAlways;add(item)
    }
}
