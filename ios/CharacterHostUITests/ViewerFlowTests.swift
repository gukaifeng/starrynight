import XCTest
import UIKit

final class ViewerFlowTests: XCTestCase {
    @MainActor
    func testA_CancelDuringInitializationAndReopen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--test-ready-delay=4"]
        app.launch()
        app.selectHomeModel("studio-robot")
        let open = app.buttons["chat-studio-robot"]
        XCTAssertTrue(open.waitForExistence(timeout:10)); open.tap()
        let cancel = app.buttons["cancelLoadingButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout:5))
        XCTAssertGreaterThan(cancel.frame.midY,app.frame.midY,"Loading is a lower card hint, not a full-screen page")
        capture("09-loading")
        cancel.tap()
        XCTAssertTrue(open.waitForExistence(timeout:5))
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:cancel)],timeout:2),.completed)
        // The delayed engine ready event must not reopen a cancelled presentation.
        let unexpected = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in MainActor.assumeIsolated {
            app.buttons["viewerBackButton"].exists || app.buttons["cancelLoadingButton"].exists
        } },object:nil)
        unexpected.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for:[unexpected],timeout:5),.completed)
        open.tap()
        XCTAssertTrue(app.buttons["viewerBackButton"].waitForExistence(timeout:12))
        capture("10-cancel-recovered")
        app.buttons["viewerBackButton"].tap()
        XCTAssertTrue(open.waitForExistence(timeout:5))
    }
    @MainActor
    func testB_TimeoutAndRecover() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--test-ready-delay=35"]
        app.launch()
        app.selectHomeModel("studio-robot")
        let open = app.buttons["chat-studio-robot"]
        XCTAssertTrue(open.waitForExistence(timeout:10)); open.tap()
        XCTAssertTrue(app.staticTexts["准备模型所需时间较长，请返回后重试。"].waitForExistence(timeout:42))
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
        app.selectHomeModel("studio-robot")
        let open = app.buttons["chat-studio-robot"]
        XCTAssertTrue(open.waitForExistence(timeout:15))
        capture("01-home")
        app.openAccountAbout()
        XCTAssertTrue(app.buttons["closeAccountCenterButton"].waitForExistence(timeout:5))
        capture("02-about")
        app.buttons["closeAccountCenterButton"].tap()
        open.tap()
        let back = app.buttons["viewerBackButton"]
        XCTAssertTrue(back.waitForExistence(timeout:30),"Unity scene must actually become ready")
        XCTAssertTrue(app.buttons["characterActionsMenu"].waitForExistence(timeout:3))
        // Public entries now share chat. Frame targets remain covered by the
        // dedicated diagnostic preview in testE below.
        capture("03-chat-initial")
        app.toggleModelLock()
        let start = app.coordinate(withNormalizedOffset:CGVector(dx:0.35,dy:0.5))
        let end = app.coordinate(withNormalizedOffset:CGVector(dx:0.75,dy:0.56))
        start.press(forDuration:0.1,thenDragTo:end,withVelocity:.slow,thenHoldForDuration:0.1)
        Thread.sleep(forTimeInterval:0.6)
        capture("04-viewer-drag")
        app.images["characterGestureRegion"].pinch(withScale:1.6,velocity:1)
        Thread.sleep(forTimeInterval:0.6)
        capture("05-viewer-pinch")
        restoreFraming(app)
        Thread.sleep(forTimeInterval:0.5)
        capture("06-viewer-reset")
        // Actual animation buttons and exact head hit testing, including negative hits.
        app.performCharacterAction("Wave")
        Thread.sleep(forTimeInterval:0.2); capture("13-wave")
        Thread.sleep(forTimeInterval:2)
        app.performCharacterAction("Jump")
        capture("14-jump")
        Thread.sleep(forTimeInterval:1)
        app.performCharacterAction("Dance")
        Thread.sleep(forTimeInterval:0.3); capture("15-dance")
        Thread.sleep(forTimeInterval:3.4)
        headCoordinate(app).tap()
        app.waitForCharacter { $0["action"] as? String == "No" || ($0["headTapCount"] as? Int ?? 0) > 0 }
        capture("16-head-shake")
        Thread.sleep(forTimeInterval:2)
        app.coordinate(withNormalizedOffset:CGVector(dx:0.08,dy:0.35)).tap()
        app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.59)).tap()
        let head = headCoordinate(app)
        let away = app.coordinate(withNormalizedOffset:CGVector(dx:0.75,dy:0.45))
        head.press(forDuration:0.1,thenDragTo:away,withVelocity:.slow,thenHoldForDuration:0.1)
        restoreFraming(app)
        app.performCharacterAction("Wave")
        app.performCharacterAction("Dance")
        app.performCharacterAction("Jump")
        Thread.sleep(forTimeInterval:1)
        app.performCharacterAction("Dance")
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
        app.performCharacterAction("Dance")
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
    func testD_CharacterSwitchAndAdditionalActions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--test-character-switch"]
        app.launch()
        app.selectHomeModel("studio-robot")
        let robot = app.buttons["chat-studio-robot"]
        XCTAssertTrue(robot.waitForExistence(timeout:15))
        robot.tap()
        XCTAssertTrue(app.buttons["viewerBackButton"].waitForExistence(timeout:30))
        app.performCharacterAction("Dance")
        app.buttons["viewerBackButton"].tap()
        let miku = app.buttons["chat-hatsune-miku"]
        app.selectHomeModel("hatsune-miku")
        XCTAssertTrue(miku.isHittable); miku.tap()
        XCTAssertTrue(app.buttons["viewerBackButton"].waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["初音未来"].exists)
        capture("miku-01-viewer")
        for action in ["Wave","Jump","Dance","Bow","Spin","Greet","Cheer"] {
            app.performCharacterAction(action)
            // Short clips can finish before XCTest's accessibility snapshot under load.
            // verify_character_events.py independently requires each actual start + completion.
            Thread.sleep(forTimeInterval:0.35)
            capture("miku-" + action)
            app.waitForCharacter {
                ($0["characterPlatform"] as? [String:Any])?["lastAction"] as? String == action &&
                $0["actionFraming"] as? Bool == false
            }
        }
        // Leave during an action, then select the other rig; old animation state must not leak.
        app.performCharacterAction("Cheer")
        app.buttons["viewerBackButton"].tap()
        app.selectHomeModel("studio-robot")
        XCTAssertTrue(robot.isHittable); robot.tap()
        XCTAssertTrue(app.buttons["viewerBackButton"].waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["Luma"].exists)
        app.buttons["characterActionsMenu"].tap()
        XCTAssertTrue(app.buttons["actionWaveButton"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["actionBowButton"].exists)
        app.buttons["actionWaveButton"].tap()
        app.waitForCharacter { ($0["characterPlatform"] as? [String:Any])?["lastAction"] as? String == "Wave" }
        Thread.sleep(forTimeInterval:3)
        capture("miku-02-back-to-luma")
    }
    @MainActor
    func testE_MikuHeadInteractionFramingAndFrameTargets() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--test-miku-head", "--preview-miku"]
        app.launch()
        XCTAssertTrue(app.buttons["viewerBackButton"].waitForExistence(timeout:30))
        Thread.sleep(forTimeInterval:3)
        headCoordinate(app).tap()
        XCTAssertTrue(app.staticTexts["正在摇头"].waitForExistence(timeout:2))
        capture("miku-head-shake")
        XCTAssertTrue(app.staticTexts["HATSUNE MIKU · FAN ART"].waitForExistence(timeout:5))
        app.coordinate(withNormalizedOffset:CGVector(dx:0.08,dy:0.32)).tap()
        app.coordinate(withNormalizedOffset:CGVector(dx:0.50,dy:0.59)).tap()
        XCTAssertFalse(app.staticTexts["正在摇头"].exists)
        app.toggleModelLock()
        let head = headCoordinate(app)
        head.press(forDuration:0.1,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.75,dy:0.45)),withVelocity:.slow,thenHoldForDuration:0.1)
        XCTAssertFalse(app.staticTexts["正在摇头"].exists)
        restoreFraming(app)
        Thread.sleep(forTimeInterval:0.5)
        app.images["characterGestureRegion"].pinch(withScale:1.5,velocity:1)
        Thread.sleep(forTimeInterval:0.6); capture("miku-close-view")
        restoreFraming(app)
        let fps = app.buttons["frameRateButton"]
        for target in [60,120] {
            fps.tap()
            app.buttons[target == 60 ? "60 FPS · 标准" : "120 FPS · 高刷新率"].tap()
            Thread.sleep(forTimeInterval:6)
            XCTAssertTrue((fps.value as? String ?? "").contains("目标 \(target) 帧"))
        }
        capture("miku-phone-final")
    }
    @MainActor
    func testF_IPadPortraitAndLandscape() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad layout runs on the iPad Pro M4 simulator") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--test-ipad", "--preview-miku"]
        app.launch()
        XCTAssertTrue(app.buttons["viewerBackButton"].waitForExistence(timeout:30))
        Thread.sleep(forTimeInterval:4); capture("miku-ipad-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval:2)
        XCTAssertTrue(app.buttons["viewerBackButton"].isHittable)
        XCTAssertTrue(app.buttons["actionCheerButton"].isHittable)
        app.buttons["actionCheerButton"].tap()
        XCTAssertTrue(app.staticTexts["正在应援"].waitForExistence(timeout:2))
        Thread.sleep(forTimeInterval:1); capture("miku-ipad-landscape-action")
        restoreFraming(app)
        Thread.sleep(forTimeInterval:1); capture("miku-ipad-landscape")
        app.buttons["viewerBackButton"].tap()
        app.selectHomeModel("studio-robot")
        XCTAssertTrue(app.buttons["chat-studio-robot"].waitForExistence(timeout:5))
        capture("miku-ipad-home")
    }
    @MainActor private func restoreFraming(_ app: XCUIApplication) {
        app.openCustomization("framing")
        XCTAssertTrue(app.buttons["restoreFramingButton"].waitForExistence(timeout:5))
        app.buttons["restoreFramingButton"].tap(); app.closeCustomizationPage("closeFramingButton")
        Thread.sleep(forTimeInterval:0.7)
    }
    @MainActor private func headCoordinate(_ app: XCUIApplication) -> XCUICoordinate {
        let raw = app.buttons["customizationButton"].value as? String ?? "{}"
        let state = (try? JSONSerialization.jsonObject(with:Data(raw.utf8))) as? [String:Any] ?? [:]
        return app.coordinate(withNormalizedOffset:CGVector(dx:state["headX"] as? Double ?? 0.5,dy:state["headY"] as? Double ?? 0.3))
    }
    @MainActor
    private func capture(_ name:String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
