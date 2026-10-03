import XCTest

final class NaturalIdleTests: XCTestCase {
    @MainActor func testVisibleIdleAndCategoryDefaultsPreserveOtherSelections() {
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
            XCTAssertEqual(number(before,"revision"),2)
            XCTAssertEqual(number(before,"blinkDurationSeconds"),0.455,accuracy:0.002)
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
            app.openCharacterPerformance()
            XCTAssertTrue(app.buttons["closeCharacterPerformance"].waitForExistence(timeout:8))
            app.buttons["performanceGroup-expression"].tap()
            let defaultExpression=app.buttons["performanceDefault-expression"]
            XCTAssertTrue(defaultExpression.waitForExistence(timeout:5))
            XCTAssertEqual(defaultExpression.value as? String,"已选择")
            let expression=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","performanceOption-")).firstMatch
            XCTAssertTrue(expression.waitForExistence(timeout:5));expression.tap()
            let expressionID=String(expression.identifier.dropFirst("performanceOption-".count))
            app.waitForCharacter {
                let selections=($0["characterPlatform"] as? [String:Any])?["performanceSelections"] as? [String] ?? []
                return selections.contains(expressionID)
            }
            app.buttons["performanceGroup-pose"].tap()
            let poseID=role=="anime-kipfel" ? "kipfel-sit" : "mamehinata-sit"
            let pose=app.buttons["performanceOption-"+poseID]
            for _ in 0..<6 {
                let options=app.scrollViews["performanceOptions"]
                if options.frame.insetBy(dx:0,dy:6).contains(pose.frame) { break }
                options.swipeUp()
            }
            XCTAssertTrue(pose.waitForExistence(timeout:5));pose.tap()
            app.buttons["performanceGroup-expression"].tap()
            XCTAssertTrue(defaultExpression.isHittable,"Each category opens at its visible default choice")
            capture(role+"-default-option",app)
            defaultExpression.tap()
            app.waitForCharacter {
                let selections=($0["characterPlatform"] as? [String:Any])?["performanceSelections"] as? [String] ?? []
                return !selections.contains(expressionID) && selections.contains(poseID)
            }
            XCTAssertEqual(defaultExpression.value as? String,"已选择")
            app.closeCharacterPerformance()
            refresh(app)
            app.waitForCharacter { self.autonomy($0)["blinkSuppressed"] as? Bool == false }
            capture(role+"-expression-restored-pose-retained",app)
            app.openCharacterPerformance()
            app.buttons["performanceGroup-pose"].tap()
            app.buttons["performanceDefault-pose"].tap()
            app.waitForCharacter {
                let selections=($0["characterPlatform"] as? [String:Any])?["performanceSelections"] as? [String] ?? []
                return !selections.contains(poseID)
            }
            XCTAssertEqual(app.buttons["performanceDefault-pose"].value as? String,"已选择")
            let appearanceGroup=app.buttons["performanceGroup-appearance"]
            for _ in 0..<4 {
                let groups=app.scrollViews["performanceGroups"]
                // Off-screen SwiftUI cells can make isHittable itself fail in
                // XCTest. Scroll by geometry before asking for an activation point.
                if groups.frame.insetBy(dx:6,dy:0).contains(appearanceGroup.frame) { break }
                groups.swipeLeft()
            }
            XCTAssertTrue(appearanceGroup.isHittable);appearanceGroup.tap()
            XCTAssertEqual(app.buttons["performanceDefault-appearance"].value as? String,"已选择",
                           "Authored default-on accessories are part of the default state")
            app.buttons["performanceReset"].tap()
            app.closeCharacterPerformance()
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
