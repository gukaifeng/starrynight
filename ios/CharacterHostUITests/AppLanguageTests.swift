import XCTest

final class AppLanguageTests: XCTestCase {
    @MainActor func testEnglishShellPersistsLanguageWithoutClosingSettings() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing"]
        app.launch();defer{app.terminate()}
        XCTAssertTrue(app.buttons["tab-mine"].waitForExistence(timeout:25));app.buttons["tab-mine"].tap()
        app.buttons["profileSettingsButton"].tap()
        XCTAssertTrue(app.buttons["languageSettingsButton"].waitForExistence(timeout:5));app.buttons["languageSettingsButton"].tap()
        app.buttons["language-en"].tap()
        XCTAssertTrue(app.navigationBars["Language"].waitForExistence(timeout:3))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["closeSettingsButton"].waitForExistence(timeout:3));app.buttons["closeSettingsButton"].tap()
        XCTAssertEqual(app.buttons["tab-messages"].label,"Messages")
        XCTAssertTrue(app.staticTexts["profileAccountID"].label.contains("StarryNight ID:"))
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name="english-profile-shell";shot.lifetime = .keepAlways;add(shot)
        app.terminate();app.launch()
        XCTAssertTrue(app.buttons["tab-messages"].waitForExistence(timeout:25))
        XCTAssertEqual(app.buttons["tab-messages"].label,"Messages")
    }
    @MainActor func testLanguageSwitchAndOfflineStructuredTranslation() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--language-check"]
        app.launch();defer{app.terminate()}
        let result=app.staticTexts["languageCoreResult"]
        XCTAssertTrue(result.waitForExistence(timeout:15));XCTAssertTrue(result.label.hasPrefix("PASS:"),result.label)
        let translate=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'translate-'")).firstMatch
        XCTAssertTrue(translate.waitForExistence(timeout:3));translate.tap()
        XCTAssertTrue(app.staticTexts["assistantMessage"].label.contains("今天过得怎么样"))
        XCTAssertTrue(app.staticTexts["aiThought"].label.contains("安心"))
        XCTAssertTrue(app.staticTexts["aiNarration"].label.contains("挥了挥手"))
        translate.tap();XCTAssertTrue(app.staticTexts["assistantMessage"].label.contains("Good morning"))
        app.buttons["fixtureLanguageSettings"].tap()
        app.buttons["language-en"].tap()
        XCTAssertTrue(app.navigationBars["Language"].waitForExistence(timeout:3))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertEqual(app.staticTexts["localizedTitle"].label,"Messages")
        XCTAssertFalse(translate.exists)
        app.buttons["fixtureLanguageSettings"].tap();app.buttons["language-zh-Hant"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertEqual(app.staticTexts["localizedOriginalLabel"].label,"原文")
        XCTAssertTrue(translate.waitForExistence(timeout:3));translate.tap()
        XCTAssertTrue(app.staticTexts["assistantMessage"].label.contains("今天過得怎麼樣"))
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name="traditional-structured-translation";shot.lifetime = .keepAlways;add(shot)
    }
}
