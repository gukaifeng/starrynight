import XCTest

final class PersonaScenarioTests:XCTestCase {
    @MainActor func testRoleSpecificRoutesEnglishBadgeAndPause() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch();defer{app.terminate()}
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:75))
        for (role,route) in [("lime","lime-greenhouse"),("mafuyu","mafuyu-snow-letter")] {
            app.buttons["tab-discover"].tap()
            let search=app.textFields["discoverSearch"]
            XCTAssertTrue(search.waitForExistence(timeout:8))
            if app.buttons["clearDiscoverSearch"].exists {app.buttons["clearDiscoverSearch"].tap()}
            search.tap();search.typeText(role == "lime" ? "英语" : "真冬")
            let open=app.buttons["discover-open-anime-"+role]
            XCTAssertTrue(open.waitForExistence(timeout:8));open.tap()
            XCTAssertTrue(app.staticTexts["publicCharacterStory"].waitForExistence(timeout:8))
            XCTAssertTrue(app.staticTexts["publicCharacterStory"].label.contains(role == "lime" ? "只说英语" : "26岁"))
            app.buttons["profileChatButton"].tap()
            app.waitForCharacter({$0["modelId"] as? String == "anime-"+role},timeout:60)
            app.buttons["customizationButton"].tap()
            let together=app.buttons["profileTogetherButton"]
            XCTAssertTrue(together.waitForExistence(timeout:8))
            for _ in 0..<4 {if together.isHittable {break};app.swipeUp()}
            together.tap()
            app.segmentedControls["togetherTabs"].buttons["故事"].tap()
            XCTAssertTrue(app.buttons["start-story-"+route].waitForExistence(timeout:8))
            XCTAssertEqual(app.staticTexts["englishOnlyBadge"].exists,role == "lime")
            XCTAssertFalse(app.buttons["start-story-siska-blank-page"].exists)
            let picture=XCTAttachment(screenshot:app.screenshot());picture.name=role+"-scenario-shelf";picture.lifetime = .keepAlways;add(picture)
            app.buttons["start-story-"+route].tap()
            let pause=app.buttons["pause-story-"+route]
            XCTAssertTrue(pause.waitForExistence(timeout:8));pause.tap()
            XCTAssertTrue(app.buttons["start-story-"+route].waitForExistence(timeout:8))
            app.buttons["closeTogetherButton"].tap()
            app.buttons["closeCharacterDetails"].tap()
        }
    }
}
