import XCTest

final class AuthoredCharacterTests:XCTestCase {
    @MainActor func testCAFPlaybackAndMusicPreferencesStayInsideEachCharacter() {
        let app = launch()
        func evidence() -> [String:Any] {
            guard let raw = app.buttons["musicToggleButton"].value as? String,
                  let value = try? JSONSerialization.jsonObject(with:Data(raw.utf8)) as? [String:Any] else { return [:] }
            return value
        }
        func reveal(_ element:XCUIElement) {
            let scroll = app.scrollViews.containing(.button,identifier:"musicToggleButton").firstMatch
            for _ in 0..<8 {
                if element.isHittable { return }
                if element.exists && element.frame.midY < scroll.frame.midY { scroll.swipeDown() }
                else { scroll.swipeUp() }
            }
            XCTAssertTrue(element.isHittable,element.identifier)
        }
        func openMusic() {
            app.openCustomization("music")
            waitForPage(app,"closeMusicButton",leaving:"closeCustomizationButton")
            XCTAssertTrue(app.buttons["musicToggleButton"].waitForExistence(timeout:5))
        }
        func muteVoice() {
            let mute = app.buttons["characterMuteButton"]
            XCTAssertTrue(mute.waitForExistence(timeout:5))
            if mute.value as? String != "已静音" { mute.tap() }
            wait { mute.value as? String == "已静音" }
        }
        func checkPlayback(track:String,source:String,asset:String,hash:String,after samples:Double) {
            wait {
                let state = evidence()
                return state["playing"] as? Bool == true && state["enabled"] as? Bool == true
                    && state["track"] as? String == track && self.number(state,"samples") >= samples+3
                    && self.number(state,"time") > 0.3
            }
            let state = evidence()
            XCTAssertEqual(state["collectionScope"] as? String,source)
            XCTAssertEqual(state["sourceModelID"] as? String,source)
            XCTAssertEqual(state["asset"] as? String,asset)
            XCTAssertEqual(state["assetSHA256"] as? String,hash)
            XCTAssertGreaterThan(number(state,"duration"),19,"The actual CAF must decode into a playable loop")
            XCTAssertGreaterThan(number(state,"outputVolume"),0)
        }
        func preserveMusic(_ name:String) {
            capture(name,app)
            let proof = XCTAttachment(string:app.buttons["musicToggleButton"].value as? String ?? "missing music evidence")
            proof.name = name+"-player"; proof.lifetime = .keepAlways; add(proof)
        }

        muteVoice(); openMusic()
        XCTAssertEqual(Set(evidence()["availableTrackIDs"] as? [String] ?? []),Set(["hatsune-miku/night","hatsune-miku/day"]))
        XCTAssertFalse(app.buttons["musicTrack-studio-robot/orbit"].exists)
        var samples = number(evidence(),"samples")
        let night = app.buttons["musicTrack-hatsune-miku/night"]
        reveal(night); night.tap()
        checkPlayback(track:"hatsune-miku/night",source:"hatsune-miku",asset:"Music_hatsune_miku_night",
                      hash:"310cf51b54b15985abc5971045efa842e911f38d8649a758fb52b28be52d145f",after:samples)
        preserveMusic("authored-music-01-miku-night-playing")
        samples = number(evidence(),"samples")
        let day = app.buttons["musicTrack-hatsune-miku/day"]
        reveal(day); day.tap()
        let quiet = app.buttons["musicQuietButton"]
        reveal(quiet); quiet.tap()
        checkPlayback(track:"hatsune-miku/day",source:"hatsune-miku",asset:"Music_hatsune_miku_day",
                      hash:"10ca0899c28c02638be0ed6fae2a429f79c1ffa93eadbf143a34d9ce28c195b6",after:samples)
        XCTAssertEqual(number(evidence(),"volume"),0.15,accuracy:0.001)
        preserveMusic("authored-music-02-miku-day-playing")
        app.closeCustomizationPage("closeMusicButton")

        app.buttons["tab-discover"].tap()
        XCTAssertTrue(app.buttons["discover-open-studio-robot"].waitForExistence(timeout:8))
        app.buttons["discover-open-studio-robot"].tap()
        waitForPage(app,"closeCharacterDetails")
        app.buttons["profileChatButton"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.waitForCharacter { $0["modelId"] as? String == "studio-robot" && $0["framingMotionActive"] as? Bool == false }
        muteVoice(); openMusic()
        XCTAssertEqual(Set(evidence()["availableTrackIDs"] as? [String] ?? []),Set(["studio-robot/orbit","studio-robot/light"]))
        XCTAssertFalse(app.buttons["musicTrack-hatsune-miku/night"].exists)
        XCTAssertFalse(app.buttons["musicTrack-hatsune-miku/day"].exists)
        XCTAssertEqual(evidence()["enabled"] as? Bool,true,"Luma starts her own music automatically")
        XCTAssertEqual(evidence()["track"] as? String,"studio-robot/orbit","Luma does not inherit Miku's selected track")
        XCTAssertEqual(number(evidence(),"volume"),0.28,accuracy:0.001)
        samples = number(evidence(),"samples")
        let orbit = app.buttons["musicTrack-studio-robot/orbit"]
        reveal(orbit); orbit.tap()
        let medium = app.buttons["musicMediumButton"]
        reveal(medium); medium.tap()
        checkPlayback(track:"studio-robot/orbit",source:"studio-robot",asset:"Music_studio_robot_orbit",
                      hash:"75d5e0eb3f23825599c405370e3cdf8e133d4d9aeb2433211caef3a4f5154530",after:samples)
        XCTAssertEqual(number(evidence(),"volume"),0.35,accuracy:0.001)
        preserveMusic("authored-music-03-luma-playing")
        app.closeCustomizationPage("closeMusicButton")

        app.buttons["tab-messages"].tap()
        XCTAssertTrue(app.buttons["message-hatsune-miku"].waitForExistence(timeout:8)); app.buttons["message-hatsune-miku"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.waitForCharacter { $0["modelId"] as? String == "hatsune-miku" && $0["framingMotionActive"] as? Bool == false }
        XCTAssertEqual(app.buttons["characterMuteButton"].value as? String,"已静音")
        openMusic()
        samples = number(evidence(),"samples")
        checkPlayback(track:"hatsune-miku/day",source:"hatsune-miku",asset:"Music_hatsune_miku_day",
                      hash:"10ca0899c28c02638be0ed6fae2a429f79c1ffa93eadbf143a34d9ce28c195b6",after:samples)
        XCTAssertEqual(number(evidence(),"volume"),0.15,accuracy:0.001,"Miku keeps her selected track and volume after another role plays")
        preserveMusic("authored-music-04-miku-choice-restored")
        app.closeCustomizationPage("closeMusicButton")
    }

    @MainActor func testCapsuleMuteAndPersonalSettingsKeepTheAuthoredCharacter() {
        let app = launch()
        let camera = app.characterRuntime
        let mute = app.buttons["characterMuteButton"]
        XCTAssertTrue(mute.waitForExistence(timeout:5))
        XCTAssertEqual(mute.value as? String,"自动播放")
        mute.tap()
        wait { mute.value as? String == "已静音" }
        XCTAssertFalse(app.buttons["closeCharacterDetails"].exists,"The capsule mute action must not open the character profile")
        sameCamera(app,camera)
        capture("authored-01-capsule-muted",app)
        mute.tap(); wait { mute.value as? String == "自动播放" }

        app.openCustomization()
        waitForPage(app,"closeCustomizationButton",leaving:"closeCharacterDetails")
        let options = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'customize-'"))
        XCTAssertEqual(Set(options.allElementsBoundByIndex.map(\.identifier)),Set(["customize-music","customize-memory","customize-history"]))
        XCTAssertFalse(app.switches["modelControlLockToggle"].exists)
        XCTAssertFalse(app.switches["autoSpeakToggle"].exists)
        capture("authored-02-personal-settings",app)
        for (page,header) in [("music","closeMusicButton"),("memory","closeMemoryButton"),("history","closeHistoryButton")] {
            app.openCustomization(page)
            waitForPage(app,header,leaving:"closeCustomizationButton")
            sameCamera(app,camera)
            capture("authored-setting-"+page,app)
            app.buttons[header].tap()
            waitForPage(app,"closeCustomizationButton",leaving:header)
        }
        app.buttons["closeCustomizationButton"].tap()
        waitForPage(app,"closeCharacterDetails",leaving:"closeCustomizationButton")
        app.buttons["closeCharacterDetails"].tap()
        wait { !app.buttons["closeCharacterDetails"].exists && mute.isHittable }
        XCTAssertEqual(mute.value as? String,"自动播放")
        sameCamera(app,camera)
    }

    @MainActor func testHeadReactsButDragAndPinchCannotChangeTheAuthoredCamera() {
        let app = launch()
        let before = app.characterRuntime
        XCTAssertEqual(before["nativeHeadHit"] as? String,"CharacterTouchSurface")
        XCTAssertEqual(before["framingGesturesEnabled"] as? Bool,false)
        let headTaps = number(before,"headTapCount")
        app.coordinate(withNormalizedOffset:CGVector(dx:number(before,"headX"),dy:number(before,"headY"))).press(forDuration:0.12)
        app.waitForCharacter { self.number($0,"headTapCount") > headTaps }
        let reaction = app.characterRuntime["gaze"] as? [String:Any] ?? [:]
        XCTAssertGreaterThan(number(reaction,"headReactionCount"),number(before["gaze"] as? [String:Any] ?? [:],"headReactionCount"))
        sameCamera(app,before)
        let touchSurface = app.images["characterGestureRegion"]
        XCTAssertTrue(touchSurface.waitForExistence(timeout:5))
        touchSurface.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:0.7)).press(forDuration:0.05,
            thenDragTo:touchSurface.coordinate(withNormalizedOffset:CGVector(dx:0.75,dy:0.7)))
        touchSurface.pinch(withScale:1.5,velocity:1)
        XCTAssertEqual(number(app.characterRuntime,"gestureCount"),number(before,"gestureCount"))
        // A profile round-trip and one subsequent head touch obtain a fresh
        // ordinary bridge snapshot after both gestures, without a polling hook.
        app.buttons["customizationButton"].tap()
        waitForPage(app,"closeCharacterDetails")
        app.buttons["closeCharacterDetails"].tap()
        wait { !app.buttons["closeCharacterDetails"].exists }
        let current = app.characterRuntime
        app.coordinate(withNormalizedOffset:CGVector(dx:number(current,"headX"),dy:number(current,"headY"))).press(forDuration:0.12)
        app.waitForCharacter { self.number($0,"headTapCount") > self.number(current,"headTapCount") }
        sameCamera(app,before)
        XCTAssertEqual(app.characterRuntime["modelControlsLocked"] as? Bool,true)
        capture("authored-03-reactive-head-fixed-camera",app)
    }

    @MainActor func testCompactDiscoveryLeadsFromCharacterToAuthorAndWorks() {
        let app = launch(discover:true)
        XCTAssertFalse(app.segmentedControls["discoverMode"].exists,"Discovery has one character directory")
        let cards = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'discover-open-'"))
        let visible = cards.allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertGreaterThanOrEqual(visible.count,4,"A phone should expose several compact role cards without an oversized author section")
        for card in visible.prefix(4) {
            XCTAssertLessThan(card.frame.width,app.frame.width*0.5)
            XCTAssertLessThan(card.frame.height,app.frame.height*0.36)
        }
        capture("authored-04-compact-discovery",app)
        app.buttons["discover-open-studio-robot"].tap()
        waitForPage(app,"closeCharacterDetails")
        app.buttons["characterAuthorButton"].tap()
        waitForPage(app,"closeAuthorProfile",leaving:"closeCharacterDetails")
        XCTAssertTrue(app.buttons["followAuthor-starry-studio"].exists)
        let work = app.buttons["authorWork-real-woman"]
        for _ in 0..<6 {
            if work.isHittable { break }
            app.scrollViews["authorProfileScroll"].swipeUp()
        }
        XCTAssertTrue(work.isHittable); work.tap()
        waitForPage(app,"closeCharacterDetails",leaving:"closeAuthorProfile")
        XCTAssertEqual(app.staticTexts["profileName"].label,"小夏")
        XCTAssertTrue(app.buttons["profileChatButton"].exists)
        capture("authored-05-author-work-profile",app)
        app.buttons["closeCharacterDetails"].tap()
        waitForPage(app,"closeAuthorProfile",leaving:"closeCharacterDetails")
        app.buttons["closeAuthorProfile"].tap()
        waitForPage(app,"closeCharacterDetails",leaving:"closeAuthorProfile")
        app.buttons["closeCharacterDetails"].tap()
        wait { !app.buttons["closeCharacterDetails"].exists && app.textFields["discoverSearch"].isHittable }
        XCTAssertFalse(app.segmentedControls["discoverMode"].exists)
    }

    @MainActor private func launch(discover:Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing"] + (discover ? ["--shell-discover"] : [])
        app.launch()
        if discover { XCTAssertTrue(app.buttons["discover-open-studio-robot"].waitForExistence(timeout:30)) }
        else {
            XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
            app.waitForCharacter { $0["modelId"] as? String == "hatsune-miku" && $0["framingMotionActive"] as? Bool == false }
        }
        return app
    }
    @MainActor private func waitForPage(_ app:XCUIApplication,_ header:String,leaving old:String? = nil) {
        wait { app.buttons[header].exists && app.buttons[header].isHittable && (old == nil || !app.buttons[old!].exists) }
    }
    @MainActor private func wait(_ condition:@escaping () -> Bool) {
        let ready = NSPredicate { _,_ in MainActor.assumeIsolated { condition() } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:ready,object:nil)],timeout:8),.completed)
    }
    @MainActor private func sameCamera(_ app:XCUIApplication,_ expected:[String:Any]) {
        let actual = app.characterRuntime
        for key in ["distance","framingSize","framingAngle","pitch","yaw","cameraFov"] {
            XCTAssertEqual(number(actual,key),number(expected,key),accuracy:0.0001,key)
        }
        XCTAssertEqual(actual["framingMotionActive"] as? Bool,false)
    }
    private func number(_ state:[String:Any],_ key:String) -> Double { (state[key] as? NSNumber)?.doubleValue ?? -1 }
    @MainActor private func capture(_ name:String,_ app:XCUIApplication) {
        let screenshot = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        if app.buttons["customizationButton"].exists,
           let data = try? JSONSerialization.data(withJSONObject:app.characterRuntime,options:[.prettyPrinted,.sortedKeys]) {
            let state = XCTAttachment(data:data,uniformTypeIdentifier:"public.json")
            state.name = name+"-runtime"; state.lifetime = .keepAlways; add(state)
        }
    }
}
