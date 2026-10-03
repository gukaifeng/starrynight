import XCTest

final class NaturalBodyMotionTests:XCTestCase {
    private func body(_ state:[String:Any])->[String:Any] {
        (state["characterPlatform"] as? [String:Any])?["naturalMotion"] as? [String:Any] ?? [:]
    }
    @MainActor func testClothingAndFingerCalibrationInCurrentDownloadedBundles() throws {
        continueAfterFailure=false
        struct Account:Decodable {let username,password:String}
        guard let url=Bundle(for:Self.self).url(forResource:"DownloadTestAccount",withExtension:"json") else {throw XCTSkip("Requires private OSS test account")}
        let credentials=try JSONDecoder().decode(Account.self,from:Data(contentsOf:url))
        // Real market/OSS requests; generation/prewarming stays disabled.
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--shell-discover","-starry.app.language.v1","zh-Hans"]
        app.launch();defer {app.terminate()}
        XCTAssertTrue(app.buttons["tab-mine"].waitForExistence(timeout:60));app.buttons["tab-mine"].tap();app.buttons["accountCenterButton"].tap()
        if app.buttons["connectPlatformAccount"].exists {app.buttons["connectPlatformAccount"].tap()}
        XCTAssertTrue(app.textFields["passwordUsername"].waitForExistence(timeout:10))
        app.textFields["passwordUsername"].tap();app.textFields["passwordUsername"].typeText(credentials.username)
        app.secureTextFields["passwordCredential"].tap();app.secureTextFields["passwordCredential"].typeText(credentials.password);app.buttons["passwordSignIn"].tap()
        let authenticated=NSPredicate {_,_ in MainActor.assumeIsolated {!app.buttons["passwordSignIn"].exists}}
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:authenticated,object:nil)],timeout:60),.completed)
        if app.buttons["closeAccountButton"].exists {app.buttons["closeAccountButton"].tap()}
        if app.buttons["closeCharacterDownload"].waitForExistence(timeout:3) {app.buttons["closeCharacterDownload"].tap()}
        app.buttons["tab-mine"].tap();app.buttons["profileSettingsButton"].tap();app.buttons["cacheSettingsButton"].tap();app.buttons["characterResourceSettingsButton"].tap()
        XCTAssertTrue(app.staticTexts["characterResourceTotal"].waitForExistence(timeout:15))
        for name in ["fiona","mizuki","ramune"] {
            let remove=app.buttons["removeCharacterResource-anime-"+name]
            if remove.exists {
                remove.tap();XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout:5));app.alerts.buttons["删除资源"].tap()
                XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in MainActor.assumeIsolated {!remove.exists}},object:nil)],timeout:30),.completed)
            }
        }
        app.navigationBars["角色资源"].buttons.firstMatch.tap();app.navigationBars["存储与缓存"].buttons.firstMatch.tap();app.buttons["closeSettingsButton"].tap()
        for name in ["fiona","mizuki","ramune"] {
            app.buttons["tab-discover"].tap()
            let search=app.textFields["discoverSearch"];XCTAssertTrue(search.waitForExistence(timeout:10))
            if app.buttons["clearDiscoverSearch"].exists {app.buttons["clearDiscoverSearch"].tap()}
            search.tap();search.typeText(name+"\n")
            let card=app.buttons["discover-open-anime-"+name];XCTAssertTrue(card.waitForExistence(timeout:10));card.tap()
            XCTAssertTrue(app.buttons["downloadCharacter-anime-"+name].waitForExistence(timeout:15));app.buttons["downloadCharacter-anime-"+name].tap()
            XCTAssertTrue(app.buttons["confirmCharacterDownload"].waitForExistence(timeout:8));app.buttons["confirmCharacterDownload"].tap()
            app.waitForCharacter({$0["modelId"] as? String=="anime-"+name && (self.body($0)["handTravel"] as? Double ?? 0)>0.006},timeout:240)
            let state=body(app.characterRuntime);let clothing=state["clothing"] as? [String:Any] ?? [:]
            XCTAssertEqual(state["legacyCalibration"] as? Bool,false);XCTAssertGreaterThanOrEqual(state["fingers"] as? Int ?? 0,8)
            XCTAssertEqual(clothing["meshCalibrated"] as? Int,7)
            XCTAssertLessThan(clothing["maximumAddedPenetration"] as? Double ?? 1,0.001)
            let evidence=XCTAttachment(data:try JSONSerialization.data(withJSONObject:app.characterRuntime),uniformTypeIdentifier:"public.json")
            evidence.name=name+"-downloaded-clothing";evidence.lifetime = .keepAlways;add(evidence)
        }
    }
    @MainActor func testSharedBodyLifeAcrossDifferentRigsAndSoundReset() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","-starry.app.language.v1","zh-Hans","-hostEmotionMotionEnabled.v1","NO","-hostEmotionMotionSpeechLinked.v3","NO"]
        app.launch();defer{app.terminate()}
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:75))
        for role in ["chiffon","hikarun","ichigo","lime"] {
            if role != "chiffon" {
                app.buttons["tab-discover"].tap()
                let search=app.textFields["discoverSearch"];XCTAssertTrue(search.waitForExistence(timeout:8))
                if app.buttons["clearDiscoverSearch"].exists {app.buttons["clearDiscoverSearch"].tap()}
                let term=role
                search.tap();search.typeText(term+"\n")
                let card=app.buttons["discover-open-anime-"+role];XCTAssertTrue(card.waitForExistence(timeout:10));card.tap()
                XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:8));app.buttons["profileChatButton"].tap()
            }
            app.waitForCharacter({$0["modelId"] as? String=="anime-"+role && self.body($0)["supported"] as? Bool==true},timeout:60)
            app.waitForCharacter({(self.body($0)["weight"] as? Double ?? 0)>0.95 && (self.body($0)["handTravel"] as? Double ?? 0)>0.006},timeout:20)
            let state=body(app.characterRuntime)
            XCTAssertGreaterThanOrEqual(state["fingers"] as? Int ?? 0,8)
            XCTAssertLessThan(state["footError"] as? Double ?? 1,0.004)
            let clothing=state["clothing"] as? [String:Any] ?? [:]
            XCTAssertGreaterThanOrEqual(clothing["meshCalibrated"] as? Int ?? 0,3)
            XCTAssertLessThan(clothing["maximumAddedPenetration"] as? Double ?? 1,0.001)
            let picture=XCTAttachment(screenshot:app.screenshot());picture.name=role+"-natural-body";picture.lifetime = .keepAlways;add(picture)
            let data=try! JSONSerialization.data(withJSONObject:app.characterRuntime,options:[.sortedKeys])
            let evidence=XCTAttachment(data:data,uniformTypeIdentifier:"public.json");evidence.name=role+"-body-runtime";evidence.lifetime = .keepAlways;add(evidence)
        }
        app.openConversationSettings("sound")
        app.sliders["speechSoundVolume"].adjust(toNormalizedSliderPosition:0.25)
        app.sliders["musicSoundVolume"].adjust(toNormalizedSliderPosition:0.8)
        app.buttons["resetConversationSound"].tap()
        app.waitForCharacter {abs((($0["sound"] as? [String:Any])?["volume"] as? Double ?? -1)-0.28)<0.01 && (($0["sound"] as? [String:Any])?["speechVolume"] as? Double)==1}
    }
}
