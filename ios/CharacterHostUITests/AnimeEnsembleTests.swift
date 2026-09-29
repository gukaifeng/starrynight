import XCTest

final class AnimeEnsembleTests:XCTestCase {
    @MainActor func testRefinedMaterialCustomizationAndHeadTouchDuringAction() {
        let app=launch();open(app,id:"anime-shino",name:"小诗");stopVoice(app)
        capture("refined-shino-conversation",app)
        send("放松一下",app)
        app.waitForCharacter { ($0["characterPlatform"] as? [String:Any])?["activeAction"] as? String == "Relax" }
        let before=app.characterRuntime
        let count=number(before["gaze"] as? [String:Any] ?? [:],"headReactionCount")
        app.coordinate(withNormalizedOffset:CGVector(dx:number(before,"headX"),dy:number(before,"headY"))).tap()
        app.waitForCharacter {
            let gaze=$0["gaze"] as? [String:Any] ?? [:]
            return self.number(gaze,"headReactionCount")>count && self.number(gaze,"headReactionPeak")>8
        }
        capture("refined-shino-touch-during-relax",app);stopVoice(app)
        app.openCustomization("appearance")
        XCTAssertTrue(app.buttons["parameter-hair-tone-1"].waitForExistence(timeout:6))
        app.buttons["parameter-hair-tone-1"].tap()
        app.closeCustomizationPage("closeStudioButton")
        capture("refined-shino-tinted",app)
        open(app,id:"anime-vita",name:"小光");stopVoice(app)
        capture("refined-vita-conversation",app)
        app.openCustomization("appearance")
        XCTAssertTrue(app.buttons["parameter-hair-tone-0"].isSelected)
        app.closeCustomizationPage("closeStudioButton")
        open(app,id:"anime-shino",name:"小诗")
        app.openCustomization("appearance")
        XCTAssertTrue(app.buttons["parameter-hair-tone-1"].isSelected)
        app.buttons["parameter-hair-tone-0"].tap()
        app.closeCustomizationPage("closeStudioButton")
        capture("refined-shino-returned",app)
    }
    @MainActor func testThreeNewCharactersSearchSpeakAndRespondToHeadTouch() {
        let app = launch()
        for (id,name) in [("anime-vita","小光"),("anime-shino","小诗"),("anime-fumiriya","晴川")] {
            open(app,id:id,name:name)
            app.waitForCharacter { $0["modelId"] as? String == id && $0["greetingCount"] as? Int == 1 }
            XCTAssertTrue(app.staticTexts.matching(identifier:"assistantMessage").firstMatch.label.contains(name))
            XCTAssertEqual(app.characterRuntime["modelControlsLocked"] as? Bool,true)
            XCTAssertEqual(app.characterRuntime["actionFraming"] as? Bool,false)
            let voices = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","messageVoice-"))
            let playing = NSPredicate { _,_ in MainActor.assumeIsolated {
                voices.allElementsBoundByIndex.contains { ($0.value as? String ?? "").contains("voiceMotion:playing") }
            } }
            XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:playing,object:nil)],timeout:30),.completed)
            capture(id+"-conversation",app); stopVoice(app)
            let before = app.characterRuntime, count = number(before,"headTapCount")
            app.coordinate(withNormalizedOffset:CGVector(dx:number(before,"headX"),dy:number(before,"headY"))).press(forDuration:0.12)
            app.waitForCharacter { self.number($0,"headTapCount") > count }
            app.waitForCharacter { ($0["characterPlatform"] as? [String:Any])?["lastAction"] as? String == "No" }
            capture(id+"-head-touch",app)
            send("抬手和我打招呼",app)
            app.waitForCharacter { ($0["characterPlatform"] as? [String:Any])?["lastAction"] as? String == "Hello" }
            capture(id+"-hello",app); stopVoice(app)
        }
    }

    @MainActor func testConversationActionsAndAppearanceRemainCharacterScoped() {
        let app = launch();open(app,id:"anime-shino",name:"小诗");stopVoice(app)
        for (text,action) in [("点点头","Yes"),("想一想","Think"),("侧耳倾听一下","Listen"),("轻声讲述","Talk"),("放松一下","Relax"),("认真回应","Thanks")] {
            send(text,app)
            app.waitForCharacter { ($0["characterPlatform"] as? [String:Any])?["lastAction"] as? String == action }
            XCTAssertEqual(app.characterRuntime["actionFraming"] as? Bool,false)
            capture("anime-action-"+action,app);stopVoice(app)
        }
        app.openCustomization("appearance")
        let hair = app.buttons["parameter-hair-tone-1"]
        XCTAssertTrue(hair.waitForExistence(timeout:8));hair.tap()
        XCTAssertTrue(hair.isSelected)
        capture("anime-shino-custom-hair",app)
        app.closeCustomizationPage("closeStudioButton")
        app.toggleModelLock()
        let region = app.images["characterGestureRegion"]
        let previous = number(app.characterRuntime,"gestureCount")
        region.coordinate(withNormalizedOffset:CGVector(dx:0.35,dy:0.6)).press(forDuration:0.1,thenDragTo:region.coordinate(withNormalizedOffset:CGVector(dx:0.65,dy:0.6)))
        app.waitForCharacter { self.number($0,"gestureCount") > previous }
        capture("anime-shino-turned",app)
        open(app,id:"anime-vita",name:"小光")
        XCTAssertEqual(app.characterRuntime["modelControlsLocked"] as? Bool,true)
        capture("anime-vita-independent",app)
        app.openCustomization("appearance")
        XCTAssertTrue(app.buttons["parameter-hair-tone-0"].isSelected,"A different character retains its original hair color")
        app.closeCustomizationPage("closeStudioButton")
        app.buttons["tab-messages"].tap()
        XCTAssertTrue(app.buttons["message-anime-shino"].waitForExistence(timeout:8));app.buttons["message-anime-shino"].tap()
        app.waitForCharacter { $0["modelId"] as? String == "anime-shino" }
        XCTAssertEqual(app.characterRuntime["modelControlsLocked"] as? Bool,true,"Entering a different conversation restores the default gesture lock")
        capture("anime-shino-return",app)
        app.openCustomization("appearance")
        XCTAssertTrue(app.buttons["parameter-hair-tone-1"].isSelected,"The character's saved hair choice survives switching conversations")
        capture("anime-shino-saved-hair",app)
        app.closeCustomizationPage("closeStudioButton")
    }

    @MainActor private func launch() -> XCUIApplication {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing"];app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60));return app
    }
    @MainActor private func open(_ app:XCUIApplication,id:String,name:String) {
        app.buttons["tab-discover"].tap();let search=app.textFields["discoverSearch"]
        XCTAssertTrue(search.waitForExistence(timeout:8))
        if app.buttons["clearDiscoverSearch"].exists {app.buttons["clearDiscoverSearch"].tap()}
        search.tap();search.typeText(name)
        XCTAssertTrue(app.buttons["discover-open-"+id].waitForExistence(timeout:8));app.buttons["discover-open-"+id].tap()
        XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:8));app.buttons["profileChatButton"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:45))
        app.waitForCharacter { $0["modelId"] as? String == id }
    }
    @MainActor private func send(_ text:String,_ app:XCUIApplication) {
        let input=app.textFields["chatInput"];XCTAssertTrue(input.waitForExistence(timeout:8));input.tap();input.typeText(text);app.buttons["sendMessageButton"].tap()
    }
    @MainActor private func stopVoice(_ app:XCUIApplication) {
        for voice in app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","messageVoice-")).allElementsBoundByIndex {
            let value=voice.value as? String ?? ""
            if value.contains("播放中") || value.contains("准备中") {voice.tap();break}
        }
    }
    private func number(_ state:[String:Any],_ key:String)->Double {(state[key] as? NSNumber)?.doubleValue ?? 0}
    @MainActor private func capture(_ name:String,_ app:XCUIApplication) {
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
        if let data=try? JSONSerialization.data(withJSONObject:app.characterRuntime,options:[.prettyPrinted,.sortedKeys]) {
            let attachment=XCTAttachment(data:data,uniformTypeIdentifier:"public.json");attachment.name=name+"-runtime";attachment.lifetime = .keepAlways;add(attachment)
        }
    }
}
