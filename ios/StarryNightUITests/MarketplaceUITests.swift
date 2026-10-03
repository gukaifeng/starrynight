import XCTest

final class MarketplaceUITests:XCTestCase {
    @MainActor func testFinalVisualPreviewModelsOpen() {
        for (name,id) in [("真央","anime-mao"),("Ramune","anime-ramune"),
                          ("露露奈","anime-rurune"),("小春","anime-koharu")] {
            let app=launch()
            let search=app.textFields["discoverSearch"]
            XCTAssertTrue(search.waitForExistence(timeout:12))
            search.tap();search.typeText(name+"\n")
            let card=app.buttons["discover-open-"+id]
            XCTAssertTrue(card.waitForExistence(timeout:8),name)
            card.tap()
            let open=app.buttons["profileChatButton"]
            XCTAssertTrue(open.waitForExistence(timeout:5))
            XCTAssertEqual(open.label,"查看模型")
            open.tap()
            XCTAssertTrue(app.staticTexts["localModelPreview"].waitForExistence(timeout:35),name)
            XCTAssertFalse(app.textViews["chatInput"].exists)
            capture("visual-preview-"+id)
            app.terminate()
        }
    }
    @MainActor func testVisualPreviewBatchKeepsBothKipfelVersions() {
        for (name,id) in [("小猫·新版","anime-kipfel-v111"),("Azuki","anime-azuki"),
                          ("可露","anime-cornet"),("Fiona","anime-fiona")] {
            let app=launch()
            let search=app.textFields["discoverSearch"]
            XCTAssertTrue(search.waitForExistence(timeout:12))
            search.tap();search.typeText(name+"\n")
            let card=app.buttons["discover-open-"+id]
            XCTAssertTrue(card.waitForExistence(timeout:8),name)
            card.tap()
            let open=app.buttons["profileChatButton"]
            XCTAssertTrue(open.waitForExistence(timeout:5))
            XCTAssertEqual(open.label,"查看模型")
            open.tap()
            XCTAssertTrue(app.staticTexts["localModelPreview"].waitForExistence(timeout:30),name)
            XCTAssertFalse(app.textViews["chatInput"].exists)
            app.terminate()
        }
        let app=launch()
        XCTAssertTrue(app.buttons["discover-open-anime-kipfel"].waitForExistence(timeout:12),"旧版小猫仍应保留")
    }
    @MainActor func testThirdLocalPreviewBatchOpensWithoutComposer() {
        for (name,id) in [("意可蕾","anime-eku"),("Sio","anime-sio")] {
            let app=launch()
            let search=app.textFields["discoverSearch"]
            XCTAssertTrue(search.waitForExistence(timeout:12))
            search.tap();search.typeText(name+"\n")
            let card=app.buttons["discover-open-"+id]
            XCTAssertTrue(card.waitForExistence(timeout:6),name)
            card.tap()
            let open=app.buttons["profileChatButton"]
            XCTAssertTrue(open.waitForExistence(timeout:5))
            XCTAssertEqual(open.label,"查看模型")
            open.tap()
            XCTAssertTrue(app.staticTexts["localModelPreview"].waitForExistence(timeout:30),name)
            XCTAssertFalse(app.textViews["chatInput"].exists)
            capture("local-preview-"+id)
            app.terminate()
        }
    }
    @MainActor func testSecondLocalPreviewBatchOpensWithoutComposer() {
        for (name,id) in [("米露菲","anime-milfy"),("Shizuku","anime-shizuku")] {
            let app=launch()
            let search=app.textFields["discoverSearch"]
            XCTAssertTrue(search.waitForExistence(timeout:12))
            search.tap();search.typeText(name+"\n")
            let card=app.buttons["discover-open-"+id]
            XCTAssertTrue(card.waitForExistence(timeout:6),name)
            card.tap()
            let open=app.buttons["profileChatButton"]
            XCTAssertTrue(open.waitForExistence(timeout:5))
            XCTAssertEqual(open.label,"查看模型")
            open.tap()
            XCTAssertTrue(app.staticTexts["localModelPreview"].waitForExistence(timeout:30),name)
            XCTAssertFalse(app.textViews["chatInput"].exists)
            capture("local-preview-"+id)
            app.terminate()
        }
    }
    @MainActor func testImportedLocalPreviewDoesNotOpenAIComposer() {
        let app=launch()
        let search=app.textFields["discoverSearch"]
        XCTAssertTrue(search.waitForExistence(timeout:12))
        search.tap();search.typeText("爱莉\n")
        let card=app.buttons["discover-open-anime-airi"]
        XCTAssertTrue(card.waitForExistence(timeout:6))
        card.tap()
        XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:5))
        XCTAssertEqual(app.buttons["profileChatButton"].label,"查看模型")
        app.buttons["profileChatButton"].tap()
        XCTAssertTrue(app.staticTexts["localModelPreview"].waitForExistence(timeout:30))
        XCTAssertFalse(app.textViews["chatInput"].exists)
        capture("05-local-preview-airi")
    }
    @MainActor func testCatalogVisibilityAndHiddenConversationPersistence() {
        let app = XCUIApplication(); app.launchArguments = ["--market-core-check"]
        app.launch()
        let result = app.staticTexts["marketCoreResult"]
        XCTAssertTrue(result.waitForExistence(timeout:20))
        XCTAssertTrue(result.label.hasPrefix("PASS:"),result.label)
    }
    @MainActor func testMarketBrowseSearchFiltersAndConsistentSearchGeometry() {
        let app = launch()
        let first = app.buttons["discover-open-anime-kipfel"]
        XCTAssertTrue(first.waitForExistence(timeout:12))
        XCTAssertEqual(app.buttons["tab-home"].label,"对话")
        let search = app.textFields["discoverSearch"]
        let discoveryFrame = app.otherElements["searchContainer-discoverSearch"].frame
        XCTAssertEqual(discoveryFrame.height,44,accuracy:0.5)
        capture("01-market-selected")
        first.tap()
        XCTAssertTrue(app.buttons["closeCharacterDetails"].waitForExistence(timeout:5))
        XCTAssertFalse(app.textViews["chatInput"].exists,"Cards open a profile, never a conversation immediately")
        app.buttons["closeCharacterDetails"].tap()
        search.tap(); search.typeText("豆日向\n")
        XCTAssertTrue(app.buttons["discover-open-anime-mamehinata"].waitForExistence(timeout:5))
        XCTAssertFalse(first.exists)
        XCTAssertEqual(app.staticTexts["discoverCount"].label,"1 位")
        capture("02-market-search")
        app.buttons["clearDiscoverSearch"].tap()
        app.buttons["discover-治愈"].tap()
        XCTAssertTrue(first.exists)
        XCTAssertFalse(app.buttons["discover-open-anime-mamehinata"].exists)
        app.buttons["discover-全部"].tap()
        app.buttons["marketShelf-创作者"].tap()
        XCTAssertTrue(app.otherElements["marketEmptyState"].waitForExistence(timeout:3))
        XCTAssertEqual(app.staticTexts["discoverCount"].label,"0 位")
        capture("03-market-creators-empty")
        app.buttons["resetMarketQuery"].tap()
        XCTAssertTrue(first.exists)
        app.buttons["marketFilterMenu"].tap()
        app.buttons["只看已订阅"].tap()
        XCTAssertEqual(app.staticTexts["discoverCount"].label,"1 位")
        XCTAssertTrue(first.exists)
        app.buttons["tab-messages"].tap()
        XCTAssertTrue(app.textFields["conversationSearchField"].waitForExistence(timeout:5))
        let messagesFrame = app.otherElements["searchContainer-conversationSearchField"].frame
        XCTAssertEqual(messagesFrame.height,discoveryFrame.height,accuracy:0.5)
        XCTAssertEqual(messagesFrame.width,discoveryFrame.width,accuracy:0.5)
        XCTAssertEqual(messagesFrame.minX,discoveryFrame.minX,accuracy:0.5)
        capture("04-messages-shared-search")
    }
    @MainActor func testSwipeHideSurvivesRelaunchAndCanBeRestored() {
        let app = launch()
        app.buttons["tab-messages"].tap()
        let row = app.buttons["message-anime-kipfel"]
        XCTAssertTrue(row.waitForExistence(timeout:8))
        row.swipeLeft()
        let hide = app.buttons["hideConversation-anime-kipfel"]
        XCTAssertTrue(hide.waitForExistence(timeout:3)); hide.tap()
        XCTAssertFalse(row.exists)
        XCTAssertTrue(app.buttons["undoHideConversation"].exists)
        capture("05-message-hidden")
        app.terminate(); app.launchArguments += ["--keep-companion-data","--keep-auth-data"]; app.launch()
        XCTAssertTrue(app.buttons["tab-messages"].waitForExistence(timeout:10)); app.buttons["tab-messages"].tap()
        XCTAssertFalse(row.exists)
        app.buttons["hiddenConversationsButton"].tap()
        XCTAssertTrue(app.buttons["restoreConversation-anime-kipfel"].waitForExistence(timeout:5))
        capture("06-hidden-conversation-manager")
        app.buttons["restoreConversation-anime-kipfel"].tap()
        app.buttons["closeHiddenConversations"].tap()
        XCTAssertTrue(row.waitForExistence(timeout:5))
        row.swipeLeft(); app.buttons["hideConversation-anime-kipfel"].tap()
        app.buttons["undoHideConversation"].tap()
        XCTAssertTrue(row.exists)
    }
    @MainActor func testConversationCardKeepsResetBehindSecondPage() {
        let app=launch()
        app.buttons["tab-messages"].tap()
        let row=app.buttons["message-anime-kipfel"]
        XCTAssertTrue(row.waitForExistence(timeout:8))
        row.tap()
        XCTAssertTrue(app.staticTexts["你们的故事"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["enterConversation-anime-kipfel"].exists)
        XCTAssertFalse(app.buttons["resetConversation-anime-kipfel"].exists)
        app.buttons["moreConversationActions-anime-kipfel"].tap()
        XCTAssertTrue(app.buttons["resetConversation-anime-kipfel"].waitForExistence(timeout:3))
        app.buttons["backConversationDetail"].tap()
        XCTAssertFalse(app.buttons["resetConversation-anime-kipfel"].exists)
        app.buttons["closeConversationDetail"].tap()
        XCTAssertTrue(row.waitForExistence(timeout:5))
    }
    @MainActor private func launch() -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--auth-testing","--shell-discover"]
        app.launch()
        return app
    }
    @MainActor private func capture(_ name:String) {
        let capture = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        capture.name = name; capture.lifetime = .keepAlways; add(capture)
    }
}
