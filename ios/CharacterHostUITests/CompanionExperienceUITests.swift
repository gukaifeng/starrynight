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
    @MainActor func testStoryChoicesPersistAndPanelsKeepCamera() {
        let app=launch()
        let camera=app.characterRuntime
        openTogether(app);capture("01-together-stories",app)
        tap(app,"start-story-rain-letter")
        XCTAssertTrue(app.staticTexts["activeStoryText"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["activeStoryText"].label.contains("没署名的信"))
        sameCamera(app,camera)
        tap(app,"story-choice-read")
        XCTAssertTrue(app.staticTexts["activeStoryText"].label.contains("空白车票"))
        capture("02-story-branch",app);sameCamera(app,camera)
        closeTogether(app)
        XCTAssertTrue(app.staticTexts.matching(identifier:"userMessage").allElementsBoundByIndex.contains { $0.label == "一起拆开信" })
        app.terminate()
        app.launchArguments=["--ui-testing","--companion-testing","--keep-companion-data","--keep-auth-data"]
        app.launch();XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.waitForCharacter { $0["modelId"] as? String == "real-woman" && $0["framingMotionActive"] as? Bool == false }
        let restoredCamera=app.characterRuntime
        openTogether(app)
        XCTAssertTrue(app.staticTexts["activeStoryText"].label.contains("空白车票"))
        tap(app,"story-choice-reply")
        XCTAssertTrue(app.staticTexts["activeStoryText"].label.contains("陌生人的愿望"))
        sameCamera(app,restoredCamera);capture("03-story-ending",app)
        app.segmentedControls["togetherTabs"].buttons["时光"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","送给明天的回信")).firstMatch.exists)
        capture("04-shared-journal",app);sameCamera(app,restoredCamera)
        closeTogether(app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","messageVoice-")).count > 0)
        sameCamera(app,restoredCamera)
    }

    @MainActor func testPreferencesMemoryJournalAndCloudPreviews() {
        let app=launch();openTogether(app)
        app.segmentedControls["togetherTabs"].buttons["相处"].tap()
        let nickname=app.descendants(matching:.any)["togetherNickname"].firstMatch
        nickname.tap();nickname.typeText("小北")
        closeTogether(app);openTogether(app)
        app.segmentedControls["togetherTabs"].buttons["相处"].tap()
        XCTAssertEqual(app.descendants(matching:.any)["togetherNickname"].firstMatch.value as? String,"小北")
        app.segmentedControls["togetherResponseStyle"].buttons["一起想办法"].tap()
        capture("05-relationship",app)
        closeTogether(app)
        let input=app.textFields["chatInput"]
        input.tap();input.typeText("我喜欢安静的海边")
        app.buttons["sendMessageButton"].tap()
        app.waitForReply()
        openTogether(app)
        app.segmentedControls["togetherTabs"].buttons["相处"].tap()
        tap(app,"togetherMemoryButton")
        tap(app,"acceptMemorySuggestion")
        XCTAssertFalse(app.buttons["acceptMemorySuggestion"].exists)
        XCTAssertTrue(app.buttons["editMemoryButton"].exists)
        capture("06-confirmed-memory",app)
        app.buttons["closeMemoryButton"].tap()
        app.segmentedControls["togetherTabs"].buttons["时光"].tap()
        app.segmentedControls["momentMood"].buttons["开心"].tap()
        tap(app,"saveMomentButton")
        capture("07-moment-after-save",app)
        XCTAssertTrue(app.buttons["deleteMomentButton"].waitForExistence(timeout:5))
        capture("07-moment-checkin",app)
        app.segmentedControls["togetherTabs"].buttons["更多"].tap()
        let camera=app.characterRuntime
        for feature in ["voice","vision","sync","community"] {
            tap(app,"cloud-feature-"+feature)
            XCTAssertTrue(app.buttons["cloudUnavailableButton"].waitForExistence(timeout:5))
            XCTAssertFalse(app.buttons["cloudUnavailableButton"].isEnabled)
            XCTAssertEqual(app.alerts.count,0)
            sameCamera(app,camera);capture("08-preview-"+feature,app)
            app.buttons["closeCloudPreview"].tap()
            XCTAssertTrue(app.segmentedControls["togetherTabs"].waitForExistence(timeout:5))
        }
        closeTogether(app)
        app.buttons["tab-discover"].tap()
        app.buttons["discover-校园"].tap()
        XCTAssertTrue(app.buttons["discover-open-hatsune-miku"].exists)
        XCTAssertFalse(app.buttons["discover-open-real-woman"].exists)
        capture("09-discovery-category",app)
    }

    @MainActor private func launch() -> XCUIApplication {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--shell-discover"]
        app.launch();XCTAssertTrue(app.buttons["discover-open-real-woman"].waitForExistence(timeout:25))
        app.buttons["discover-open-real-woman"].tap()
        XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:6));app.buttons["profileChatButton"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.waitForCharacter { $0["modelId"] as? String == "real-woman" && $0["framingMotionActive"] as? Bool == false }
        return app
    }
    @MainActor private func openTogether(_ app:XCUIApplication) {
        app.buttons["customizationButton"].tap()
        XCTAssertTrue(app.buttons["profileTogetherButton"].waitForExistence(timeout:6))
        app.buttons["profileTogetherButton"].tap()
        XCTAssertTrue(app.segmentedControls["togetherTabs"].waitForExistence(timeout:5))
    }
    @MainActor private func closeTogether(_ app:XCUIApplication) {
        app.buttons["closeTogetherButton"].tap()
        XCTAssertTrue(app.buttons["closeCharacterDetails"].waitForExistence(timeout:5))
        app.buttons["closeCharacterDetails"].tap()
        XCTAssertTrue(app.textFields["chatInput"].waitForExistence(timeout:5))
    }
    @MainActor private func tap(_ app:XCUIApplication,_ id:String) {
        let button=app.buttons[id].firstMatch
        let scroll=app.scrollViews.firstMatch
        for _ in 0..<6 {
            if button.isHittable { break }
            scroll.coordinate(withNormalizedOffset:CGVector(dx:0.93,dy:0.85)).press(forDuration:0.05,
                thenDragTo:scroll.coordinate(withNormalizedOffset:CGVector(dx:0.93,dy:0.15)))
        }
        XCTAssertTrue(button.isHittable,id);button.tap()
    }
    @MainActor private func sameCamera(_ app:XCUIApplication,_ expected:[String:Any]) {
        app.waitForCharacter { $0["distance"] is NSNumber }
        let actual=app.characterRuntime
        for key in ["distance","framingSize","framingAngle","pitch","yaw","cameraFov"] {
            XCTAssertEqual((actual[key] as? NSNumber)?.doubleValue ?? -1,(expected[key] as? NSNumber)?.doubleValue ?? -2,accuracy:0.0001,key)
        }
        XCTAssertEqual(actual["framingMotionActive"] as? Bool,false)
    }
    @MainActor private func capture(_ name:String,_ app:XCUIApplication) {
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
        if app.buttons["customizationButton"].exists,
           let data=try? JSONSerialization.data(withJSONObject:app.characterRuntime,options:[.prettyPrinted,.sortedKeys]) {
            let attachment=XCTAttachment(data:data,uniformTypeIdentifier:"public.json");attachment.name=name+"-runtime";attachment.lifetime = .keepAlways;add(attachment)
        }
    }
}
