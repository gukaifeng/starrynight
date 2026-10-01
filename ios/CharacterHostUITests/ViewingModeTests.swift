import XCTest

final class ViewingModeTests:XCTestCase {
    @MainActor func testViewingPreservesDraftAndPoseAndReleasesConversationTouchRegion() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--conversation-gesture-fixture","-starry.app.language.v1","zh-Hans"]
        app.launch();defer {app.terminate()}
        let toggle=app.buttons["characterViewingButton"]
        XCTAssertTrue(toggle.waitForExistence(timeout:65))
        app.waitForCharacter {($0["name"] as? String)=="state"}
        let input=app.textViews["chatInput"]
        input.tap();XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5))
        input.typeText("Keep draft")
        XCTAssertEqual(input.value as? String,"Keep draft","Verify the native keyboard completed entry before toggling")
        let before=app.characterRuntime
        toggle.tap()
        let hidden=NSPredicate { _,_ in !input.isHittable && toggle.value as? String=="on" }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:hidden,object:nil)],timeout:5),.completed)
        XCTAssertFalse(app.scrollViews["chatMessages"].isHittable)
        XCTAssertEqual(app.characterRuntime["viewPoseSaved"] as? [String:Double],before["viewPoseSaved"] as? [String:Double])
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="viewing-only-no-chat-veil";shot.lifetime = .keepAlways;add(shot)
        // Start on the real displayed head, then travel through the former chat
        // area. The hidden scroll view must not own this gesture.
        let state=app.characterRuntime
        let x=(state["headX"] as? Double) ?? 0.5,y=(state["headY"] as? Double) ?? 0.3
        let start=app.coordinate(withNormalizedOffset:CGVector(dx:x,dy:y))
        let end=app.coordinate(withNormalizedOffset:CGVector(dx:min(0.93,x+0.38),dy:min(0.75,y+0.35)))
        let count=state["previewRotationCount"] as? Int ?? 0
        start.press(forDuration:0.08,thenDragTo:end,withVelocity:.fast,thenHoldForDuration:0.55)
        app.waitForCharacter {($0["previewRotationCount"] as? Int ?? 0)>count && ($0["previewRotationReturnCount"] as? Int ?? 0)>0}
        XCTAssertGreaterThan(app.characterRuntime["previewRotationPeakYaw"] as? Double ?? 0,60)
        XCTAssertGreaterThan(app.characterRuntime["previewRotationPeakPitch"] as? Double ?? 0,8)
        XCTAssertLessThanOrEqual(app.characterRuntime["previewRotationPeakYaw"] as? Double ?? 999,540.01)
        toggle.tap()
        XCTAssertTrue(input.waitForExistence(timeout:5));XCTAssertTrue(input.isHittable)
        XCTAssertEqual(input.value as? String,"Keep draft")
        XCTAssertEqual(app.characterRuntime["viewPoseSaved"] as? [String:Double],before["viewPoseSaved"] as? [String:Double])
    }
}
