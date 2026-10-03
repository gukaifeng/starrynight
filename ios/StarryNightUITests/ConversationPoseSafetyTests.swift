import XCTest

/// Uses the real Unity player and authored controls. No paid AI calls.
final class ConversationPoseSafetyTests:XCTestCase {
    @MainActor func testBundledRolePerformancePreviewsAndHikarunBreathing() throws {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--shell-discover","-starry.app.language.v1","zh-Hans"]
        app.launch();defer {app.terminate()}
        let url=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"CharacterCatalog",withExtension:"json"))
        let catalog=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
        let roles=try XCTUnwrap(catalog["characters"] as? [[String:Any]])
        for name in ["hikarun","chiffon","ichigo","koharu","lime","mafuyu","meiyun","milfy","mao","perula","plum","shinano","sio"] {
            XCTAssertTrue(app.buttons["tab-discover"].waitForExistence(timeout:75));app.buttons["tab-discover"].tap()
            let search=app.textFields["discoverSearch"];XCTAssertTrue(search.waitForExistence(timeout:10))
            if app.buttons["clearDiscoverSearch"].exists {app.buttons["clearDiscoverSearch"].tap()}
            search.tap();search.typeText(name+"\n")
            let id="anime-"+name
            XCTAssertTrue(app.buttons["discover-open-"+id].waitForExistence(timeout:10));app.buttons["discover-open-"+id].tap()
            XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:10));app.buttons["profileChatButton"].tap()
            app.waitForCharacter({$0["modelId"] as? String==id && $0["idlePlaying"] as? Bool==true},timeout:75)
            app.waitForCharacter {state in
                state["voiceProcessingMs"] as? Double != nil && (state["voiceUnityAckCount"] as? Int ?? 0)>0 && (state["voiceUnityControlMs"] as? Double ?? -1)>=0
            }
            if name=="hikarun" {
                for index in 0..<4 {
                    Thread.sleep(forTimeInterval:2)
                    let shot=XCTAttachment(screenshot:app.screenshot());shot.name="hikarun-idle-"+String(index);shot.lifetime = .keepAlways;add(shot)
                }
            }
            app.openCharacterDeveloper();app.buttons["profilePerformanceButton"].tap()
            XCTAssertTrue(app.buttons["closeCharacterPerformance"].waitForExistence(timeout:8),id)
            let profile=try XCTUnwrap(roles.first {$0["id"] as? String==id}?["performance"] as? [String:Any])
            let options=try XCTUnwrap(profile["options"] as? [[String:Any]])
            let groups=try XCTUnwrap(profile["groups"] as? [[String:Any]])
            let groupID=try XCTUnwrap(groups.first?["id"] as? String)
            let option=try XCTUnwrap(options.first {$0["group"] as? String==groupID})
            let optionID=try XCTUnwrap(option["id"] as? String)
            if (option["control"] as? [String:Any])?["kind"] as? String == "slider" {
                let slider=app.sliders["performanceSlider-"+optionID]
                XCTAssertTrue(slider.waitForExistence(timeout:5),id);XCTAssertTrue(slider.isEnabled,id)
                slider.adjust(toNormalizedSliderPosition:0.65)
                let initial=(option["control"] as? [String:Any])?["initial"] as? Double ?? 0
                app.waitForCharacter {
                    let values=($0["characterPlatform"] as? [String:Any])?["avatarControlValues"] as? [[String:Any]] ?? []
                    let value=values.first {$0["id"] as? String==optionID}?["value"] as? Double ?? -1
                    // XCTest's thumb geometry need not equal the requested
                    // fraction. Verify a valid changed value reaches Unity.
                    return value>=0 && value<=1 && abs(value-initial)>0.05
                }
            } else {
                let button=app.buttons["performanceOption-"+optionID]
                for _ in 0..<10 {if button.isHittable{break};app.scrollViews["performanceOptions"].swipeUp()}
                XCTAssertTrue(button.isEnabled,id);button.tap()
                app.waitForCharacter { ((($0["characterPlatform"] as? [String:Any])?["performanceSelections"] as? [String]) ?? []).contains(optionID) }
            }
            app.buttons["performanceReset"].tap();app.closeCharacterPerformance()
        }
    }
}
