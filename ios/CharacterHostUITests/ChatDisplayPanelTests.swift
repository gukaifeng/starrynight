import XCTest
import UIKit

final class ChatDisplayPanelTests: XCTestCase {
    @MainActor func testGlobalFontAcrossCharactersAccountsAndRelaunch() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.waitForCharacter { $0["modelId"] as? String == "hatsune-miku" && $0["framingMotionActive"] as? Bool == false }
        let originalCamera = app.characterRuntime
        let panel = app.otherElements["companionPanel"]
        XCTAssertEqual(panel.frame.height/app.frame.height,0.60,accuracy:0.02)

        let phrase = "每句话都看得清楚"
        let input = app.textFields["chatInput"].exists ? app.textFields["chatInput"] : app.textViews["chatInput"]
        input.tap(); input.typeText(phrase); app.buttons["sendMessageButton"].tap()
        app.waitForReply()
        let message = app.staticTexts.matching(identifier:"userMessage").matching(NSPredicate(format:"label == %@",phrase)).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout:5))
        let originalTextHeight = message.frame.height

        func openGlobalFont() {
            app.buttons["tab-mine"].tap()
            XCTAssertTrue(app.buttons["profileSettingsButton"].waitForExistence(timeout:6))
            app.buttons["profileSettingsButton"].tap()
            XCTAssertTrue(app.buttons["chatDisplaySettingsButton"].waitForExistence(timeout:5))
            app.buttons["chatDisplaySettingsButton"].tap()
            XCTAssertTrue(app.sliders["chatFontSlider"].waitForExistence(timeout:5))
            XCTAssertFalse(app.sliders["chatHeightSlider"].exists)
        }
        func closeGlobalFont() {
            app.buttons["closeChatDisplayButton"].tap()
            XCTAssertTrue(app.buttons["closeSettingsButton"].waitForExistence(timeout:5))
            app.buttons["closeSettingsButton"].tap()
            app.buttons["tab-home"].tap()
            XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:20))
        }
        openGlobalFont()
        XCTAssertEqual(app.staticTexts["chatFontValue"].label,"15")
        app.sliders["chatFontSlider"].adjust(toNormalizedSliderPosition:1)
        XCTAssertEqual(app.staticTexts["chatFontValue"].label,"24")
        capture("global-font-01-settings")
        closeGlobalFont()
        wait { message.frame.height > originalTextHeight+4 }
        XCTAssertEqual(panel.frame.height/app.frame.height,0.60,accuracy:0.02,"Font changes cannot resize the conversation area")
        let afterFont = app.characterRuntime
        for key in ["distance","framingSize","framingAngle","pitch","yaw","cameraFov"] {
            XCTAssertEqual((afterFont[key] as? NSNumber)?.doubleValue ?? -1,
                           (originalCamera[key] as? NSNumber)?.doubleValue ?? -2,accuracy:0.0001,key)
        }
        capture("global-font-02-conversation")
        app.openCustomization()
        XCTAssertFalse(app.buttons["customize-display"].exists,"Font settings belong to My Settings, not a character")
        app.openCustomization("history")
        let historic = app.staticTexts.matching(NSPredicate(format:"label == %@",phrase)).firstMatch
        XCTAssertTrue(historic.waitForExistence(timeout:6))
        XCTAssertGreaterThan(historic.frame.height,originalTextHeight+4,"History shares the same global font")
        app.closeCustomizationPage("closeHistoryButton")

        app.buttons["tab-discover"].tap()
        XCTAssertTrue(app.buttons["discover-open-studio-robot"].waitForExistence(timeout:8))
        app.buttons["discover-open-studio-robot"].tap()
        XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:5)); app.buttons["profileChatButton"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.waitForCharacter { $0["modelId"] as? String == "studio-robot" }
        openGlobalFont()
        XCTAssertEqual(app.staticTexts["chatFontValue"].label,"24","A different character uses the global font immediately")
        app.buttons["closeChatDisplayButton"].tap()
        XCTAssertTrue(app.buttons["switchDemoIdentity"].waitForExistence(timeout:5)); app.buttons["switchDemoIdentity"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        openGlobalFont()
        XCTAssertEqual(app.staticTexts["chatFontValue"].label,"24","Account switching must not restore old per-account settings")
        closeGlobalFont()

        app.terminate(); app.launchArguments.append("--keep-companion-data"); app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        openGlobalFont()
        XCTAssertEqual(app.staticTexts["chatFontValue"].label,"24","The device-wide font survives relaunch")
        app.buttons["resetChatDisplayButton"].tap()
        XCTAssertEqual(app.staticTexts["chatFontValue"].label,"15")
        capture("global-font-03-restored-default")
        closeGlobalFont()
        XCTAssertEqual(panel.frame.height/app.frame.height,0.60,accuracy:0.02)
    }

    @MainActor func testAllPanelExitPathsSaveAndReopen() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch()
        // A tap at the underlying viewer back location must close only the window.
        app.openCustomization("framing")
        XCTAssertTrue(app.buttons["closeFramingButton"].waitForExistence(timeout:5))
        app.buttons["framingSizeMax"].tap(); outside(app)
        wait { app.buttons["customizationButton"].isHittable }
        app.openCustomization("framing")
        XCTAssertTrue(app.staticTexts["framingSizeValue"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["framingSizeValue"].label,"110%")
        app.buttons["restoreFramingButton"].tap(); app.closeCustomizationPage("closeFramingButton")
        wait { app.buttons["customizationButton"].isHittable }
        app.openCustomization("appearance")
        XCTAssertTrue(app.buttons["closeStudioButton"].waitForExistence(timeout:5))
        app.sliders["studio-faceWidth"].adjust(toNormalizedSliderPosition:0.85)
        let savedFace = app.sliders["studio-faceWidth"].value as? String
        app.closeCustomizationPage("closeStudioButton")
        wait { app.buttons["customizationButton"].isHittable }
        app.openCustomization("appearance")
        XCTAssertTrue(app.buttons["closeStudioButton"].waitForExistence(timeout:5))
        XCTAssertEqual(app.sliders["studio-faceWidth"].value as? String,savedFace)
        capture("05-studio-back")
        outside(app)
        for (section,back) in [("music","closeMusicButton"),("","closeCustomizationButton")] {
            wait { app.buttons["customizationButton"].isHittable }; app.openCustomization(section.isEmpty ? nil : section)
            XCTAssertTrue(app.buttons[back].waitForExistence(timeout:5))
            if section.isEmpty { app.buttons[back].tap() } else { app.closeCustomizationPage(back) }
            wait { app.buttons["customizationButton"].isHittable }; app.openCustomization(section.isEmpty ? nil : section)
            XCTAssertTrue(app.buttons[back].waitForExistence(timeout:5)); outside(app)
        }
        wait { app.buttons["customizationButton"].isHittable }; app.openCustomization("music")
        XCTAssertTrue(app.buttons["closeMusicButton"].waitForExistence(timeout:5))
        let handle = app.buttons["调整面板高度"]
        let start = handle.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        start.press(forDuration:0.1,thenDragTo:start.withOffset(CGVector(dx:0,dy:180)))
        wait { app.buttons["customizationButton"].isHittable }
        for (entry,back) in [("customize-profile","closeProfileButton"),("customize-memory","closeMemoryButton"),("customize-history","closeHistoryButton")] {
            wait { app.buttons["customizationButton"].isHittable }
            app.openCustomization(String(entry.dropFirst("customize-".count)))
            XCTAssertTrue(app.buttons[back].waitForExistence(timeout:5))
            if entry == "customize-profile" {
                app.textFields["profileName"].tap();app.textFields["profileName"].typeText("好")
                outside(app)
            } else { app.closeCustomizationPage(back) }
        }
        wait { app.buttons["customizationButton"].isHittable }
        XCTAssertTrue(app.staticTexts["chatCharacterName"].label.hasSuffix("好"))
        XCUIDevice.shared.orientation = .landscapeLeft
        wait { app.frame.width > app.frame.height }
        app.openCustomization("framing")
        XCTAssertTrue(app.buttons["closeFramingButton"].waitForExistence(timeout:5)); outside(app)
        wait { app.buttons["customizationButton"].isHittable }
        capture("06-landscape-return")
        app.buttons["viewerBackButton"].tap()
        for about in [false,true] {
            let entry="accountCenterButton", back="closeAccountCenterButton"
            XCTAssertTrue(app.buttons[entry].waitForExistence(timeout:10))
            if about { app.openAccountAbout() } else { app.buttons[entry].tap() }
            XCTAssertTrue(app.buttons[back].waitForExistence(timeout:5)); app.buttons[back].tap()
            wait { app.buttons[entry].isHittable }
            if about { app.openAccountAbout() } else { app.buttons[entry].tap() }
            XCTAssertTrue(app.buttons[back].waitForExistence(timeout:5)); outside(app)
        }
        XCTAssertFalse(app.buttons["完成"].exists)
    }
    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--preview-companion","--preview-human"]
        app.launch();XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        return app
    }
    @MainActor private func outside(_ app:XCUIApplication) {
        // Exposed character area, also reachable in compact landscape layouts.
        app.coordinate(withNormalizedOffset:CGVector(dx:0.12,dy:0.11)).tap()
    }
    @MainActor private func wait(_ condition:@escaping () -> Bool) {
        let predicate = NSPredicate { _,_ in MainActor.assumeIsolated { condition() } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:nil)],timeout:15),.completed)
    }
    @MainActor private func capture(_ name:String) {
        let image = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
