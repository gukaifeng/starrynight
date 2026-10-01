import XCTest
import UIKit

final class VoiceAtmosphereTests:XCTestCase {
    @MainActor func testBundledFirstMeetingAndPersistentReset() {
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--opening-check"]
        app.launch();defer{app.terminate()}
        let result=app.staticTexts["openingCheckResult"]
        wait {result.exists && (result.label.hasPrefix("PASS:") || result.label.hasPrefix("FAIL:"))}
        XCTAssertTrue(result.label.hasPrefix("PASS:"),result.label)
        let evidence=XCTAttachment(string:result.label);evidence.lifetime = .keepAlways;add(evidence)
    }

    @MainActor func testHoldSurvivesEarlyRecognitionAndReleasesIntoEditor() {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--voice-atmosphere-check"]
        app.launch();defer {app.terminate()}
        wait {app.staticTexts["voiceCoreResult"].exists && app.staticTexts["voiceCoreResult"].label.hasPrefix("PASS:")}
        app.buttons["inputModeButton"].tap()
        let hold=app.buttons["holdToTalkButton"]
        XCTAssertTrue(hold.waitForExistence(timeout:5))
        let origin=hold.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        // The deterministic ASR final arrives after 340ms, while this finger is
        // still held. The landing area sits immediately above the composer.
        origin.press(forDuration:0.8,thenDragTo:origin.withOffset(CGVector(dx:85,dy:-75)),withVelocity:.slow,thenHoldForDuration:0.6)
        let edit=app.textViews["voiceEditText"]
        XCTAssertTrue(edit.waitForExistence(timeout:5));XCTAssertEqual(edit.value as? String,"今天窗外下雨了")
        XCTAssertEqual(app.staticTexts.matching(identifier:"userMessage").count,0,"Sliding to edit cannot send an early ASR result")
        capture("voice-release-to-edit")
        app.buttons["取消语音消息"].tap()
        XCTAssertTrue(hold.waitForExistence(timeout:5))
        hold.press(forDuration:1.2)
        wait {app.staticTexts.matching(identifier:"userMessage").count==1}
        XCTAssertFalse(edit.exists,"A release outside the target sends directly")
    }
    @MainActor func testHeldCancelDiscardsEarlyRecognitionAndPreservesTypedDraft() {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--voice-atmosphere-check"]
        app.launch();defer {app.terminate()}
        wait {app.staticTexts["voiceCoreResult"].exists && app.staticTexts["voiceCoreResult"].label.hasPrefix("PASS:")}
        let input=app.textViews["chatInput"]
        input.tap();input.typeText("Keep draft")
        let draft=input.value as? String
        app.buttons["inputModeButton"].tap()
        let origin=app.buttons["holdToTalkButton"].coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        origin.press(forDuration:0.8,thenDragTo:origin.withOffset(CGVector(dx:-85,dy:-75)),withVelocity:.slow,thenHoldForDuration:0.5)
        XCTAssertFalse(app.textViews["voiceEditText"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier:"userMessage").count,0)
        XCTAssertEqual(app.buttons["holdToTalkButton"].value as? String,"未录音")
        app.buttons["inputModeButton"].tap()
        XCTAssertEqual(input.value as? String,draft)
        capture("cancelled-voice-keeps-draft")
    }
    @MainActor func testCaptureFailureKeepsHeldWordsForReview() {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--voice-atmosphere-check","--voice-capture-error"]
        app.launch();defer {app.terminate()}
        wait {app.staticTexts["voiceCoreResult"].exists && app.staticTexts["voiceCoreResult"].label.hasPrefix("PASS:")}
        app.buttons["inputModeButton"].tap()
        app.buttons["holdToTalkButton"].press(forDuration:1.2)
        let edit=app.textViews["voiceEditText"]
        XCTAssertTrue(edit.waitForExistence(timeout:5));XCTAssertEqual(edit.value as? String,"今天窗外下雨了")
        XCTAssertEqual(app.staticTexts.matching(identifier:"userMessage").count,0,"An interrupted recording requires review")
        edit.tap();edit.typeText("!")
        app.buttons["sendVoiceEditButton"].tap()
        wait {app.staticTexts.matching(identifier:"userMessage").count==1}
    }
    @MainActor func testCompactVoiceEditingWithLandscapeKeyboard() {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--voice-atmosphere-check"]
        app.launch();defer {app.terminate();XCUIDevice.shared.orientation = .portrait}
        wait {app.staticTexts["voiceCoreResult"].exists && app.staticTexts["voiceCoreResult"].label.hasPrefix("PASS:")}
        app.buttons["fixtureVoiceEdit"].tap()
        var edit=app.textViews["voiceEditText"]
        XCTAssertTrue(edit.waitForExistence(timeout:5));edit.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5))
        wait {app.keyboards.firstMatch.frame.height>80}
        // Query again after compact layout replaces the original editor.
        edit=app.textViews["voiceEditText"];edit.typeText("!")
        XCTAssertTrue(app.frame.contains(edit.frame))
        XCTAssertLessThanOrEqual(edit.frame.maxY,app.keyboards.firstMatch.frame.minY+2)
        XCTAssertTrue(app.buttons["sendVoiceEditButton"].isHittable)
        XCTAssertTrue(app.buttons["取消语音消息"].isHittable)
        capture("landscape-voice-editor")
        app.buttons["sendVoiceEditButton"].tap()
        XCTAssertTrue(app.staticTexts.matching(identifier:"userMessage").firstMatch.waitForExistence(timeout:5))
    }
    @MainActor func testVoiceDraftEditingAndReleaseLifecycle() {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--voice-atmosphere-check"]
        app.launch();defer {app.terminate()}
        let result=app.staticTexts["voiceCoreResult"]
        wait {result.exists && result.label.hasPrefix("PASS:")}
        let evidence=XCTAttachment(string:result.label);evidence.lifetime = .keepAlways;add(evidence)
        let input=app.textViews["chatInput"]
        input.tap();input.typeText("Keep this typed draft")
        let typedDraft=input.value as? String
        XCTAssertFalse(typedDraft?.isEmpty ?? true)
        app.buttons["inputModeButton"].tap()
        XCTAssertTrue(app.buttons["holdToTalkButton"].waitForExistence(timeout:4))
        XCTAssertFalse(app.buttons["sendMessageButton"].exists)
        app.buttons["inputModeButton"].tap()
        XCTAssertEqual(input.value as? String,typedDraft)
        app.buttons["fixtureVoiceEdit"].tap()
        let edit=app.textViews["voiceEditText"]
        XCTAssertTrue(edit.waitForExistence(timeout:5));XCTAssertEqual(edit.value as? String,"今天窗外下雨了")
        XCTAssertEqual(app.staticTexts.matching(identifier:"userMessage").count,0,"Editing must not send prematurely")
        edit.tap();edit.typeText("!")
        capture("voice-edit-draft")
        app.buttons["sendVoiceEditButton"].tap()
        XCTAssertTrue(app.staticTexts.matching(identifier:"userMessage").matching(NSPredicate(format:"label CONTAINS %@","今天窗外下雨了")).firstMatch.waitForExistence(timeout:6))
        XCTAssertEqual(input.value as? String,typedDraft,"Voice edits cannot overwrite the keyboard draft")
        app.buttons["fixtureVoiceEdit"].tap();app.buttons["取消语音消息"].tap()
        XCTAssertFalse(edit.exists)
        let before=app.staticTexts.matching(identifier:"userMessage").count
        app.buttons["fixtureVoiceSend"].tap()
        wait {app.staticTexts.matching(identifier:"userMessage").count==before+1}
        XCTAssertEqual(input.value as? String,typedDraft)
    }
    @MainActor func testPhoneAndTabletCompositionMediaAndControls() {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch();defer {app.terminate();XCUIDevice.shared.orientation = .portrait}
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:75))
        app.waitForCharacter {$0["modelId"] as? String == "anime-kipfel"}
        for orientation:UIDeviceOrientation in [.portrait,.landscapeLeft,.landscapeRight] {
            XCUIDevice.shared.orientation=orientation
            wait {(app.frame.width>app.frame.height)==orientation.isLandscape}
            let input=app.textViews["chatInput"],toggle=app.buttons["inputModeButton"],smart=app.buttons["smartReplyButton"]
            XCTAssertTrue(toggle.isHittable && smart.isHittable)
            XCTAssertLessThan(toggle.frame.maxX,input.frame.minX+8)
            XCTAssertGreaterThan(smart.frame.minX,input.frame.maxX-8)
            XCTAssertTrue(app.frame.contains(input.frame))
            let audio=audioState(app)
            XCTAssertEqual((audio["availableTrackIDs"] as? [String])?.count,1)
            XCTAssertEqual(audio["track"] as? String,"anime-kipfel/theme")
            capture(orientation.isLandscape ? "conversation-landscape-\(orientation.rawValue)" : "conversation-portrait")
            input.tap();input.typeText("draft")
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5))
            XCTAssertLessThanOrEqual(input.frame.maxY,app.keyboards.firstMatch.frame.minY+2)
            capture("keyboard-\(orientation.rawValue)")
            app.buttons["inputModeButton"].tap()
            wait {!app.keyboards.firstMatch.exists}
            XCTAssertTrue(app.buttons["holdToTalkButton"].isHittable)
            app.buttons["inputModeButton"].tap()
            XCTAssertTrue((input.value as? String ?? "").contains("draft"))
            app.openConversationSettings("sound")
            XCTAssertTrue(app.sliders["musicSoundVolume"].waitForExistence(timeout:5))
            XCTAssertFalse(app.buttons["chooseSoundTrack"].exists)
            XCTAssertTrue(app.sliders["speechSoundVolume"].isHittable)
            capture("sound-\(orientation.rawValue)")
            app.buttons["closeCharacterViewEditor"].tap()
        }
        XCUIDevice.shared.orientation = .portrait
        wait {app.frame.height>app.frame.width}
        app.openConversationSettings("atmosphere")
        let effects=app.sliders["atmosphereLevelSlider"]
        XCTAssertTrue(effects.waitForExistence(timeout:5));XCTAssertEqual(effects.value as? String,"适中")
        effects.adjust(toNormalizedSliderPosition:0);XCTAssertEqual(effects.value as? String,"关闭")
        app.buttons["closeCharacterViewEditor"].tap()
        for role in ["anime-mamehinata","anime-chiffon","anime-karin","anime-kipfel"] {
            app.buttons["tab-discover"].tap()
            let card=app.buttons["discover-open-"+role]
            XCTAssertTrue(card.waitForExistence(timeout:7));capture("discover-"+role);card.tap()
            XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:5));capture("profile-"+role)
            app.buttons["profileChatButton"].tap()
            app.waitForCharacter({$0["modelId"] as? String == role},timeout:50)
            wait {(self.audioState(app)["track"] as? String)==role+"/theme"}
            capture("scene-"+role)
        }
        app.openConversationSettings("atmosphere");XCTAssertEqual(effects.value as? String,"关闭","Effects preference survives a role switch")
        app.buttons["closeCharacterViewEditor"].tap()
        app.buttons["tab-messages"].tap();capture("tablet-phone-messages")
        app.buttons["tab-mine"].tap();capture("tablet-phone-account")
    }
    @MainActor private func audioState(_ app:XCUIApplication)->[String:Any] {
        return app.characterAudio
    }
    @MainActor private func wait(_ condition:@escaping ()->Bool) {
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in MainActor.assumeIsolated {condition()}},object:nil)],timeout:20),.completed)
    }
    @MainActor private func capture(_ name:String) {
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
    }
}
