import XCTest
import UIKit

final class PanelSurfaceTests: XCTestCase {
    @MainActor func testAdaptiveSurfacesAndLockAcrossPanels() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--preview-companion","--preview-human"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.waitForCharacter { $0["modelControlsLocked"] as? Bool == true }
        let handle = app.buttons["softPanelHandle"]

        app.openCustomization("framing")
        XCTAssertTrue(app.buttons["closeFramingButton"].waitForExistence(timeout:5))
        wait { handle.value as? String == "surfaceAlpha=0.000" }
        capture("01-translucent-framing")
        // Expanded previews occupy the screen on iPhone; narrow iPad editors remain previews.
        expand(handle,app)
        if UIDevice.current.userInterfaceIdiom != .pad {
            wait { handle.value as? String == "surfaceAlpha=1.000" }
            capture("02-expanded-opaque-framing")
        }
        app.closeCustomizationPage("closeFramingButton")
        wait { app.buttons["customizationButton"].isHittable }
        XCTAssertEqual(app.characterRuntime["modelControlsLocked"] as? Bool,true)
        app.openCustomization()
        XCTAssertTrue(app.buttons["closeCustomizationButton"].waitForExistence(timeout:5))
        wait { handle.value as? String == "surfaceAlpha=0.000" }
        capture("03-tools-adaptive-surface")
        if UIDevice.current.userInterfaceIdiom == .pad {
            expand(handle,app)
            wait { handle.value as? String == "surfaceAlpha=1.000" }
            capture("04-ipad-expanded-opaque")
        }
        // Rotation changes the same presented controller into a transparent sidebar.
        XCUIDevice.shared.orientation = .landscapeLeft
        wait { app.frame.width > app.frame.height && handle.value as? String == "surfaceAlpha=0.000" }
        capture("05-landscape-translucent-sidebar")
        app.buttons["closeCustomizationButton"].tap()
        wait { app.buttons["customizationButton"].isHittable }; XCTAssertEqual(app.characterRuntime["modelControlsLocked"] as? Bool,true)
        app.toggleModelLock(); XCTAssertEqual(app.characterRuntime["modelControlsLocked"] as? Bool,false)
        app.openCustomization()
        XCTAssertTrue(app.buttons["closeCustomizationButton"].waitForExistence(timeout:5))
        app.coordinate(withNormalizedOffset:CGVector(dx:0.2,dy:0.35)).tap()
        wait { app.buttons["customizationButton"].isHittable }; XCTAssertEqual(app.characterRuntime["modelControlsLocked"] as? Bool,false)
        capture("06-unlocked-after-outside-dismiss")
    }
    @MainActor private func expand(_ handle:XCUIElement,_ app:XCUIApplication) {
        let start = handle.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        start.press(forDuration:0.1,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.1)),withVelocity:.slow,thenHoldForDuration:0.1)
    }
    @MainActor private func wait(_ condition:@escaping () -> Bool) {
        let predicate = NSPredicate { _,_ in MainActor.assumeIsolated { condition() } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:nil)],timeout:10),.completed)
    }
    @MainActor private func capture(_ name:String) {
        let attachment = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
