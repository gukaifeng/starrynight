import XCTest

final class ActionFramingMotionTests: XCTestCase {
    @MainActor func testThreeCharactersEaseOutInterruptAndReturn() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing","--companion-testing"]
        app.launch()
        let models = [("real-woman","humanModelCard","Bow","Greet"),
                      ("studio-robot","chat-studio-robot","Jump","Dance"),
                      ("hatsune-miku","chat-hatsune-miku","Jump","Dance")]
        for (id, openID, second, third) in models {
            app.selectHomeModel(id)
            let open = app.buttons[openID]
            XCTAssertTrue(open.waitForExistence(timeout:15))

            XCTAssertTrue(open.isHittable); open.tap()
            XCTAssertTrue(app.buttons["characterActionsMenu"].waitForExistence(timeout:40))
            wait(app) { $0["modelId"] as? String == id && $0["framingMotionActive"] as? Bool == false && ($0["environment"] as? [String:Any])?["transitioning"] as? Bool == false }
            let initial = values(app), originalDistance = number(initial,"distance")
            XCTAssertEqual(number(initial,"framingMotionRevision"),2)
            capture(id + "-rest",app)

            // Request successive actions through the folded menu. Continuous motion is
            // evaluated from Unity events; menu presentation also consumes time.
            let count = number(initial,"actionCount")
            app.performCharacterAction("Wave")
            app.performCharacterAction(second)
            app.performCharacterAction(third)
            capture(id + "-action-switch",app)
            wait(app,timeout:15) { self.number($0,"actionCount") >= count+3 && $0["actionFraming"] as? Bool == false && $0["framingMotionActive"] as? Bool == false }
            let restored = values(app)
            XCTAssertEqual(number(restored,"distance"),originalDistance,accuracy:originalDistance * 0.001)
            XCTAssertEqual(number(restored,"framingSize"),number(initial,"framingSize"))
            XCTAssertEqual(number(restored,"framingAngle"),number(initial,"framingAngle"))
            capture(id + "-restored",app)
            app.buttons["viewerBackButton"].tap()
        }
    }
    @MainActor private func values(_ app:XCUIApplication) -> [String:Any] {
        guard let raw=app.buttons["customizationButton"].value as? String,
              let data=raw.data(using:.utf8),let json=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return [:] }
        return json
    }
    private func number(_ value:[String:Any],_ key:String) -> Double { (value[key] as? NSNumber)?.doubleValue ?? -999 }
    @MainActor private func wait(_ app:XCUIApplication,timeout:TimeInterval=8,_ check:@escaping ([String:Any])->Bool) {
        let expectation=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in MainActor.assumeIsolated { check(self.values(app)) } },object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[expectation],timeout:timeout),.completed,"Runtime state: \(values(app))")
    }
    @MainActor private func capture(_ name:String,_ app:XCUIApplication) {
        let screenshot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());screenshot.name=name;screenshot.lifetime = .keepAlways;add(screenshot)
        if let data=try? JSONSerialization.data(withJSONObject:values(app),options:[.prettyPrinted,.sortedKeys]) {
            let state=XCTAttachment(data:data,uniformTypeIdentifier:"public.json");state.name=name+"-runtime";state.lifetime = .keepAlways;add(state)
        }
    }
}
