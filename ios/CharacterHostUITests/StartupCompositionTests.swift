import XCTest

final class StartupCompositionTests:XCTestCase {
    @MainActor func testBackgroundDuringStartupResumesToPreparedConversation() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--auth-testing","--test-ready-delay=8"]
        app.launch()
        XCTAssertTrue(app.otherElements["appStartupScreen"].waitForExistence(timeout:8))
        XCUIDevice.shared.press(.home)
        RunLoop.current.run(until:Date().addingTimeInterval(1))
        app.activate()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:30))
        XCTAssertFalse(app.otherElements["appStartupScreen"].exists)
        XCTAssertEqual(app.characterRuntime["framingMotionActive"] as? Bool,false)
        XCTAssertEqual(app.characterRuntime["actionFraming"] as? Bool,false)
        XCTAssertTrue(app.textFields["chatInput"].isHittable)
    }
    @MainActor func testColdIntroWaitsForContentAndNeverReplaysOnResume() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--auth-testing","--test-ready-delay=4","--layout-motion-review"]
        app.launch()
        let startup = app.otherElements["appStartupScreen"]
        XCTAssertTrue(startup.waitForExistence(timeout:8))
        let waiting = NSPredicate { _,_ in MainActor.assumeIsolated { startup.value as? String == "等待就绪" } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:waiting,object:nil)],timeout:6),.completed)
        XCTAssertFalse(app.buttons["customizationButton"].exists,"Chat stays hidden until both startup and rendering are ready")
        XCTAssertFalse(app.descendants(matching:.any).matching(identifier:"characterArrival").firstMatch.exists)
        capture("app-startup-waiting")
        RunLoop.current.run(until:Date().addingTimeInterval(0.55))
        capture("app-startup-breath")
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:30))
        XCTAssertFalse(startup.exists)
        let first = app.characterRuntime
        XCTAssertEqual(first["actionFraming"] as? Bool,false)
        XCTAssertEqual(first["framingMotionActive"] as? Bool,false)
        XCTAssertEqual((first["characterPlatform"] as? [String:Any])?["bodyCues"] as? Int,0)
        capture("app-startup-final-framing")
        RunLoop.current.run(until:Date().addingTimeInterval(3))
        XCTAssertEqual(app.characterRuntime["cameraSnapCount"] as? Int,first["cameraSnapCount"] as? Int)
        XCTAssertEqual((app.characterRuntime["distance"] as? NSNumber)?.doubleValue ?? -2,
                       (first["distance"] as? NSNumber)?.doubleValue ?? -1,accuracy:0.0001)
        XCUIDevice.shared.press(.home);app.activate()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:10))
        XCTAssertFalse(startup.exists,"Returning from the background does not replay startup")
        XCTAssertEqual(app.characterRuntime["presentationId"] as? Int,first["presentationId"] as? Int)
    }
    @MainActor private func capture(_ name:String) {
        let image=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        image.name=name;image.lifetime = .keepAlways;add(image)
    }
}
