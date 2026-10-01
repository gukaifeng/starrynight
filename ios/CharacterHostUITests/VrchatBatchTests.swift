import XCTest

/// Exercises actual native-to-Unity controls and eviction/reload across old and
/// new character packages. No paid AI request is enabled by these launch flags.
final class VrchatBatchTests:XCTestCase {
    @MainActor func testIchigoExpressionChangesAndDefaultRecovery() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch();defer{app.terminate()}
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:75))
        app.buttons["tab-discover"].tap()
        let search=app.textFields["discoverSearch"]
        XCTAssertTrue(search.waitForExistence(timeout:8));search.tap();search.typeText("ichigo")
        app.buttons["discover-open-anime-ichigo"].tap()
        XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:8));app.buttons["profileChatButton"].tap()
        app.waitForCharacter({$0["modelId"] as? String == "anime-ichigo" && $0["idlePlaying"] as? Bool == true},timeout:60)
        capture("ichigo-conversation",app)
        app.openCharacterPerformance()
        let group=app.buttons["performanceGroup-menu-5a963eacb2279abe"]
        let strip=app.scrollViews["performanceGroups"]
        for _ in 0..<20 {
            if strip.frame.insetBy(dx:4,dy:0).contains(group.frame){break}
            let left=group.frame.midX>strip.frame.midX
            strip.coordinate(withNormalizedOffset:CGVector(dx:left ? 0.75:0.25,dy:0.5)).press(forDuration:0.05,
                thenDragTo:strip.coordinate(withNormalizedOffset:CGVector(dx:left ? 0.35:0.65,dy:0.5)),withVelocity:.slow,thenHoldForDuration:0.2)
        }
        XCTAssertTrue(group.isHittable);group.tap()
        for id in ["gesture-left-2","gesture-left-6","gesture-left-3"] {
            let option=app.buttons["performanceOption-"+id]
            for _ in 0..<8 {
                if app.scrollViews["performanceOptions"].frame.contains(option.frame){break}
                app.scrollViews["performanceOptions"].swipeUp()
            }
            XCTAssertTrue(option.isHittable);option.tap()
            app.waitForCharacter{self.selections($0).contains(id)}
            capture("ichigo-"+id,app)
        }
        app.buttons["performanceReset"].tap()
        app.waitForCharacter{self.selections($0).contains("gesture-left-0") && self.selections($0).contains("gesture-right-0")}
        XCTAssertFalse(app.staticTexts["performanceError"].exists)
        app.closeCharacterPerformance();capture("ichigo-return-to-default",app)
    }
    @MainActor func testBatchThreeAutonomousBlink() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch();defer { app.terminate() }
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:75))
        for name in ["mafuyu","plum"] {
            app.buttons["tab-discover"].tap()
            let search=app.textFields["discoverSearch"]
            XCTAssertTrue(search.waitForExistence(timeout:8))
            if app.buttons["clearDiscoverSearch"].exists {app.buttons["clearDiscoverSearch"].tap()}
            search.tap();search.typeText(name)
            app.buttons["discover-open-anime-"+name].tap()
            XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:8));app.buttons["profileChatButton"].tap()
            app.waitForCharacter({$0["modelId"] as? String == "anime-"+name && $0["idlePlaying"] as? Bool == true},timeout:60)
            capture(name+"-before-blink",app)
            app.waitForCharacter({ state in
                let platform=state["characterPlatform"] as? [String:Any] ?? [:]
                let autonomy=platform["autonomy"] as? [String:Any] ?? [:]
                return autonomy["enabled"] as? Bool == true && (autonomy["blinkCount"] as? Int ?? 0)>0
            },timeout:15)
            capture(name+"-after-blink",app)
        }
    }
    @MainActor func testBatchTwoCharactersMediaControlsAndGestures() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch();defer {app.terminate()}
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:75))
        let cases=[
            ("torao","menu-5027e850fe98cb0f","control-5528f6bc16a8f30f664e"),
            ("ichigo","menu-6b146f621ce11aba","control-d7ee32b491e770595f93"),
            ("lime","menu-97cfbf86b90cf8ce","control-3a39f70e5ac1fd6ce4c9"),
            ("mafuyu","menu-5a963eacb2279abe","gesture-left-2"),
            ("nozomi","menu-72d4da533df57485","control-006150e1396b6e39fc63"),
            ("siska","menu-5a963eacb2279abe","gesture-left-2"),
            ("plum","menu-5a963eacb2279abe","gesture-left-2")]
        for (name,groupID,optionID) in cases {
            let role="anime-"+name
            app.buttons["tab-discover"].tap()
            let search=app.textFields["discoverSearch"]
            XCTAssertTrue(search.waitForExistence(timeout:8))
            if app.buttons["clearDiscoverSearch"].exists {app.buttons["clearDiscoverSearch"].tap()}
            search.tap();search.typeText(name)
            let card=app.buttons["discover-open-"+role]
            XCTAssertTrue(card.waitForExistence(timeout:8));card.tap()
            XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:8))
            capture(role+"-profile",app);app.buttons["profileChatButton"].tap()
            app.waitForCharacter({$0["modelId"] as? String == role && $0["idlePlaying"] as? Bool == true},timeout:60)
            if name == "mafuyu" || name == "plum" {
                app.waitForCharacter({ state in
                    let platform=state["characterPlatform"] as? [String:Any] ?? [:]
                    let autonomy=platform["autonomy"] as? [String:Any] ?? [:]
                    return autonomy["enabled"] as? Bool == true && (autonomy["blinkCount"] as? Int ?? 0)>0
                },timeout:15)
            }
            let audio=app.characterAudio
            XCTAssertEqual(audio["collectionScope"] as? String,role)
            XCTAssertEqual(audio["track"] as? String,role+"/theme")
            XCTAssertEqual((audio["availableTrackIDs"] as? [String])?.count,1)
            let before=app.characterRuntime["previewRotationCount"] as? Int ?? 0
            let start=app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.34))
            start.press(forDuration:0.06,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.72,dy:0.34)),withVelocity:.slow,thenHoldForDuration:0.1)
            app.waitForCharacter {($0["previewRotationCount"] as? Int ?? 0)>before}
            capture(role+"-conversation",app)
            app.openCharacterPerformance()
            XCTAssertTrue(app.buttons["closeCharacterPerformance"].waitForExistence(timeout:8))
            let group=app.buttons["performanceGroup-"+groupID]
            for _ in 0..<20 {
                let strip=app.scrollViews["performanceGroups"]
                if strip.frame.insetBy(dx:4,dy:0).contains(group.frame) {break}
                // Small directed drags avoid flinging past narrow author groups.
                let left=group.frame.midX > strip.frame.midX
                strip.coordinate(withNormalizedOffset:CGVector(dx:left ? 0.75 : 0.25,dy:0.5))
                    .press(forDuration:0.05,thenDragTo:strip.coordinate(withNormalizedOffset:CGVector(dx:left ? 0.35 : 0.65,dy:0.5)),withVelocity:.slow,thenHoldForDuration:0.2)
            }
            XCTAssertTrue(group.isHittable);group.tap()
            let option=app.buttons["performanceOption-"+optionID]
            for _ in 0..<8 {
                if app.scrollViews["performanceOptions"].frame.contains(option.frame) {break}
                app.scrollViews["performanceOptions"].swipeUp()
            }
            XCTAssertTrue(option.isHittable);option.tap()
            app.waitForCharacter {self.selections($0).contains(optionID)}
            capture(role+"-expression",app)
            app.buttons["performanceReset"].tap()
            app.waitForCharacter {!self.selections($0).contains(optionID)}
            XCTAssertFalse(app.staticTexts["performanceError"].exists)
            app.closeCharacterPerformance()
        }
    }
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
            let audio=app.characterAudio
            XCTAssertEqual(audio["collectionScope"] as? String,role)
            if role == "anime-chiffon" || role == "anime-karin" {
                app.openCharacterPerformance()
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
                app.closeCharacterPerformance()
            }
        }
    }
    private func selections(_ state:[String:Any])->[String] {
        (state["characterPlatform"] as? [String:Any])?["performanceSelections"] as? [String] ?? []
    }
    @MainActor private func capture(_ name:String,_ app:XCUIApplication) {
        let image=XCTAttachment(screenshot:XCUIScreen.main.screenshot());image.name=name;image.lifetime = .keepAlways;add(image)
        // Discovery profiles do not mount the conversation's runtime probe.
        guard app.buttons["customizationButton"].exists else { return }
        if let data=try? JSONSerialization.data(withJSONObject:app.characterRuntime,options:[.prettyPrinted,.sortedKeys]) {
            let item=XCTAttachment(data:data,uniformTypeIdentifier:"public.json");item.name=name+"-runtime";item.lifetime = .keepAlways;add(item)
        }
    }
}
