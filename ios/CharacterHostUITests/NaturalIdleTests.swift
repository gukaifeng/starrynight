import XCTest

final class NaturalIdleTests: XCTestCase {
    @MainActor func testBothCharactersMoveWithoutTouchAndKeepSourceExpressionPriority() {
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--layout-motion-review"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.waitForCharacter { $0["modelId"] as? String == "anime-kipfel" && self.autonomy($0)["enabled"] as? Bool == true }
        for role in ["anime-kipfel","anime-mamehinata"] {
            if role == "anime-mamehinata" {
                app.buttons["tab-discover"].tap()
                XCTAssertTrue(app.buttons["discover-open-"+role].waitForExistence(timeout:10))
                app.buttons["discover-open-"+role].tap()
                app.buttons["profileChatButton"].tap()
                app.waitForCharacter({ $0["modelId"] as? String == role && self.autonomy($0)["enabled"] as? Bool == true },timeout:35)
            }
            let before=autonomy(app.characterRuntime)
            let settled=expectation(description:"observe autonomous activity with no touches")
            DispatchQueue.main.asyncAfter(deadline:.now()+22){settled.fulfill()}
            wait(for:[settled],timeout:25)
            refresh(app)
            let after=autonomy(app.characterRuntime)
            XCTAssertGreaterThan(number(after,"blinkCount"),number(before,"blinkCount"))
            XCTAssertGreaterThan(number(after,"headMotionDegrees")-number(before,"headMotionDegrees"),0.4)
            XCTAssertGreaterThan(number(after,"chestMotionDegrees")-number(before,"chestMotionDegrees"),0.4)
            XCTAssertGreaterThan(number(after,"hairTravel")-number(before,"hairTravel"),0.005)
            XCTAssertGreaterThan(number(after,"clothTravel")-number(before,"clothTravel"),0.001)
            XCTAssertEqual(number(after,"poseBreathWeight"),0)
            capture(role+"-autonomous",app)
            app.buttons["conversationPerformanceButton"].tap()
            XCTAssertTrue(app.buttons["closeCharacterPerformance"].waitForExistence(timeout:8))
            app.buttons["performanceGroup-expression"].tap()
            let expression=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","performanceOption-")).firstMatch
            XCTAssertTrue(expression.waitForExistence(timeout:5));expression.tap()
            app.buttons["closeCharacterPerformance"].tap()
            refresh(app)
            app.waitForCharacter { self.autonomy($0)["blinkSuppressed"] as? Bool == true }
            capture(role+"-expression-priority",app)
            app.buttons["conversationPerformanceButton"].tap()
            app.buttons["performanceReset"].tap()
            app.buttons["closeCharacterPerformance"].tap()
            refresh(app)
        }
    }
    private func autonomy(_ data:[String:Any])->[String:Any] {
        (data["characterPlatform"] as? [String:Any])?["autonomy"] as? [String:Any] ?? [:]
    }
    private func number(_ data:[String:Any],_ key:String)->Double { (data[key] as? NSNumber)?.doubleValue ?? 0 }
    @MainActor private func refresh(_ app:XCUIApplication) {
        let time=number(app.characterRuntime,"sampleTime")
        app.buttons["tab-messages"].tap();app.buttons["tab-home"].tap()
        app.waitForCharacter { self.number($0,"sampleTime")>time }
    }
    @MainActor private func capture(_ name:String,_ app:XCUIApplication) {
        let image=XCTAttachment(screenshot:XCUIScreen.main.screenshot());image.name=name;image.lifetime = .keepAlways;add(image)
        if let data=try? JSONSerialization.data(withJSONObject:app.characterRuntime,options:[.prettyPrinted,.sortedKeys]) {
            let item=XCTAttachment(data:data,uniformTypeIdentifier:"public.json");item.name=name+"-runtime";item.lifetime = .keepAlways;add(item)
        }
    }
}
