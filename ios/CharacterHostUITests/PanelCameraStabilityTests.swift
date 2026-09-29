import XCTest

final class PanelCameraStabilityTests:XCTestCase {
    @MainActor func testPanelsKeyboardAndTabsKeepThePortraitCamera() {
        let app = launch(captureMotion:true)
        let original = app.characterRuntime
        capture("01-conversation",app)
        app.buttons["customizationButton"].tap()
        XCTAssertTrue(app.buttons["profileCustomizeButton"].waitForExistence(timeout:6))
        sameCamera(app,original);capture("02-profile",app)
        app.buttons["profileCustomizeButton"].tap()
        XCTAssertTrue(app.buttons["closeCustomizationButton"].waitForExistence(timeout:5))
        sameCamera(app,original)

        for (page,back) in [("music","closeMusicButton"),("memory","closeMemoryButton"),("history","closeHistoryButton")] {
            app.openCustomization(page)
            waitForPage(app,back,leaving:"closeCustomizationButton")
            sameCamera(app,original)
            capture("panel-"+page,app)
            app.buttons[back].tap()
            waitForPage(app,"closeCustomizationButton",leaving:back)
            sameCamera(app,original)
        }
        app.buttons["closeCustomizationButton"].tap()
        XCTAssertTrue(app.buttons["closeCharacterDetails"].waitForExistence(timeout:5))
        app.buttons["closeCharacterDetails"].tap()
        sameCamera(app,original)

        let input = app.textFields["chatInput"]
        input.tap();input.typeText("先留一句草稿")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5))
        sameCamera(app,original);capture("03-keyboard",app)
        app.openCustomization("memory")
        sameCamera(app,original)
        let handle = app.buttons["softPanelHandle"]
        handle.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).press(forDuration:0.1,
            thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.1)),withVelocity:.slow,thenHoldForDuration:0.1)
        sameCamera(app,original);capture("04-expanded",app)
        // The same close/save path is used by interactive dismissal.
        handle.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).press(forDuration:0.1,
            thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.75)),withVelocity:.slow,thenHoldForDuration:0.1)
        XCTAssertTrue(input.waitForExistence(timeout:6));sameCamera(app,original)
        XCTAssertEqual(input.value as? String,"先留一句草稿")

        app.buttons["customizationButton"].tap()
        XCTAssertTrue(app.buttons["profileCustomizeButton"].waitForExistence(timeout:5))
        app.coordinate(withNormalizedOffset:CGVector(dx:0.12,dy:0.18)).tap()
        XCTAssertTrue(input.waitForExistence(timeout:6));sameCamera(app,original)

        for tab in ["messages","discover","create","mine"] {
            app.buttons["tab-"+tab].tap()
            XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout:8))
            app.buttons["tab-home"].tap()
            XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:15))
            sameCamera(app,original)
        }
        capture("05-returned-home",app)
    }

    @MainActor func testLandscapePanelsAndKeyboardKeepCamera() {
        let app = launch(captureMotion:false)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        app.waitForCharacter { self.number($0,"cameraAspect") > 1 && $0["framingMotionActive"] as? Bool == false }
        let landscape = app.characterRuntime
        app.openCustomization("music")
        waitForPage(app,"closeMusicButton",leaving:"closeCustomizationButton")
        sameCamera(app,landscape)
        app.closeCustomizationPage("closeMusicButton");sameCamera(app,landscape)
        app.textFields["chatInput"].tap();app.textFields["chatInput"].typeText("横屏草稿")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5))
        sameCamera(app,landscape);capture("07-landscape-keyboard",app)
        app.openCustomization("history")
        waitForPage(app,"closeHistoryButton",leaving:"closeCustomizationButton")
        sameCamera(app,landscape)
        app.closeCustomizationPage("closeHistoryButton");sameCamera(app,landscape)
        XCTAssertEqual(app.textFields["chatInput"].value as? String,"横屏草稿")
        capture("08-landscape-personal-panels",app)
    }

    @MainActor private func waitForPage(_ app:XCUIApplication,_ header:String,leaving old:String) {
        let ready = NSPredicate { _,_ in MainActor.assumeIsolated {
            app.buttons[header].exists && app.buttons[header].isHittable && !app.buttons[old].exists
        } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:ready,object:nil)],timeout:6),.completed,header)
    }

    @MainActor private func launch(captureMotion:Bool) -> XCUIApplication {
        continueAfterFailure = false;XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--shell-discover"]
        if captureMotion { app.launchArguments.append("--layout-motion-review") }
        app.launch()
        XCTAssertTrue(app.buttons["discover-open-real-woman"].waitForExistence(timeout:20))
        app.buttons["discover-open-real-woman"].tap()
        XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:6))
        app.buttons["profileChatButton"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.waitForCharacter { $0["modelId"] as? String == "real-woman" && $0["framingMotionActive"] as? Bool == false }
        return app
    }
    @MainActor private func sameCamera(_ app:XCUIApplication,_ expected:[String:Any],file:StaticString = #filePath,line:UInt = #line) {
        app.waitForCharacter { $0["distance"] is NSNumber }
        let actual = app.characterRuntime
        for key in ["distance","framingSize","framingAngle","pitch","yaw","cameraFov","cameraSnapCount","presentationId"] {
            XCTAssertEqual(number(actual,key),number(expected,key),accuracy:0.0001,"Unexpected camera change: \(key)",file:file,line:line)
        }
        for field in ["cameraPosition","compositionArea","renderViewport"] {
            let a = actual[field] as? [String:Any] ?? [:], b = expected[field] as? [String:Any] ?? [:]
            XCTAssertFalse(a.isEmpty,file:file,line:line)
            for key in ["x","y","z","width","height"] where b[key] != nil {
                XCTAssertEqual(number(a,key),number(b,key),accuracy:0.0001,"\(field).\(key)",file:file,line:line)
            }
        }
        XCTAssertEqual(actual["framingShot"] as? String,expected["framingShot"] as? String,file:file,line:line)
        XCTAssertEqual(actual["framingMotionActive"] as? Bool,false,file:file,line:line)
    }
    private func number(_ values:[String:Any],_ key:String)->Double { (values[key] as? NSNumber)?.doubleValue ?? -999 }
    @MainActor private func capture(_ name:String,_ app:XCUIApplication) {
        let screenshot = XCTAttachment(screenshot:XCUIScreen.main.screenshot());screenshot.name=name;screenshot.lifetime = .keepAlways;add(screenshot)
        if let data = try? JSONSerialization.data(withJSONObject:app.characterRuntime,options:[.prettyPrinted,.sortedKeys]) {
            let state = XCTAttachment(data:data,uniformTypeIdentifier:"public.json");state.name=name+"-runtime";state.lifetime = .keepAlways;add(state)
        }
    }
}
