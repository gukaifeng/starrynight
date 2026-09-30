import XCTest

final class NearbyExperienceTests: XCTestCase {
    @MainActor private func start(_ extra:[String] = []) -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing","--companion-testing"] + extra
        app.launch(); return app
    }
    @MainActor private func wait(_ condition:@escaping ()->Bool,timeout:TimeInterval = 20) {
        let p = NSPredicate { _,_ in MainActor.assumeIsolated { condition() } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:p,object:nil)],timeout:timeout),.completed)
    }
    @MainActor private func ready(_ app:XCUIApplication) { XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:90)) }
    @MainActor private func tab(_ app:XCUIApplication,_ tab:String) {
        let button = app.buttons["tab-"+tab]; wait { button.isHittable }; button.tap()
    }
    @MainActor private func send(_ text:String,_ app:XCUIApplication) {
        let field = app.textViews["chatInput"]
        let previous = app.staticTexts.matching(identifier:"assistantMessage").count
        field.tap(); field.typeText(text)
        wait { app.buttons["sendMessageButton"].isEnabled && app.buttons["sendMessageButton"].isHittable }
        app.buttons["sendMessageButton"].tap()
        wait { !app.buttons["stopReplyButton"].exists && app.staticTexts.matching(identifier:"assistantMessage").count == previous + 1 }
    }
    @MainActor private func music(_ app:XCUIApplication) -> [String:Any] {
        let value = app.buttons["musicToggleButton"].value as? String ?? "{}"
        return (try? JSONSerialization.jsonObject(with:Data(value.utf8))) as? [String:Any] ?? [:]
    }
    @MainActor private func capture(_ name:String) {
        RunLoop.current.run(until:Date().addingTimeInterval(0.5))
        let attachment = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testGuestFiveTurnsDefaultSpeechLoginAndEmptyAccount() {
        let app = start(["--auth-testing"]); ready(app)
        XCTAssertEqual(app.staticTexts["chatCharacterName"].label,"初音未来")
        XCTAssertTrue(app.staticTexts["guestAllowance"].label.contains("5"))
        XCTAssertEqual(app.buttons["voiceMuteButton"].value as? String,"自动朗读")
        capture("nearby-guest-home")
        app.buttons["starter-hello"].tap(); app.waitForReply()
        wait({ (app.staticTexts["speechStatus"].value as? String ?? "").range(of:"audioSegments:[1-9]",options:.regularExpression) != nil },timeout:90)
        app.buttons["voiceMuteButton"].tap()
        XCTAssertEqual(app.buttons["voiceMuteButton"].value as? String,"已静音")
        tab(app,"messages"); XCTAssertTrue(app.buttons["message-hatsune-miku"].waitForExistence(timeout:10))
        capture("nearby-guest-messages"); app.buttons["message-hatsune-miku"].tap(); ready(app)
        XCTAssertEqual(app.buttons["voiceMuteButton"].value as? String,"已静音")
        for round in 2...5 { send("你好，这是第\(round)轮",app) }
        XCTAssertTrue(app.staticTexts["guestAllowance"].label.contains("登录"),app.staticTexts["guestAllowance"].label); capture("nearby-guest-limit")
        app.terminate(); app.launchArguments = ["--ui-testing","--companion-testing","--auth-testing","--keep-companion-data","--keep-auth-data"]; app.launch(); ready(app)
        XCTAssertTrue(app.staticTexts["guestAllowance"].label.contains("登录"))
        let field = app.textViews["chatInput"]
        field.tap(); field.typeText("第六轮需要登录"); app.buttons["sendMessageButton"].tap()
        XCTAssertTrue(app.buttons["signInButton"].waitForExistence(timeout:15)); capture("nearby-login")
        app.buttons["signInButton"].tap(); ready(app)
        XCTAssertFalse(app.staticTexts["guestAllowance"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier:"assistantMessage").count,5)
        tab(app,"discover"); app.buttons["follow-hatsune-miku"].tap()
        tab(app,"messages"); XCTAssertTrue(app.buttons["emptyStateAction"].waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["message-hatsune-miku"].exists)
        tab(app,"home"); XCTAssertTrue(app.buttons["emptyStateAction"].waitForExistence(timeout:10)); capture("nearby-empty-home")
        app.terminate(); app.launchArguments = ["--ui-testing","--companion-testing","--keep-companion-data","--auth-testing","--keep-auth-data"];app.launch()
        XCTAssertTrue(app.buttons["emptyStateAction"].waitForExistence(timeout:20)); XCTAssertFalse(app.buttons["customizationButton"].exists)
    }
    @MainActor func testLocalSearchCompactDiscoveryAndPersistentTheme() {
        let app = start(["--shell-discover"])
        XCTAssertTrue(app.textFields["discoverSearch"].waitForExistence(timeout:20))
        for id in ["real-woman","studio-robot","hatsune-miku","sample-robot"] {
            XCTAssertTrue(app.buttons["discover-open-"+id].isHittable)
            XCTAssertLessThan(app.otherElements["discover-card-"+id].frame.height,210)
        }
        capture("nearby-discover")
        app.textFields["discoverSearch"].tap(); app.textFields["discoverSearch"].typeText("初音")
        XCTAssertTrue(app.buttons["discover-open-hatsune-miku"].exists)
        XCTAssertFalse(app.buttons["discover-open-real-woman"].exists)
        capture("nearby-search")
        app.buttons["clearDiscoverSearch"].tap(); app.textFields["discoverSearch"].typeText("不存在xyz\n")
        XCTAssertFalse(app.buttons["discover-open-hatsune-miku"].exists)
        tab(app,"mine"); capture("nearby-profile")
        app.buttons["profileSettingsButton"].tap()
        XCTAssertTrue(app.buttons["themeSettingsButton"].waitForExistence(timeout:5));app.buttons["themeSettingsButton"].tap()
        XCTAssertTrue(app.buttons["theme-forest"].waitForExistence(timeout:5)); app.buttons["theme-forest"].tap()
        let style = app.segmentedControls["themeStyle"]
        if !style.isHittable { app.scrollViews.firstMatch.swipeUp() }
        style.buttons["沉静"].tap(); capture("nearby-themes")
        app.terminate(); app.launchArguments = ["--ui-testing","--companion-testing","--keep-companion-data","--shell-discover"];app.launch()
        tab(app,"mine"); app.buttons["profileSettingsButton"].tap();app.buttons["themeSettingsButton"].tap()
        XCTAssertEqual(app.buttons["theme-forest"].value as? String,"已选择")
        XCTAssertTrue(app.segmentedControls["themeStyle"].buttons["沉静"].isSelected)
    }
    @MainActor func testCollectionMusicSceneAndMuteIsolation() {
        let app = start();ready(app)
        app.buttons["voiceMuteButton"].tap()
        app.openCustomization("space")
        XCTAssertTrue(app.buttons["environment-evening"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["environment-studio"].exists)
        XCTAssertFalse(app.buttons["environment-seaside"].exists)
        capture("nearby-miku-scenes"); app.closeCustomizationPage("closeStudioButton")
        app.openCustomization("music")
        XCTAssertTrue(app.buttons["musicTrack-hatsune-miku/day"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["musicTrack-studio-robot/orbit"].exists)
        app.buttons["musicTrack-hatsune-miku/day"].tap();app.buttons["musicQuietButton"].tap()
        wait { (app.buttons["musicToggleButton"].value as? String ?? "").contains("\"playing\":true") }
        capture("nearby-miku-music");app.closeCustomizationPage("closeMusicButton")
        tab(app,"discover");app.buttons["discover-open-studio-robot"].tap();ready(app)
        XCTAssertEqual(app.buttons["voiceMuteButton"].value as? String,"自动朗读")
        app.openCustomization("space")
        XCTAssertTrue(app.buttons["environment-studio"].exists);XCTAssertTrue(app.buttons["environment-courtyard"].exists)
        XCTAssertFalse(app.buttons["environment-evening"].exists);app.closeCustomizationPage("closeStudioButton")
        app.openCustomization("music")
        XCTAssertTrue(app.buttons["musicTrack-studio-robot/orbit"].exists)
        XCTAssertFalse(app.buttons["musicTrack-hatsune-miku/day"].exists)
        XCTAssertTrue((app.buttons["musicToggleButton"].value as? String ?? "").contains("\"enabled\":false"))
        XCTAssertEqual(app.staticTexts["musicVolumeValue"].label,"28%")
        app.closeCustomizationPage("closeMusicButton")
        tab(app,"messages");app.buttons["message-hatsune-miku"].tap();ready(app)
        XCTAssertEqual(app.buttons["voiceMuteButton"].value as? String,"已静音")
        app.openCustomization("music")
        XCTAssertEqual(app.staticTexts["musicVolumeValue"].label,"15%")
        XCTAssertEqual(music(app)["track"] as? String,"hatsune-miku/day")
    }
}
