import XCTest

final class CharacterPaletteUITests:XCTestCase {
    @MainActor func testPalettePersistenceAndSourceSelection() throws {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--shell-discover","--keep-companion-data"]
        defer {app.terminate()}
        func enter() {
            app.launch()
            let search=app.textFields["discoverSearch"];XCTAssertTrue(search.waitForExistence(timeout:60))
            search.tap();search.typeText("Chiffon\n");app.buttons["discover-open-anime-chiffon"].tap()
            let chat=app.buttons["profileChatButton"];XCTAssertTrue(chat.waitForExistence(timeout:10));chat.tap()
            app.waitForCharacter({$0["modelId"] as? String=="anime-chiffon" && ($0["stableRenderedFrames"] as? Int ?? 0)>=3},timeout:75)
            app.openCharacterDeveloper();app.buttons["openCharacterPalette"].tap()
        }
        enter()
        let panel=app.staticTexts["paletteStatus"]
        XCTAssertTrue(panel.waitForExistence(timeout:8))
        XCTAssertTrue(wait {(panel.value as? String ?? "").contains("ready:true")})
        app.buttons["原作"].tap()
        XCTAssertTrue(app.buttons["paletteSourceChannels"].label.contains("主贴图色系"))
        app.buttons["整体"].tap()
        let hue=app.sliders["paletteHue"]
        if !hue.isHittable {app.scrollViews.firstMatch.swipeUp()}
        hue.adjust(toNormalizedSliderPosition:0.71)
        XCTAssertTrue(wait {(panel.value as? String ?? "").contains("engineEdits:1")})
        app.terminate();enter()
        XCTAssertTrue(panel.waitForExistence(timeout:8))
        XCTAssertTrue(wait {(panel.value as? String ?? "").contains("ready:true") && (panel.value as? String ?? "").contains("engineEdits:1")})
        app.buttons["paletteResetComponent"].tap()
        XCTAssertTrue(wait {(panel.value as? String ?? "").contains("engineEdits:0")})
    }
    @MainActor func testBuiltInPaletteCatalogEditingResetAndIsolation() throws {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--shell-discover"]
        defer {app.terminate()}
        // Download-only roles are audited on their original prefabs in Unity;
        // an additional real OSS test covers the old release-4 compatibility.
        let roles=["Chiffon","Hikarun","Ichigo","Koharu","Lime","Mafuyu","Meiyun","Milfy","Mao","Perula","Plum","Shinano","Sio"]
        for name in roles {
            let id="anime-"+name.lowercased()
            app.launch()
            let search=app.textFields["discoverSearch"]
            XCTAssertTrue(search.waitForExistence(timeout:60))
            search.tap();search.typeText(name+"\n")
            app.buttons["discover-open-"+id].tap()
            let chat=app.buttons["profileChatButton"]
            XCTAssertTrue(chat.waitForExistence(timeout:10));chat.tap()
            app.waitForCharacter({$0["modelId"] as? String==id && ($0["stableRenderedFrames"] as? Int ?? 0)>=3},timeout:75)
            app.openCharacterDeveloper()
            app.buttons["openCharacterPalette"].tap()
            let panel=app.staticTexts["paletteStatus"]
            XCTAssertTrue(panel.waitForExistence(timeout:8))
            XCTAssertTrue(wait { (panel.value as? String ?? "").contains("ready:true") })
            XCTAssertTrue((panel.value as? String ?? "").contains("engineEdits:0"),"Role isolation and previous reset")
            let hue=app.sliders["paletteHue"]
            if !hue.isHittable {app.scrollViews.firstMatch.swipeUp()}
            XCTAssertTrue(hue.isHittable);hue.adjust(toNormalizedSliderPosition:0.68)
            XCTAssertTrue(wait {(panel.value as? String ?? "").contains("engineEdits:1")})
            let image=XCTAttachment(screenshot:app.screenshot());image.name=id+"-palette";image.lifetime = .keepAlways;add(image)
            let reset=app.buttons["paletteResetComponent"]
            if !reset.isHittable {app.scrollViews.firstMatch.swipeDown()}
            XCTAssertTrue(reset.isHittable);reset.tap()
            XCTAssertTrue(wait {(panel.value as? String ?? "").contains("engineEdits:0")})
            app.terminate()
        }
    }
    @MainActor private func wait(_ check:()->Bool,seconds:Double=8)->Bool {
        let end=Date().addingTimeInterval(seconds)
        while Date()<end {if check() {return true};RunLoop.current.run(until:Date().addingTimeInterval(0.1))}
        return false
    }
}
