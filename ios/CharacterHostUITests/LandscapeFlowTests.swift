import XCTest
import UIKit

final class LandscapeFlowTests: XCTestCase {
    @MainActor func testConversationKeyboardPosturesAndRotatingEditors() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--preview-companion","--preview-human","--layout-motion-review"]
        app.launch(); XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        settled(app); let snaps = event(app)["cameraSnapCount"] as? Int
        capture("01-portrait")
        rotate(.landscapeLeft,app); checkComposition(app); capture("02-landscape-conversation")
        let head = event(app), taps = head["headTapCount"] as? Int ?? 0
        app.coordinate(withNormalizedOffset:CGVector(dx:head["headX"] as? Double ?? 0.3,dy:head["headY"] as? Double ?? 0.4)).press(forDuration:0.12)
        wait { (self.event(app)["headTapCount"] as? Int ?? 0)>taps }
        let gestureCount = event(app)["gestureCount"] as? Int ?? 0
        let region = app.images["characterGestureRegion"]
        let start = region.coordinate(withNormalizedOffset:CGVector(dx:0.4,dy:0.65))
        start.press(forDuration:0.05,thenDragTo:start.withOffset(CGVector(dx:45,dy:0)))
        wait { (self.event(app)["gestureCount"] as? Int ?? 0)>gestureCount }
        XCTAssertLessThanOrEqual(abs(event(app)["framingAngle"] as? Double ?? 100),20)

        let input = field(app)
        input.tap(); input.typeText("横屏草稿")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:8))
        wait { self.field(app).frame.maxY <= app.keyboards.firstMatch.frame.minY+2 }
        XCTAssertTrue(app.buttons["sendMessageButton"].isHittable)
        XCTAssertTrue(app.buttons["dismissChatKeyboardButton"].isHittable)
        capture("03-landscape-keyboard")
        rotate(.portrait,app)
        XCTAssertTrue((field(app).value as? String ?? "").contains("横屏草稿"))
        rotate(.landscapeRight,app)
        wait { self.field(app).frame.maxY <= app.keyboards.firstMatch.frame.minY+2 }
        capture("04-reverse-landscape-keyboard")
        app.buttons["dismissChatKeyboardButton"].tap()
        wait { !app.keyboards.firstMatch.exists }; settled(app)
        app.buttons["sendMessageButton"].tap()
        app.waitForReply(timeout:20)
        send("坐下",app); pose("sit",app); settled(app);checkComposition(app);capture("05-landscape-sit")
        send("侧躺休息一下",app);pose("lie",app);settled(app);checkComposition(app);capture("06-landscape-lie")

        app.openCustomization("framing");XCTAssertTrue(app.buttons["closeFramingButton"].waitForExistence(timeout:8))
        XCTAssertGreaterThan(app.buttons["closeFramingButton"].frame.midX,app.frame.width*0.5)
        app.buttons["framingSizeMax"].tap();capture("07-landscape-framing")
        rotate(.portrait,app); XCTAssertEqual(app.staticTexts["framingSizeValue"].label,"110%")
        XCTAssertTrue(app.buttons["closeFramingButton"].isHittable);capture("08-editor-rotated-portrait")
        rotate(.landscapeLeft,app);app.closeCustomizationPage("closeFramingButton");settled(app)
        XCTAssertEqual(event(app)["framingSize"] as? Double ?? 0,1.1,accuracy:0.001)

        app.openCustomization("appearance");XCTAssertTrue(app.buttons["closeStudioButton"].waitForExistence(timeout:8))
        app.segmentedControls["studioTabs"].buttons["姿势"].tap()
        app.buttons["posture-crouch"].tap();pose("crouch",app);settled(app);capture("09-landscape-posture-editor")
        rotate(.portrait,app);rotate(.landscapeRight,app)
        XCTAssertTrue(app.buttons["closeStudioButton"].isHittable);app.buttons["posture-lie"].tap();app.closeCustomizationPage("closeStudioButton");pose("lie",app)
        app.openCustomization("music");XCTAssertTrue(app.buttons["closeMusicButton"].waitForExistence(timeout:8))
        capture("10-landscape-music");rotate(.portrait,app);rotate(.landscapeLeft,app)
        app.closeCustomizationPage("closeMusicButton")
        app.openCustomization();XCTAssertTrue(app.buttons["closeCustomizationButton"].waitForExistence(timeout:8))
        capture("11-landscape-tools");app.buttons["closeCustomizationButton"].tap();settled(app);checkComposition(app)
        app.openCustomization();app.openCustomization("profile")
        XCTAssertTrue(app.textFields["profileName"].waitForExistence(timeout:8))
        app.textFields["profileName"].tap();app.textFields["profileName"].typeText("横屏")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:8))
        XCTAssertLessThan(app.textFields["profileName"].frame.maxY,app.keyboards.firstMatch.frame.minY+2)
        XCTAssertGreaterThan(app.textFields["profileName"].frame.minY,app.buttons["closeProfileButton"].frame.maxY)
        XCTAssertTrue(app.textFields["profileName"].isHittable)
        profilePreviewSettles()
        capture("11b-profile-keyboard")
        app.buttons["finishProfileInput"].tap();app.closeCustomizationPage("closeProfileButton")
        app.openCustomization();app.openCustomization("history")
        XCTAssertTrue(app.buttons["closeHistoryButton"].waitForExistence(timeout:8));capture("11c-landscape-history")
        app.closeCustomizationPage("closeHistoryButton");settled(app)
        XCTAssertEqual(event(app)["cameraSnapCount"] as? Int,snaps)
        XCTAssertEqual(app.descendants(matching:.scrollBar).count,0)
        rotate(.portrait,app);pose("lie",app);capture("12-restored-portrait")
    }

    @MainActor func testLandscapeHomeLoginAndExplorer() {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--auth-testing","--companion-testing","--layout-motion-review"]
        app.launch()
        // Auth storage reset is explicit in AccountStore; signing out handles an earlier test session.
        if app.buttons["accountCenterButton"].waitForExistence(timeout:3) {
            app.buttons["accountCenterButton"].tap()
            if app.buttons["signOutButton"].waitForExistence(timeout:4) {app.buttons["signOutButton"].tap()}
        }
        XCTAssertTrue(app.buttons["signInButton"].waitForExistence(timeout:10))
        wait {app.frame.width>app.frame.height};capture("13-landscape-login")
        if !app.buttons["signInButton"].isHittable {app.swipeUp()}
        app.buttons["signInButton"].tap();XCTAssertTrue(app.buttons["accountCenterButton"].waitForExistence(timeout:10))
        capture("14-landscape-home")
        let card=app.buttons["humanModelCard"]
        app.selectHomeModel("real-woman");card.tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60));settled(app)
        XCTAssertTrue(app.buttons["characterActionsMenu"].isHittable)
        XCTAssertFalse(app.scrollViews["characterActionsScroll"].exists);capture("15-landscape-chat")
        app.performCharacterAction("Wave")
        wait { (self.event(app)["characterPlatform"] as? [String:Any])?["lastAction"] as? String == "Wave" }
        rotate(.landscapeRight,app);capture("16-reverse-landscape-chat")
        app.buttons["viewerBackButton"].tap();XCTAssertTrue(app.buttons["accountCenterButton"].waitForExistence(timeout:8))
    }
    @MainActor func testProfileKeyboardKeepsInputAndLowCharacterVisible() {
        continueAfterFailure=false
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--preview-companion","--preview-human","--layout-motion-review"]
        app.launch();XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60));settled(app)
        send("侧躺休息一下",app);pose("lie",app);settled(app)
        app.openCustomization();app.openCustomization("profile")
        let name=app.textFields["profileName"]
        XCTAssertTrue(name.waitForExistence(timeout:8));name.tap();name.typeText("横屏")
        for direction in [UIDeviceOrientation.landscapeLeft,.landscapeRight] {
            XCUIDevice.shared.orientation=direction
            wait {app.frame.width>app.frame.height}
            profilePreviewSettles()
            XCTAssertTrue(app.keyboards.firstMatch.exists)
            XCTAssertTrue(name.isHittable)
            XCTAssertGreaterThan(name.frame.minY,app.buttons["closeProfileButton"].frame.maxY)
            XCTAssertLessThan(name.frame.maxY,app.keyboards.firstMatch.frame.minY-2)
            XCTAssertTrue(app.buttons["finishProfileInput"].isHittable)
            capture(direction == .landscapeLeft ? "11b-profile-keyboard" : "17-profile-keyboard-reversed")
        }
        app.buttons["finishProfileInput"].tap()
        wait { !app.keyboards.firstMatch.exists }
        app.closeCustomizationPage("closeProfileButton");settled(app);pose("lie",app)
    }
    @MainActor private func field(_ app:XCUIApplication)->XCUIElement {app.textViews["chatInput"]}
    @MainActor private func send(_ text:String,_ app:XCUIApplication){let f=field(app);f.tap();f.typeText(text);app.buttons["sendMessageButton"].tap()}
    @MainActor private func pose(_ id:String,_ app:XCUIApplication){wait {let p=self.event(app)["posture"] as? [String:Any];return p?["id"] as? String == id && p?["transitioning"] as? Bool == false}}
    @MainActor private func rotate(_ orientation:UIDeviceOrientation,_ app:XCUIApplication){
        XCUIDevice.shared.orientation=orientation
        let landscape=orientation.isLandscape
        wait { (app.frame.width>app.frame.height)==landscape && ((self.event(app)["cameraAspect"] as? Double ?? 0)>1)==landscape }
        settled(app)
    }
    @MainActor private func settled(_ app:XCUIApplication){wait {let e=self.event(app);return e["framingMotionActive"] as? Bool == false && e["name"] != nil}}
    @MainActor private func profilePreviewSettles() {
        // UIKit correctly hides the underlying framing button from accessibility when
        // the modal keyboard is active. Its telemetry still runs: review the captured
        // samples separately, and allow the 1.6 s camera spring to settle for screenshots.
        let start=Date()
        wait {Date().timeIntervalSince(start)>4}
    }
    @MainActor private func checkComposition(_ app:XCUIApplication){
        let e=event(app),area=e["compositionArea"] as? [String:Any] ?? [:],render=e["renderViewport"] as? [String:Any] ?? [:]
        XCTAssertLessThan(area["width"] as? Double ?? 1,0.7)
        XCTAssertEqual(render["width"] as? Double,1);XCTAssertEqual(render["height"] as? Double,1)
        XCTAssertLessThan((e["headX"] as? Double ?? 1)*app.frame.width,field(app).frame.minX-12)
        XCTAssertGreaterThan(e["headY"] as? Double ?? 0,0.05);XCTAssertLessThan(e["headY"] as? Double ?? 1,0.92)
        XCTAssertGreaterThan(app.scrollViews["chatMessages"].frame.height,90)
    }
    @MainActor private func event(_ app:XCUIApplication)->[String:Any]{guard let raw=app.buttons["customizationButton"].value as? String,let data=raw.data(using:.utf8),let e=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else{return [:]};return e}
    @MainActor private func wait(_ condition:@escaping ()->Bool){let p=NSPredicate{_,_ in MainActor.assumeIsolated{condition()}};XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:p,object:nil)],timeout:20),.completed)}
    @MainActor private func capture(_ name:String){let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
