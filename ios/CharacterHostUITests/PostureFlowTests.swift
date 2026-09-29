import XCTest
import UIKit
final class PostureFlowTests: XCTestCase {
    @MainActor func testDialoguePostureTuningTransitionsAndPersistence() {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--preview-companion","--preview-human","--layout-motion-review"]
        app.launch();XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        wait(app) { self.isPose($0,"stand") }
        send("坐下陪我聊天",app);wait(app) {self.isPose($0,"sit")};capture("01-chat-sit")
        let head=event(app)
        app.coordinate(withNormalizedOffset:CGVector(dx:head["headX"] as? Double ?? 0.5,dy:head["headY"] as? Double ?? 0.35)).press(forDuration:0.12)
        wait(app) {($0["characterPlatform"] as? [String:Any])?["lastAction"] as? String == "No"}
        wait(app) {self.isPose($0,"sit") && ($0["characterPlatform"] as? [String:Any])?["activeAction"] as? String == ""}
        send("上身前倾6度，把腿收一点",app)
        wait(app) { self.isPose($0,"sit") && abs(self.value($0,"lean")-6)<0.05 && abs(self.value($0,"legRoom")-0.35)<0.01 }
        capture("02-dialogue-tuning")
        send("不要站起来",app)
        app.waitForReply(timeout:15)
        XCTAssertEqual(pose(event(app))["id"] as? String,"sit")
        app.openCustomization("appearance");app.segmentedControls["studioTabs"].buttons["姿势"].tap()
        let handle=app.buttons["调整面板高度"],start=app.buttons["调整面板高度"].coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        XCTAssertTrue(handle.exists);start.press(forDuration:0.05,thenDragTo:start.withOffset(CGVector(dx:0,dy:-200)))
        XCTAssertTrue(app.sliders["postureParameter-lean"].waitForExistence(timeout:8))
        app.sliders["postureParameter-lean"].adjust(toNormalizedSliderPosition:0.82)
        wait(app) {self.isPose($0,"sit") && self.value($0,"lean")>6.5};capture("03-precision-controls")
        app.buttons["posture-crouch"].tap();app.buttons["posture-lie"].tap();app.buttons["posture-sit"].tap()
        wait(app) {self.isPose($0,"sit")};capture("03b-interrupted-transition")
        app.buttons["posture-crouch"].tap();wait(app) {self.isPose($0,"crouch")};capture("04-crouch-preview")
        app.closeCustomizationPage("closeStudioButton");wait(app) {self.isPose($0,"crouch")}
        send("蹲下吧",app);wait(app) {self.isPose($0,"crouch")};capture("05-chat-crouch")
        send("侧躺休息一下",app);wait(app) {self.isPose($0,"lie")};capture("06-chat-lie")
        // Switching environments must keep the persistent posture.
        app.openCustomization("appearance");app.segmentedControls["studioTabs"].buttons["空间"].tap()
        app.segmentedControls["environmentCategory"].buttons["室外"].tap()
        let garden=app.buttons["environment-garden"];if !garden.isHittable {app.scrollViews.firstMatch.swipeUp()};garden.tap()
        app.closeCustomizationPage("closeStudioButton")
        wait(app) {self.isPose($0,"lie") && ($0["environment"] as? [String:Any])?["visibleId"] as? String == "garden"};capture("07-lying-in-garden")
        app.terminate();app.launchArguments.append("--keep-companion-data");app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60));wait(app) {self.isPose($0,"lie")};capture("08-restored-posture")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            wait(app){($0["cameraAspect"] as? Double ?? 0)>1 && self.isPose($0,"lie") && $0["framingMotionActive"] as? Bool == false}
            XCTAssertLessThan(event(app)["headX"] as? Double ?? 1,0.6,"The lying face must remain in the model column")
            capture("09-ipad-landscape")
            XCUIDevice.shared.orientation = .portrait
            wait(app){($0["cameraAspect"] as? Double ?? 2)<1 && self.isPose($0,"lie")}
        }
        send("站起来",app);wait(app) {self.isPose($0,"stand")};capture("10-return-standing")
        send("坐下",app);wait(app) {self.isPose($0,"sit") && self.value($0,"lean")>6.5}
        XCTAssertEqual(app.descendants(matching:.scrollBar).count,0)
    }
    @MainActor func testIndependentGLBAndLegacyFallback() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing"];app.launch()
        XCTAssertTrue(app.buttons["chat-real-woman"].waitForExistence(timeout:15))
        let sample=app.buttons["chat-sample-robot"]
        app.selectHomeModel("sample-robot");sample.tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        send("坐下",app);wait(app){self.isPose($0,"sit")};capture("11-independent-glb-sit")
        send("上身前倾3度",app);wait(app){self.isPose($0,"sit") && abs(self.value($0,"lean")-3)<0.01}
        app.buttons["viewerBackButton"].tap()
        let legacy=app.buttons["chat-studio-robot"]
        app.selectHomeModel("studio-robot");legacy.tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:40));send("坐下",app)
        let reply=app.staticTexts.matching(identifier:"assistantMessage")
        let predicate=NSPredicate{_,_ in MainActor.assumeIsolated {reply.allElementsBoundByIndex.contains{$0.label.contains("没有制作")}}}
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:nil)],timeout:20),.completed)
        XCTAssertEqual(pose(event(app))["id"] as? String,"stand");capture("12-legacy-fallback")
    }
    private func pose(_ e:[String:Any])->[String:Any]{e["posture"] as? [String:Any] ?? [:]}
    private func isPose(_ e:[String:Any],_ id:String)->Bool{pose(e)["id"] as? String == id && pose(e)["transitioning"] as? Bool == false}
    private func value(_ e:[String:Any],_ id:String)->Double{(pose(e)["parameters"] as? [[String:Any]])?.first{$0["id"] as? String == id}?["value"] as? Double ?? -999}
    @MainActor private func send(_ text:String,_ app:XCUIApplication) {
        let input=app.textViews["chatInput"].exists ? app.textViews["chatInput"] : app.textFields["chatInput"]
        XCTAssertTrue(input.waitForExistence(timeout:8));input.tap();input.typeText(text);app.buttons["sendMessageButton"].tap()
        app.waitForReply(timeout:20)
    }
    @MainActor private func event(_ app:XCUIApplication)->[String:Any] {
        guard let raw=app.buttons["customizationButton"].value as? String,let data=raw.data(using:.utf8),let result=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else{return [:]};return result
    }
    @MainActor private func wait(_ app:XCUIApplication,_ condition:@escaping ([String:Any])->Bool) {
        let predicate=NSPredicate{_,_ in MainActor.assumeIsolated{condition(self.event(app))}}
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:nil)],timeout:20),.completed,"Event: \(event(app))")
    }
    @MainActor private func capture(_ name:String){let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
