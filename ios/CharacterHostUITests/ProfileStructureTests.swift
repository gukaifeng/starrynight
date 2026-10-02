import XCTest

final class ProfileStructureTests:XCTestCase {
    @MainActor func testAccountIdentityEditorAndProfileTools() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--profile-page-fixture","-starry.app.language.v1","zh-Hans"]
        app.launch();defer {app.terminate()}
        XCTAssertTrue(app.buttons["tab-mine"].waitForExistence(timeout:15));app.buttons["tab-mine"].tap()
        XCTAssertTrue(app.otherElements["myPage"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["profileAccountID"].label.contains("xy1"))
        XCTAssertEqual(app.staticTexts["profileBio"].label,"收藏日常里的温柔")
        XCTAssertTrue(app.buttons["profileTool-privacy"].exists);XCTAssertTrue(app.buttons["profileTool-help"].exists)
        app.buttons["accountCenterButton"].tap()
        XCTAssertTrue(app.buttons["editAccountProfile"].waitForExistence(timeout:5));app.buttons["editAccountProfile"].tap()
        XCTAssertTrue(app.textFields["profileNameInput"].waitForExistence(timeout:5))
        XCTAssertEqual(app.textFields["profileNameInput"].value as? String,"小星")
        XCTAssertFalse(app.textFields["immutableAccountID"].exists)
        XCTAssertTrue(app.buttons["chooseAccountPhoto"].exists)
        XCTAssertTrue(app.buttons["avatar-starry-orbit-v1"].exists)
        XCTAssertFalse(app.buttons["avatar-starry-cat-v1"].exists)
        XCTAssertFalse(app.buttons["avatar-starry-bunny-v1"].exists)
        app.buttons["avatar-starry-orbit-v1"].tap()
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name="account-profile-editor";shot.lifetime = .keepAlways;add(shot)
    }
    @MainActor func testUnifiedNicknamePageSavesRolePriorityAndInheritance() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--profile-page-fixture","-starry.app.language.v1","zh-Hans"]
        app.launch();defer{app.terminate()}
        XCTAssertTrue(app.buttons["tab-mine"].waitForExistence(timeout:15));app.buttons["tab-mine"].tap()
        app.buttons["profileSettingsButton"].tap();app.buttons["defaultNicknameSettingsButton"].tap()
        let global=app.textFields["defaultNicknameInput"],role=app.textFields["roleNicknameInput-anime-kipfel"]
        XCTAssertTrue(global.waitForExistence(timeout:5));global.tap();global.typeText("Sky")
        XCTAssertTrue(role.exists)
        for _ in 0..<3 {if role.isHittable {break};app.scrollViews.firstMatch.swipeUp()}
        role.tap();role.typeText("Captain")
        XCTAssertTrue(app.staticTexts["nicknameEffective-anime-kipfel"].label.contains("Captain"))
        app.buttons["closeDefaultNicknameButton"].tap();app.buttons["defaultNicknameSettingsButton"].tap()
        XCTAssertEqual(global.value as? String,"Sky");XCTAssertEqual(role.value as? String,"Captain")
        role.tap();role.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:7))
        XCTAssertTrue(app.staticTexts["nicknameEffective-anime-kipfel"].label.contains("Sky"))
        app.buttons["closeDefaultNicknameButton"].tap();app.buttons["defaultNicknameSettingsButton"].tap()
        XCTAssertTrue(app.staticTexts["nicknameEffective-anime-kipfel"].label.contains("Sky"))
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
