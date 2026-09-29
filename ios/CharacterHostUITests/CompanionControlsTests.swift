import XCTest

final class CompanionControlsTests: XCTestCase {
    @MainActor func testMikuAppearanceMemoryAndDataControls() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--preview-companion","--preview-miku"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:45))
        app.openCustomization(); app.openCustomization("profile")
        let accent = app.buttons["accentPicker"]
        XCTAssertTrue(accent.waitForExistence(timeout:5)); accent.tap()
        app.buttons["鸢紫"].tap()
        let toggle = app.switches["autoSpeakToggle"]
        if !toggle.isHittable { app.swipeUp() }
        let actual = toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle
        if actual.value as? String == "1" { actual.tap() }
        app.closeCustomizationPage("closeProfileButton")
        XCTAssertEqual(app.staticTexts["chatCharacterName"].label,"初音未来")
        capture("13-miku-purple-chat")

        app.openCustomization(); app.openCustomization("memory")
        let memory = app.textFields["memoryInput"]
        XCTAssertTrue(memory.waitForExistence(timeout:5)); memory.tap(); memory.typeText("喜欢星空")
        app.buttons["saveMemoryButton"].tap()
        app.buttons["editMemoryButton"].tap(); memory.tap()
        memory.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:4)+"喜欢海边")
        app.buttons["saveMemoryButton"].tap()
        XCTAssertTrue(app.staticTexts["喜欢海边"].exists)
        app.buttons["deleteMemoryButton"].tap()
        XCTAssertFalse(app.buttons["deleteMemoryButton"].exists)
        app.closeCustomizationPage("closeMemoryButton")
        app.buttons["你好"].tap()
        XCTAssertTrue(app.staticTexts.matching(identifier:"assistantMessage").firstMatch.waitForExistence(timeout:15))
        app.openCustomization(); app.openCustomization("history")
        app.buttons["exportArchiveButton"].tap()
        XCTAssertTrue(app.buttons["shareArchiveButton"].waitForExistence(timeout:5))
        capture("14-history-export")
        app.buttons["clearHistoryButton"].tap()
        app.buttons["确认清空聊天"].tap()
        app.closeCustomizationPage("closeHistoryButton")
        XCTAssertTrue(app.staticTexts["chatEmptyState"].exists || app.otherElements["chatEmptyState"].exists)
        capture("15-miku-cleared-chat")
        app.buttons["viewerBackButton"].tap()
        app.selectHomeModel("studio-robot")
        let luma = app.buttons["chat-studio-robot"]
        XCTAssertTrue(luma.waitForExistence(timeout:5)); luma.tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:20))
        XCTAssertEqual(app.staticTexts["chatCharacterName"].label,"Luma")
        XCTAssertFalse(app.staticTexts.matching(identifier:"assistantMessage").firstMatch.exists)
    }
    @MainActor private func capture(_ name: String) {
        let image = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); image.name = name
        image.lifetime = .keepAlways; add(image)
    }
}
