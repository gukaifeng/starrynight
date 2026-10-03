import XCTest

final class SafeAreaFramingTests:XCTestCase {
    @MainActor func testActualWindowSafeAreaProtectsDefaultAndIllustratedCharacter() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--auth-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.waitForCharacter { $0["safeFramingRevision"] as? Int == 1 && $0["framingMotionActive"] as? Bool == false }
        check(app,name:"safe-frame-default")
        app.buttons["tab-discover"].tap()
        let search = app.textFields["discoverSearch"]
        XCTAssertTrue(search.waitForExistence(timeout:8));search.tap();search.typeText("优可")
        let card = app.buttons["discover-open-anime-uka"]
        XCTAssertTrue(card.waitForExistence(timeout:8));card.tap()
        XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:8));app.buttons["profileChatButton"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.waitForCharacter { $0["modelId"] as? String == "anime-uka" && $0["framingMotionActive"] as? Bool == false }
        check(app,name:"safe-frame-uka")
    }
    @MainActor private func check(_ app:XCUIApplication,name:String) {
        let state = app.characterRuntime
        let safe = state["characterSafeFrame"] as? [String:Any] ?? [:]
        let projected = state["framingEnvelopeViewport"] as? [String:Any] ?? [:]
        let window = state["nativeWindowGeometry"] as? [String:Any] ?? [:]
        XCTAssertFalse(safe.isEmpty);XCTAssertFalse(projected.isEmpty);XCTAssertFalse(window.isEmpty)
        let height = number(window,"height")
        let top = 1-number(safe,"y")-number(safe,"height")
        XCTAssertEqual(top*height,number(window,"safeTop")+10,accuracy:0.1,"Actual UIWindow safe area must reach Unity")
        XCTAssertGreaterThanOrEqual(number(state,"framingTopClearance"),-0.0001)
        XCTAssertGreaterThanOrEqual(number(projected,"x"),number(safe,"x")-0.0001)
        XCTAssertLessThanOrEqual(number(projected,"x")+number(projected,"width"),number(safe,"x")+number(safe,"width")+0.0001)
        XCTAssertEqual(state["framingMotionActive"] as? Bool,false)
        XCTAssertGreaterThanOrEqual(number(state,"headY"),top,"Head centre must be below cutout")
        let shot = XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
        if let data = try? JSONSerialization.data(withJSONObject:state,options:[.prettyPrinted,.sortedKeys]) {
            let audit = XCTAttachment(data:data,uniformTypeIdentifier:"public.json");audit.name=name+"-projection";audit.lifetime = .keepAlways;add(audit)
        }
    }
    private func number(_ values:[String:Any],_ key:String)->Double { (values[key] as? NSNumber)?.doubleValue ?? -999 }
}
