import XCTest

final class ExpressiveConversationTests:XCTestCase {
    @MainActor func testRichTimelineAndNativeShakeRouting() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--expressive-conversation-fixture"]
        app.launch();defer {app.terminate()}
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:70))
        app.waitForCharacter {$0["previewShakeCount"] != nil}
        let notice=app.buttons.matching(NSPredicate(format:"label == %@","关闭提示")).firstMatch
        if notice.exists {notice.tap()}
        XCTAssertTrue(app.staticTexts["aiNarration"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","圆圆的眼睛")).firstMatch.exists)
        let baseline=Set((app.characterRuntime["characterPlatform"] as? [String:Any])?["performanceSelections"] as? [String] ?? [])
        let voice=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","messageVoice-")).firstMatch
        XCTAssertTrue(voice.waitForExistence(timeout:5));voice.tap()
        // Paid audio is disabled; the production silent-visual fallback must
        // still execute the same native timeline and real Unity selections.
        app.waitForCharacter({ state in
            let counts=state["confirmedPerformanceCounts"] as? [String:Int] ?? [:]
            return counts.keys.filter {$0 != "all" && !["expression","hands","ears","tail"].contains($0)}.count>=8
        },timeout:15)
        app.waitForCharacter({state in
            Set((state["characterPlatform"] as? [String:Any])?["performanceSelections"] as? [String] ?? [])==baseline
        },timeout:12)
        if notice.exists {notice.tap()}
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="expressive-asides-and-dialogue";shot.lifetime = .keepAlways;add(shot)
        func shake() {
            let chat=app.scrollViews["chatMessages"].frame
            let done=expectation(description:"real repeated single-finger rotation")
            SNSynthesizeConversationShake(CGPoint(x:app.frame.midX,y:chat.maxY-45)) {error in XCTAssertNil(error);done.fulfill()}
            wait(for:[done],timeout:10)
        }
        shake()
        app.waitForCharacter {($0["previewShakeCount"] as? Int ?? 0)==1 && ($0["shakeReactions"] as? Int ?? 0)==1}
        let saved=app.characterRuntime["viewPoseSaved"] as? [String:Double]
        shake()
        XCTAssertEqual(app.characterRuntime["previewShakeCount"] as? Int,1,"Repeated gesture is cooled down")
        XCTAssertEqual(app.characterRuntime["viewPoseSaved"] as? [String:Double],saved,"Temporary rotation cannot rewrite placement")
        XCTAssertEqual(app.characterRuntime["viewEditorOpen"] as? Bool,false)
    }
}
