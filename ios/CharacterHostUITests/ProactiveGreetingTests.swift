import XCTest

final class ProactiveGreetingTests:XCTestCase {
    @MainActor func testLaunchSwitchReturnAndRelaunchGreetings() {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch()
        greeting(app,model:"anime-kipfel",scene:"firstLaunch",count:1,speaking:true)
        capture("launch-greeting-speaking",app)
        app.buttons["tab-messages"].tap();app.buttons["tab-home"].tap()
        app.waitForCharacter {$0["modelId"] as? String == "anime-kipfel" && $0["nativeHoldAvailable"] as? Bool == true}
        XCTAssertEqual(app.characterRuntime["greetingCount"] as? Int,1,"Returning to the same retained role adds no greeting")
        app.buttons["tab-discover"].tap()
        XCTAssertTrue(app.buttons["discover-open-anime-mamehinata"].waitForExistence(timeout:10))
        app.buttons["discover-open-anime-mamehinata"].tap()
        XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:6));app.buttons["profileChatButton"].tap()
        greeting(app,model:"anime-mamehinata",scene:"firstMeeting",count:1,speaking:true)
        capture("switch-first-meeting-speaking",app)
        app.buttons["tab-messages"].tap()
        XCTAssertTrue(app.buttons["message-anime-kipfel"].waitForExistence(timeout:8));app.buttons["message-anime-kipfel"].tap()
        greeting(app,model:"anime-kipfel",scene:"characterSwitch",count:2,speaking:true)
        capture("switch-known-character-speaking",app)
        XCTAssertEqual(app.characterRuntime["guestTurns"] as? Int,0)
        XCTAssertEqual(app.characterRuntime["userMessageCount"] as? Int,0)
        app.terminate();app.launchArguments += ["--keep-companion-data","--keep-auth-data"];app.launch()
        greeting(app,model:"anime-kipfel",scene:"appLaunch",count:3,speaking:true)
        capture("relaunch-greeting-speaking",app)
        XCUIDevice.shared.press(.home);app.activate()
        app.waitForCharacter {$0["nativeHoldAvailable"] as? Bool == true}
        XCTAssertEqual(app.characterRuntime["greetingCount"] as? Int,3,"Background return must not count as a fresh App launch")
    }
    @MainActor func testZeroSpeechVolumeSurvivesRestartAndGreetsSilently() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch();greeting(app,model:"anime-kipfel",scene:"firstLaunch",count:1,speaking:true)
        app.buttons["conversationSoundButton"].tap()
        XCTAssertTrue(app.buttons["closeConversationSound"].waitForExistence(timeout:6))
        app.sliders["speechSoundVolume"].adjust(toNormalizedSliderPosition:0)
        app.buttons["closeConversationSound"].tap()
        app.terminate();app.launchArguments += ["--keep-companion-data","--keep-auth-data"];app.launch()
        greeting(app,model:"anime-kipfel",scene:"appLaunch",count:2,speaking:false)
        XCTAssertEqual(app.characterRuntime["avatarVoicePlaying"] as? Bool,false)
        let sound=app.buttons["conversationSoundButton"].value as? String ?? "{}"
        let audio=(try? JSONSerialization.jsonObject(with:Data(sound.utf8))) as? [String:Any]
        XCTAssertEqual(audio?["speechVolume"] as? Double,0)
        XCTAssertEqual(audio?["playing"] as? Bool,true,"Speech zero does not mute the music channel")
        capture("zero-volume-greeting",app)
    }
    @MainActor private func greeting(_ app:XCUIApplication,model:String,scene:String,count:Int,speaking:Bool) {
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.waitForCharacter({$0["modelId"] as? String == model && $0["greetingScene"] as? String == scene && $0["greetingCount"] as? Int == count && (!speaking || $0["avatarVoicePlaying"] as? Bool == true)},timeout:35)
        XCTAssertEqual(app.characterRuntime["actionFraming"] as? Bool,false)
    }
    @MainActor private func capture(_ name:String,_ app:XCUIApplication) {
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
        if let data=try? JSONSerialization.data(withJSONObject:app.characterRuntime,options:[.prettyPrinted,.sortedKeys]) {
            let value=XCTAttachment(data:data,uniformTypeIdentifier:"public.json");value.name=name+"-runtime";value.lifetime = .keepAlways;add(value)
        }
    }
}
