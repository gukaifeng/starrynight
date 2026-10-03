import XCTest

final class EnvironmentPresentationTests:XCTestCase {
    @MainActor func testDefaultNightStudioPersistenceAndCharacterIsolation() {
        let app = launch()
        wait(app,scene:"evening")
        assertAmbientMotionAdvances(app,scene:"evening")
        capture("environment-01-evening-conversation",app)

        app.openCustomization("space")
        XCTAssertFalse(app.buttons["environment-garden"].exists,"初音仅展示自己的配套空间")
        select("studio",in:app)
        customize(app,palette:"sage",decorations:false)
        app.closeCustomizationPage("closeStudioButton")
        wait(app,scene:"studio",palette:"sage",decorations:false)
        capture("environment-02-custom-studio-conversation",app)

        app.terminate()
        app.launchArguments.append("--keep-companion-data")
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        wait(app,scene:"studio",palette:"sage",decorations:false)
        XCTAssertEqual(app.characterRuntime["modelId"] as? String,"hatsune-miku")
        capture("environment-03-restored-studio",app)

        openCharacter("studio-robot",search:"Luma",in:app)
        wait(app,scene:"studio",palette:"original",decorations:true)
        capture("environment-04-independent-luma-studio",app)
        app.openCustomization("space")
        select("courtyard",in:app,category:"室外")
        app.closeCustomizationPage("closeStudioButton")
        wait(app,scene:"courtyard",palette:"original",decorations:true)
        assertAmbientMotionAdvances(app,scene:"courtyard")
        capture("environment-05-courtyard-conversation",app)

        app.buttons["tab-messages"].tap()
        let miku = app.buttons["message-hatsune-miku"]
        XCTAssertTrue(miku.waitForExistence(timeout:8)); miku.tap()
        app.waitForCharacter { $0["modelId"] as? String == "hatsune-miku" && $0["framingMotionActive"] as? Bool == false }
        wait(app,scene:"studio",palette:"sage",decorations:false)
        capture("environment-06-miku-space-preserved",app)
    }

    @MainActor func testDaylightGardenAndSeasideKeepTheirOwnDecorations() {
        let app = launch()
        openCharacter("real-woman",search:"小夏",in:app)
        wait(app,scene:"sunroom",palette:"original",decorations:true)
        assertAmbientMotionAdvances(app,scene:"sunroom")
        capture("environment-07-sunroom-conversation",app)

        app.openCustomization("space")
        select("garden",in:app,category:"室外")
        customize(app,palette:"rose",decorations:false)
        app.closeCustomizationPage("closeStudioButton")
        wait(app,scene:"garden",palette:"rose",decorations:false)
        capture("environment-08-personalized-garden-conversation",app)

        app.openCustomization("space")
        select("seaside",in:app,category:"室外")
        app.closeCustomizationPage("closeStudioButton")
        wait(app,scene:"seaside",palette:"original",decorations:true)
        assertAmbientMotionAdvances(app,scene:"seaside")
        capture("environment-09-seaside-conversation",app)

        app.openCustomization("space")
        select("garden",in:app,category:"室外")
        wait(app,scene:"garden",palette:"rose",decorations:false)
        tap(app.segmentedControls["environmentMode"].buttons["布置与光影"],in:app)
        XCTAssertEqual(app.buttons["environmentPalette-rose"].value as? String,"已选择")
        XCTAssertEqual(app.switches["environmentDecorations"].value as? String,"0")
        app.closeCustomizationPage("closeStudioButton")
        wait(app,scene:"garden",palette:"rose",decorations:false)
        capture("environment-10-restored-garden-conversation",app)
    }

    @MainActor private func launch() -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.waitForCharacter { $0["modelId"] as? String == "hatsune-miku" && $0["framingMotionActive"] as? Bool == false }
        return app
    }

    @MainActor private func openCharacter(_ id:String,search:String,in app:XCUIApplication) {
        app.buttons["tab-discover"].tap()
        let field = app.textFields["discoverSearch"]
        XCTAssertTrue(field.waitForExistence(timeout:8))
        if app.buttons["clearDiscoverSearch"].exists { app.buttons["clearDiscoverSearch"].tap() }
        field.tap(); field.typeText(search)
        let card = app.buttons["discover-open-"+id]
        XCTAssertTrue(card.waitForExistence(timeout:8)); card.tap()
        let enter = app.buttons["profileChatButton"]
        XCTAssertTrue(enter.waitForExistence(timeout:6)); enter.tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.waitForCharacter { $0["modelId"] as? String == id && $0["framingMotionActive"] as? Bool == false }
    }

    @MainActor private func select(_ scene:String,in app:XCUIApplication,category:String? = nil) {
        if let category { tap(app.segmentedControls["environmentCategory"].buttons[category],in:app) }
        let button = app.buttons["environment-"+scene]
        tap(button,in:app)
        let selected = XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@","已选择"),object:button)
        XCTAssertEqual(XCTWaiter.wait(for:[selected],timeout:5),.completed,"选择卡片应先响应点击")
        wait(app,scene:scene)
        XCTAssertEqual(button.value as? String,"已选择")
    }

    @MainActor private func customize(_ app:XCUIApplication,palette:String,decorations:Bool) {
        tap(app.segmentedControls["environmentMode"].buttons["布置与光影"],in:app)
        tap(app.buttons["environmentPalette-"+palette],in:app)
        let toggle = app.switches["environmentDecorations"]
        reveal(toggle,in:app)
        if toggle.value as? String != (decorations ? "1" : "0") { toggle.tap() }
    }

    @MainActor private func wait(_ app:XCUIApplication,scene:String,palette:String? = nil,decorations:Bool? = nil) {
        app.waitForCharacter({ runtime in
            let state = runtime["environment"] as? [String:Any] ?? [:]
            return state["visibleId"] as? String == scene && state["selectedId"] as? String == scene
                && state["transitioning"] as? Bool == false
                && (palette == nil || state["palette"] as? String == palette)
                && (decorations == nil || state["decorations"] as? Bool == decorations)
        },timeout:20)
    }

    @MainActor private func assertAmbientMotionAdvances(_ app:XCUIApplication,scene:String) {
        // Read the ordinary runtime snapshot, so the test observes the same
        // environment instance that is actually visible behind the conversation.
        let before = app.characterRuntime["environment"] as? [String:Any] ?? [:]
        let phase = number(before,"ambientTime")
        XCTAssertEqual(before["ambientRunning"] as? Bool,true,"\(scene) should animate in the foreground")
        XCTAssertGreaterThan(number(before,"ambientNodes"),0,"\(scene) should have bounded ambient motion")
        // Accessibility exposes the last ordinary bridge event, not a live
        // timer. A normal profile round-trip separates the observations; one
        // real head touch then publishes a new snapshot without polling or
        // colliding with the character's 1.8-second active-reaction guard.
        app.buttons["customizationButton"].tap()
        let back = app.buttons["closeCharacterDetails"]
        XCTAssertTrue(back.waitForExistence(timeout:5)); back.tap()
        let returned = XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:back)
        XCTAssertEqual(XCTWaiter.wait(for:[returned],timeout:5),.completed)
        let runtime = app.characterRuntime
        let environment = runtime["environment"] as? [String:Any] ?? [:]
        XCTAssertEqual(environment["visibleId"] as? String,scene)
        let x = number(runtime,"headX"), y = number(runtime,"headY")
        XCTAssertTrue((0...1).contains(x) && (0...1).contains(y),"头部坐标应位于当前原生触控平面内")
        let taps = number(runtime,"headTapCount")
        app.coordinate(withNormalizedOffset:CGVector(dx:x,dy:y)).press(forDuration:0.12)
        app.waitForCharacter { self.number($0,"headTapCount") > taps }
        XCTAssertEqual(app.characterRuntime["nativeHeadHit"] as? String,"CharacterTouchSurface")
        app.waitForCharacter({ runtime in
            let state = runtime["environment"] as? [String:Any] ?? [:]
            return state["visibleId"] as? String == scene && state["ambientRunning"] as? Bool == true
                && self.number(state,"ambientTime") > phase + 0.4
        },timeout:10)
    }

    @MainActor private func tap(_ element:XCUIElement,in app:XCUIApplication) {
        reveal(element,in:app); element.tap()
    }
    @MainActor private func reveal(_ element:XCUIElement,in app:XCUIApplication) {
        let panel = app.descendants(matching:.any).matching(identifier:"characterStudioPanel").firstMatch
        let scroll = panel.scrollViews.firstMatch
        for _ in 0..<8 {
            if element.isHittable { return }
            if element.exists && element.frame.midY < scroll.frame.midY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.isHittable,element.identifier)
    }
    private func number(_ state:[String:Any],_ key:String) -> Double { (state[key] as? NSNumber)?.doubleValue ?? -1 }
    @MainActor private func capture(_ name:String,_ app:XCUIApplication) {
        let closed = XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:app.buttons["closeStudioButton"])
        XCTAssertEqual(XCTWaiter.wait(for:[closed],timeout:5),.completed,"效果截图应回到实际会话，不能以编辑面板代替背景展示")
        let screenshot = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        if let data = try? JSONSerialization.data(withJSONObject:app.characterRuntime,options:[.prettyPrinted,.sortedKeys]) {
            let state = XCTAttachment(data:data,uniformTypeIdentifier:"public.json")
            state.name = name+"-runtime"; state.lifetime = .keepAlways; add(state)
        }
    }
}
