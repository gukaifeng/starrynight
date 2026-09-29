import XCTest

final class IllustrationPortraitTests: XCTestCase {
    private let characters = [("anime-uka", "优可"), ("anime-velara", "维拉"), ("anime-onyx", "安宁")]

    @MainActor func testIllustratedCharactersSearchGreetAndReactToRealHeadTouches() {
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
            capture(id + "-conversation-speaking", app)

            stopVoiceAndWaitForIdle(app)
            capture(id + "-portrait-idle", app)
            let before = app.characterRuntime
            XCTAssertEqual(before["modelControlsLocked"] as? Bool, true)
            XCTAssertEqual(before["nativeHeadHit"] as? String, "CharacterTouchSurface")
            let gaze = before["gaze"] as? [String: Any] ?? [:]
            XCTAssertEqual(gaze["available"] as? Bool, true)
            let reactions = number(gaze, "headReactionCount")
            let x = number(before, "headX"), y = number(before, "headY")
            XCTAssertTrue((0.05 ... 0.95).contains(x))
            XCTAssertTrue((0.08 ... 0.65).contains(y), "The portrait must leave the actual head touch point visible")
            app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
            app.waitForCharacter {
                let response = $0["gaze"] as? [String: Any] ?? [:]
                return self.number(response, "headReactionCount") > reactions &&
                    self.number(response, "headReactionPeak") > 8
            }
            sameCamera(app, before, includingPresentation: true)
            capture(id + "-head-reacted", app)
            stopVoiceAndWaitForIdle(app)

            let settled = app.characterRuntime
            app.buttons["customizationButton"].tap()
            XCTAssertTrue(app.buttons["profileCustomizeButton"].waitForExistence(timeout: 6))
            XCTAssertFalse(app.buttons["profileChatButton"].exists,
                "The in-conversation profile must not offer a redundant conversation entry")
            sameCamera(app, settled, includingPresentation: true)
            capture(id + "-profile-camera-kept", app)
            app.buttons["closeCharacterDetails"].tap()
            XCTAssertTrue(app.textFields["chatInput"].waitForExistence(timeout: 6))
            sameCamera(app, settled, includingPresentation: true)
            capture(id + "-capsule-after-profile", app)
        }
    }

    @MainActor func testSavedFramingSurvivesCharacterSwitchesAndProfilePresentation() {
        let app = launch()
        openFromDiscovery(app, id: "anime-uka", name: "优可")
        stopVoiceAndWaitForIdle(app)
        app.openCustomization("framing")
        XCTAssertTrue(app.buttons["framingSizeMax"].waitForExistence(timeout: 6))
        app.buttons["framingSizeMax"].tap()
        app.buttons["framingAngleRight"].tap()
        app.waitForCharacter {
            $0["framingMotionActive"] as? Bool == false &&
            self.number($0, "framingSize") > 1.09 &&
            abs(self.number($0, "framingAngle") - 20) < 0.001
        }
        app.closeCustomizationPage("closeFramingButton")
        stopVoiceAndWaitForIdle(app)
        let chosen = app.characterRuntime
        capture("illustration-uka-chosen-framing", app)

        for (id, name) in characters.dropFirst() {
            openFromDiscovery(app, id: id, name: name)
            stopVoiceAndWaitForIdle(app)
            XCTAssertEqual(number(app.characterRuntime, "framingAngle"), 0, accuracy: 0.001,
                "A different character must not inherit Uka's saved angle")
            capture(id + "-independent-framing", app)
        }

        app.buttons["tab-messages"].tap()
        let row = app.buttons["message-anime-uka"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        waitForRenderedCharacter(app, id: "anime-uka")
        stopVoiceAndWaitForIdle(app)
        sameCamera(app, chosen, includingPresentation: false)
        XCTAssertEqual(app.characterRuntime["modelControlsLocked"] as? Bool, true)
        capture("illustration-uka-saved-framing-returned", app)

        let returned = app.characterRuntime
        app.buttons["customizationButton"].tap()
        XCTAssertTrue(app.buttons["profileCustomizeButton"].waitForExistence(timeout: 6))
        sameCamera(app, returned, includingPresentation: true)
        capture("illustration-uka-profile-saved-framing", app)
        app.buttons["closeCharacterDetails"].tap()
        XCTAssertTrue(app.textFields["chatInput"].waitForExistence(timeout: 6))
        sameCamera(app, returned, includingPresentation: true)
    }

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
        XCTAssertTrue(app.textFields["chatInput"].isHittable)
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
