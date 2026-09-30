import XCTest

final class CharacterViewEditorTests:XCTestCase {
    @MainActor func testNormalDragReturnsToSavedPoseWithoutOpeningEditor() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch();ready(app)
        app.waitForCharacter {self.number($0,"inspectionGestureRevision")>=8}
        func previewAndReturn() {
            let before=app.characterRuntime,saved=pose(before)
            let stored=before["viewPoseSaved"] as? [String:Double]
            let count=number(before,"previewRotationCount"),returns=number(before,"previewRotationReturnCount")
            let start=app.coordinate(withNormalizedOffset:CGVector(dx:number(before,"headX"),dy:number(before,"headY")))
            start.press(forDuration:0.06,thenDragTo:start.withOffset(CGVector(dx:app.frame.width * 0.25,dy:45)),withVelocity:.slow,thenHoldForDuration:0.3)
            app.waitForCharacter {self.number($0,"previewRotationReturnCount")>returns}
            let after=app.characterRuntime
            XCTAssertEqual(number(after,"previewRotationCount"),count+1)
            XCTAssertGreaterThan(number(after,"previewRotationPeakYaw"),5)
            XCTAssertLessThanOrEqual(number(after,"previewRotationPeakYaw"),18.001)
            XCTAssertLessThanOrEqual(number(after,"previewRotationPeakPitch"),8.001)
            XCTAssertEqual(number(after,"previewRotationYaw"),0)
            XCTAssertEqual(number(after,"previewRotationPitch"),0)
            XCTAssertEqual(after["viewEditorOpen"] as? Bool,false)
            XCTAssertEqual(after["inspectionChatLocked"] as? Bool,false)
            XCTAssertEqual(after["viewPoseSaved"] as? [String:Double],stored,"Temporary rotation must never write the account's saved view")
            for key in ["yaw","pitch","scale","x","y"] {XCTAssertEqual(pose(after)[key] ?? -1,saved[key] ?? -2,accuracy:0.001)}
        }
        previewAndReturn()
        open(app);drag(app,dx:0.06,dy:-0.02)
        app.buttons["closeCharacterViewEditor"].tap()
        app.waitForCharacter {$0["viewEditorOpen"] as? Bool == false && self.number($0,"inspectionMoving")==0}
        previewAndReturn()
        // Message-vs-whitespace routing is covered by ConversationGestureTests.
        capture("temporary-single-finger-rotation",app)
    }
    @MainActor func testNormalPinchReturnsToCustomPoseWithRemainingFinger() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch();ready(app);open(app);drag(app,dx:0.06,dy:-0.02)
        app.buttons["closeCharacterViewEditor"].tap()
        app.waitForCharacter {$0["viewEditorOpen"] as? Bool == false && self.number($0,"inspectionMoving")==0}
        let before=app.characterRuntime,saved=pose(before)
        let center=CGPoint(x:number(before,"headX")*app.frame.width,y:number(before,"headY")*app.frame.height)
        let done=expectation(description:"pinch then move the remaining finger")
        SNSynthesizePreviewPinch(center,0.65) {error in XCTAssertNil(error);done.fulfill()}
        wait(for:[done],timeout:8)
        app.waitForCharacter {self.number($0,"previewPinchReturnCount")>self.number(before,"previewPinchReturnCount")}
        let after=app.characterRuntime
        XCTAssertLessThan(number(after,"previewScaleMinimum"),0.94)
        XCTAssertEqual(number(after,"previewPinchCount"),number(before,"previewPinchCount")+1)
        XCTAssertEqual(number(after,"previewRotationCount"),number(before,"previewRotationCount"),"The remaining finger must not start rotation")
        XCTAssertEqual(number(after,"previewScaleRatio"),1)
        for key in ["yaw","pitch","scale","x","y"] {XCTAssertEqual(pose(after)[key] ?? -1,saved[key] ?? -2,accuracy:0.001)}
        XCTAssertEqual(after["viewPoseSaved"] as? [String:Double],before["viewPoseSaved"] as? [String:Double])
        capture("temporary-pinch-restores-custom-pose",app)
    }
    @MainActor private func previewPinch(ratio:CGFloat,kind:String) {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch();ready(app);app.waitForCharacter {self.number($0,"inspectionGestureRevision")>=12}
        let before=app.characterRuntime,saved=pose(before)
        let center=CGPoint(x:number(before,"headX")*app.frame.width,y:number(before,"headY")*app.frame.height)
        if ratio>1 {
            let done=expectation(description:"two-finger pinch with centroid drift")
            SNSynthesizePreviewPinch(center,ratio) {error in XCTAssertNil(error);done.fulfill()}
            wait(for:[done],timeout:8)
        } else {app.scrollViews["chatMessages"].pinch(withScale:ratio,velocity:-1)}
        app.waitForCharacter {self.number($0,"previewPinchReturnCount")>self.number(before,"previewPinchReturnCount")}
        let after=app.characterRuntime
        XCTAssertEqual(number(after,"previewPinchCount"),number(before,"previewPinchCount")+1)
        XCTAssertEqual(number(after,"previewRotationCount"),number(before,"previewRotationCount"),"The remaining finger cannot become a rotation")
        XCTAssertEqual(number(after,"previewScaleRatio"),1)
        XCTAssertGreaterThanOrEqual(number(after,"previewScaleMinimum"),0.8999)
        XCTAssertLessThanOrEqual(number(after,"previewScaleMaximum"),1.1001)
        if ratio>1 {XCTAssertGreaterThan(number(after,"previewScaleMaximum"),1.06)}
        else {XCTAssertLessThan(number(after,"previewScaleMinimum"),0.94)}
        XCTAssertEqual(after["lastModelInteraction"] as? String,kind)
        XCTAssertEqual(number(after,"pinchReactions"),number(before,"pinchReactions")+1)
        XCTAssertEqual(number(after,"shakeReactions"),number(before,"shakeReactions"))
        XCTAssertEqual(after["viewEditorOpen"] as? Bool,false)
        XCTAssertEqual(after["viewPoseSaved"] as? [String:Double],before["viewPoseSaved"] as? [String:Double])
        for key in ["yaw","pitch","scale","x","y"] {XCTAssertEqual(pose(after)[key] ?? -1,saved[key] ?? -2,accuracy:0.001)}
        capture("ordinary-"+kind,app)
    }
    @MainActor func testNormalPinchOutReactsWithoutSavingOrMoving() {previewPinch(ratio:1.8,kind:"pinch_out")}
    @MainActor func testNormalPinchInReactsWithoutSavingOrMoving() {previewPinch(ratio:0.45,kind:"pinch_in")}
    @MainActor func testPresetPersistenceAndIsolation() {
        let app=XCUIApplication();app.launchArguments=["--view-presets-check"]
        app.launch()
        let result=app.staticTexts["viewPresetsCoreResult"]
        XCTAssertTrue(result.waitForExistence(timeout:20));XCTAssertTrue(result.label.hasPrefix("PASS:"),result.label)
    }
    @MainActor func testCompactPhoneEditorInBothOrientations() {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        defer {XCUIDevice.shared.orientation = .portrait}
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch();ready(app);open(app)
        func controlsInsideWindow() {
            for id in ["closeCharacterViewEditor","resetCharacterView"] {
                let c=app.buttons[id];XCTAssertTrue(c.exists);XCTAssertTrue(c.isHittable)
                XCTAssertGreaterThanOrEqual(c.frame.minX,app.frame.minX);XCTAssertGreaterThanOrEqual(c.frame.minY,app.frame.minY)
                XCTAssertLessThanOrEqual(c.frame.maxX,app.frame.maxX);XCTAssertLessThanOrEqual(c.frame.maxY,app.frame.maxY)
            }
            let frame=app.characterRuntime["viewEditorFrame"] as? [String:Double] ?? [:]
            XCTAssertLessThanOrEqual(frame["height"] ?? 999,94)
        }
        controlsInsideWindow();capture("compact-position-portrait",app)
        XCUIDevice.shared.orientation = .landscapeLeft
        app.waitForCharacter {self.number($0,"cameraAspect")>1.5 && $0["viewEditorOpen"] as? Bool == true}
        controlsInsideWindow();capture("compact-position-landscape",app)
        app.buttons["closeCharacterViewEditor"].tap()
        app.waitForCharacter {$0["viewEditorOpen"] as? Bool == false}
    }
    @MainActor func testButtonPassThroughAutoRememberAndReset() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch();ready(app)
        let state=app.characterRuntime
        app.coordinate(withNormalizedOffset:CGVector(dx:number(state,"headX"),dy:number(state,"headY"))).press(forDuration:1.3)
        XCTAssertFalse(app.buttons["closeCharacterViewEditor"].exists,"Long hold no longer opens or charges")
        open(app)
        XCTAssertFalse(app.buttons["saveCharacterView"].exists)
        XCTAssertEqual(number(app.characterRuntime,"inspectionHapticCount"),1)
        XCTAssertEqual(app.buttons["closeCharacterViewEditor"].frame.midY,app.buttons["customizationButton"].frame.midY,accuracy:1)
        let before=pose(app.characterRuntime)
        let f=app.characterRuntime["viewEditorFrame"] as? [String:Double] ?? [:]
        let start=app.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:(f["x"] ?? 0)+42,dy:(f["y"] ?? 0)+64))
        start.press(forDuration:0.08,thenDragTo:start.withOffset(CGVector(dx:35,dy:0)),withVelocity:.slow,thenHoldForDuration:0.2)
        capture("single-drag-diagnostic",app)
        app.waitForCharacter {abs(self.pose($0)["yaw"] ?? 0)>5 && $0["inspectionMoving"] as? Bool == false}
        let after=pose(app.characterRuntime)
        for key in ["scale","x","y"] {XCTAssertEqual(after[key] ?? -1,before[key] ?? -2,accuracy:0.001,"Rotation through glass must keep \(key)")}
        capture("position-pass-through",app)
        let samples=app.characterRuntime["positionAnimationSamples"] as? [[String:Double]] ?? []
        XCTAssertGreaterThanOrEqual(samples.count,4)
        if let first=samples.first,let last=samples.last {
            for sample in samples {XCTAssertEqual(sample["x"] ?? -1,last["x"] ?? -2,accuracy:0.5,"Popup must not fly horizontally from the origin")}
            XCTAssertGreaterThan(first["y"] ?? 0,last["y"] ?? 1,"Popup rises into place from the chat region")
            XCTAssertLessThan(first["opacity"] ?? 1,last["opacity"] ?? 0,"Popup fades in")
        }
        app.buttons["closeCharacterViewEditor"].tap()
        app.waitForCharacter {$0["viewEditorOpen"] as? Bool == false}
        XCTAssertEqual(pose(app.characterRuntime)["yaw"] ?? 0,after["yaw"] ?? 1,accuracy:0.1)
        app.terminate();app.launchArguments += ["--keep-companion-data","--keep-auth-data"];app.launch();ready(app)
        app.waitForCharacter {abs((self.pose($0)["yaw"] ?? 0)-(after["yaw"] ?? 1))<0.1}
        open(app);capture("position-restored-on-launch",app)
        app.buttons["resetCharacterView"].tap()
        app.waitForCharacter {self.number($0,"inspectionYaw")==0 && self.number($0,"inspectionScale")==1}
        app.buttons["closeCharacterViewEditor"].tap()
        app.waitForCharacter {$0["viewEditorOpen"] as? Bool == false}
        XCTAssertEqual((app.characterRuntime["viewPoseSaved"] as? [String:Double])?["yaw"],0)
    }
    @MainActor func testTwoFingerAndCompactSoundSettings() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch();ready(app);open(app)
        let size=app.frame.size
        let f=app.characterRuntime["viewEditorFrame"] as? [String:Double] ?? [:]
        let start=CGPoint(x:(f["x"] ?? 0)+42,y:(f["y"] ?? 0)+65)
        let done=expectation(description:"real two-finger edit through glass")
        SNSynthesizeViewEdit(start,size){error in XCTAssertNil(error);done.fulfill()}
        wait(for:[done],timeout:8)
        app.waitForCharacter {$0["inspectionMoving"] as? Bool == false && (self.pose($0)["scale"] ?? 1)>1.01}
        XCTAssertGreaterThan(abs(pose(app.characterRuntime)["y"] ?? 0),0.01)
        let last=pose(app.characterRuntime);assertBoundedTransform(app.characterRuntime)
        capture("position-two-finger",app)
        app.buttons["closeCharacterViewEditor"].tap()
        app.waitForCharacter {$0["viewEditorOpen"] as? Bool == false}
        XCTAssertEqual(pose(app.characterRuntime)["scale"] ?? 0,last["scale"] ?? 1,accuracy:0.002)
        let sound=app.buttons["conversationSoundButton"]
        sound.tap()
        XCTAssertTrue(app.buttons["closeConversationSound"].waitForExistence(timeout:8))
        XCTAssertEqual(app.switches.count,0,"Volumes are the sole sound controls")
        app.sliders["speechSoundVolume"].adjust(toNormalizedSliderPosition:0.42)
        app.sliders["musicSoundVolume"].adjust(toNormalizedSliderPosition:0.18)
        app.buttons["conversationMusicPicker"].tap()
        let track=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","musicTrack-")).allElementsBoundByIndex.last
        XCTAssertNotNil(track);track?.tap()
        capture("compact-sound-settings",app)
        app.buttons["closeConversationSound"].tap()
        XCTAssertTrue(sound.waitForExistence(timeout:8));sound.tap()
        XCTAssertTrue(app.buttons["closeConversationSound"].waitForExistence(timeout:8))
        XCTAssertEqual(app.switches.count,0)
        // XCTest's normalized iOS 26 slider synthesis can stop ~6% short.
        // Exercise the requested real drag all the way past the track endpoint.
        for id in ["musicSoundVolume","speechSoundVolume"] {
            let slider=app.sliders[id]
            let frame=slider.frame
            let thumbX=frame.minX+18+(frame.width-36)*CGFloat(slider.normalizedSliderPosition)
            app.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:thumbX,dy:frame.midY)).press(forDuration:0.1,
                thenDragTo:app.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:30,dy:frame.midY)),withVelocity:.slow,thenHoldForDuration:0.15)
        }
        capture("compact-sound-zero-volumes",app)
        app.buttons["closeConversationSound"].tap()
        func audio()->[String:Any] {
            (try? JSONSerialization.jsonObject(with:Data((sound.value as? String ?? "{}").utf8))) as? [String:Any] ?? [:]
        }
        XCTAssertEqual(audio()["volume"] as? Double,0);XCTAssertEqual(audio()["speechVolume"] as? Double,0)
        XCTAssertEqual(audio()["playing"] as? Bool,false)
        sound.tap();app.sliders["musicSoundVolume"].adjust(toNormalizedSliderPosition:0.30)
        app.buttons["closeConversationSound"].tap()
        XCTAssertEqual(audio()["playing"] as? Bool,true,"Raising volume starts music without any hidden enable switch")
    }
    @MainActor func testFreeYawBoundedPitchAndReload() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch();ready(app);open(app)
        app.waitForCharacter {self.number($0,"inspectionGestureRevision")>=10}
        let start=app.coordinate(withNormalizedOffset:CGVector(dx:0.83,dy:0.38))
        start.press(forDuration:0.08,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.14,dy:0.38)),withVelocity:.slow,thenHoldForDuration:0.2)
        let top=app.coordinate(withNormalizedOffset:CGVector(dx:0.48,dy:0.27))
        for _ in 0..<2 {
            top.press(forDuration:0.08,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.48,dy:0.76)),withVelocity:.slow,thenHoldForDuration:0.2)
        }
        app.waitForCharacter {abs(self.pose($0)["yaw"] ?? 0)>200 && abs(self.pose($0)["pitch"] ?? 0)>79}
        XCTAssertLessThanOrEqual(abs(pose(app.characterRuntime)["pitch"] ?? 100),80.01)
        let bottom=app.coordinate(withNormalizedOffset:CGVector(dx:0.48,dy:0.78))
        for _ in 0..<3 {
            bottom.press(forDuration:0.08,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.48,dy:0.16)),withVelocity:.slow,thenHoldForDuration:0.2)
        }
        app.waitForCharacter {(self.pose($0)["pitch"] ?? 0)>79}
        XCTAssertLessThanOrEqual(pose(app.characterRuntime)["pitch"] ?? 100,80.01)
        let saved=pose(app.characterRuntime)
        XCTAssertEqual(saved["scale"] ?? 0,1,accuracy:0.001);XCTAssertEqual(saved["x"] ?? 1,0,accuracy:0.001);XCTAssertEqual(saved["y"] ?? 1,0,accuracy:0.001)
        capture("free-yaw-bounded-pitch",app)
        app.buttons["closeCharacterViewEditor"].tap()
        app.terminate();app.launchArguments += ["--keep-companion-data","--keep-auth-data"];app.launch();ready(app)
        for key in ["yaw","pitch"] {
            XCTAssertEqual(((pose(app.characterRuntime)[key] ?? 0)-(saved[key] ?? 1)).remainder(dividingBy:360),0,accuracy:0.2,"Free yaw and bounded pitch survive angle normalization")
        }
        open(app);app.buttons["resetCharacterView"].tap()
        app.waitForCharacter {self.number($0,"inspectionYaw")==0 && self.number($0,"inspectionPitch")==0}
        app.buttons["closeCharacterViewEditor"].tap()
    }
    @MainActor private func ready(_ app:XCUIApplication) {
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.waitForCharacter{$0["nativeHoldAvailable"] as? Bool == true}
    }
    @MainActor private func open(_ app:XCUIApplication) {
        app.buttons["characterPositionButton"].tap()
        XCTAssertTrue(app.buttons["closeCharacterViewEditor"].waitForExistence(timeout:8))
        app.waitForCharacter{$0["viewEditorOpen"] as? Bool == true}
    }
    @MainActor private func drag(_ app:XCUIApplication,dx:Double,dy:Double) {
        let start=app.coordinate(withNormalizedOffset:CGVector(dx:0.48,dy:0.31))
        start.press(forDuration:0.08,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.48+dx,dy:0.31+dy)),withVelocity:.slow,thenHoldForDuration:0.3)
    }
    private func number(_ d:[String:Any],_ key:String)->Double {(d[key] as? NSNumber)?.doubleValue ?? -1}
    private func pose(_ d:[String:Any])->[String:Double] {d["inspectionPose"] as? [String:Double] ?? [:]}
    private func assertBoundedTransform(_ d:[String:Any]) {
        // Unlimited orientation may extend the silhouette past the portrait crop.
        // Unity review separately checks the neutral envelope on five viewports.
        let p=pose(d)
        for key in ["yaw","pitch","scale","x","y"] {XCTAssertTrue(p[key]?.isFinite == true)}
        XCTAssertGreaterThanOrEqual(p["scale"] ?? 0,0.4);XCTAssertLessThanOrEqual(p["scale"] ?? 2,1.28)
        XCTAssertLessThanOrEqual(abs(p["x"] ?? 1),0.45);XCTAssertLessThanOrEqual(abs(p["y"] ?? 1),0.45)
    }
    @MainActor private func capture(_ name:String,_ app:XCUIApplication) {
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
        if let data=try? JSONSerialization.data(withJSONObject:app.characterRuntime,options:[.prettyPrinted,.sortedKeys]) {
            let value=XCTAttachment(data:data,uniformTypeIdentifier:"public.json");value.name=name+"-runtime";value.lifetime = .keepAlways;add(value)
        }
    }
}
