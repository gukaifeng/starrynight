import XCTest
import UIKit

final class InterfaceMotionTests: XCTestCase {
    @MainActor func testSheetsKeyboardDraftResumeAndRestore() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--preview-companion","--preview-human","--layout-motion-review"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        settled(app)
        let initial = state(app), originalDistance = number(initial,"distance"), snaps = number(initial,"cameraSnapCount")
        XCTAssertEqual(number(initial,"layoutMotionRevision"),2)
        capture("01-conversation",app)

        let input = app.textViews["chatInput"].exists ? app.textViews["chatInput"] : app.textFields["chatInput"]
        input.tap(); input.typeText("hello")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5))
        XCTAssertLessThanOrEqual(input.frame.maxY,app.keyboards.firstMatch.frame.minY+1)
        capture("02-keyboard",app)
        app.openCustomization("framing")
        XCTAssertTrue(app.buttons["closeFramingButton"].waitForExistence(timeout:5))
        settled(app); fullRender(app)
        XCTAssertEqual(number(state(app),"distance"),originalDistance,accuracy:originalDistance*0.002)
        capture("03-preview",app)
        app.segmentedControls["framingShotPicker"].buttons["全身互动"].tap()
        app.buttons["framingSizeMax"].tap()
        settled(app)
        let draftDistance = number(state(app),"distance")
        capture("04-full-preview",app)

        // Backgrounding must not apply the saved profile over an unsaved preview or snap its camera.
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["closeFramingButton"].waitForExistence(timeout:10))
        settled(app)
        XCTAssertEqual(state(app)["framingShot"] as? String,"full")
        XCTAssertEqual(number(state(app),"framingSize"),1.1,accuracy:0.001)
        XCTAssertEqual(number(state(app),"distance"),draftDistance,accuracy:draftDistance*0.003)
        XCTAssertEqual(number(state(app),"cameraSnapCount"),snaps)
        capture("05-resumed-draft",app)
        app.buttons["restoreFramingButton"].tap()
        app.closeCustomizationPage("closeFramingButton")
        restored(app,distance:originalDistance,snaps:snaps)
        capture("06-cancel-restored",app)

        app.openCustomization("appearance")
        XCTAssertTrue(app.buttons["closeStudioButton"].waitForExistence(timeout:5))
        app.segmentedControls["studioTabs"].buttons["身形"].tap()
        settled(app); fullRender(app)
        capture("07-studio-body",app)
        app.segmentedControls["studioTabs"].buttons["面容"].tap()
        app.closeCustomizationPage("closeStudioButton")
        restored(app,distance:originalDistance,snaps:snaps)

        app.openCustomization("framing")
        XCTAssertTrue(app.buttons["closeFramingButton"].waitForExistence(timeout:5))
        app.buttons["framingAngleRight"].tap(); app.buttons["framingAngleFront"].tap()
        let panel = app.descendants(matching:.any)["framingPanel"].firstMatch
        panel.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.01)).press(forDuration:0.1,
            thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.98)))
        wait { !app.buttons["closeFramingButton"].exists }
        restored(app,distance:originalDistance,snaps:snaps)
        capture("08-swipe-restored",app)
        app.openCustomization("framing")
        XCTAssertTrue(app.buttons["closeFramingButton"].waitForExistence(timeout:5))
        let expandedPanel = app.descendants(matching:.any)["framingPanel"].firstMatch
        expandedPanel.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.01)).press(forDuration:0.1,
            thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.12)))
        XCTAssertTrue(app.buttons["closeFramingButton"].isHittable)
        app.closeCustomizationPage("closeFramingButton")
        restored(app,distance:originalDistance,snaps:snaps)


        app.openCustomization("music")
        XCTAssertTrue(app.buttons["closeMusicButton"].waitForExistence(timeout:5))
        app.closeCustomizationPage("closeMusicButton")
        app.openCustomization()
        XCTAssertTrue(app.buttons["closeCustomizationButton"].waitForExistence(timeout:5))
        app.buttons["closeCustomizationButton"].tap()
        restored(app,distance:originalDistance,snaps:snaps)
        capture("09-popups-restored",app)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            wait { app.frame.width > app.frame.height }; settled(app); fullRender(app)
            input.tap(); input.typeText("hi")
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5))
            XCTAssertGreaterThan(input.frame.minX,app.frame.midX)
            capture("10-landscape-keyboard",app)
            app.openCustomization("framing")
            XCTAssertTrue(app.buttons["closeFramingButton"].waitForExistence(timeout:5))
            app.closeCustomizationPage("closeFramingButton")
            settled(app); fullRender(app)
            XCTAssertEqual(number(state(app),"cameraSnapCount"),snaps)
            capture("11-landscape-restored",app)
        }
    }
    @MainActor private func fullRender(_ app:XCUIApplication) {
        let rect = state(app)["renderViewport"] as? [String:Any] ?? [:]
        XCTAssertEqual(number(rect,"x"),0); XCTAssertEqual(number(rect,"y"),0)
        XCTAssertEqual(number(rect,"width"),1); XCTAssertEqual(number(rect,"height"),1)
    }
    @MainActor private func restored(_ app:XCUIApplication,distance:Double,snaps:Double) {
        settled(app); fullRender(app)
        XCTAssertEqual(number(state(app),"distance"),distance,accuracy:distance*0.002)
        XCTAssertEqual(number(state(app),"cameraSnapCount"),snaps)
        XCTAssertTrue(app.buttons["customizationButton"].isHittable)
        wait { !app.keyboards.firstMatch.exists }
    }
    @MainActor private func settled(_ app:XCUIApplication) {
        wait { self.state(app)["name"] as? String == "state" && self.state(app)["framingMotionActive"] as? Bool == false }
    }
    @MainActor private func state(_ app:XCUIApplication) -> [String:Any] {
        guard let raw=app.buttons["customizationButton"].value as? String,let data=raw.data(using:.utf8),
              let value=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return [:] }
        return value
    }
    private func number(_ state:[String:Any],_ key:String) -> Double { (state[key] as? NSNumber)?.doubleValue ?? -999 }
    @MainActor private func wait(_ check:@escaping ()->Bool) {
        let expectation=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in MainActor.assumeIsolated { check() } },object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[expectation],timeout:15),.completed)
    }
    @MainActor private func capture(_ name:String,_ app:XCUIApplication) {
        let image=XCTAttachment(screenshot:XCUIScreen.main.screenshot());image.name=name;image.lifetime = .keepAlways;add(image)
        if let data=try? JSONSerialization.data(withJSONObject:state(app),options:[.prettyPrinted,.sortedKeys]) {
            let json=XCTAttachment(data:data,uniformTypeIdentifier:"public.json");json.name=name+"-runtime";json.lifetime = .keepAlways;add(json)
        }
    }
}
