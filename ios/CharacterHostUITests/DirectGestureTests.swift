import XCTest
import UIKit

final class DirectGestureTests: XCTestCase {
    @MainActor func testBoundedGesturesPersistenceAndPrecisionPanel() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--preview-companion","--preview-human"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        wait(app) { $0["name"] as? String == "state" }
        let region = app.images["characterGestureRegion"]
        XCTAssertEqual(app.characterRuntime["modelControlsLocked"] as? Bool,true)
        wait(app) { $0["framingGesturesEnabled"] as? Bool == false && $0["gesturesEnabled"] as? Bool == true }
        drag(region,from:0.25,to:0.75)
        region.pinch(withScale:1.6,velocity:1)
        XCTAssertEqual(number(state(app),"framingAngle"),0,accuracy:0.01)
        XCTAssertEqual(number(state(app),"framingSize"),1,accuracy:0.01)
        XCTAssertEqual(number(state(app),"gestureCount"),0)
        let headWhileLocked = state(app), previousTaps = number(headWhileLocked,"headTapCount")
        app.coordinate(withNormalizedOffset:CGVector(dx:number(headWhileLocked,"headX"),dy:number(headWhileLocked,"headY"))).press(forDuration:0.12)
        wait(app) { self.number($0,"headTapCount") > previousTaps }
        capture("00-default-locked-head-interaction")
        app.toggleModelLock()
        XCTAssertEqual(app.characterRuntime["modelControlsLocked"] as? Bool,false)
        wait(app) { $0["framingGesturesEnabled"] as? Bool == true }
        let initialTaps = number(state(app),"headTapCount")
        drag(region,from:0.25,to:0.75)
        wait(app) { self.number($0,"framingAngle") < -19.9 && self.number($0,"gestureCount") == 1 }
        XCTAssertEqual(number(state(app),"headTapCount"),initialTaps)
        // Reversing at the limit must respond immediately, without accumulating off-screen motion.
        drag(region,from:0.65,to:0.55)
        wait(app) { self.number($0,"framingAngle") > -19 && self.number($0,"gestureCount") == 2 }
        let angle = number(state(app),"framingAngle")
        region.pinch(withScale:1.6,velocity:1)
        wait(app) { self.number($0,"framingSize") > 1.099 && self.number($0,"gestureCount") == 3 }
        region.pinch(withScale:0.6,velocity:-1)
        wait(app) { self.number($0,"framingSize") < 0.901 && self.number($0,"gestureCount") == 4 }
        XCTAssertEqual(number(state(app),"framingAngle"),angle,accuracy:0.01,"The last pinch finger cannot become a rotation")
        XCTAssertEqual(number(state(app),"headTapCount"),initialTaps,"A pinch cannot become a head tap")
        capture("01-direct-gesture")

        app.openCustomization("framing")
        XCTAssertTrue(app.buttons["closeFramingButton"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["framingSizeValue"].label,"90%")
        XCTAssertTrue(app.staticTexts["framingAngleValue"].label.contains(String(format:"%.0f",abs(angle))))
        app.buttons["restoreFramingButton"].tap()
        wait(app) { self.number($0,"framingSize") == 1 && self.number($0,"framingAngle") == 0 }
        drag(region,from:0.3,to:0.7)
        XCTAssertEqual(number(state(app),"gestureCount"),4,"The outside touch is consumed without rotating the model")
        XCTAssertFalse(app.buttons["closeFramingButton"].exists,"The outside touch closes only the panel")
        wait(app) { self.number($0,"framingSize") == 1 && self.number($0,"framingAngle") == 0 }
        XCTAssertEqual(app.characterRuntime["modelControlsLocked"] as? Bool,false,"Closing the editor preserves the chosen lock state")
        app.toggleModelLock()
        app.openCustomization("framing"); app.buttons["framingAngleRight"].tap(); app.closeCustomizationPage("closeFramingButton")
        wait(app) { self.number($0,"framingAngle") == 20 && $0["framingGesturesEnabled"] as? Bool == false }
        XCTAssertEqual(app.characterRuntime["modelControlsLocked"] as? Bool,true,"Precision controls must not unlock direct gestures")
        drag(region,from:0.25,to:0.75)
        XCTAssertEqual(number(state(app),"framingAngle"),20,accuracy:0.01)
        app.openCustomization("framing"); app.buttons["restoreFramingButton"].tap(); app.closeCustomizationPage("closeFramingButton")
        app.terminate(); app.launchArguments.append("--keep-companion-data"); app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        wait(app) { self.number($0,"framingSize") == 1 && self.number($0,"framingAngle") == 0 }
        capture("02-restored-gesture")
        XCTAssertEqual(app.characterRuntime["modelControlsLocked"] as? Bool,true)
        wait(app) { $0["framingGesturesEnabled"] as? Bool == false }

        // Swiping messages belongs to the chat; it must not rotate the scene behind it.
        let beforeScroll = state(app)
        app.scrollViews["chatMessages"].swipeDown()
        Thread.sleep(forTimeInterval:0.7)
        XCTAssertEqual(number(state(app),"gestureCount"),number(beforeScroll,"gestureCount"))
        XCTAssertEqual(number(state(app),"framingAngle"),0,accuracy:0.01)
        app.openCustomization("framing")
        app.buttons["framingSizeMax"].tap(); app.buttons["framingAngleRight"].tap()
        app.closeCustomizationPage("closeFramingButton")
        wait(app) { self.number($0,"framingAngle") == 20 && self.number($0,"framingSize") > 1.099 }
        app.toggleModelLock(); wait(app) { $0["framingGesturesEnabled"] as? Bool == true }
        drag(region,from:0.35,to:0.45)
        wait(app) { self.number($0,"framingAngle") < 19 && self.number($0,"framingAngle") > 0 }
        app.openCustomization("framing"); app.buttons["restoreFramingButton"].tap(); app.closeCustomizationPage("closeFramingButton")
        wait(app) { self.number($0,"framingAngle") == 0 && self.number($0,"framingSize") == 1 && $0["name"] as? String == "state" }
        let head = state(app), taps = number(head,"headTapCount")
        app.coordinate(withNormalizedOffset:CGVector(dx:number(head,"headX"),dy:number(head,"headY"))).press(forDuration:0.12)
        wait(app) { self.number($0,"headTapCount") > taps }
        capture("03-head-after-gesture")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            let wide = NSPredicate { _,_ in MainActor.assumeIsolated { app.frame.width > app.frame.height } }
            XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:wide,object:nil)],timeout:8),.completed)
            let before = number(state(app),"gestureCount")
            drag(region,from:0.35,to:0.55)
            wait(app) { self.number($0,"gestureCount") > before && self.number($0,"framingAngle") < -5 }
            capture("04-ipad-landscape-gesture")
        }
    }
    @MainActor private func drag(_ region:XCUIElement,from:CGFloat,to:CGFloat) {
        region.coordinate(withNormalizedOffset:CGVector(dx:from,dy:0.5)).press(forDuration:0.1,
            thenDragTo:region.coordinate(withNormalizedOffset:CGVector(dx:to,dy:0.5)),withVelocity:.slow,thenHoldForDuration:0.1)
    }
    @MainActor private func state(_ app:XCUIApplication) -> [String:Any] {
        guard let raw = app.buttons["customizationButton"].value as? String,let data = raw.data(using:.utf8),
              let event = try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return [:] }
        return event
    }
    private func number(_ value:[String:Any],_ key:String) -> Double { (value[key] as? NSNumber)?.doubleValue ?? -999 }
    @MainActor private func wait(_ app:XCUIApplication,_ condition:@escaping ([String:Any]) -> Bool) {
        let predicate = NSPredicate { _,_ in MainActor.assumeIsolated { condition(self.state(app)) } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:nil)],timeout:10),.completed,"State: \(state(app))")
    }
    @MainActor private func capture(_ name:String) {
        let a = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
        if let data = try? JSONSerialization.data(withJSONObject:state(XCUIApplication()),options:[.sortedKeys,.prettyPrinted]) {
            let evidence = XCTAttachment(data:data,uniformTypeIdentifier:"public.json"); evidence.name = name+"-runtime"; evidence.lifetime = .keepAlways; add(evidence)
        }
    }
}
