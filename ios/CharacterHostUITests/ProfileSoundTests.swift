import XCTest

final class ProfileSoundTests:XCTestCase {
    @MainActor func testCompactProfileKeepsAccountAndCreatorNavigation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--shell-discover"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-mine"].waitForExistence(timeout:15)); app.buttons["tab-mine"].tap()
        let identity = app.buttons["accountCenterButton"], settings = app.buttons["profileSettingsButton"]
        XCTAssertTrue(identity.waitForExistence(timeout:5))
        XCTAssertEqual(identity.frame.midY,settings.frame.midY,accuracy:1)
        XCTAssertLessThan(app.buttons["mySubscriptionsButton"].frame.maxY-identity.frame.minY,200)
        XCTAssertFalse(app.buttons["myAuthorProfileButton"].exists)
        for id in ["mySubscriptionsButton","myFollowsButton","myCreationsButton","myConversationsButton"] {
            XCTAssertTrue(app.buttons[id].isHittable)
        }
        capture("01-compact-profile-signed")
        identity.tap()
        XCTAssertTrue(app.staticTexts["accountID"].waitForExistence(timeout:5))
        app.buttons["closeAccountButton"].tap()
        app.buttons["myCreationsButton"].tap()
        XCTAssertTrue(app.buttons["myAuthorProfileButton"].waitForExistence(timeout:5))
        capture("02-creator-tools")
        let creationsHeader = app.buttons["closeCreationsButton"].frame
        app.buttons["myAuthorProfileButton"].tap()
        XCTAssertTrue(app.buttons["editAuthorProfile"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["closeCreationsButton"].exists,"Author is a subpage of the same panel")
        XCTAssertEqual(app.buttons["closeAuthorProfile"].frame.minY,creationsHeader.minY,accuracy:1)
        app.buttons["editAuthorProfile"].tap()
        let name = app.textFields["authorNameInput"]
        XCTAssertTrue(name.waitForExistence(timeout:5)); name.tap()
        name.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:(name.value as? String ?? "").count)+"晚风")
        app.buttons["closeAuthorEditor"].tap()
        XCTAssertTrue(app.staticTexts["authorProfileName"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["authorProfileName"].label,"晚风")
        capture("03-author-subpage")
        app.buttons["closeAuthorProfile"].tap()
        XCTAssertTrue(app.buttons["closeCreationsButton"].waitForExistence(timeout:5))
        app.buttons["closeCreationsButton"].tap()
        XCTAssertTrue(app.staticTexts["晚风"].waitForExistence(timeout:5))
        settings.tap()
        XCTAssertTrue(app.buttons["aboutStarryButton"].waitForExistence(timeout:5))
        app.buttons["closeSettingsButton"].tap()

        app.terminate()
        app.launchArguments += ["--auth-testing"]
        app.launch(); XCTAssertTrue(app.buttons["tab-mine"].waitForExistence(timeout:15)); app.buttons["tab-mine"].tap()
        XCTAssertTrue(identity.waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["myAuthorProfileButton"].exists)
        capture("04-compact-profile-guest")
        identity.tap()
        XCTAssertTrue(app.buttons["signInButton"].waitForExistence(timeout:5),"Guest identity still opens login")
    }

    @MainActor func testTwoRealSoundChannelsMutePersistAndStayIsolated() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--auth-testing"]
        app.launch()
        let sound = app.buttons["characterPositionButton"]
        XCTAssertTrue(sound.waitForExistence(timeout:65))
        app.openConversationSettings("sound")
        XCTAssertTrue(app.sliders["speechSoundVolume"].waitForExistence(timeout:5))
        XCTAssertEqual(app.sliders.count,2)
        XCTAssertFalse(app.sliders["effectsSoundVolume"].exists)
        app.sliders["speechSoundVolume"].adjust(toNormalizedSliderPosition:0)
        app.sliders["musicSoundVolume"].adjust(toNormalizedSliderPosition:0)
        capture("05-sound-two-channels-muted")
        app.buttons["closeCharacterViewEditor"].tap()
        XCTAssertEqual(audio(app)["masterMuted"] as? Bool,true)
        app.openConversationSettings("sound"); app.sliders["musicSoundVolume"].adjust(toNormalizedSliderPosition:0.3)
        app.buttons["closeCharacterViewEditor"].tap()
        let playing = NSPredicate { _,_ in MainActor.assumeIsolated {
            self.audio(app)["playing"] as? Bool == true && self.audio(app)["masterMuted"] as? Bool == false
        } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:playing,object:nil)],timeout:5),.completed)
        XCTAssertEqual(audio(app)["speechVolume"] as? Double,0)
        // XCTest's synthetic slider drag is approximate. Persistence must retain
        // the value actually chosen by that gesture, not its requested coordinate.
        let savedVolume = audio(app)["volume"] as? Double ?? -1
        XCTAssertGreaterThan(savedVolume,0); XCTAssertLessThan(savedVolume,1)
        app.terminate(); app.launchArguments += ["--keep-companion-data","--keep-auth-data"]; app.launch()
        XCTAssertTrue(sound.waitForExistence(timeout:65))
        XCTAssertEqual(audio(app)["speechVolume"] as? Double,0)
        XCTAssertEqual(audio(app)["volume"] as? Double ?? -1,savedVolume,accuracy:0.0001)
        app.buttons["tab-discover"].tap()
        XCTAssertTrue(app.buttons["discover-open-anime-mamehinata"].waitForExistence(timeout:8))
        app.buttons["discover-open-anime-mamehinata"].tap(); app.buttons["profileChatButton"].tap()
        app.waitForCharacter { $0["modelId"] as? String == "anime-mamehinata" }
        XCTAssertEqual(audio(app)["speechVolume"] as? Double,1,"A different character keeps its own volume")
        XCTAssertEqual(audio(app)["volume"] as? Double ?? -1,0.28,accuracy:0.001)
        app.openConversationSettings("sound"); XCTAssertTrue(app.sliders["speechSoundVolume"].waitForExistence(timeout:5))
        XCTAssertEqual(app.sliders.count,2)
        capture("06-sound-other-character")
    }
    @MainActor private func audio(_ app:XCUIApplication)->[String:Any] {
        return app.characterAudio
    }
    @MainActor private func capture(_ name:String) {
        let item = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
