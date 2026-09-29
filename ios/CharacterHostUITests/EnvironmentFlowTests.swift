import XCTest
import UIKit
final class EnvironmentFlowTests: XCTestCase {
    @MainActor func testSceneSelectionCustomizationReturnPersistenceAndIsolation() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--preview-companion","--layout-motion-review"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        wait(app) { $0["visibleId"] as? String == "sunroom" }
        app.openCustomization("appearance")
        XCTAssertTrue(app.buttons["environment-garden"].waitForExistence(timeout:10))
        app.segmentedControls["environmentCategory"].buttons["室外"].tap()
        tap(app.buttons["environment-garden"],app)
        wait(app) { self.settled($0,"garden") };capture("01-garden-preview")
        app.segmentedControls["environmentMode"].buttons["布置与光影"].tap()
        let handle=app.buttons["调整面板高度"]
        let start=handle.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        start.press(forDuration:0.05,thenDragTo:start.withOffset(CGVector(dx:0,dy:-240)))
        tap(app.buttons["environmentPalette-rose"],app)
        tap(app.switches["environmentDecorations"],app)
        let angle=app.sliders["environmentAngle"];reveal(angle,app);angle.adjust(toNormalizedSliderPosition:0.75)
        let light=app.sliders["studio-lightAngle"];reveal(light,app);light.adjust(toNormalizedSliderPosition:0.82)
        wait(app) { self.settled($0,"garden") && $0["palette"] as? String == "rose" && $0["decorations"] as? Bool == false && ($0["angle"] as? Double ?? 0)>8 && ($0["keyAngle"] as? Double ?? 0)>35 }
        capture("02-personalized-garden")
        app.closeCustomizationPage("closeStudioButton");capture("03-garden-conversation")
        app.openCustomization("appearance")
        app.segmentedControls["environmentCategory"].buttons["室外"].tap()
        tap(app.buttons["environment-seaside"],app)
        wait(app) { self.settled($0,"seaside") };capture("04-seaside-preview")
        app.closeCustomizationPage("closeStudioButton")
        wait(app) { self.settled($0,"seaside") }
        app.openCustomization("appearance")
        app.segmentedControls["environmentCategory"].buttons["室外"].tap()
        tap(app.buttons["environment-seaside"],app)
        tap(app.buttons["environment-courtyard"],app)
        wait(app) { self.settled($0,"courtyard") };capture("05-independent-glb-courtyard")
        tap(app.buttons["environment-garden"],app)
        wait(app) { self.settled($0,"garden") && $0["palette"] as? String == "rose" && $0["decorations"] as? Bool == false }
        app.closeCustomizationPage("closeStudioButton")
        app.terminate();app.launchArguments.append("--keep-companion-data");app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        wait(app) { self.settled($0,"garden") && $0["palette"] as? String == "rose" && ($0["angle"] as? Double ?? 0)>8 };capture("06-restored")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            waitOrientation(app,landscape:true)
            app.openCustomization("appearance")
            XCTAssertTrue(app.buttons["closeStudioButton"].waitForExistence(timeout:8));capture("07-ipad-landscape-space")
            app.closeCustomizationPage("closeStudioButton");XCUIDevice.shared.orientation = .portrait
            waitOrientation(app,landscape:false)
        }
        app.buttons["viewerBackButton"].tap()
        let other=app.buttons["chat-real-woman"];reveal(other,app);other.tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:45))
        wait(app) { self.settled($0,"sunroom") };capture("08-other-character-independent")
        app.openCustomization("appearance")
        app.segmentedControls["studioTabs"].buttons["空间"].tap()
        app.segmentedControls["environmentCategory"].buttons["室外"].tap()
        tap(app.buttons["environment-seaside"],app)
        wait(app) { self.settled($0,"seaside") }
        app.closeCustomizationPage("closeStudioButton");capture("09-human-by-the-sea")
        XCTAssertEqual(app.descendants(matching:.scrollBar).count,0)
        app.openCustomization("appearance")
        tap(app.buttons["restoreStudioButton"],app)
        app.closeCustomizationPage("closeStudioButton")
        wait(app) { self.settled($0,"seaside") }
        capture("10-appearance-reset-keeps-space")
    }
    @MainActor private func waitOrientation(_ app:XCUIApplication,landscape:Bool) {
        let predicate=NSPredicate {_,_ in MainActor.assumeIsolated {
            guard let raw=app.buttons["customizationButton"].value as? String,let data=raw.data(using:.utf8),
                  let event=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let aspect=event["cameraAspect"] as? Double else {return false}
            let window=app.windows.firstMatch.frame,back=app.buttons["viewerBackButton"].frame
            return (aspect>1)==landscape && (window.width>window.height)==landscape && back.minY>=0 && back.midX<window.width*0.4 && app.buttons["customizationButton"].isHittable
        }}
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:nil)],timeout:15),.completed)
    }
    private func settled(_ e:[String:Any],_ id:String)->Bool { e["visibleId"] as? String == id && e["selectedId"] as? String == id && e["transitioning"] as? Bool == false }
    @MainActor private func reveal(_ element:XCUIElement,_ app:XCUIApplication) {
        for _ in 0..<9 {
            if element.isHittable { return }
            let scroll: XCUIElement = app.scrollViews.firstMatch.exists ? app.scrollViews.firstMatch : app
            if element.exists && element.frame.midY < scroll.frame.midY { scroll.swipeDown() } else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func tap(_ element:XCUIElement,_ app:XCUIApplication) { reveal(element,app);element.tap() }
    @MainActor private func state(_ app:XCUIApplication)->[String:Any] {
        guard let value=app.buttons["customizationButton"].value as? String,let data=value.data(using:.utf8),let event=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else {return [:]}
        return event["environment"] as? [String:Any] ?? [:]
    }
    @MainActor private func wait(_ app:XCUIApplication,_ check:@escaping ([String:Any])->Bool) {
        let predicate=NSPredicate {_,_ in MainActor.assumeIsolated {check(self.state(app))}}
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:nil)],timeout:15),.completed,"Environment: \(state(app))")
    }
    @MainActor private func capture(_ name:String) {let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
