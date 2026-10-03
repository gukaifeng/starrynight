import XCTest

final class HostEmotionMotionTests:XCTestCase {
    private func motion(_ state:[String:Any])->[String:Any] {
        (state["characterPlatform"] as? [String:Any])?["hostEmotionMotion"] as? [String:Any] ?? [:]
    }
    @MainActor func testPilotPreviewsSwitchAndOriginalControls() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","-starry.app.language.v1","zh-Hans"]
        app.launch();defer{app.terminate()}
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:75))
        app.waitForCharacter {self.motion($0)["supported"] as? Bool == true}
        for role in ["lime","chiffon","plum"] {
            app.buttons["tab-discover"].tap()
            let search=app.textFields["discoverSearch"];XCTAssertTrue(search.waitForExistence(timeout:8))
            if app.buttons["clearDiscoverSearch"].exists {app.buttons["clearDiscoverSearch"].tap()}
            search.tap();search.typeText(role);app.buttons["discover-open-anime-"+role].tap()
            XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:8));app.buttons["profileChatButton"].tap()
            app.waitForCharacter({$0["modelId"] as? String == "anime-"+role && self.motion($0)["supported"] as? Bool == true},timeout:60)
            app.openCharacterDeveloper()
            XCTAssertTrue(app.buttons["openHostEmotionMotion"].waitForExistence(timeout:8))
            app.buttons["openHostEmotionMotion"].tap()
            let toggle=app.switches["hostEmotionMotionToggle"]
            XCTAssertTrue(toggle.waitForExistence(timeout:8));if toggle.value as? String != "1" {toggle.tap()}
            app.waitForCharacter {self.motion($0)["enabled"] as? Bool == true}
            let count=motion(app.characterRuntime)["started"] as? Int ?? 0
            app.buttons["hostEmotionPreview-happy"].tap()
            app.waitForCharacter { (self.motion($0)["started"] as? Int ?? 0)>count && (self.motion($0)["peakDegrees"] as? Double ?? 0)>2 }
            let picture=XCTAttachment(screenshot:app.screenshot());picture.name=role+"-host-emotion";picture.lifetime = .keepAlways;add(picture)
            if role == "lime" {
                app.waitForCharacter {self.motion($0)["gesture"] as? String == ""}
                for id in ["agree","curious","shy","pout","sad","surprised","welcome","encourage","disagree"] {
                    let preview=app.buttons["hostEmotionPreview-"+id]
                    for _ in 0..<3 {
                        if preview.exists && preview.isHittable && app.scrollViews["hostEmotionMotionPanel"].frame.contains(preview.frame) {break}
                        app.scrollViews["hostEmotionMotionPanel"].swipeUp()
                    }
                    preview.tap()
                    app.waitForCharacter {self.motion($0)["gesture"] as? String == id}
                    app.waitForCharacter {self.motion($0)["gesture"] as? String == ""}
                }
                app.scrollViews["hostEmotionMotionPanel"].swipeDown()
                app.buttons["hostEmotionPreview-happy"].tap()
                app.waitForCharacter {self.motion($0)["gesture"] as? String == "happy"}
                app.buttons["hostEmotionStop"].tap()
                app.waitForCharacter {self.motion($0)["gesture"] as? String == ""}
            }
            toggle.tap()
            app.waitForCharacter {self.motion($0)["enabled"] as? Bool == false && self.motion($0)["gesture"] as? String == ""}
            XCTAssertFalse(app.buttons["hostEmotionPreview-happy"].isEnabled)
            app.buttons["closeHostEmotionMotion"].tap()
            app.buttons["profilePerformanceButton"].tap()
            // Author gesture choices must still work while the new layer is off.
            if role == "lime" {
            let group=app.buttons["performanceGroup-menu-5a963eacb2279abe"]
            let strip=app.scrollViews["performanceGroups"]
            for _ in 0..<22 {
                if strip.frame.insetBy(dx:4,dy:0).contains(group.frame) {break}
                let left=group.frame.midX>strip.frame.midX
                strip.coordinate(withNormalizedOffset:CGVector(dx:left ? 0.75:0.25,dy:0.5))
                    .press(forDuration:0.05,thenDragTo:strip.coordinate(withNormalizedOffset:CGVector(dx:left ? 0.35:0.65,dy:0.5)),withVelocity:.slow,thenHoldForDuration:0.15)
            }
            XCTAssertTrue(group.isHittable);group.tap()
            let original=app.buttons["performanceOption-gesture-left-2"]
            XCTAssertTrue(original.waitForExistence(timeout:5));original.tap()
            app.waitForCharacter {
                let selections=($0["characterPlatform"] as? [String:Any])?["performanceSelections"] as? [String] ?? []
                return selections.contains("gesture-left-2") && self.motion($0)["enabled"] as? Bool == false
            }
            }
            app.buttons["performanceReset"].tap();app.closeCharacterPerformance()
            if role == "lime" {
                app.openCharacterDeveloper()
                let library=app.buttons["openSourceMotionLibrary"]
                for _ in 0..<3 {if library.isHittable {break};app.scrollViews.firstMatch.swipeUp()}
                library.tap()
                app.buttons["performanceGroup-source-library-source-face-motion"].tap()
                let search=app.textFields["sourceMotionSearch"]
                XCTAssertTrue(search.waitForExistence(timeout:5));search.tap();search.typeText("F_smile_1")
                let source=app.buttons["performanceOption-source-motion-a712a81ddc58e9f45bb244c4dff3b092"]
                XCTAssertTrue(source.waitForExistence(timeout:5));source.tap()
                app.waitForCharacter {
                    let p=($0["characterPlatform"] as? [String:Any])?["sourceMotionPreview"] as? [String:Any] ?? [:]
                    return p["id"] as? String == "source-motion-a712a81ddc58e9f45bb244c4dff3b092" && (p["weight"] as? Double ?? 0) > 0.9
                }
                app.buttons["performanceDefault-source-library-source-face-motion"].tap()
                app.waitForCharacter {
                    let p=($0["characterPlatform"] as? [String:Any])?["sourceMotionPreview"] as? [String:Any] ?? [:]
                    return p["id"] as? String == ""
                }
                app.closeCharacterPerformance()
            }
        }
        // Return to the separate developer page and leave manual previews enabled.
        app.openCharacterDeveloper();app.buttons["openHostEmotionMotion"].tap()
        app.switches["hostEmotionMotionToggle"].tap()
        app.waitForCharacter {self.motion($0)["enabled"] as? Bool == true}
    }
}
