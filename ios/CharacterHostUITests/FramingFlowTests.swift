import XCTest
import UIKit

final class FramingFlowTests: XCTestCase {
    @MainActor func testPhoneFramingPersistenceAndInteraction() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--preview-companion","--preview-miku"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:45))
        waitFor(app) { $0["framingShot"] as? String == "conversation" && $0["name"] as? String == "state" }
        capture("01-miku-conversation")
        app.openCustomization("framing")
        XCTAssertTrue(app.buttons["closeFramingButton"].waitForExistence(timeout:5))
        app.segmentedControls["framingShotPicker"].buttons["全身互动"].tap()
        app.buttons["framingSizeMax"].tap()
        app.buttons["framingAngleLeft"].tap()
        XCTAssertEqual(app.staticTexts["framingSizeValue"].label,"110%")
        XCTAssertEqual(app.staticTexts["framingAngleValue"].label,"左 20°")
        capture("02-framing-controls")
        app.closeCustomizationPage("closeFramingButton")
        waitFor(app) { $0["framingShot"] as? String == "full" && self.number($0,"framingSize") > 1.099 && self.number($0,"framingAngle") == -20 && $0["name"] as? String == "state" }
        capture("03-full-left")
        let stage = app.images["characterStage"]
        XCTAssertTrue(stage.exists)
        // Direct gestures, clamping, tap separation and persistence are covered in DirectGestureTests.
        // Returning now saves the preview, including explicit restoration of defaults.
        app.openCustomization("framing")
        app.buttons["restoreFramingButton"].tap()
        app.closeCustomizationPage("closeFramingButton")
        waitFor(app) { $0["framingShot"] as? String == "conversation" && self.number($0,"framingAngle") == 0 }
        app.openCustomization("framing")
        app.segmentedControls["framingShotPicker"].buttons["对话近景"].tap()
        app.buttons["framingSizeMin"].tap()
        app.buttons["framingAngleRight"].tap()
        app.closeCustomizationPage("closeFramingButton")
        waitFor(app) { $0["framingShot"] as? String == "conversation" && self.number($0,"framingAngle") == 20 && $0["name"] as? String == "state" }
        let input = app.textViews["chatInput"].exists ? app.textViews["chatInput"] : app.textFields["chatInput"]
        XCTAssertTrue(input.exists); input.tap(); input.typeText("你好")
        waitFor(app) { self.number($0,"framingAngle") == 20 && $0["name"] as? String == "state" }
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        capture("04-keyboard-framing")
        app.openCustomization("framing") // dismiss the keyboard before presenting framing
        app.closeCustomizationPage("closeFramingButton")
        waitFor(app) { $0["name"] as? String == "state" }
        let head = values(app), taps = number(head,"headTapCount")
        app.coordinate(withNormalizedOffset:CGVector(dx:number(head,"headX"),dy:number(head,"headY"))).tap()
        waitFor(app) { self.number($0,"headTapCount") > taps }
        capture("05-head-interaction")
        app.buttons["viewerBackButton"].tap()
        app.selectHomeModel("studio-robot")
        let robot = app.buttons["chat-studio-robot"]
        XCTAssertTrue(robot.waitForExistence(timeout:5)); robot.tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:20))
        waitFor(app) { $0["modelId"] as? String == "studio-robot" && self.number($0,"framingSize") == 1 && self.number($0,"framingAngle") == 0 }
        capture("06-luma-default")
        app.terminate()
        app.launchArguments.append("--keep-companion-data"); app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:45))
        waitFor(app) { $0["modelId"] as? String == "hatsune-miku" && self.number($0,"framingSize") < 0.901 && self.number($0,"framingAngle") == 20 }
        capture("07-miku-restored")
        // Re-entered chat shares saved framing and uses automatic action framing.
        app.buttons["viewerBackButton"].tap()
        let open = app.buttons["chat-hatsune-miku"]
        app.selectHomeModel("hatsune-miku")
        XCTAssertTrue(open.isHittable); open.tap()
        XCTAssertTrue(app.buttons["characterActionsMenu"].waitForExistence(timeout:20))
        waitFor(app) { $0["framingShot"] as? String == "conversation" && self.number($0,"framingAngle") == 20 }
        app.performCharacterAction("Dance")
        waitFor(app) { $0["effectiveShot"] as? String == "full" && $0["actionFraming"] as? Bool == true }
        capture("08-action-full")
        waitFor(app,timeout:12) { $0["effectiveShot"] as? String == "conversation" && $0["actionFraming"] as? Bool == false && $0["name"] as? String == "state" }
        capture("09-action-return")
        app.openCustomization("framing"); app.buttons["restoreFramingButton"].tap(); app.closeCustomizationPage("closeFramingButton")
        waitFor(app) { self.number($0,"framingSize") == 1 && self.number($0,"framingAngle") == 0 }
    }
    @MainActor func testKeyboardLayoutAndLumaHead() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--preview-companion"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:45))
        waitFor(app) { $0["modelId"] as? String == "studio-robot" && $0["name"] as? String == "state" }
        let head = values(app), taps = number(head,"headTapCount")
        // Hold for a human-like short tap so frame-polled Unity input sees the contact.
        // This remains below the runtime's 0.4 s maximum; the real head event must fire.
        app.coordinate(withNormalizedOffset:CGVector(dx:number(head,"headX"),dy:number(head,"headY"))).press(forDuration:0.12)
        waitFor(app) { self.number($0,"headTapCount") == taps + 1 }
        capture("13-luma-head")
        let input = app.textViews["chatInput"].exists ? app.textViews["chatInput"] : app.textFields["chatInput"]
        input.tap(); input.typeText("你好")
        let title = app.staticTexts["写下此刻想说的话"]
        XCTAssertTrue(title.waitForExistence(timeout:5)); XCTAssertEqual(title.label,"写下此刻想说的话")
        XCTAssertLessThan(title.frame.maxY,input.frame.minY)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        capture("14-compact-keyboard")
        app.buttons["sendMessageButton"].tap()
        XCTAssertTrue(app.staticTexts.matching(identifier:"assistantMessage").firstMatch.waitForExistence(timeout:20))
        waitFor(app,timeout:12) { self.number($0,"actionCount") >= 2 && $0["actionFraming"] as? Bool == false }
        capture("15-luma-conversation")
    }
    @MainActor func testIPadFramingRotationAndDismissal() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad only") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--preview-companion","--preview-miku"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:45))
        app.openCustomization("framing")
        app.buttons["framingSizeMax"].tap()
        app.buttons["framingAngleRight"].tap()
        app.closeCustomizationPage("closeFramingButton")
        waitFor(app) { self.number($0,"framingAngle") == 20 && $0["name"] as? String == "state" }
        let stage = app.images["characterStage"]
        XCTAssertGreaterThan(stage.frame.height,app.frame.height * 0.95,"The conversation renders the room behind its bottom overlay")
        capture("10-ipad-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = NSPredicate { _,_ in MainActor.assumeIsolated { app.frame.width > app.frame.height } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:landscape,object:nil)],timeout:8),.completed)
        waitFor(app) { self.number($0,"framingAngle") == 20 && self.number($0,"framingSize") > 1.099 && $0["name"] as? String == "state" }
        XCTAssertTrue(app.buttons["customizationButton"].isHittable)
        capture("11-ipad-landscape")
        app.openCustomization("framing")
        app.buttons["restoreFramingButton"].tap()
        // Swipe from the side grabber; dismissal saves the restored defaults.
        let panel = app.descendants(matching:.any)["framingPanel"].firstMatch
        let top = panel.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.01))
        top.press(forDuration:0.1,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.99,dy:0.2)))
        waitFor(app) { self.number($0,"framingAngle") == 0 && self.number($0,"framingSize") == 1 }
        XCTAssertTrue(app.buttons["customizationButton"].isHittable)
        capture("12-ipad-dismissed")
    }
    @MainActor private func values(_ app: XCUIApplication) -> [String:Any] {
        guard let raw = app.buttons["customizationButton"].value as? String, let data = raw.data(using:.utf8),
              let value = try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return [:] }
        return value
    }
    private func number(_ value:[String:Any],_ key:String) -> Double { (value[key] as? NSNumber)?.doubleValue ?? -999 }
    @MainActor private func waitFor(_ app: XCUIApplication, timeout:TimeInterval = 8, _ check: @escaping ([String:Any]) -> Bool) {
        let predicate = NSPredicate { _,_ in MainActor.assumeIsolated { check(self.values(app)) } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:nil)],timeout:timeout),.completed,"Runtime state: \(values(app))")
    }
    @MainActor private func capture(_ name:String) {
        let attachment = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
        if let data = try? JSONSerialization.data(withJSONObject:values(XCUIApplication()),options:[.prettyPrinted,.sortedKeys]) {
            let state = XCTAttachment(data:data,uniformTypeIdentifier:"public.json")
            state.name = name + "-runtime.json"; state.lifetime = .keepAlways; add(state)
        }
    }
}
