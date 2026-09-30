import XCTest

final class StartupCompositionTests:XCTestCase {
    @MainActor func testNativeHomeAppearsBeforeCharacterAndKeepsFinalFraming() {
        let app = launch(delay:10)
        assertNativeHome(app)
        XCTAssertFalse(app.buttons["customizationButton"].exists,"Unity is deliberately not ready yet")
        XCTAssertFalse(app.descendants(matching:.any).matching(identifier:"characterArrival").firstMatch.exists,
                       "Cold launch opens native home instead of replacing the brand cover with another loading page")
        capture("01-native-home-before-character")
        waitForConversation(app)
        let first = app.characterRuntime
        XCTAssertEqual(first["framingMotionActive"] as? Bool,false)
        XCTAssertEqual(first["actionFraming"] as? Bool,false)
        capture("02-character-ready")
        RunLoop.current.run(until:Date().addingTimeInterval(2))
        XCTAssertEqual(app.characterRuntime["cameraSnapCount"] as? Int,first["cameraSnapCount"] as? Int)
        XCTAssertEqual((app.characterRuntime["distance"] as? NSNumber)?.doubleValue ?? -2,
                       (first["distance"] as? NSNumber)?.doubleValue ?? -1,accuracy:0.0001)
        XCUIDevice.shared.press(.home); app.activate()
        waitForConversation(app)
        XCTAssertEqual(app.characterRuntime["presentationId"] as? Int,first["presentationId"] as? Int,
                       "Foreground return retains the same conversation")
        XCTAssertFalse(app.otherElements["appStartupScreen"].exists)
    }

    @MainActor func testTabsWorkDuringInitialLoadAndLateReadyDoesNotStealNavigation() {
        let app = launch(delay:12)
        assertNativeHome(app)
        // Allow the real first frame to enqueue its deferred ready delivery.
        // Leaving immediately can pause Unity before Start(), which exercises a
        // different (also supported) cancellation path instead of a late reply.
        RunLoop.current.run(until:Date().addingTimeInterval(5))
        app.buttons["tab-discover"].tap()
        XCTAssertTrue(app.textFields["discoverSearch"].waitForExistence(timeout:5))
        XCTAssertTrue(app.textFields["discoverSearch"].isHittable)
        app.buttons["tab-messages"].tap()
        XCTAssertTrue(app.textFields["conversationSearchField"].waitForExistence(timeout:5))
        capture("03-messages-while-character-pending")
        // The deferred sceneReady arrives while another tab is on screen. It must
        // not resume a cancelled presentation, hide navigation, or start a greeting.
        let hijacked = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in MainActor.assumeIsolated {
            app.buttons["customizationButton"].exists || app.otherElements["appStartupScreen"].exists
        } },object:nil)
        hijacked.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for:[hijacked],timeout:14),.completed)
        XCTAssertTrue(app.textFields["conversationSearchField"].isHittable)
        app.buttons["tab-home"].tap()
        waitForConversation(app)
        capture("04-conversation-after-cancelled-initial-load")
    }

    @MainActor func testBackgroundDuringCharacterLoadResumesWithoutBrandCover() {
        let app = launch(delay:10)
        assertNativeHome(app)
        XCUIDevice.shared.press(.home)
        RunLoop.current.run(until:Date().addingTimeInterval(1))
        app.activate()
        XCTAssertFalse(app.otherElements["appStartupScreen"].exists)
        waitForConversation(app)
        XCTAssertEqual(app.characterRuntime["framingMotionActive"] as? Bool,false)
        XCTAssertEqual(app.characterRuntime["actionFraming"] as? Bool,false)
        capture("05-background-during-character-load")
    }

    @MainActor private func launch(delay:Int) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--auth-testing",
                               "--test-ready-delay=\(delay)","--startup-review","--layout-motion-review"]
        app.launch()
        return app
    }
    @MainActor private func assertNativeHome(_ app:XCUIApplication,file:StaticString = #filePath,line:UInt = #line) {
        XCTAssertTrue(app.otherElements["conversationPreparing"].waitForExistence(timeout:8),file:file,line:line)
        XCTAssertFalse(app.otherElements["appStartupScreen"].exists,file:file,line:line)
        for tab in ["home","messages","discover","mine"] {
            XCTAssertTrue(app.buttons["tab-"+tab].isHittable,file:file,line:line)
        }
    }
    @MainActor private func waitForConversation(_ app:XCUIApplication,file:StaticString = #filePath,line:UInt = #line) {
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:30),file:file,line:line)
        XCTAssertFalse(app.otherElements["conversationPreparing"].exists,file:file,line:line)
        XCTAssertTrue(app.textViews["chatInput"].isHittable,file:file,line:line)
    }
    @MainActor private func capture(_ name:String) {
        let image=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        image.name=name; image.lifetime = .keepAlways; add(image)
    }
}
