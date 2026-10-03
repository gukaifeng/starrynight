import XCTest

final class ConversationExportUITests: XCTestCase {
    @MainActor func testRangeStylesPreviewAndSystemShare() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--export-ui-check"]; app.launch()
        XCTAssertTrue(app.buttons["generateConversationImage"].waitForExistence(timeout: 15))
        capture("01-export-editor")
        app.buttons["exportStart"].tap()
        let search = app.textFields["exportRangeSearch"]; search.tap(); search.typeText("今天有点累")
        app.buttons["exportMessage-1"].tap()
        XCTAssertEqual(app.staticTexts["exportSelectionCount"].label, "已选 9 条")
        app.buttons["exportEnd"].tap()
        app.textFields["exportRangeSearch"].tap(); app.textFields["exportRangeSearch"].typeText("声音调轻")
        app.buttons["exportMessage-6"].tap()
        XCTAssertEqual(app.staticTexts["exportSelectionCount"].label, "已选 6 条")
        capture("02-selected-range")
        app.buttons["generateConversationImage"].tap()
        XCTAssertTrue(app.buttons["shareConversationImage"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.staticTexts["exportPreviewSummary"].label, "6 条 · 1 张长图")
        capture("03-moon-preview")
        app.buttons["shareConversationImage"].tap()
        let shareTitle = app.navigationBars["与小光的对话 · 星夜"]
        XCTAssertTrue(shareTitle.waitForExistence(timeout: 15), app.debugDescription)
        capture("04-system-share")
        // Dismiss the share sheet without choosing a recipient or sending anything.
        app.buttons["header.closeButton"].tap()
        XCTAssertTrue(app.buttons["closeConversationExport"].isHittable)
        app.buttons["closeConversationExport"].tap()
        XCTAssertTrue(app.buttons["generateConversationImage"].waitForExistence(timeout: 5))
        app.buttons["exportStyle-paper"].tap()
        app.switches["exportDatesToggle"].tap()
        app.buttons["generateConversationImage"].tap()
        XCTAssertTrue(app.buttons["shareConversationImage"].waitForExistence(timeout: 30))
        capture("05-paper-preview")
        app.buttons["closeConversationExport"].tap()
        XCTAssertEqual(app.staticTexts["exportSelectionCount"].label, "已选 6 条")
        XCTAssertEqual(app.buttons["exportStyle-paper"].value as? String, "已选")
    }
    @MainActor func testExportContractsInIOSRuntime() {
        let app = XCUIApplication(); app.launchArguments = ["--export-core-check"]; app.launch()
        let label = app.staticTexts["exportCoreResult"]
        XCTAssertTrue(label.waitForExistence(timeout: 15))
        let ready = NSPredicate { _, _ in MainActor.assumeIsolated { label.label.hasPrefix("PASS:") || label.label.hasPrefix("FAIL:") } }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 60), .completed)
        XCTAssertTrue(label.label.hasPrefix("PASS:"), label.label)
        let attachment = XCTAttachment(string: label.label); attachment.name = "export-core-result"; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testProfileEntryReopensAndKeepsCamera() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--companion-testing", "--shell-discover"]
        app.launch()
        XCTAssertTrue(app.buttons["discover-open-real-woman"].waitForExistence(timeout: 25))
        app.buttons["discover-open-real-woman"].tap()
        XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout: 5)); app.buttons["profileChatButton"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout: 60))
        app.waitForCharacter { $0["modelId"] as? String == "real-woman" && $0["framingMotionActive"] as? Bool == false }
        let camera = app.characterRuntime
        for _ in 0..<2 {
            app.buttons["customizationButton"].tap()
            XCTAssertTrue(app.buttons["profileExportButton"].waitForExistence(timeout: 6)); app.buttons["profileExportButton"].tap()
            XCTAssertTrue(app.buttons["generateConversationImage"].waitForExistence(timeout: 5))
            capture("06-live-character-export")
            app.buttons["closeConversationExport"].tap()
            XCTAssertTrue(app.buttons["closeCharacterDetails"].waitForExistence(timeout: 5)); app.buttons["closeCharacterDetails"].tap()
        }
        app.openCustomization("history")
        let historyBack = app.buttons["closeHistoryButton"]
        let historySearch = app.textFields["historySearch"]
        XCTAssertTrue(historyBack.waitForExistence(timeout: 5))
        XCTAssertTrue(historySearch.waitForExistence(timeout: 5))
        let historyBackFrame = historyBack.frame
        let handleFrame = app.buttons["softPanelHandle"].frame
        let filter = "今天"
        historySearch.tap(); historySearch.typeText(filter)
        for pass in 1...2 {
            XCTAssertEqual(historySearch.value as? String,filter,"The retained history filter survives round trip \(pass)")
            app.buttons["historyExportImageButton"].tap()
            XCTAssertTrue(app.buttons["generateConversationImage"].waitForExistence(timeout: 5))
            let exportBack = app.buttons["closeConversationExport"]
            XCTAssertTrue(exportBack.waitForExistence(timeout: 5))
            // A second presented sheet has a different panel height/origin. The
            // real export header and drag handle must remain in the first panel.
            for (actual,expected,label) in [(exportBack.frame,historyBackFrame,"export header"),
                                            (app.buttons["softPanelHandle"].frame,handleFrame,"existing panel")] {
                XCTAssertEqual(actual.minX,expected.minX,accuracy:1,label)
                XCTAssertEqual(actual.minY,expected.minY,accuracy:1,label)
                XCTAssertEqual(actual.width,expected.width,accuracy:1,label)
                XCTAssertEqual(actual.height,expected.height,accuracy:1,label)
            }
            XCTAssertFalse(historyBack.exists,"The hidden history page must not expose a second back button")
            let exportedCamera = app.characterRuntime
            for key in ["distance", "framingSize", "framingAngle", "pitch", "yaw", "cameraFov"] {
                XCTAssertEqual((exportedCamera[key] as? NSNumber)?.doubleValue ?? -1,
                               (camera[key] as? NSNumber)?.doubleValue ?? -2,accuracy:0.0001,key)
            }
            XCTAssertEqual(exportedCamera["framingMotionActive"] as? Bool,false)
            capture("07-history-export-same-panel-\(pass)")
            exportBack.tap()
            XCTAssertTrue(historyBack.waitForExistence(timeout: 5),"Export return must work on every entry")
            XCTAssertTrue(historySearch.waitForExistence(timeout: 5))
            XCTAssertEqual(historySearch.value as? String,filter)
            let returnedFrame = historyBack.frame
            XCTAssertEqual(returnedFrame.minX,historyBackFrame.minX,accuracy:1)
            XCTAssertEqual(returnedFrame.minY,historyBackFrame.minY,accuracy:1)
            XCTAssertEqual(returnedFrame.width,historyBackFrame.width,accuracy:1)
            XCTAssertEqual(returnedFrame.height,historyBackFrame.height,accuracy:1)
            let returnedCamera = app.characterRuntime
            for key in ["distance", "framingSize", "framingAngle", "pitch", "yaw", "cameraFov"] {
                XCTAssertEqual((returnedCamera[key] as? NSNumber)?.doubleValue ?? -1,
                               (camera[key] as? NSNumber)?.doubleValue ?? -2,accuracy:0.0001,key)
            }
            XCTAssertEqual(returnedCamera["framingMotionActive"] as? Bool,false)
            capture("08-history-filter-retained-\(pass)")
        }
        app.closeCustomizationPage("closeHistoryButton")
        let actual = app.characterRuntime
        for key in ["distance", "framingSize", "framingAngle", "pitch", "yaw", "cameraFov"] {
            XCTAssertEqual((actual[key] as? NSNumber)?.doubleValue ?? -1, (camera[key] as? NSNumber)?.doubleValue ?? -2, accuracy: 0.0001, key)
        }
        XCTAssertEqual(actual["framingMotionActive"] as? Bool, false)
    }
    @MainActor private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
