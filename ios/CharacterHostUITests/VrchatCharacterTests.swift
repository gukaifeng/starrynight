import XCTest

final class VrchatCharacterTests: XCTestCase {
    private let characters = [("anime-kipfel", "琪宝"), ("anime-mamehinata", "豆日向")]

    @MainActor func testSourceOnlyCharactersSpeakWithoutAddedMotionAndKeepCamera() {
        let app = launch()
        for (id, name) in characters {
            openFromDiscovery(app, id: id, name: name)
            app.waitForCharacter {
                $0["greetingScene"] as? String == "firstMeeting" &&
                ($0["greetingCount"] as? Int ?? 0) == 1
            }
            let greeting = app.staticTexts.matching(NSPredicate(format:
                "identifier == %@ AND value == %@", "assistantMessage", "主动问候：firstMeeting")).firstMatch
            XCTAssertTrue(greeting.exists, "The new character must greet without a user message")
            XCTAssertFalse(greeting.label.isEmpty)
            XCTAssertEqual(app.staticTexts.matching(identifier: "userMessage").count, 0)
            let playingVoice = app.buttons.matching(NSPredicate(format:
                "identifier BEGINSWITH %@ AND value CONTAINS %@", "messageVoice-", "voiceMotion:playing")).firstMatch
            XCTAssertTrue(playingVoice.waitForExistence(timeout: 30), "The proactive greeting must really start playing")
            XCTAssertEqual(app.characterRuntime["avatarVoicePlaying"] as? Bool, true)
            assertNoAddedMotion(app.characterRuntime)
            capture(id + "-conversation-speaking", app)

            stopVoiceAndWaitForIdle(app)
            capture(id + "-source-rest-pose", app)
            let before = app.characterRuntime
            XCTAssertEqual(before["modelControlsLocked"] as? Bool, true)
            XCTAssertEqual(before["nativeHeadHit"] as? String, "CharacterTouchSurface")
            assertNoAddedMotion(before)
            let x = number(before, "headX"), y = number(before, "headY")
            XCTAssertTrue((0.05 ... 0.95).contains(x))
            XCTAssertTrue((0.08 ... 0.65).contains(y), "The portrait must leave the actual head touch point visible")
            app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()

            // A negative assertion needs time for the former head reaction to
            // run, then an ordinary bridge receipt. Reading the pre-tap cached
            // accessibility state would let a broken input path pass this test.
            let reactionWindow = Date().addingTimeInterval(1.8)
            let elapsed = NSPredicate { _, _ in Date() >= reactionWindow }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: elapsed, object: nil)],
                                          timeout: 4), .completed)
            app.buttons["tab-messages"].tap()
            app.buttons["tab-home"].tap() // The retained conversation requests getState.
            app.waitForCharacter {
                $0["modelId"] as? String == id &&
                self.number($0, "sampleTime") >= self.number(before, "sampleTime") + 1.8 &&
                self.number($0, "nativeTouchSequences") > self.number(before, "nativeTouchSequences")
            }
            let afterTouch = app.characterRuntime
            assertNoAddedMotion(afterTouch)
            XCTAssertEqual(number(afterTouch, "actionCount"), number(before, "actionCount"),
                           "A head tap must not invent an action absent from the source avatar")
            sameCamera(app, before, includingPresentation: true)
            capture(id + "-head-touch-source-pose-kept", app)
            stopVoiceAndWaitForIdle(app)

            let settled = app.characterRuntime
            app.buttons["customizationButton"].tap()
            XCTAssertTrue(app.buttons["profileCustomizeButton"].waitForExistence(timeout: 6))
            XCTAssertFalse(app.buttons["profileChatButton"].exists,
                "The in-conversation profile must not offer a redundant conversation entry")
            sameCamera(app, settled, includingPresentation: true)
            capture(id + "-profile-camera-kept", app)
            app.buttons["closeCharacterDetails"].tap()
            XCTAssertTrue(app.textViews["chatInput"].waitForExistence(timeout: 6))
            sameCamera(app, settled, includingPresentation: true)
            capture(id + "-capsule-after-profile", app)
        }
    }

    private func assertNoAddedMotion(_ state: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        let gaze = state["gaze"] as? [String: Any] ?? [:]
        XCTAssertEqual(gaze["available"] as? Bool, false,
                       "Source-only avatars must not gain procedural camera tracking", file: file, line: line)
        XCTAssertEqual(number(gaze, "headReactionCount"), 0, file: file, line: line)
        XCTAssertEqual(number(gaze, "headReactionPeak"), 0, file: file, line: line)
        let platform = state["characterPlatform"] as? [String: Any] ?? [:]
        XCTAssertEqual(number(platform, "bodyCues"), 0,
                       "Dialogue must not schedule added body animations", file: file, line: line)
        XCTAssertEqual(number(platform, "expressionCues"), 0,
                       "Dialogue must not synthesize expressions outside the original selections", file: file, line: line)
        XCTAssertEqual(platform["activeAction"] as? String, "", file: file, line: line)
    }

    @MainActor func testOriginalPerformanceSelectionsResetAndRemainCharacterScoped() {
        let app = launch()
        // Characters without an authored performance profile keep the existing card.
        app.buttons["customizationButton"].tap()
        XCTAssertTrue(app.buttons["closeCharacterDetails"].waitForExistence(timeout:6))
        XCTAssertFalse(app.buttons["profilePerformanceButton"].exists)
        app.buttons["closeCharacterDetails"].tap()

        var previousCharacterSelection:String?
        for (id,name) in characters {
            openFromDiscovery(app,id:id,name:name)
            stopVoiceAndWaitForIdle(app)
            let camera = app.characterRuntime
            let defaults = selections(app)
            if let previousCharacterSelection {
                XCTAssertFalse(defaults.contains(previousCharacterSelection),"A new character must not inherit another character's expression")
            }
            app.buttons["customizationButton"].tap()
            let entry = app.buttons["profilePerformanceButton"]
            XCTAssertTrue(entry.waitForExistence(timeout:6))
            if !entry.isHittable { app.scrollViews.firstMatch.swipeUp() }
            entry.tap()
            XCTAssertTrue(app.buttons["closeCharacterPerformance"].waitForExistence(timeout:6))
            XCTAssertFalse(app.buttons["closeCharacterDetails"].exists,"Performance must replace the page inside the same sheet")
            sameCamera(app,camera,includingPresentation:true)
            capture(id+"-performance-overview",app)

            for group in ["expression","hands","ears","tail","pose"] {
                chooseGroup(group,app)
                let options = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND value == %@",
                    "performanceOption-","未选择"))
                let option = options.firstMatch
                XCTAssertTrue(option.waitForExistence(timeout:5),"Expected an authored \(group) choice for \(id)")
                let optionID = String(option.identifier.dropFirst("performanceOption-".count))
                let selectedOption = app.buttons["performanceOption-"+optionID]
                XCTAssertTrue(selectedOption.isEnabled)
                selectedOption.tap()
                app.waitForCharacter { self.selections($0).contains(optionID) }
                let selectedValue = NSPredicate(format:"value == %@","已选择")
                XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:selectedValue,object:selectedOption)],timeout:5),
                    .completed,"Selection must follow the runtime response")
                XCTAssertEqual(selectedOption.value as? String,"已选择")
                sameCamera(app,camera,includingPresentation:true)
                capture(id+"-performance-"+group,app)
                app.buttons["performanceReset"].tap()
                app.waitForCharacter { self.selections($0) == defaults }
            }

            chooseGroup("appearance",app)
            let outfit = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","performanceOption-")).firstMatch
            XCTAssertTrue(outfit.waitForExistence(timeout:5))
            let outfitID = String(outfit.identifier.dropFirst("performanceOption-".count))
            let initiallySelected = selections(app).contains(outfitID)
            outfit.tap()
            app.waitForCharacter { self.selections($0).contains(outfitID) != initiallySelected }
            capture(id+"-performance-accessory",app)
            outfit.tap()
            app.waitForCharacter { self.selections($0).contains(outfitID) == initiallySelected }
            app.buttons["performanceReset"].tap()
            app.waitForCharacter { self.selections($0) == defaults }
            XCTAssertFalse(app.staticTexts["performanceError"].exists)
            sameCamera(app,camera,includingPresentation:true)

            // Keep one explicit expression across a tab round trip, then switch actors.
            chooseGroup("expression",app)
            let retainedChoice = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND value == %@",
                "performanceOption-","未选择")).firstMatch
            XCTAssertTrue(retainedChoice.waitForExistence(timeout:5))
            let retainedID = String(retainedChoice.identifier.dropFirst("performanceOption-".count))
            retainedChoice.tap()
            app.waitForCharacter { self.selections($0).contains(retainedID) }
            previousCharacterSelection = retainedID

            app.buttons["closeCharacterPerformance"].tap()
            XCTAssertTrue(app.buttons["closeCharacterDetails"].waitForExistence(timeout:5))
            app.buttons["closeCharacterDetails"].tap()
            XCTAssertTrue(app.textViews["chatInput"].waitForExistence(timeout:6))
            sameCamera(app,camera,includingPresentation:true)
            // Retained home tab resumes the same engine instance and actual choices.
            app.buttons["tab-messages"].tap()
            app.buttons["tab-home"].tap()
            app.waitForCharacter { $0["modelId"] as? String == id && self.selections($0).contains(retainedID) }
        }
    }

    @MainActor private func chooseGroup(_ group:String,_ app:XCUIApplication) {
        let chip = app.buttons["performanceGroup-"+group]
        let strip = app.scrollViews["performanceGroups"]
        XCTAssertTrue(strip.waitForExistence(timeout:5))
        XCTAssertTrue(chip.waitForExistence(timeout:5),"Group \(group) must exist")
        // XCUITest can throw while resolving isHittable for a fully offscreen
        // SwiftUI chip. Bring its complete frame into the strip before hit testing.
        for _ in 0..<6 {
            let visible = strip.frame.intersection(app.frame).insetBy(dx:1,dy:0)
            let frame = chip.frame
            if !frame.isEmpty && visible.contains(frame) { break }
            if frame.midX > visible.midX { strip.swipeLeft() }
            else { strip.swipeRight() }
        }
        let visible = strip.frame.intersection(app.frame).insetBy(dx:1,dy:0)
        guard !chip.frame.isEmpty, visible.contains(chip.frame) else {
            XCTFail("Group \(group) must scroll fully into view")
            return
        }
        XCTAssertTrue(chip.isHittable,"Group \(group) must be reachable")
        chip.tap()
    }
    private func selections(_ state:[String:Any]) -> Set<String> {
        Set((state["characterPlatform"] as? [String:Any])?["performanceSelections"] as? [String] ?? [])
    }
    @MainActor private func selections(_ app:XCUIApplication) -> Set<String> { selections(app.characterRuntime) }

    @MainActor private func launch() -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--companion-testing", "--auth-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout: 60))
        return app
    }

    @MainActor private func openFromDiscovery(_ app: XCUIApplication, id: String, name: String) {
        app.buttons["tab-discover"].tap()
        let search = app.textFields["discoverSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        if app.buttons["clearDiscoverSearch"].exists { app.buttons["clearDiscoverSearch"].tap() }
        search.tap()
        search.typeText(name)
        let card = app.buttons["discover-open-" + id]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.tap()
        XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout: 8))
        capture(id + "-discovery-profile", app, runtime: false)
        app.buttons["profileChatButton"].tap()
        waitForRenderedCharacter(app, id: id)
    }

    @MainActor private func waitForRenderedCharacter(_ app: XCUIApplication, id: String) {
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout: 60))
        app.waitForCharacter({
            $0["modelId"] as? String == id &&
            ($0["stableRenderedFrames"] as? Int ?? 0) >= 3 &&
            $0["framingMotionActive"] as? Bool == false
        }, timeout: 45)
        XCTAssertTrue(app.textViews["chatInput"].isHittable)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "characterArrival").firstMatch.exists)
        XCTAssertEqual(app.characterRuntime["actionFraming"] as? Bool, false)
    }

    @MainActor private func stopVoiceAndWaitForIdle(_ app: XCUIApplication) {
        // Greeting synthesis may still be starting immediately after the stage is revealed.
        app.waitForCharacter { ($0["greetingCount"] as? Int ?? 0) > 0 }
        let active = app.buttons.matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND (value CONTAINS %@ OR value CONTAINS %@ OR value CONTAINS %@)",
            "messageVoice-", "voiceMotion:playing", "播放中", "准备中")).firstMatch
        if active.waitForExistence(timeout: 3) { active.tap() }
        app.waitForCharacter({
            $0["avatarVoicePlaying"] as? Bool == false &&
            ($0["characterPlatform"] as? [String: Any])?["activeAction"] as? String == "" &&
            $0["framingMotionActive"] as? Bool == false
        }, timeout: 25)
    }

    @MainActor private func sameCamera(_ app: XCUIApplication, _ expected: [String: Any],
                                      includingPresentation: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let actual = app.characterRuntime
        var keys = ["distance", "framingSize", "framingAngle", "pitch", "yaw", "cameraFov"]
        if includingPresentation { keys += ["presentationId", "cameraSnapCount"] }
        for key in keys {
            XCTAssertNotNil(expected[key], file: file, line: line)
            XCTAssertNotNil(actual[key], file: file, line: line)
            XCTAssertEqual(number(actual, key), number(expected, key), accuracy: 0.001,
                "Camera changed: \(key)", file: file, line: line)
        }
        for field in ["cameraPosition", "compositionArea", "renderViewport"] {
            let a = actual[field] as? [String: Any] ?? [:]
            let b = expected[field] as? [String: Any] ?? [:]
            XCTAssertFalse(a.isEmpty, file: file, line: line)
            XCTAssertFalse(b.isEmpty, file: file, line: line)
            for key in ["x", "y", "z", "width", "height"] where b[key] != nil {
                XCTAssertEqual(number(a, key), number(b, key), accuracy: 0.001,
                    "Camera changed: \(field).\(key)", file: file, line: line)
            }
        }
        XCTAssertEqual(actual["framingShot"] as? String, expected["framingShot"] as? String, file: file, line: line)
        XCTAssertEqual(actual["framingMotionActive"] as? Bool, false, file: file, line: line)
    }

    private func number(_ state: [String: Any], _ key: String) -> Double {
        (state[key] as? NSNumber)?.doubleValue ?? -999
    }

    @MainActor private func capture(_ name: String, _ app: XCUIApplication, runtime: Bool = true) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
        if runtime, let data = try? JSONSerialization.data(withJSONObject: app.characterRuntime,
                                                           options: [.prettyPrinted, .sortedKeys]) {
            let state = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            state.name = name + "-runtime"
            state.lifetime = .keepAlways
            add(state)
        }
    }
}
