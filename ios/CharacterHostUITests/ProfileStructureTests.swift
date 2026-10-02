import XCTest

final class ProfileStructureTests:XCTestCase {
    @MainActor func testAccountIdentityEditorAndProfileTools() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--profile-page-fixture","-starry.app.language.v1","zh-Hans"]
        app.launch();defer {app.terminate()}
        XCTAssertTrue(app.buttons["tab-mine"].waitForExistence(timeout:15));app.buttons["tab-mine"].tap()
        XCTAssertTrue(app.otherElements["myPage"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["profileAccountID"].label.contains("xy100000001"))
        XCTAssertEqual(app.staticTexts["profileBio"].label,"收藏日常里的温柔")
        XCTAssertTrue(app.buttons["profileTool-privacy"].exists);XCTAssertTrue(app.buttons["profileTool-help"].exists)
        app.buttons["accountCenterButton"].tap()
        XCTAssertTrue(app.buttons["editAccountProfile"].waitForExistence(timeout:5));app.buttons["editAccountProfile"].tap()
        XCTAssertTrue(app.textFields["profileNameInput"].waitForExistence(timeout:5))
        XCTAssertEqual(app.textFields["profileNameInput"].value as? String,"小星")
        XCTAssertFalse(app.textFields["immutableAccountID"].exists)
        XCTAssertTrue(app.buttons["chooseAccountPhoto"].exists)
        XCTAssertFalse(app.buttons["saveAccountProfile"].exists)
        XCTAssertTrue(app.buttons["avatar-starry-orbit-v1"].exists)
        XCTAssertFalse(app.buttons["avatar-starry-cat-v1"].exists)
        XCTAssertFalse(app.buttons["avatar-starry-bunny-v1"].exists)
        app.buttons["avatar-starry-orbit-v1"].tap()
        let name=app.textFields["profileNameInput"]
        replaceProfileName(name,with:"Nova")
        // Leave immediately: dismissal flushes the pending debounce without a
        // save button. Reopening must read the updated account profile.
        app.navigationBars.buttons.element(boundBy:0).tap()
        app.buttons["editAccountProfile"].tap()
        XCTAssertTrue(name.waitForExistence(timeout:5))
        XCTAssertEqual(name.value as? String,"Nova")
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name="account-profile-editor";shot.lifetime = .keepAlways;add(shot)
    }
    @MainActor func testUnifiedNicknamePageSavesRolePriorityAndInheritance() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--profile-page-fixture","-starry.app.language.v1","zh-Hans"]
        app.launch();defer{app.terminate()}
        XCTAssertTrue(app.buttons["tab-mine"].waitForExistence(timeout:15));app.buttons["tab-mine"].tap()
        app.buttons["profileSettingsButton"].tap();app.buttons["defaultNicknameSettingsButton"].tap()
        let global=app.textFields["defaultNicknameInput"]
        let role=app.textFields.matching(NSPredicate(format:"identifier BEGINSWITH %@","roleNicknameInput-")).firstMatch
        XCTAssertTrue(global.waitForExistence(timeout:5));global.tap();global.typeText("Sky")
        XCTAssertTrue(role.exists)
        let effective=app.staticTexts["nicknameEffective-"+String(role.identifier.dropFirst("roleNicknameInput-".count))]
        for _ in 0..<3 {if role.isHittable {break};app.scrollViews.firstMatch.swipeUp()}
        role.tap();role.typeText("Captain")
        XCTAssertTrue(effective.label.contains("Captain"))
        app.buttons["closeDefaultNicknameButton"].tap();app.buttons["defaultNicknameSettingsButton"].tap()
        XCTAssertEqual(global.value as? String,"Sky");XCTAssertEqual(role.value as? String,"Captain")
        role.tap();role.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:7))
        XCTAssertTrue(effective.label.contains("Sky"))
        app.buttons["closeDefaultNicknameButton"].tap();app.buttons["defaultNicknameSettingsButton"].tap()
        XCTAssertTrue(effective.label.contains("Sky"))
    }
    @MainActor func testNicknameAndAIAddressAreEditedIndependently() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--profile-page-fixture","-starry.app.language.v1","zh-Hans"]
        app.launch();defer{app.terminate()}
        XCTAssertTrue(app.buttons["tab-mine"].waitForExistence(timeout:15));app.buttons["tab-mine"].tap()
        XCTAssertEqual(app.staticTexts["profileNickname"].label,"小星")
        XCTAssertTrue(app.staticTexts["profileAccountID"].label.contains("xy100000001"))
        app.buttons["profileAddressButton"].tap()
        let address=app.textFields["defaultNicknameInput"]
        XCTAssertTrue(address.waitForExistence(timeout:5));address.tap();address.typeText("Sky")
        app.buttons["closeDefaultNicknameButton"].tap()
        XCTAssertEqual(app.staticTexts["profileNickname"].label,"小星")
        XCTAssertEqual(app.staticTexts["profileDefaultAddress"].label,"Sky")
        app.buttons["accountCenterButton"].tap();app.buttons["editAccountProfile"].tap()
        let name=app.textFields["profileNameInput"]
        XCTAssertTrue(name.waitForExistence(timeout:5));replaceProfileName(name,with:"Nova")
        app.navigationBars.buttons.element(boundBy:0).tap();app.buttons["closeAccountButton"].tap()
        let renamed=app.staticTexts.matching(identifier:"profileNickname").matching(NSPredicate(format:"label == %@","Nova")).firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["profileDefaultAddress"].label,"Sky")
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name="minimal-profile-independent-names";shot.lifetime = .keepAlways;add(shot)
        app.buttons["profileAddressButton"].tap()
        XCTAssertEqual(address.value as? String,"Sky")
    }
    @MainActor func testProfileInEnglishAndGuestLayout() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--profile-page-fixture","-starry.app.language.v1","en"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-mine"].waitForExistence(timeout:15));app.buttons["tab-mine"].tap()
        XCTAssertTrue(app.buttons["profileAddressButton"].isHittable)
        XCTAssertTrue(app.buttons["profileTool-help"].isHittable)
        let english=XCTAttachment(screenshot:XCUIScreen.main.screenshot());english.name="minimal-profile-english";english.lifetime = .keepAlways;add(english)
        app.terminate();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","-starry.app.language.v1","zh-Hans"]
        app.launch();defer{app.terminate()}
        app.buttons["tab-mine"].tap()
        XCTAssertEqual(app.staticTexts["profileNickname"].label,"初来星夜")
        XCTAssertTrue(app.buttons["profileAddressButton"].isHittable)
        let guest=XCTAttachment(screenshot:XCUIScreen.main.screenshot());guest.name="minimal-profile-guest";guest.lifetime = .keepAlways;add(guest)
        app.buttons["accountCenterButton"].tap()
        XCTAssertTrue(app.buttons["signInButton"].waitForExistence(timeout:5))
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
    @MainActor private func replaceProfileName(_ field:XCUIElement,with value:String) {
        let count=(field.value as? String ?? "").count
        field.tap()
        // The standard profile row is right-aligned. Place the cursor at the
        // text end before deleting; a center tap can place it before the name.
        field.coordinate(withNormalizedOffset:CGVector(dx:0.98,dy:0.5)).tap()
        field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:count)+value)
    }
}
