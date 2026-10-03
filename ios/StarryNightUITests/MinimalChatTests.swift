import XCTest

final class MinimalChatTests:XCTestCase {
    @MainActor private func capture(_ name:String) {
        let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)
    }
    @MainActor func testGuestCanvasNameOpensCustomizationAndMutePersists() {
        continueAfterFailure = false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch()
        let name=app.buttons["customizationButton"]
        XCTAssertTrue(name.waitForExistence(timeout:60))
        XCTAssertTrue(name.label.hasPrefix("初音未来"))
        XCTAssertEqual(name.frame.midX,app.frame.midX,accuracy:1)
        XCTAssertFalse(app.staticTexts["guestAllowance"].exists)
        XCTAssertFalse(app.staticTexts["companionPresence"].exists)
        XCTAssertFalse(app.staticTexts["speechStatus"].exists)
        XCTAssertFalse(app.buttons["voiceMuteButton"].exists)
        RunLoop.current.run(until:Date().addingTimeInterval(3))
        capture("minimal-guest-home")
        name.tap()
        let mute=app.switches["characterMuteToggle"]
        XCTAssertTrue(mute.waitForExistence(timeout:8));XCTAssertEqual(mute.value as? String,"0")
        mute.tap();XCTAssertEqual(mute.value as? String,"1")
        capture("minimal-customization-mute")
        app.buttons["closeCustomizationButton"].tap()
        XCTAssertTrue(app.buttons["starter-hello"].isHittable)
        app.terminate()
        app.launchArguments += ["--keep-companion-data","--keep-auth-data"]
        app.launch();XCTAssertTrue(name.waitForExistence(timeout:60));name.tap()
        XCTAssertTrue(mute.waitForExistence(timeout:8));XCTAssertEqual(mute.value as? String,"1")
        app.buttons["closeCustomizationButton"].tap()
        app.buttons["tab-messages"].tap()
        XCTAssertTrue(app.buttons["message-hatsune-miku"].waitForExistence(timeout:8))
        capture("minimal-brand-and-dock")
    }
}
