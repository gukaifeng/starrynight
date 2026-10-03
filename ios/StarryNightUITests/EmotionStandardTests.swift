import XCTest
final class EmotionStandardTests:XCTestCase {
    private func motion(_ state:[String:Any])->[String:Any] { (state["characterPlatform"] as? [String:Any])?["hostEmotionMotion"] as? [String:Any] ?? [:] }
    @MainActor func testOpeningAndPerCharacterStandardMappings() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","-starry.app.language.v1","zh-Hans","-hostEmotionMotionEnabled.v1","YES","-hostEmotionMotionSpeechLinked.v3","NO"]
        app.launch();defer{app.terminate()}
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:75))
        app.waitForCharacter({(self.motion($0)["standardEmotion"] as? String ?? "").isEmpty==false && (self.motion($0)["peakDegrees"] as? Double ?? 0)>1},timeout:40)
        XCTAssertTrue((motion(app.characterRuntime)["gesture"] as? String ?? "").contains("emotion."))
        app.openCharacterDeveloper();XCTAssertTrue(app.buttons["openEmotionStandard"].waitForExistence(timeout:10));app.buttons["openEmotionStandard"].tap()
        XCTAssertTrue(app.scrollViews["emotionStandardPanel"].waitForExistence(timeout:10))
        let mapping=app.staticTexts["emotionStandardMappingSummary"]
        XCTAssertTrue(mapping.waitForExistence(timeout:10))
        let loaded=NSPredicate(format:"label == %@","已匹配 42 项")
        expectation(for:loaded,evaluatedWith:mapping);waitForExpectations(timeout:12)
        let image=XCTAttachment(screenshot:app.screenshot());image.name="emotion-standard-character-mapping";image.lifetime = .keepAlways;add(image)
        let search=app.textFields["emotionStandardSearch"];XCTAssertTrue(search.isHittable);search.tap();search.typeText("neutral\n")
        let button=app.buttons["standardPreview-emotion.neutral.1"];XCTAssertTrue(button.waitForExistence(timeout:5));XCTAssertTrue(button.isEnabled);button.tap()
        app.waitForCharacter({self.motion($0)["gesture"] as? String=="emotion.neutral.1"},timeout:10)
        for (category,query,id) in [("发声风格 7","whisper","style.whisper.1"),("拟声 7","giggle","vocal.giggle.1")] {
            app.segmentedControls["emotionStandardKind"].buttons[category].tap()
            search.tap();search.typeText(query+"\n")
            let preview=app.buttons["standardPreview-"+id];XCTAssertTrue(preview.waitForExistence(timeout:5));XCTAssertTrue(preview.isEnabled);preview.tap()
            app.waitForCharacter({self.motion($0)["gesture"] as? String==id},timeout:12)
        }
        app.buttons["closeEmotionStandard"].tap()
    }
}
