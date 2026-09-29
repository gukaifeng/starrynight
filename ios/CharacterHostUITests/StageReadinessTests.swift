import XCTest

final class StageReadinessTests: XCTestCase {
    @MainActor func testSwitchingCharactersRevealsOnlyRenderedScenes() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--companion-testing", "--auth-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        for id in ["real-woman", "studio-robot", "sample-robot", "hatsune-miku"] {
            app.buttons["tab-discover"].tap()
            let choice = app.buttons["discover-open-"+id]
            XCTAssertTrue(choice.waitForExistence(timeout:8)); choice.tap()
            XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:30))
            wait(app) { $0["modelId"] as? String == id && ($0["stableRenderedFrames"] as? Int ?? 0) >= 3 }
            let state = app.characterRuntime
            XCTAssertEqual(state["presentationRevision"] as? Int,2)
            let environment = state["environment"] as? [String:Any] ?? [:]
            XCTAssertEqual(environment["transitioning"] as? Bool,false)
            XCTAssertEqual(environment["selectedId"] as? String,environment["visibleId"] as? String)
            XCTAssertEqual(state["actionFraming"] as? Bool,false,"First visible frame must already use conversational framing")
            XCTAssertEqual(state["framingMotionActive"] as? Bool,false)
            XCTAssertEqual((state["characterPlatform"] as? [String:Any])?["bodyCues"] as? Int,0,"Opening a role must not schedule a greeting body cue")
            let distance = (state["distance"] as? NSNumber)?.doubleValue ?? -1
            capture("first-framing-"+id,app)
            RunLoop.current.run(until:Date().addingTimeInterval(3))
            XCTAssertEqual((app.characterRuntime["distance"] as? NSNumber)?.doubleValue ?? -2,distance,accuracy:0.0001,"Entry must not zoom out then back in")
            wait(app) { ($0["characterPlatform"] as? [String:Any])?["activeAction"] as? String == "" && $0["framingMotionActive"] as? Bool == false }
            let settled = app.characterRuntime
            let taps = settled["headTapCount"] as? Int ?? 0
            let actions = settled["actionCount"] as? Int ?? 0
            let x = (settled["headX"] as? NSNumber)?.doubleValue ?? 0.5
            let y = (settled["headY"] as? NSNumber)?.doubleValue ?? 0.25
            app.coordinate(withNormalizedOffset:CGVector(dx:x,dy:y)).press(forDuration:0.12)
            wait(app) { ($0["headTapCount"] as? Int ?? 0) > taps && ($0["actionCount"] as? Int ?? 0) > actions }
            capture("ready-and-interactive-"+id,app)
        }
    }
    @MainActor func testHeadTouchReachesCharacterWhileFramingLocked() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--companion-testing", "--auth-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        wait(app) { $0["framingMotionActive"] as? Bool == false && ($0["action"] as? String ?? "").isEmpty }
        let before = app.characterRuntime
        capture("head-before-touch", app)
        let headX = (before["headX"] as? NSNumber)?.doubleValue ?? 0.5
        let headY = (before["headY"] as? NSNumber)?.doubleValue ?? 0.25
        XCTAssertTrue((0.1...0.9).contains(headX)); XCTAssertTrue((0.12...0.5).contains(headY))
        let taps = (before["headTapCount"] as? Int) ?? 0
        let actions = (before["actionCount"] as? Int) ?? 0
        XCTAssertEqual(before["modelControlsLocked"] as? Bool, true)
        app.coordinate(withNormalizedOffset:CGVector(dx:headX,dy:headY)).press(forDuration:0.12)
        wait(app) { ($0["headTapCount"] as? Int ?? 0) > taps && ($0["actionCount"] as? Int ?? 0) > actions }
        capture("head-after-touch", app)
        wait(app) { ($0["characterPlatform"] as? [String:Any])?["activeAction"] as? String == "" && $0["framingMotionActive"] as? Bool == false }
        let beforeCrown = app.characterRuntime
        let crownTaps = beforeCrown["headTapCount"] as? Int ?? 0
        let crownActions = beforeCrown["actionCount"] as? Int ?? 0
        // Visible crown/bangs, not only the centre of the face reported by the hit mesh.
        let crownY = (beforeCrown["headY"] as? NSNumber)?.doubleValue ?? 0.25
        app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:crownY-0.065)).press(forDuration:0.12)
        wait(app) { ($0["headTapCount"] as? Int ?? 0) > crownTaps && ($0["actionCount"] as? Int ?? 0) > crownActions }
        capture("head-crown-touch", app)
        wait(app) { ($0["characterPlatform"] as? [String:Any])?["activeAction"] as? String == "" }
        let afterHead = app.characterRuntime["headTapCount"] as? Int ?? 0
        app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.43)).press(forDuration:0.12)
        RunLoop.current.run(until:Date().addingTimeInterval(0.6))
        XCTAssertEqual(app.characterRuntime["headTapCount"] as? Int,afterHead,"The chest must not be included in the head envelope")
    }
    @MainActor private func wait(_ app:XCUIApplication, _ condition:@escaping ([String:Any])->Bool) {
        let predicate = NSPredicate { _,_ in MainActor.assumeIsolated { condition(app.characterRuntime) } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:nil)],timeout:12),.completed,"Runtime: \(app.characterRuntime)")
    }
    @MainActor private func capture(_ name:String, _ app:XCUIApplication) {
        let screenshot = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        if let data = try? JSONSerialization.data(withJSONObject:app.characterRuntime,options:[.sortedKeys,.prettyPrinted]) {
            let state = XCTAttachment(data:data,uniformTypeIdentifier:"public.json")
            state.name = name + "-runtime"; state.lifetime = .keepAlways; add(state)
        }
    }
}
