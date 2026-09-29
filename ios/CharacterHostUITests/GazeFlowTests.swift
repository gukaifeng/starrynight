import XCTest
import UIKit

final class GazeFlowTests: XCTestCase {
    @MainActor func testEyeContactGesturesPanelsAndActions() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--preview-companion","--preview-human","--layout-motion-review"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        settled(app); contact(app); capture("01-human-front",app)
        app.toggleModelLock()
        let stage = app.images["characterGestureRegion"]
        for (name,from,to) in [("02-human-left",0.25,0.75),("03-human-right",0.75,0.25)] {
            stage.coordinate(withNormalizedOffset:CGVector(dx:from,dy:0.45)).press(forDuration:0.1,
                thenDragTo:stage.coordinate(withNormalizedOffset:CGVector(dx:to,dy:0.45)),withVelocity:.slow,thenHoldForDuration:0.1)
            settled(app); contact(app); capture(name,app)
            let event = state(app), g = gaze(event)
            XCTAssertGreaterThan(abs(number(g,"headYaw")),8,"The head must visibly follow the angle")
            XCTAssertGreaterThan(number(g,"headYaw")*number(g,"targetYaw"),0,"The head must turn toward the virtual camera")
        }
        app.openCustomization("framing")
        XCTAssertTrue(app.buttons["closeFramingButton"].waitForExistence(timeout:5))
        app.segmentedControls["framingShotPicker"].buttons["全身互动"].tap()
        app.buttons["framingSizeMin"].tap(); settled(app); contact(app)
        capture("04-human-panel",app)
        app.closeCustomizationPage("closeFramingButton"); settled(app); contact(app)
        let head = state(app), taps = number(head,"headTapCount")
        app.coordinate(withNormalizedOffset:CGVector(dx:number(head,"headX"),dy:number(head,"headY"))).press(forDuration:0.12)
        wait(app) { self.number($0,"headTapCount") > taps }
        settled(app); capture("05-head-touch",app)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            wait(app) { _ in app.frame.width > app.frame.height }
            settled(app); contact(app); capture("06-ipad-landscape",app)
        }
        app.buttons["viewerBackButton"].tap()
        app.selectHomeModel("hatsune-miku")
        let open = app.buttons["chat-hatsune-miku"]
        XCTAssertTrue(open.waitForExistence(timeout:10))

        open.tap()
        XCTAssertTrue(app.buttons["characterActionsMenu"].waitForExistence(timeout:30))
        settled(app); contact(app); capture("07-miku-front",app)
        app.performCharacterAction("Spin")
        wait(app,timeout:16) { $0["name"] as? String == "state" && $0["actionFraming"] as? Bool == false && $0["framingMotionActive"] as? Bool == false }
        contact(app); capture("08-miku-return",app)
        app.performCharacterAction("Bow")
        wait(app,timeout:16) { $0["name"] as? String == "state" && $0["actionFraming"] as? Bool == false && $0["framingMotionActive"] as? Bool == false }
        contact(app)
    }
    @MainActor private func contact(_ app:XCUIApplication) {
        let g = gaze(state(app))
        XCTAssertEqual(number(g,"revision"),1)
        XCTAssertEqual(g["independentEyes"] as? Bool,true)
        XCTAssertGreaterThan(number(g,"weight"),0.99)
        XCTAssertLessThan(number(g,"eyeError"),1.5,"Eyes should settle on the virtual camera: \(g)")
        XCTAssertLessThanOrEqual(abs(number(g,"headYaw")),50.01)
        XCTAssertTrue((-28.01...22.01).contains(number(g,"headPitch")))
    }
    @MainActor private func settled(_ app:XCUIApplication) {
        wait(app) { $0["name"] as? String == "state" && $0["framingMotionActive"] as? Bool == false }
    }
    private func gaze(_ event:[String:Any])->[String:Any] { event["gaze"] as? [String:Any] ?? [:] }
    private func number(_ event:[String:Any],_ key:String)->Double { (event[key] as? NSNumber)?.doubleValue ?? -999 }
    @MainActor private func state(_ app:XCUIApplication)->[String:Any] {
        guard let raw=app.buttons["customizationButton"].value as? String,let data=raw.data(using:.utf8),
              let event=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return [:] }
        return event
    }
    @MainActor private func wait(_ app:XCUIApplication,timeout:TimeInterval=12,_ condition:@escaping ([String:Any])->Bool) {
        let predicate=NSPredicate { _,_ in MainActor.assumeIsolated { condition(self.state(app)) } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:nil)],timeout:timeout),.completed,"State: \(state(app))")
    }
    @MainActor private func capture(_ name:String,_ app:XCUIApplication) {
        let image=XCTAttachment(screenshot:XCUIScreen.main.screenshot()); image.name=name; image.lifetime = .keepAlways; add(image)
        if let data=try? JSONSerialization.data(withJSONObject:state(app),options:[.prettyPrinted,.sortedKeys]) {
            let evidence=XCTAttachment(data:data,uniformTypeIdentifier:"public.json"); evidence.name=name+"-runtime"; evidence.lifetime = .keepAlways; add(evidence)
        }
    }
}
