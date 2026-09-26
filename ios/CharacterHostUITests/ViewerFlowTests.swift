import XCTest

final class ViewerFlowTests: XCTestCase {
    @MainActor
    func testA_CancelDuringInitializationAndReopen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--test-ready-delay=4"]
        app.launch()
        let open = app.buttons["openModelButton"]
        XCTAssertTrue(open.waitForExistence(timeout:10)); open.tap()
        let cancel = app.buttons["cancelLoadingButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout:5))
        capture("09-loading")
        cancel.tap()
        XCTAssertTrue(open.waitForExistence(timeout:5)); open.tap()
        XCTAssertTrue(app.buttons["viewerBackButton"].waitForExistence(timeout:12))
        capture("10-cancel-recovered")
        app.buttons["viewerBackButton"].tap()
        XCTAssertTrue(open.waitForExistence(timeout:5))
    }
    @MainActor
    func testB_TimeoutAndRecover() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--test-ready-delay=18"]
        app.launch()
        let open = app.buttons["openModelButton"]
        XCTAssertTrue(open.waitForExistence(timeout:10)); open.tap()
        XCTAssertTrue(app.staticTexts["准备模型所需时间较长，请返回后重试。"].waitForExistence(timeout:22))
        capture("11-timeout")
        app.buttons["cancelLoadingButton"].tap()
        XCTAssertTrue(open.waitForExistence(timeout:5)); open.tap()
        XCTAssertTrue(app.buttons["viewerBackButton"].waitForExistence(timeout:12))
        capture("12-timeout-recovered")
        app.buttons["viewerBackButton"].tap()
    }
    @MainActor
    func testCompleteViewerFlow() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let open = app.buttons["openModelButton"]
        XCTAssertTrue(open.waitForExistence(timeout:15))
        capture("01-home")
        app.buttons["aboutButton"].tap()
        XCTAssertTrue(app.buttons["closeAboutButton"].waitForExistence(timeout:5))
        capture("02-about")
        app.buttons["closeAboutButton"].tap()
        open.tap()
        let back = app.buttons["viewerBackButton"]
        XCTAssertTrue(back.waitForExistence(timeout:30),"Unity scene must actually become ready")
        let frameRate = app.buttons["frameRateButton"]
        XCTAssertTrue(frameRate.waitForExistence(timeout:3))
        // Sample steady rendering separately from initialization, then exercise both targets.
        Thread.sleep(forTimeInterval:12)
        capture("03-viewer-initial")
        frameRate.tap()
        app.buttons["60 FPS · 标准"].tap()
        Thread.sleep(forTimeInterval:6)
        XCTAssertTrue((frameRate.value as? String ?? "").contains("目标 60 帧"))
        capture("17-target60")
        frameRate.tap()
        app.buttons["120 FPS · 高刷新率"].tap()
        Thread.sleep(forTimeInterval:12)
        XCTAssertTrue((frameRate.value as? String ?? "").contains("目标 120 帧"))
        capture("18-target120")
        let start = app.coordinate(withNormalizedOffset:CGVector(dx:0.35,dy:0.5))
        let end = app.coordinate(withNormalizedOffset:CGVector(dx:0.75,dy:0.56))
        start.press(forDuration:0.1,thenDragTo:end,withVelocity:.slow,thenHoldForDuration:0.1)
        Thread.sleep(forTimeInterval:0.6)
        capture("04-viewer-rotated")
        app.pinch(withScale:1.6,velocity:1)
        Thread.sleep(forTimeInterval:0.6)
        capture("05-viewer-zoomed")
        app.buttons["resetViewButton"].tap()
        Thread.sleep(forTimeInterval:0.5)
        capture("06-viewer-reset")
        // Actual animation buttons and exact head hit testing, including negative hits.
        app.buttons["actionWaveButton"].tap()
        Thread.sleep(forTimeInterval:0.2); capture("13-wave")
        Thread.sleep(forTimeInterval:2)
        app.buttons["actionJumpButton"].tap()
        capture("14-jump")
        Thread.sleep(forTimeInterval:1)
        app.buttons["actionDanceButton"].tap()
        Thread.sleep(forTimeInterval:0.3); capture("15-dance")
        Thread.sleep(forTimeInterval:3.4)
        app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.37)).tap()
        XCTAssertTrue(app.staticTexts["正在摇头"].waitForExistence(timeout:2),"A real head tap must trigger the No clip")
        capture("16-head-shake")
        Thread.sleep(forTimeInterval:2)
        app.coordinate(withNormalizedOffset:CGVector(dx:0.08,dy:0.35)).tap()
        app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.59)).tap()
        let head = app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.37))
        let away = app.coordinate(withNormalizedOffset:CGVector(dx:0.75,dy:0.45))
        head.press(forDuration:0.1,thenDragTo:away,withVelocity:.slow,thenHoldForDuration:0.1)
        app.buttons["resetViewButton"].tap()
        app.buttons["actionWaveButton"].tap()
        app.buttons["actionDanceButton"].tap()
        app.buttons["actionJumpButton"].tap()
        Thread.sleep(forTimeInterval:1)
        app.buttons["actionDanceButton"].tap()
        back.tap()
        XCTAssertTrue(open.waitForExistence(timeout:5))
        for index in 1...20 {
            open.tap()
            XCTAssertTrue(back.waitForExistence(timeout:10),"Re-entry \(index) failed")
            back.tap()
            XCTAssertTrue(open.waitForExistence(timeout:5),"Return \(index) failed")
        }
        open.tap()
        XCTAssertTrue(back.waitForExistence(timeout:10))
        app.buttons["actionDanceButton"].tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(back.waitForExistence(timeout:10),"Viewer should restore after backgrounding")
        Thread.sleep(forTimeInterval:3.5)
        capture("07-viewer-resumed")
        back.tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(open.waitForExistence(timeout:10),"Home should remain visible after backgrounding")
        capture("08-home-final")
    }
    @MainActor
    private func capture(_ name:String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
