import XCTest
import UIKit

extension XCUIApplication {
    @MainActor func openCharacterDeveloper(file:StaticString = #filePath,line:UInt = #line) {
        if buttons["closeCharacterDeveloper"].exists {return}
        if buttons["closeCharacterDetails"].exists {buttons["closeCharacterDetails"].tap()}
        let entry=buttons["openCharacterDeveloper"]
        XCTAssertTrue(entry.isHittable,file:file,line:line);entry.tap()
        XCTAssertTrue(buttons["closeCharacterDeveloper"].waitForExistence(timeout:5),file:file,line:line)
    }
    @MainActor func openCharacterPerformance(file:StaticString = #filePath,line:UInt = #line) {
        openCharacterDeveloper(file:file,line:line)
        buttons["profilePerformanceButton"].tap()
        XCTAssertTrue(buttons["closeCharacterPerformance"].waitForExistence(timeout:5),file:file,line:line)
    }
    @MainActor func closeCharacterPerformance(returnToProfile:Bool=false) {
        buttons["closeCharacterPerformance"].tap()
        XCTAssertTrue(buttons["closeCharacterDeveloper"].waitForExistence(timeout:5))
        buttons["closeCharacterDeveloper"].tap()
        if returnToProfile {buttons["customizationButton"].tap();XCTAssertTrue(buttons["closeCharacterDetails"].waitForExistence(timeout:5))}
    }

    @MainActor func openCustomization(_ section:String? = nil,file:StaticString = #filePath,line:UInt = #line) {
        if !buttons["closeCustomizationButton"].exists {
            XCTAssertTrue(buttons["customizationButton"].waitForExistence(timeout:60),file:file,line:line)
            if !buttons["profileCustomizeButton"].exists { buttons["customizationButton"].tap() }
            XCTAssertTrue(buttons["profileCustomizeButton"].waitForExistence(timeout:5),file:file,line:line)
            buttons["profileCustomizeButton"].tap()
        }
        XCTAssertTrue(buttons["closeCustomizationButton"].waitForExistence(timeout:5),file:file,line:line)
        if let section {
            let row = buttons["customize-" + section]
            // A phone landscape sidebar has a much shorter visible scroll area.
            let scroll = scrollViews["customizationSections"]
            for _ in 0..<10 {
                if row.isHittable { break }
                scroll.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.85)).press(forDuration:0.05,
                    thenDragTo:scroll.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.15)))
            }
            if !row.isHittable {
                XCTContext.runActivity(named:"Unreachable customization section") { activity in
                    let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name="unreachable-"+section;shot.lifetime = .keepAlways;activity.add(shot)
                    let tree=XCTAttachment(string:debugDescription);tree.name="unreachable-section-tree";tree.lifetime = .keepAlways;activity.add(tree)
                }
            }
            XCTAssertTrue(row.isHittable,file:file,line:line); row.tap()
        }
    }
    @MainActor func closeCustomizationPage(_ identifier:String) {
        buttons[identifier].tap()
        XCTAssertTrue(buttons["closeCustomizationButton"].waitForExistence(timeout:5))
        buttons["closeCustomizationButton"].tap()
        if buttons["closeCharacterDetails"].waitForExistence(timeout:3) { buttons["closeCharacterDetails"].tap() }
    }
    @MainActor func toggleModelLock() {
        openCustomization()
        let toggle = switches["modelControlLockToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout:5))
        let wasLocked = toggle.value as? String == "1"
        toggle.tap(); buttons["closeCustomizationButton"].tap()
        if buttons["closeCharacterDetails"].waitForExistence(timeout:3) { buttons["closeCharacterDetails"].tap() }
        waitForCharacter { $0["modelControlsLocked"] as? Bool == !wasLocked }
    }
    @MainActor func openAccountAbout() {
        buttons["accountCenterButton"].tap()
        XCTAssertTrue(segmentedControls["accountCenterTabs"].waitForExistence(timeout:5))
        segmentedControls["accountCenterTabs"].buttons["关于星夜"].tap()
    }
    @MainActor var musicEvidence:String { characterRuntime["soundscape"] as? String ?? "" }
    @MainActor func waitForReply(timeout:TimeInterval = 20) {
        let predicate=NSPredicate { _,_ in MainActor.assumeIsolated {
            self.staticTexts.matching(identifier:"assistantMessage").count > 0 && !self.buttons["stopReplyButton"].exists
        } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:nil)],timeout:timeout),.completed)
    }
    @MainActor func messageAction(_ id:String) {
        if buttons["returnLatestButton"].exists { buttons["returnLatestButton"].tap() }
        let message = staticTexts.matching(identifier:"assistantMessage").allElementsBoundByIndex.last!
        message.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.85)).press(forDuration:1)
        XCTAssertTrue(buttons[id].waitForExistence(timeout:5)); buttons[id].tap()
    }

}

final class UnifiedControlsTests:XCTestCase {
    @MainActor func testAdaptiveHomeAndAccountPages() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing"]
        app.launch();XCTAssertTrue(app.buttons["accountCenterButton"].waitForExistence(timeout:20))
        XCTAssertFalse(app.buttons["homeDisplayModeButton"].exists)
        app.selectHomeModel("hatsune-miku")
        XCTAssertLessThanOrEqual(app.buttons["mikuModelCard"].frame.width,156)
        XCTAssertTrue(app.buttons["humanModelCard"].isHittable)
        capture("adaptive-home")
        app.openAccountAbout()
        XCTAssertTrue(app.staticTexts["让陪伴，更近一点。"].waitForExistence(timeout:5))
        app.segmentedControls["accountCenterTabs"].buttons["账号"].tap()
        XCTAssertTrue(app.staticTexts["accountID"].waitForExistence(timeout:5))
        app.buttons["closeAccountCenterButton"].tap()
    }
    @MainActor func testUnifiedPanelAndBubbleContextActions() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--shell-discover"]
        XCUIDevice.shared.orientation = .portrait
        app.launch();XCTAssertTrue(app.buttons["discover-open-real-woman"].waitForExistence(timeout:20))
        app.buttons["discover-open-real-woman"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        for old in ["characterStudioButton","framingButton","modelLockButton","musicButton","chatToolsButton"] { XCTAssertFalse(app.buttons[old].exists) }
        app.openCustomization()
        XCTAssertEqual(app.switches["modelControlLockToggle"].value as? String,"1")
        capture("unified-customization")
        app.buttons["customize-framing"].tap()
        XCTAssertTrue(app.buttons["framingSizeMax"].waitForExistence(timeout:5));app.buttons["framingSizeMax"].tap()
        app.buttons["closeFramingButton"].tap()
        XCTAssertTrue(app.buttons["closeCustomizationButton"].waitForExistence(timeout:5))
        app.buttons["customize-framing"].tap()
        XCTAssertTrue(app.staticTexts["framingSizeValue"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["framingSizeValue"].label,"110%")
        app.buttons["restoreFramingButton"].tap();app.closeCustomizationPage("closeFramingButton")
        for (section,back) in [("profile","closeProfileButton"),("music","closeMusicButton"),("display","closeChatDisplayButton"),("history","closeHistoryButton")] {
            app.openCustomization(section)
            XCTAssertTrue(app.buttons[back].waitForExistence(timeout:5)); app.buttons[back].tap()
            XCTAssertTrue(app.buttons["closeCustomizationButton"].waitForExistence(timeout:5))
            app.buttons["closeCustomizationButton"].tap()
        }
        app.buttons["starter-hello"].tap();app.waitForReply()
        for id in ["readMessageButton","regenerateButton","rememberMessageButton"] { XCTAssertFalse(app.buttons[id].exists) }
        app.messageAction("rememberMessageButton")
        app.openCustomization("memory")
        XCTAssertTrue(app.buttons["editMemoryButton"].waitForExistence(timeout:5),"Long-press memory action must persist a real memory")
        app.closeCustomizationPage("closeMemoryButton")
        app.messageAction("regenerateButton");app.waitForReply()
        XCTAssertFalse(app.buttons["readMessageButton"].exists)
        capture("clean-conversation")
    }
    @MainActor private func capture(_ name:String) {
        let attachment=XCTAttachment(screenshot:XCUIScreen.main.screenshot());attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }
}
