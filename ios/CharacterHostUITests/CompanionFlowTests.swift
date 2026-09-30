import XCTest
import UIKit

final class CompanionFlowTests: XCTestCase {
    @MainActor func testCompanionConversationMemoryAndPersistence() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing","--companion-testing"]
        app.launch()
        app.selectHomeModel("studio-robot")
        let start = app.buttons["chat-studio-robot"]
        XCTAssertTrue(start.waitForExistence(timeout:15))
        start.tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:45))
        capture("01-chat-empty")
        app.openCustomization(); app.openCustomization("profile")
        XCTAssertTrue(app.textFields["profileName"].waitForExistence(timeout:5))
        let name = app.textFields["profileName"]
        name.tap()
        // Select All uses localized system labels; replace with explicit backspaces.
        name.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:(name.value as? String ?? "").count) + "小屿")
        if app.buttons["finishProfileInput"].waitForExistence(timeout:3) { app.buttons["finishProfileInput"].tap() }
        let toggle = app.switches["autoSpeakToggle"]
        if !toggle.isHittable { app.swipeUp() }
        let actualSwitch = toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle
        actualSwitch.tap()
        let off = NSPredicate(format:"value == %@", "0")
        expectation(for:off,evaluatedWith:actualSwitch)
        waitForExpectations(timeout:5)
        capture("02-profile")
        app.closeCustomizationPage("closeProfileButton")
        XCTAssertTrue(app.staticTexts["chatCharacterName"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["chatCharacterName"].label,"小屿")
        app.openCustomization(); app.openCustomization("memory")
        let memory = app.textViews["memoryInput"].exists ? app.textViews["memoryInput"] : app.textFields["memoryInput"]
        XCTAssertTrue(memory.waitForExistence(timeout:5)); memory.tap(); memory.typeText("我喜欢海边和安静的音乐")
        app.buttons["saveMemoryButton"].tap(); capture("03-memory")
        app.closeCustomizationPage("closeMemoryButton")
        send("你记得什么",in:app)
        XCTAssertTrue(app.staticTexts.matching(identifier:"assistantMessage").firstMatch.waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts.matching(identifier:"assistantMessage").allElementsBoundByIndex.contains { $0.label.contains("海边") })
        capture("04-memory-recalled")
        send("跳舞吧",in:app)
        app.waitForReply(timeout:15)
        capture("05-chat-action")
        app.messageAction("regenerateButton")
        app.waitForReply(timeout:15)
        app.messageAction("readMessageButton")
        let speaking = NSPredicate(format:"value MATCHES %@","audioSegments:[1-9][0-9]*")
        expectation(for:speaking,evaluatedWith:app.staticTexts["speechStatus"])
        waitForExpectations(timeout:60)
        capture("06-speaking")
        if !app.buttons["stopSpeechButton"].exists { app.messageAction("readMessageButton") }
        app.buttons["stopSpeechButton"].tap()
        XCTAssertFalse(app.buttons["stopSpeechButton"].exists)
        app.buttons["viewerBackButton"].tap()
        XCTAssertTrue(start.waitForExistence(timeout:5))
        app.terminate()
        app.launchArguments = ["--ui-testing","--companion-testing","--keep-companion-data"]
        app.launch(); app.selectHomeModel("studio-robot"); XCTAssertTrue(start.waitForExistence(timeout:15))
        start.tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:45))
        XCTAssertEqual(app.staticTexts["chatCharacterName"].label,"小屿")
        app.openCustomization(); app.openCustomization("memory")
        XCTAssertTrue(app.staticTexts["我喜欢海边和安静的音乐"].waitForExistence(timeout:5))
        app.closeCustomizationPage("closeMemoryButton")
        capture("07-persisted")
    }
    @MainActor func testTabletLayoutAndActionMenuRegression() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing","--companion-testing"]
        app.launch(); app.selectHomeModel("studio-robot"); let start = app.buttons["chat-studio-robot"]
        XCTAssertTrue(start.waitForExistence(timeout:15)); start.tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:45))
        send("你好",in:app)
        XCTAssertTrue(app.staticTexts.matching(identifier:"assistantMessage").firstMatch.waitForExistence(timeout:15))
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            Thread.sleep(forTimeInterval:2); capture("08-ipad-landscape")
            XCTAssertTrue(app.buttons["customizationButton"].isHittable)
            XCUIDevice.shared.orientation = .portrait
            Thread.sleep(forTimeInterval:2); capture("09-ipad-portrait")
        }
        app.buttons["viewerBackButton"].tap()
        let explore = app.buttons["chat-studio-robot"]
        XCTAssertTrue(explore.waitForExistence(timeout:5)); explore.tap()
        XCTAssertTrue(app.buttons["characterActionsMenu"].waitForExistence(timeout:20)); app.performCharacterAction("Wave")
        app.waitForCharacter { ($0["characterPlatform"] as? [String:Any])?["lastAction"] as? String == "Wave" }
        XCTAssertTrue(app.buttons["customizationButton"].exists); capture("10-chat-action-regression")
    }
    @MainActor private func send(_ text: String, in app: XCUIApplication) {
        let input = app.textViews["chatInput"]
        XCTAssertTrue(input.waitForExistence(timeout:5)); input.tap(); input.typeText(text)
        app.buttons["sendMessageButton"].tap()
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
