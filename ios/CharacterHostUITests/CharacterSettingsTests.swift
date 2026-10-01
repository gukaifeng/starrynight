import XCTest

final class CharacterSettingsTests:XCTestCase {
    @MainActor func testPublicPersonaAndCompleteTestInspector() throws {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch();defer {app.terminate()}
        let capsule=app.buttons["customizationButton"]
        XCTAssertTrue(capsule.waitForExistence(timeout:65));capsule.tap()
        XCTAssertTrue(app.staticTexts["publicCharacterTraits"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["publicCharacterStory"].exists)
        XCTAssertTrue(app.descendants(matching:.any)["publicCharacterLikes"].exists)
        let publicShot=XCTAttachment(screenshot:app.screenshot());publicShot.name="public-character-card";publicShot.lifetime = .keepAlways;add(publicShot)
        let button=app.buttons["openAIInspector"]
#if STARRY_TEST_TOOLS
        app.openCharacterDeveloper()
        let scroll=app.scrollViews.firstMatch
        for _ in 0..<5 where !button.isHittable {scroll.swipeUp()}
        XCTAssertTrue(button.isHittable);button.tap()
        XCTAssertTrue(app.buttons["aiInspectionSection-persona"].waitForExistence(timeout:20))
        app.buttons["aiInspectionSection-persona"].tap()
        let persona=app.staticTexts["aiInspectionContent-persona"]
        XCTAssertTrue(persona.waitForExistence(timeout:20),app.staticTexts["aiInspectorError"].exists ? app.staticTexts["aiInspectorError"].label : "No complete persona")
        XCTAssertTrue(persona.label.contains("voice_prompt"));XCTAssertTrue(persona.label.contains("secrets"))
        app.buttons["closeAIInspectionSection"].tap()
        XCTAssertTrue(app.buttons["copyAllAISettings"].isEnabled)
        app.buttons["copyAllAISettings"].tap()
        XCTAssertEqual(app.buttons["copyAllAISettings"].value as? String,"已复制")
        let search=app.textFields["aiSettingsSearch"];search.tap();search.typeText("完整规划请求\n")
        let row=app.descendants(matching:.any).matching(identifier:"aiInspectionSection-payload").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout:5));row.tap()
        let payload=app.staticTexts["aiInspectionContent-payload"]
        XCTAssertTrue(payload.waitForExistence(timeout:5));XCTAssertTrue(payload.label.contains("JSON Schema"))
        XCTAssertTrue(payload.label.contains("response_format"))
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="complete-ai-settings";shot.lifetime = .keepAlways;add(shot)
#else
        XCTAssertFalse(button.exists,"Public builds must have no AI inspector entry")
#endif
    }
}
