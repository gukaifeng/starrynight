import XCTest
import UIKit

final class ImmersiveRefinementTests:XCTestCase {
    @MainActor func testDiscoveryDeveloperPagesAndConversationControls() {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--smart-reply-layout-fixture","--inspector-layout-fixture"]
        app.launch();defer {app.terminate()}
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:75))
        app.waitForCharacter({$0["modelId"] as? String == "anime-kipfel"},timeout:60)
        XCTAssertFalse(app.buttons["conversationPerformanceButton"].exists)
        XCTAssertTrue(app.staticTexts["capsuleSubscribed"].exists)
        XCTAssertLessThan(app.buttons["customizationButton"].frame.width+app.staticTexts["capsuleSubscribed"].frame.width,140)
        XCTAssertGreaterThanOrEqual(app.buttons["customizationButton"].frame.height,44)
        app.buttons["smartReplyButton"].tap()
        let replies=app.otherElements["smartRepliesPanel"]
        XCTAssertTrue(replies.waitForExistence(timeout:5))
        XCTAssertGreaterThanOrEqual(replies.frame.minX,20)
        XCTAssertLessThanOrEqual(replies.frame.maxX,app.frame.maxX-20)
        XCTAssertLessThanOrEqual(replies.frame.width,310)
        XCTAssertTrue(app.staticTexts["灵感接话"].exists)
        capture("chat-capsule-and-replies")
        app.buttons["closeSmartReplies"].tap()
        app.openConversationSettings("sound")
        XCTAssertTrue(app.sliders["speechSoundVolume"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["心声"].exists && app.staticTexts["背景音乐"].exists)
        XCTAssertTrue(app.sliders["musicSoundVolume"].isHittable)
        capture("compact-sound")
        app.buttons["closeCharacterViewEditor"].tap()
        app.openConversationSettings("atmosphere")
        let amount=app.sliders["atmosphereLevelSlider"]
        XCTAssertTrue(amount.waitForExistence(timeout:5))
        XCTAssertEqual(amount.value as? String,"50%")
        amount.adjust(toNormalizedSliderPosition:0)
        XCTAssertEqual(amount.value as? String,"关闭")
        amount.adjust(toNormalizedSliderPosition:1)
        XCTAssertEqual(amount.value as? String,"100%")
        capture("atmosphere-settings")
        app.buttons["closeCharacterViewEditor"].tap()
        capture("atmosphere-vivid")
        app.buttons["customizationButton"].tap()
        let subscribe=app.buttons["characterSubscribeButton"]
        XCTAssertTrue(subscribe.waitForExistence(timeout:5));subscribe.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout:5))
        XCTAssertTrue(app.alerts.firstMatch.staticTexts["角色将从订阅列表移除，聊天记录和共同记忆仍会保留。"].exists)
        app.alerts.buttons["保留订阅"].tap()
        XCTAssertEqual(subscribe.value as? String,"已订阅")
        subscribe.tap();app.alerts.buttons.matching(identifier:"取消订阅").firstMatch.tap()
        XCTAssertEqual(subscribe.value as? String,"未订阅")
        app.buttons["closeCharacterDetails"].tap()
        XCTAssertTrue(app.buttons["capsuleSubscribeButton"].waitForExistence(timeout:5))
        app.buttons["capsuleSubscribeButton"].tap()
        XCTAssertTrue(app.staticTexts["capsuleSubscribed"].waitForExistence(timeout:5))
        app.openCharacterDeveloper()
        XCTAssertTrue(app.buttons["openAIInspector"].waitForExistence(timeout:5))
        capture("character-developer")
        app.buttons["profilePerformanceButton"].tap()
        XCTAssertTrue(app.buttons["performanceReset"].waitForExistence(timeout:5))
        app.buttons["performanceReset"].tap()
        app.buttons["closeCharacterPerformance"].tap()
        app.buttons["openAIInspector"].tap()
        checkSection("persona",contains:"角色专属设定",app:app)
        checkSection("prompts",contains:"对话规划与叙述规则",app:app)
        app.segmentedControls["aiInspectorTrigger"].buttons["待机"].tap()
        checkSection("context",contains:"idle",app:app)
        reveal(app.buttons["aiInspectionSection-latency"],in:app)
        app.buttons["aiInspectionSection-latency"].tap()
        XCTAssertTrue(app.staticTexts["「最近回复耗时」暂无记录"].waitForExistence(timeout:5))
        capture("inspector-empty-section")
        app.buttons["closeAIInspectionSection"].tap()
        app.buttons["closeAIInspector"].tap()
        app.buttons["closeCharacterDeveloper"].tap()
        app.openConversationSettings("atmosphere")
        XCTAssertEqual(amount.value as? String,"100%","Character preferences survive closing the editor")
        amount.adjust(toNormalizedSliderPosition:0.5)
        app.buttons["closeCharacterViewEditor"].tap()
        app.buttons["tab-discover"].tap()
        let cards=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","discover-open-"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout:6))
        XCTAssertGreaterThanOrEqual(cards.allElementsBoundByIndex.filter(\.isHittable).count,6)
        capture("dense-discovery")
        app.buttons["discover-open-anime-kipfel"].tap()
        XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:5))
        capture("edge-to-edge-profile-cover")
        app.buttons["closeCharacterDetails"].tap()
        app.buttons["tab-mine"].tap();app.buttons["profileSettingsButton"].tap()
        reveal(app.buttons["openAppDeveloper"],in:app);app.buttons["openAppDeveloper"].tap()
        XCTAssertTrue(app.buttons["developerCharacter-anime-kipfel"].waitForExistence(timeout:5))
        capture("app-developer")
        app.buttons["developerCharacter-anime-kipfel"].tap()
        XCTAssertTrue(app.buttons["openAIInspector"].waitForExistence(timeout:5))
    }
    @MainActor func testFullCoverProfileAndArrival() {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--shell-discover"]
        app.launch();defer {app.terminate()}
        XCTAssertTrue(app.buttons["discover-open-anime-kipfel"].waitForExistence(timeout:20))
        app.buttons["discover-open-anime-kipfel"].tap()
        XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:5))
        capture("final-full-head-profile")
        app.buttons["profileChatButton"].tap()
        if app.otherElements["conversationPreparing"].waitForExistence(timeout:3) {capture("final-full-bleed-arrival")}
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
    }
    @MainActor private func checkSection(_ id:String,contains:String,app:XCUIApplication) {
        let entry=app.buttons["aiInspectionSection-"+id]
        XCTAssertTrue(entry.waitForExistence(timeout:5));reveal(entry,in:app);entry.tap()
        let content=app.staticTexts["aiInspectionContent-"+id]
        XCTAssertTrue(content.waitForExistence(timeout:5));XCTAssertTrue(content.label.contains(contains),content.label)
        XCTAssertEqual(app.staticTexts["aiInspectionSectionID"].label,"分区 · "+id)
        capture("inspector-"+id)
        app.buttons["closeAIInspectionSection"].tap()
    }
    @MainActor private func reveal(_ element:XCUIElement,in app:XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable {return}
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func capture(_ name:String) {
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
    }
}
