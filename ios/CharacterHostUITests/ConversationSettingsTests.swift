import XCTest

extension XCUIApplication {
    @MainActor func openConversationSettings(_ section:String="position") {
        if !buttons["closeCharacterViewEditor"].exists {
            XCTAssertTrue(buttons["characterPositionButton"].waitForExistence(timeout:8))
            buttons["characterPositionButton"].tap()
        }
        let tab=buttons["conversationSetting-"+section]
        XCTAssertTrue(tab.waitForExistence(timeout:5));tab.tap()
    }
    @MainActor var characterAudio:[String:Any] {characterRuntime["sound"] as? [String:Any] ?? [:]}
}

final class ConversationSettingsTests:XCTestCase {
    @MainActor func testSlidersNeverTransformCharacterAndSettingsFitRotations() {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch();defer {XCUIDevice.shared.orientation = .portrait;app.terminate()}
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.waitForCharacter {$0["nativeHoldAvailable"] as? Bool == true}
        XCTAssertFalse(app.buttons["conversationSoundButton"].exists)
        app.openConversationSettings()
        let initial=app.characterRuntime["viewPoseSaved"] as? [String:Double] ?? [:]
        for orientation in [UIDeviceOrientation.portrait,.landscapeLeft] {
            XCUIDevice.shared.orientation=orientation
            app.waitForCharacter {self.number($0,"cameraAspect")>(orientation.isLandscape ? 1.5 : 0) && (!orientation.isLandscape || app.frame.width>app.frame.height)}
            for section in ["sound","atmosphere","position"] {
                app.openConversationSettings(section)
                let panel=app.otherElements["conversationSettingsPanel"]
                XCTAssertTrue(panel.waitForExistence(timeout:5))
                XCTAssertTrue(app.frame.insetBy(dx:5,dy:5).contains(panel.frame),"\(section) must fit the safe visible window")
                if section == "sound" {
                    XCTAssertFalse(app.buttons["resetCharacterView"].isHittable)
                    let slider=app.sliders["musicSoundVolume"]
                    XCTAssertTrue(slider.isHittable);slider.adjust(toNormalizedSliderPosition:0.48)
                    app.sliders["speechSoundVolume"].adjust(toNormalizedSliderPosition:0.30)
                    XCTAssertGreaterThan(app.characterAudio["volume"] as? Double ?? 0,0.1)
                } else if section == "atmosphere" {
                    let slider=app.sliders["atmosphereLevelSlider"]
                    XCTAssertTrue(slider.isHittable);slider.adjust(toNormalizedSliderPosition:0)
                    XCTAssertEqual(slider.value as? String,"关闭")
                    slider.adjust(toNormalizedSliderPosition:1)
                    XCTAssertEqual(slider.value as? String,"绚烂")
                } else {XCTAssertTrue(app.buttons["resetCharacterView"].isHittable)}
                let saved=app.characterRuntime["viewPoseSaved"] as? [String:Double] ?? [:]
                XCTAssertEqual(initial,saved,"Changing tabs and sliders must never rotate, scale or move the character")
                capture("settings-\(section)-\(orientation.rawValue)")
            }
        }
        app.buttons["closeCharacterViewEditor"].tap()
        app.waitForCharacter {$0["viewEditorOpen"] as? Bool == false && $0["inspectionChatLocked"] as? Bool == false}
        XCTAssertTrue(app.textViews["chatInput"].isHittable)
    }
    private func number(_ value:[String:Any],_ key:String)->Double {(value[key] as? NSNumber)?.doubleValue ?? 0}
    @MainActor private func capture(_ name:String) {
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
    }
}
