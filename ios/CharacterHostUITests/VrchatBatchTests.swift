import XCTest

/// Exercises actual native-to-Unity controls and eviction/reload across old and
/// new character packages. No paid AI request is enabled by these launch flags.
final class VrchatBatchTests:XCTestCase {
    @MainActor func testBatchOneControlsAndMixedRosterReload() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:70))
        app.waitForCharacter { $0["modelId"] as? String == "anime-kipfel" }
        // Five switches force eviction and reloading, including the default
        // character that was originally embedded in the player scene.
        for role in ["anime-chiffon","anime-karin","anime-mamehinata","anime-kipfel","anime-chiffon"] {
            app.buttons["tab-discover"].tap()
            let card=app.buttons["discover-open-"+role]
            XCTAssertTrue(card.waitForExistence(timeout:10));card.tap()
            XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:8))
            app.buttons["profileChatButton"].tap()
            app.waitForCharacter({ $0["modelId"] as? String == role && $0["idlePlaying"] as? Bool == true },timeout:45)
            capture(role+"-conversation",app)
            let value=app.buttons["conversationSoundButton"].value as? String ?? "{}"
            let audio=(try? JSONSerialization.jsonObject(with:Data(value.utf8))) as? [String:Any] ?? [:]
            XCTAssertEqual(audio["collectionScope"] as? String,role)
            if role == "anime-chiffon" || role == "anime-karin" {
                app.buttons["conversationPerformanceButton"].tap()
                XCTAssertTrue(app.buttons["closeCharacterPerformance"].waitForExistence(timeout:8))
                let group=app.buttons["performanceGroup-menu-5a963eacb2279abe"]
                for _ in 0..<5 {
                    if app.scrollViews["performanceGroups"].frame.contains(group.frame) {break}
                    app.scrollViews["performanceGroups"].swipeLeft()
                }
                group.tap()
                let smile=app.buttons["performanceOption-gesture-left-2"]
                XCTAssertTrue(smile.waitForExistence(timeout:8));smile.tap()
                app.waitForCharacter { self.selections($0).contains("gesture-left-2") }
                capture(role+"-authored-smile",app)
                app.buttons["performanceReset"].tap()
                app.waitForCharacter { !self.selections($0).contains("gesture-left-2") && self.selections($0).contains("gesture-left-0") }
                XCTAssertFalse(app.staticTexts["performanceError"].exists)
                app.buttons["closeCharacterPerformance"].tap()
            }
        }
    }
    private func selections(_ state:[String:Any])->[String] {
        (state["characterPlatform"] as? [String:Any])?["performanceSelections"] as? [String] ?? []
    }
    @MainActor private func capture(_ name:String,_ app:XCUIApplication) {
        let image=XCTAttachment(screenshot:XCUIScreen.main.screenshot());image.name=name;image.lifetime = .keepAlways;add(image)
        if let data=try? JSONSerialization.data(withJSONObject:app.characterRuntime,options:[.prettyPrinted,.sortedKeys]) {
            let item=XCTAttachment(data:data,uniformTypeIdentifier:"public.json");item.name=name+"-runtime";item.lifetime = .keepAlways;add(item)
        }
    }
}
