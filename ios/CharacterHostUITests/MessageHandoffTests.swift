import XCTest

final class MessageHandoffTests:XCTestCase {
    @MainActor func testMessageRowsOpenNewAndRetainedRolesWithoutRecreatingHome() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--window-handoff-review"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.buttons["tab-discover"].tap()
        XCTAssertTrue(app.buttons["discover-open-studio-robot"].waitForExistence(timeout:8))
        app.buttons["discover-open-studio-robot"].tap()
        XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:5))
        app.buttons["profileChatButton"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:20))
        var previous=app.characterRuntime
        for (index,id) in ["hatsune-miku","studio-robot","studio-robot","hatsune-miku"].enumerated() {
            app.buttons["tab-messages"].tap()
            let row=app.buttons["message-"+id]
            XCTAssertTrue(row.waitForExistence(timeout:8));row.tap()
            XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:20))
            XCTAssertTrue(app.textFields["chatInput"].isHittable)
            let state=app.characterRuntime
            XCTAssertEqual(state["modelId"] as? String,id)
            XCTAssertEqual(state["framingMotionActive"] as? Bool,false)
            XCTAssertFalse(app.descendants(matching:.any).matching(identifier:"characterArrival").firstMatch.exists)
            if previous["modelId"] as? String == id {
                XCTAssertEqual(state["presentationId"] as? Int,previous["presentationId"] as? Int)
            }
            previous=state
            let image=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
            image.name="message-handoff-\(index)-\(id)";image.lifetime = .keepAlways;add(image)
            RunLoop.current.run(until:Date().addingTimeInterval(0.75))
        }
        let input=app.textFields["chatInput"]
        input.tap();input.typeText("下次继续聊")
        XCTAssertEqual(input.value as? String,"下次继续聊")
        app.buttons["dismissChatKeyboardButton"].tap()
        let state=app.characterRuntime, taps=app.characterRuntime["headTapCount"] as? Int ?? 0
        let x=(state["headX"] as? NSNumber)?.doubleValue ?? 0.5
        let y=(state["headY"] as? NSNumber)?.doubleValue ?? 0.25
        app.coordinate(withNormalizedOffset:CGVector(dx:x,dy:y)).press(forDuration:0.12)
        let touched=NSPredicate { _,_ in MainActor.assumeIsolated { (app.characterRuntime["headTapCount"] as? Int ?? 0) > taps } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:touched,object:nil)],timeout:8),.completed,
            "The transparent native shell must pass head touches to Unity")
    }
}
