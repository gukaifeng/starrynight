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
        let userTranslate=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'translateUser-'")).firstMatch
        XCTAssertTrue(userTranslate.exists);userTranslate.tap()
        XCTAssertTrue(app.staticTexts["userMessage"].label.contains("我很想听听"));userTranslate.tap()
        app.buttons["smartReplyButton"].tap()
        let suggestionTranslate=app.buttons["translateSuggestion-language-0"]
        XCTAssertTrue(suggestionTranslate.waitForExistence(timeout:3));suggestionTranslate.tap()
        XCTAssertEqual(app.buttons["smartReplyOption-0"].label,"说说你的花园吧。")
        suggestionTranslate.tap();XCTAssertEqual(app.buttons["smartReplyOption-0"].label,"Tell me about your garden.")
        // A bubble/control outside the panel closes it without swallowing that
        // control's own translation action. This fixture needs no Unity bridge.
        userTranslate.tap()
        XCTAssertTrue(app.otherElements["smartRepliesPanel"].waitForNonExistence(timeout:3))
        XCTAssertTrue(app.staticTexts["userMessage"].label.contains("我很想听听"))
        app.buttons["smartReplyButton"].tap()
        app.buttons["fixtureLanguageSettings"].tap()
        app.buttons["language-en"].tap()
        XCTAssertTrue(app.navigationBars["Language"].waitForExistence(timeout:3))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertFalse(app.otherElements["smartRepliesPanel"].exists)
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
