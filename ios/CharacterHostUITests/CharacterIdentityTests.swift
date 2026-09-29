import XCTest

final class CharacterIdentityTests:XCTestCase {
    @MainActor func testAllCharactersReactWithTallTransparentChatAndLockedFraming() {
        continueAfterFailure=false
        let app=launch()
        XCTAssertEqual(app.otherElements["companionPanel"].frame.height/app.frame.height,0.60,accuracy:0.02)
        for (id,name) in [("hatsune-miku","初音"),("studio-robot","Luma"),("real-woman","小夏"),("sample-robot","小乐"),("anime-vita","小光"),("anime-shino","小诗"),("anime-fumiriya","晴川")] {
            app.buttons["tab-discover"].tap()
            let search=app.textFields["discoverSearch"]
            XCTAssertTrue(search.waitForExistence(timeout:8))
            if app.buttons["clearDiscoverSearch"].exists { app.buttons["clearDiscoverSearch"].tap() }
            search.tap();search.typeText(name)
            XCTAssertTrue(app.buttons["discover-open-"+id].waitForExistence(timeout:8))
            app.buttons["discover-open-"+id].tap()
            XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:8))
            app.buttons["profileChatButton"].tap()
            XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:40))
            app.waitForCharacter { $0["modelId"] as? String == id && $0["framingMotionActive"] as? Bool == false }
            let before=app.characterRuntime
            XCTAssertEqual(before["nativeGestureRevision"] as? Int,2)
            XCTAssertEqual(before["modelControlsLocked"] as? Bool,true)
            XCTAssertEqual(before["nativeHeadHit"] as? String,"CharacterTouchSurface")
            let reaction=number(before["gaze"] as? [String:Any] ?? [:],"headReactionCount")
            app.coordinate(withNormalizedOffset:CGVector(dx:number(before,"headX"),dy:number(before,"headY"))).tap()
            app.waitForCharacter {
                let gaze=$0["gaze"] as? [String:Any] ?? [:]
                return self.number(gaze,"headReactionCount")>reaction && self.number(gaze,"headReactionPeak")>8
            }
            XCTAssertEqual(number(app.characterRuntime,"distance"),number(before,"distance"),accuracy:0.001)
            capture("head-reacted-"+id,app)
        }
    }
    @MainActor func testHeadTouchAfterOrdinaryStartupAndProfileDismissal() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.waitForCharacter { $0["framingMotionActive"] as? Bool == false }
        for step in 0..<2 {
            let before = app.characterRuntime
            capture("ordinary-head-before-\(step)",app)
            app.coordinate(withNormalizedOffset:CGVector(dx:number(before,"headX"),dy:number(before,"headY"))).tap()
            app.waitForCharacter { self.number($0,"headTapCount") > self.number(before,"headTapCount") }
            capture("ordinary-head-after-\(step)",app)
            if step == 0 {
                app.buttons["customizationButton"].tap()
                XCTAssertTrue(app.buttons["closeCharacterDetails"].waitForExistence(timeout:5))
                app.buttons["closeCharacterDetails"].tap()
                XCTAssertTrue(app.textFields["chatInput"].waitForExistence(timeout:5))
            }
        }
    }
    @MainActor func testProfileDiscoveryAndHeaderNavigation() {
        continueAfterFailure = false
        let app = launch()
        app.waitForCharacter { $0["framingMotionActive"] as? Bool == false }
        let before = app.characterRuntime
        capture("identity-capsule-header",app)
        app.buttons["customizationButton"].tap()
        XCTAssertTrue(app.buttons["profileCustomizeButton"].waitForExistence(timeout:6))
        XCTAssertFalse(app.buttons["closeCustomizationButton"].exists)
        XCTAssertFalse(app.buttons["profileChatButton"].exists,"The live profile is already inside its conversation")
        capture("identity-conversation-profile",app)
        app.buttons["profileCustomizeButton"].tap()
        XCTAssertTrue(app.buttons["customize-music"].waitForExistence(timeout:5))
        XCTAssertFalse(app.switches["modelControlLockToggle"].exists)
        capture("identity-customization",app)
        app.buttons["closeCustomizationButton"].tap()
        XCTAssertTrue(app.buttons["profileCustomizeButton"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["profileChatButton"].exists)
        app.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.2)).tap()
        XCTAssertTrue(app.textFields["chatInput"].waitForExistence(timeout:6))
        app.waitForCharacter { $0["framingMotionActive"] as? Bool == false }
        let after = app.characterRuntime
        for key in ["distance","framingSize","framingAngle","pitch","yaw","cameraFov"] {
            XCTAssertNotNil(before[key]); XCTAssertNotNil(after[key])
            XCTAssertEqual(number(before,key),number(after,key),accuracy:0.001,"Profile dismissal preserves \(key)")
        }
        capture("identity-capsule-after-dismiss",app)
        app.buttons["tab-discover"].tap()
        XCTAssertTrue(app.buttons["discover-open-studio-robot"].waitForExistence(timeout:8))
        capture("identity-compact-discovery",app)
        XCTAssertFalse(app.buttons["follow-studio-robot"].exists)
        app.buttons["discover-open-studio-robot"].tap()
        XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:6))
        XCTAssertFalse(app.buttons["customizationButton"].exists,"Discovery opens a profile without loading Unity")
        capture("identity-discovery-profile",app)
        app.buttons["profileChatButton"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:30))
        app.waitForCharacter { $0["modelId"] as? String == "studio-robot" }
        capture("identity-round-header",app)
        app.buttons["tab-discover"].tap()
        XCTAssertTrue(app.buttons["discover-open-studio-robot"].waitForExistence(timeout:8))
        app.buttons["discover-open-studio-robot"].tap()
        XCTAssertTrue(app.buttons["profileCustomizeButton"].waitForExistence(timeout:5))
        app.buttons["profileCustomizeButton"].tap()
        XCTAssertTrue(app.buttons["customize-music"].waitForExistence(timeout:20),"Discovery can open the retained character’s personal settings")
        XCTAssertFalse(app.switches["modelControlLockToggle"].exists)
        app.buttons["closeCustomizationButton"].tap()
    }

    @MainActor func testHeadDragAndPinchUseTheRealUnityTouchSurface() {
        continueAfterFailure = false
        let app = launch()
        app.waitForCharacter { $0["framingMotionActive"] as? Bool == false }
        let before = app.characterRuntime
        XCTAssertEqual(before["nativeGestures"] as? Bool,true)
        XCTAssertEqual(before["nativeGestureRevision"] as? Int,2)
        XCTAssertEqual(before["nativeHeadHit"] as? String,"CharacterTouchSurface")
        capture("touch-before",app)
        let taps = number(before,"headTapCount")
        app.coordinate(withNormalizedOffset:CGVector(dx:number(before,"headX"),dy:number(before,"headY"))).press(forDuration:0.12)
        app.waitForCharacter { self.number($0,"headTapCount") > taps }
        XCTAssertEqual(app.characterRuntime["modelControlsLocked"] as? Bool,true)
        let region = app.images["characterGestureRegion"]
        region.coordinate(withNormalizedOffset:CGVector(dx:0.3,dy:0.7)).press(forDuration:0.05,
            thenDragTo:region.coordinate(withNormalizedOffset:CGVector(dx:0.7,dy:0.7)))
        XCTAssertEqual(number(app.characterRuntime,"framingAngle"),number(before,"framingAngle"),accuracy:0.001)
        XCTAssertEqual(app.characterRuntime["framingGesturesEnabled"] as? Bool,false)
        let count = number(app.characterRuntime,"gestureCount")
        region.pinch(withScale:1.5,velocity:1)
        XCTAssertEqual(number(app.characterRuntime,"gestureCount"),count)
        for key in ["distance","framingSize","framingAngle","pitch","yaw","cameraFov"] {
            XCTAssertEqual(number(app.characterRuntime,key),number(before,key),accuracy:0.001,key)
        }
        capture("touch-authored-framing-after-drag-pinch",app)
        app.buttons["tab-messages"].tap()
        XCTAssertTrue(app.buttons["message-hatsune-miku"].waitForExistence(timeout:8))
        app.buttons["message-hatsune-miku"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:15))
        let resumed = app.characterRuntime
        app.coordinate(withNormalizedOffset:CGVector(dx:number(resumed,"headX"),dy:number(resumed,"headY"))).press(forDuration:0.12)
        app.waitForCharacter { self.number($0,"headTapCount") > self.number(resumed,"headTapCount") }
        capture("touch-retained-conversation",app)
    }
    @MainActor func testBlankTapDismissesKeyboardWithoutBlockingCharacterAndComposer() {
        continueAfterFailure = false
        let app = launch()
        app.waitForCharacter { $0["framingMotionActive"] as? Bool == false }
        let input = app.textViews["chatInput"].exists ? app.textViews["chatInput"] : app.textFields["chatInput"]
        let draft = "这段草稿先留着"
        let keyboard = app.keyboards.firstMatch
        func keyboardClosed() {
            let hidden = NSPredicate { _,_ in MainActor.assumeIsolated { !keyboard.exists } }
            XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:hidden,object:nil)],timeout:6),.completed)
        }
        input.tap(); input.typeText(draft)
        XCTAssertTrue(keyboard.waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["recordVoiceButton"].isHittable)
        // A real blank point over the stage, clear of the left identity capsule,
        // chat controls and the character's head. No test-only dismissal hook.
        let blankY = app.buttons["customizationButton"].frame.maxY + 48
        app.coordinate(withNormalizedOffset:.zero)
            .withOffset(CGVector(dx:app.frame.width-18,dy:blankY-app.frame.minY)).tap()
        keyboardClosed()
        XCTAssertEqual(input.value as? String,draft)
        capture("keyboard-blank-dismiss-keeps-draft",app)

        input.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout:5))
        let beforeHead = app.characterRuntime
        app.coordinate(withNormalizedOffset:CGVector(dx:number(beforeHead,"headX"),dy:number(beforeHead,"headY"))).tap()
        app.waitForCharacter { self.number($0,"headTapCount") > self.number(beforeHead,"headTapCount") }
        keyboardClosed()
        XCTAssertEqual(input.value as? String,draft,"The same head tap must dismiss typing and still reach Unity")
        capture("keyboard-head-tap-still-reacts",app)

        input.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout:5))
        app.buttons["customizationButton"].tap()
        XCTAssertTrue(app.buttons["closeCharacterDetails"].waitForExistence(timeout:5))
        app.buttons["closeCharacterDetails"].tap()
        XCTAssertTrue(input.waitForExistence(timeout:5))
        keyboardClosed()
        XCTAssertEqual(input.value as? String,draft)

        input.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout:5))
        // Composer taps retain their own handlers; the outside observer must
        // never dismiss or move a send/voice target before it receives a tap.
        XCTAssertTrue(app.buttons["recordVoiceButton"].isHittable)
        app.buttons["sendMessageButton"].tap()
        let sent = app.staticTexts.matching(NSPredicate(format:"identifier == %@ AND label == %@","userMessage",draft)).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout:8))
        keyboardClosed()
        XCTAssertNotEqual(input.value as? String,draft)
        capture("keyboard-composer-send-still-works",app)
    }
    @MainActor func testSpeakingAvatarRipplesStopWithSpeech() {
        continueAfterFailure = false
        let app = launch()
        let input = app.textFields["chatInput"]
        input.tap(); input.typeText("你好，今天一起听音乐吧")
        app.buttons["sendMessageButton"].tap()
        // A proactive greeting precedes the reply. Bind the actually playing message
        // instead of assuming the first bubble is the response to the text just sent.
        let activeVoice = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND value CONTAINS %@",
            "messageVoice-","voiceMotion:playing")).firstMatch
        XCTAssertTrue(activeVoice.waitForExistence(timeout:35))
        let voice = app.buttons[activeVoice.identifier]
        XCTAssertEqual(app.characterRuntime["avatarVoicePlaying"] as? Bool,true)
        capture("identity-avatar-speaking",app)
        voice.tap()
        let stopped = NSPredicate { _,_ in MainActor.assumeIsolated { (voice.value as? String ?? "").contains("voiceMotion:static") } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:stopped,object:nil)],timeout:5),.completed)
        XCTAssertEqual(app.characterRuntime["avatarVoicePlaying"] as? Bool,false)
        RunLoop.current.run(until:Date().addingTimeInterval(0.5))
        capture("identity-avatar-stopped",app)
    }
    @MainActor private func launch() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--auth-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        return app
    }
    private func number(_ values:[String:Any],_ key:String) -> Double { (values[key] as? NSNumber)?.doubleValue ?? 0 }
    @MainActor private func capture(_ name:String,_ app:XCUIApplication) {
        RunLoop.current.run(until:Date().addingTimeInterval(0.5))
        let shot = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        if app.buttons["customizationButton"].exists, let data = try? JSONSerialization.data(withJSONObject:app.characterRuntime,options:[.prettyPrinted,.sortedKeys]) {
            let state = XCTAttachment(data:data,uniformTypeIdentifier:"public.json");state.name = name+"-runtime";state.lifetime = .keepAlways;add(state)
        }
    }
}
