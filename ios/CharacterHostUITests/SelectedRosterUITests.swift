import XCTest

final class SelectedRosterUITests:XCTestCase {
    @MainActor func testSixteenCharactersHaveReadyConversations() throws {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--shell-discover"]
        defer{app.terminate()}
        let names=["Chiffon","Fiona","Hikarun","Ichigo","Koharu","Lime","Mafuyu","Meiyun",
                   "Milfy","Mao","Mizuki","Perula","Plum","Ramune","Shinano","Sio"]
        for name in names {
            let role=name.lowercased()
            app.launch()
            let search=app.textFields["discoverSearch"]
            XCTAssertTrue(search.waitForExistence(timeout:60))
            if app.buttons["clearDiscoverSearch"].exists {app.buttons["clearDiscoverSearch"].tap()}
            search.tap();search.typeText(name+"\n")
            let card=app.buttons["discover-open-anime-"+role]
            XCTAssertTrue(card.waitForExistence(timeout:10));card.tap()
            XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:10));app.buttons["profileChatButton"].tap()
            app.waitForCharacter({$0["modelId"] as? String == "anime-"+role && ($0["stableRenderedFrames"] as? Int ?? 0)>=3},timeout:75)
            XCTAssertFalse(app.staticTexts["localModelPreview"].exists)
            XCTAssertTrue(app.textViews["chatInput"].exists)
            let voice=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","messageVoice-")).firstMatch
            XCTAssertTrue(voice.exists,"Every role needs a bundled first-meeting voice")
            XCTAssertTrue((voice.value as? String ?? "").contains("durationSource:measured"))
            app.buttons["smartReplyButton"].tap()
            for index in 0..<3 {XCTAssertTrue(app.buttons["smartReplyOption-\(index)"].waitForExistence(timeout:5))}
            let image=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
            image.name="ready-companion-"+name;image.lifetime = .keepAlways;add(image)
            app.terminate()
        }
    }
}
