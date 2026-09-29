import XCTest

final class StudioFlowTests: XCTestCase {
    @MainActor func testLiveCustomizationReturnAndRestart() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--preview-companion","--preview-human"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        wait(app) { $0["room"] as? String == "sunroom" }
        capture("01-human-conversation")
        app.openCustomization("appearance")
        XCTAssertTrue(app.buttons["closeStudioButton"].waitForExistence(timeout:5))
        app.sliders["studio-faceWidth"].adjust(toNormalizedSliderPosition:0.8)
        wait(app) { ($0["faceWidth"] as? Double ?? 0) > 0.72 }
        capture("02-face-preview")
        app.segmentedControls["studioTabs"].buttons["身形"].tap()
        app.sliders["studio-bodyBuild"].adjust(toNormalizedSliderPosition:0.75)
        wait(app) { ($0["bodyBuild"] as? Double ?? 0) > 0.65 }
        capture("03-body-preview")
        app.segmentedControls["studioTabs"].buttons["造型"].tap()
        app.segmentedControls["studio-发型"].buttons["短发"].tap()
        wait(app) { $0["hair"] as? String == "bob" }
        capture("04-short-hair")
        app.segmentedControls["studioTabs"].buttons["空间"].tap()
        app.buttons["environment-evening"].tap()
        app.segmentedControls["environmentMode"].buttons["布置与光影"].tap()
        app.scrollViews.firstMatch.swipeUp()
        app.sliders["studio-lightAngle"].adjust(toNormalizedSliderPosition:0.82)
        wait(app) { $0["room"] as? String == "evening" && ($0["lightAngle"] as? Double ?? 0) > 40 }
        capture("05-room-and-light")
        app.closeCustomizationPage("closeStudioButton")
        app.openCustomization("appearance")
        app.segmentedControls["studioTabs"].buttons["空间"].tap()
        app.buttons["environment-studio"].tap()
        wait(app) { $0["room"] as? String == "studio" }
        app.closeCustomizationPage("closeStudioButton")
        wait(app) { $0["room"] as? String == "studio" }
        app.terminate()
        app.launchArguments.append("--keep-companion-data")
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        wait(app) { $0["room"] as? String == "studio" && $0["hair"] as? String == "bob" && ($0["faceWidth"] as? Double ?? 0) > 0.72 }
        capture("06-restored-custom-character")
        app.openCustomization("appearance")
        app.segmentedControls["studioTabs"].buttons["身形"].tap()
        let restore=app.buttons["restoreStudioButton"]
        if !restore.isHittable { app.scrollViews.firstMatch.swipeUp() }
        restore.tap(); app.closeCustomizationPage("closeStudioButton")
        wait(app) { $0["room"] as? String == "studio" && $0["hair"] as? String == "long" }
        capture("07-recommended-restored")
    }
    @MainActor private func studio(_ app: XCUIApplication) -> [String:Any] {
        guard let json=app.buttons["customizationButton"].value as? String,let data=json.data(using:.utf8),
              let event=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else { return [:] }
        return event["studio"] as? [String:Any] ?? [:]
    }
    @MainActor private func wait(_ app: XCUIApplication, condition: @escaping ([String:Any])->Bool) {
        let predicate=NSPredicate { _,_ in MainActor.assumeIsolated { condition(self.studio(app)) } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:nil)],timeout:12),.completed)
    }
    @MainActor private func capture(_ name:String) {
        let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)
    }
}
