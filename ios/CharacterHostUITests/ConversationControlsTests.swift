import XCTest

final class ConversationControlsTests:XCTestCase {
    @MainActor func testKeyboardSoundAuthoredMotionAndHold() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing","--companion-testing","--auth-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.waitForCharacter { $0["modelId"] as? String == "anime-kipfel" && $0["nativeHeadHit"] as? String == "CharacterTouchSurface" }
        XCTAssertFalse(app.buttons["characterMuteButton"].exists)
        XCTAssertTrue(app.buttons["conversationPerformanceButton"].exists)
        let sound=app.buttons["conversationSoundButton"]
        XCTAssertTrue(sound.exists)
        XCTAssertEqual(audio(app)["masterMuted"] as? Bool,false)
        sound.tap()
        XCTAssertTrue(app.buttons["closeConversationSound"].waitForExistence(timeout:8))
        app.sliders["speechSoundVolume"].adjust(toNormalizedSliderPosition:0)
        app.buttons["closeConversationSound"].tap()
        let input=app.textFields["chatInput"]
        input.tap(); input.typeText("saved draft 42")
        XCTAssertFalse(app.buttons["dismissChatKeyboardButton"].exists)
        app.coordinate(withNormalizedOffset:CGVector(dx:0.94,dy:0.30)).tap()
        capture("outside-keyboard-touch",app)
        let hidden=NSPredicate { _,_ in MainActor.assumeIsolated { app.keyboards.count == 0 } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:hidden,object:nil)],timeout:5),.completed)
        XCTAssertEqual(input.value as? String,"saved draft 42")
        capture("keyboard-dismissed-draft-kept",app)
        sound.tap()
        XCTAssertTrue(app.buttons["closeConversationSound"].waitForExistence(timeout:8))
        XCTAssertEqual(app.switches.count,0)
        app.sliders["speechSoundVolume"].adjust(toNormalizedSliderPosition:0)
        app.sliders["speechSoundVolume"].adjust(toNormalizedSliderPosition:0.45)
        app.sliders["musicSoundVolume"].adjust(toNormalizedSliderPosition:0.20)
        app.sliders["speechSoundVolume"].adjust(toNormalizedSliderPosition:0)
        capture("sound-settings",app)
        app.buttons["closeConversationSound"].tap()
        XCTAssertTrue(sound.waitForExistence(timeout:8))
        XCTAssertEqual(audio(app)["enabled"] as? Bool,true)
        XCTAssertEqual(audio(app)["masterMuted"] as? Bool,false)
        XCTAssertEqual(audio(app)["sessionCategory"] as? String,"AVAudioSessionCategoryPlayback")
        XCTAssertTrue((audio(app)["speechVolume"] as? Double ?? 1)<0.8)
        let before=app.characterRuntime
        XCTAssertEqual(before["idlePlaying"] as? Bool,true)
        refresh(app)
        XCTAssertEqual(app.characterRuntime["idlePlaying"] as? Bool,true)
        XCTAssertNotEqual(number(before,"idleTime"),number(app.characterRuntime,"idleTime"),"Original Idle clock must advance in a live app")
        app.buttons["conversationPerformanceButton"].tap()
        XCTAssertTrue(app.buttons["closeCharacterPerformance"].waitForExistence(timeout:8))
        chooseGroup("ears",app)
        let ear=app.buttons["performanceOption-kipfel-catear-pyoko-loop"]
        XCTAssertTrue(ear.waitForExistence(timeout:8));ear.tap()
        app.waitForCharacter { self.selections($0).contains("kipfel-catear-pyoko-loop") }
        capture("source-ear-loop",app)
        app.buttons["performanceReset"].tap()
        app.waitForCharacter { !self.selections($0).contains("kipfel-catear-pyoko-loop") }
        chooseGroup("pose",app)
        let wake=app.buttons["performanceOption-kipfel-afk-sleep-to-stand"]
        if !wake.isHittable { app.scrollViews["performanceOptions"].swipeUp() }
        XCTAssertTrue(wake.exists); wake.tap()
        app.waitForCharacter { self.selections($0).contains("kipfel-afk-sleep-to-stand") }
        app.waitForCharacter({ !self.selections($0).contains("kipfel-afk-sleep-to-stand") && ($0["characterPlatform"] as? [String:Any])?["performanceTransitioning"] as? Bool == false },timeout:20)
        capture("source-one-shot-restored",app)
        app.buttons["closeCharacterPerformance"].tap()
        refresh(app)
        app.buttons["characterPositionButton"].tap()
        XCTAssertTrue(app.buttons["closeCharacterViewEditor"].waitForExistence(timeout:8))
        app.buttons["closeCharacterViewEditor"].tap()
        app.waitForCharacter { $0["viewEditorOpen"] as? Bool == false }
        app.buttons["tab-discover"].tap()
        XCTAssertTrue(app.textFields["discoverSearch"].waitForExistence(timeout:8))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","discover-open-")).count,2)
        app.buttons["discover-open-anime-mamehinata"].tap()
        app.buttons["profileChatButton"].tap()
        app.waitForCharacter({ $0["modelId"] as? String == "anime-mamehinata" && $0["idlePlaying"] as? Bool == true },timeout:30)
        capture("mamehinata-live-idle",app)
    }
    // Draft retention and real two-finger input are covered by CharacterViewEditorTests.
    @MainActor private func chooseGroup(_ group:String,_ app:XCUIApplication) {
        let button=app.buttons["performanceGroup-"+group]
        if !button.isHittable { app.scrollViews["performanceGroups"].swipeLeft() }
        button.tap()
    }
    @MainActor private func refresh(_ app:XCUIApplication) {
        let time=number(app.characterRuntime,"sampleTime")
        app.buttons["tab-messages"].tap();app.buttons["tab-home"].tap()
        app.waitForCharacter { self.number($0,"sampleTime")>time && $0["nativeHeadHit"] as? String == "CharacterTouchSurface" }
    }
    private func number(_ d:[String:Any],_ k:String)->Double { (d[k] as? NSNumber)?.doubleValue ?? -1 }
    private func selections(_ d:[String:Any])->[String] { (d["characterPlatform"] as? [String:Any])?["performanceSelections"] as? [String] ?? [] }
    @MainActor private func audio(_ app:XCUIApplication)->[String:Any] {
        let raw=app.buttons["conversationSoundButton"].value as? String ?? "{}"
        return (try? JSONSerialization.jsonObject(with:Data(raw.utf8))) as? [String:Any] ?? [:]
    }
    @MainActor private func capture(_ name:String,_ app:XCUIApplication) {
        let image=XCTAttachment(screenshot:XCUIScreen.main.screenshot());image.name=name;image.lifetime = .keepAlways;add(image)
        if let data=try? JSONSerialization.data(withJSONObject:app.characterRuntime,options:[.prettyPrinted,.sortedKeys]) {
            let item=XCTAttachment(data:data,uniformTypeIdentifier:"public.json");item.name=name+"-runtime";item.lifetime = .keepAlways;add(item)
        }
    }
}
