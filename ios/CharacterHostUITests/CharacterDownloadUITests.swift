import XCTest

/// Real OSS transfers with a private synthetic account; no paid AI generation.
final class CharacterDownloadUITests:XCTestCase {
    @MainActor func testDownloadThreeCharactersAndRestoreAfterRelaunch() throws {
        continueAfterFailure=false
        struct Account:Decodable {let username,password:String}
        guard let url=Bundle(for:Self.self).url(forResource:"DownloadTestAccount",withExtension:"json") else {
            throw XCTSkip("Run with STARRY_OSS_UI_TESTS=1 and private test credentials")
        }
        let credentials=try JSONDecoder().decode(Account.self,from:Data(contentsOf:url))
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--shell-discover"]
        defer{app.terminate()};app.launch()
        XCTAssertTrue(app.buttons["tab-mine"].waitForExistence(timeout:60));app.buttons["tab-mine"].tap()
        XCTAssertTrue(app.buttons["accountCenterButton"].waitForExistence(timeout:10));app.buttons["accountCenterButton"].tap()
        // The account page either shows the cloud login form or a button opening it.
        if app.buttons["connectPlatformAccount"].exists {app.buttons["connectPlatformAccount"].tap()}
        XCTAssertTrue(app.textFields["passwordUsername"].waitForExistence(timeout:10))
        app.textFields["passwordUsername"].tap();app.textFields["passwordUsername"].typeText(credentials.username)
        app.secureTextFields["passwordCredential"].tap();app.secureTextFields["passwordCredential"].typeText(credentials.password)
        app.buttons["passwordSignIn"].tap()
        XCTAssertTrue(app.textViews["chatInput"].waitForExistence(timeout:60));app.buttons["tab-mine"].tap()
        let signed=app.staticTexts.matching(identifier:"profileAccountID").matching(NSPredicate(format:"label CONTAINS 'xy'")).firstMatch
        XCTAssertTrue(signed.waitForExistence(timeout:20))
        let close=app.buttons["closeAccountButton"]
        if close.exists{close.tap()}
        for name in ["Fiona","Mizuki","Ramune"] {
            app.buttons["tab-discover"].tap()
            let search=app.textFields["discoverSearch"];XCTAssertTrue(search.waitForExistence(timeout:15))
            if app.buttons["clearDiscoverSearch"].exists{app.buttons["clearDiscoverSearch"].tap()}
            search.tap();search.typeText(name+"\n")
            let id="anime-"+name.lowercased();let card=app.buttons["discover-open-"+id]
            XCTAssertTrue(card.waitForExistence(timeout:15));card.tap()
            XCTAssertTrue(app.buttons["marketAudition-"+id].waitForExistence(timeout:15));app.buttons["marketAudition-"+id].tap()
            let download=app.buttons["downloadCharacter-"+id]
            if download.exists {
                download.tap()
                let confirm=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","下载 · ")).firstMatch
                XCTAssertTrue(confirm.waitForExistence(timeout:5));confirm.tap()
            }else{XCTAssertTrue(app.buttons["profileChatButton"].exists);app.buttons["profileChatButton"].tap()}
            app.waitForCharacter({$0["modelId"] as? String==id && ($0["stableRenderedFrames"] as? Int ?? 0)>=3},timeout:240)
            XCTAssertTrue(app.textViews["chatInput"].exists)
            let voice=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","messageVoice-")).firstMatch
            XCTAssertTrue(voice.exists);XCTAssertTrue((voice.value as? String ?? "").contains("durationSource:measured"))
            let before=app.characterRuntime["previewRotationCount"] as? Int ?? 0
            app.coordinate(withNormalizedOffset:CGVector(dx:0.45,dy:0.35)).press(forDuration:0.05,
                thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.65,dy:0.38)))
            app.waitForCharacter({($0["previewRotationCount"] as? Int ?? 0)>before},timeout:15)
            let screenshot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());screenshot.name="downloaded-"+id;screenshot.lifetime = .keepAlways;add(screenshot)
        }
        // UI automation deliberately keeps credentials out of the app Keychain;
        // re-authenticate the same synthetic account to exercise durable assets.
        app.terminate();app.launch()
        app.buttons["tab-mine"].tap();app.buttons["accountCenterButton"].tap()
        app.buttons["connectPlatformAccount"].tap()
        XCTAssertTrue(app.textFields["passwordUsername"].waitForExistence(timeout:10))
        app.textFields["passwordUsername"].tap();app.textFields["passwordUsername"].typeText(credentials.username)
        app.secureTextFields["passwordCredential"].tap();app.secureTextFields["passwordCredential"].typeText(credentials.password)
        app.buttons["passwordSignIn"].tap()
        XCTAssertTrue(app.textViews["chatInput"].waitForExistence(timeout:90));app.buttons["tab-mine"].tap()
        XCTAssertTrue(signed.waitForExistence(timeout:20));if app.buttons["closeAccountButton"].exists{app.buttons["closeAccountButton"].tap()}
        // Durable install + media registry must restore without a new download.
        app.buttons["tab-home"].tap()
        app.waitForCharacter({$0["modelId"] as? String=="anime-ramune" && ($0["stableRenderedFrames"] as? Int ?? 0)>=3},timeout:90)
        XCTAssertFalse(app.buttons["downloadCharacter-anime-ramune"].exists)
    }
}
