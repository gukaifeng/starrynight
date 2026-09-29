import XCTest

final class PortraitHomeTests:XCTestCase {
    @MainActor func testPortraitTracksSavedAppearanceAndSurvivesRestart() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing","--companion-testing"]
        app.launch(); app.selectHomeModel("real-woman")
        app.buttons["humanModelCard"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        let input = app.textFields["chatInput"].exists ? app.textFields["chatInput"] : app.textViews["chatInput"]
        XCTAssertLessThan(input.frame.midX,app.buttons["recordVoiceButton"].frame.midX)
        XCTAssertLessThan(app.buttons["recordVoiceButton"].frame.midX,app.buttons["sendMessageButton"].frame.midX)
        XCTAssertEqual(app.buttons["viewerBackButton"].frame.width,44,accuracy:1)
        capture("01-quiet-controls-and-composer")
        app.buttons["viewerBackButton"].tap()
        XCTAssertTrue(app.buttons["humanModelCard"].waitForExistence(timeout:8))
        wait { (app.buttons["humanModelCard"].value as? String ?? "").hasPrefix("custom:") }
        let original = app.buttons["humanModelCard"].value as? String
        capture("02-default-portrait")
        app.buttons["humanModelCard"].tap()
        app.openCustomization("appearance")
        XCTAssertTrue(app.buttons["closeStudioButton"].waitForExistence(timeout:5))
        app.segmentedControls["studioTabs"].buttons["造型"].tap()
        XCTAssertTrue(app.segmentedControls["studio-发型"].waitForExistence(timeout:5))
        app.segmentedControls["studio-发型"].buttons["短发"].tap()
        app.closeCustomizationPage("closeStudioButton")
        app.buttons["viewerBackButton"].tap()
        XCTAssertTrue(app.buttons["humanModelCard"].waitForExistence(timeout:8))
        wait {
            let value=app.buttons["humanModelCard"].value as? String ?? ""
            return value.hasPrefix("custom:") && value != original
        }
        let customized = app.buttons["humanModelCard"].value as? String
        capture("03-saved-short-hair-portrait")
        app.terminate(); app.launchArguments.append("--keep-companion-data");app.launch()
        XCTAssertTrue(app.buttons["humanModelCard"].waitForExistence(timeout:20))
        XCTAssertEqual(app.buttons["humanModelCard"].value as? String,customized)
        capture("04-portrait-restored")
    }
    @MainActor func testRepeatedReturnAndCompactLandscape() {
        continueAfterFailure=false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing"]
        app.launch()
        for (id,card) in [("studio-robot","modelCard"),("hatsune-miku","mikuModelCard"),("sample-robot","card-sample-robot"),("real-woman","humanModelCard")] {
            app.selectHomeModel(id)
            XCTAssertLessThanOrEqual(app.buttons[card].frame.width,156)
            XCTAssertTrue(app.frame.contains(app.buttons["chat-"+id].frame))
            capture("portrait-"+id)
            for _ in 0..<2 {
                app.buttons[card].tap()
                XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
                app.buttons["viewerBackButton"].tap()
                XCTAssertTrue(app.buttons[card].waitForExistence(timeout:8))
                XCTAssertTrue(app.buttons[card].isHittable)
                XCTAssertFalse(app.buttons["viewerBackButton"].exists)
                XCTAssertFalse(app.staticTexts["正在准备模型"].exists)
            }
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        wait { app.frame.width > app.frame.height }
        XCTAssertTrue(app.buttons["chat-real-woman"].isHittable)
        XCTAssertTrue(app.frame.contains(app.buttons["chat-real-woman"].frame))
        capture("compact-landscape-home")
    }
    @MainActor private func wait(_ condition:@escaping ()->Bool) {
        let predicate=NSPredicate { _,_ in MainActor.assumeIsolated { condition() } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:nil)],timeout:15),.completed)
    }
    @MainActor private func capture(_ name:String) {
        let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)
    }
}
