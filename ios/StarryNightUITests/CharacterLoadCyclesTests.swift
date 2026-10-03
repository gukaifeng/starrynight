import XCTest

/// Real Unity loading/eviction/return regression. Fixtures disable paid AI.
final class CharacterLoadCyclesTests:XCTestCase {
    @MainActor func testCharacterEvictionAndReturnKeepsIdleReady() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","-starry.app.language.v1","zh-Hans"]
        app.launch();defer{app.terminate()}
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:75))
        for name in ["chiffon","lime","ichigo","mao","chiffon","lime"] {
            app.buttons["tab-discover"].tap()
            let search=app.textFields["discoverSearch"]
            XCTAssertTrue(search.waitForExistence(timeout:10))
            if app.buttons["clearDiscoverSearch"].exists {app.buttons["clearDiscoverSearch"].tap()}
            search.tap();search.typeText(name+"\n")
            let card=app.buttons["discover-open-anime-"+name]
            XCTAssertTrue(card.waitForExistence(timeout:10));card.tap()
            let open=app.buttons["profileChatButton"]
            XCTAssertTrue(open.waitForExistence(timeout:8));open.tap()
            app.waitForCharacter({$0["modelId"] as? String == "anime-"+name && $0["idlePlaying"] as? Bool == true},timeout:65)
            XCTAssertFalse(app.staticTexts["viewerError"].exists)
            let shot=XCTAttachment(screenshot:app.screenshot());shot.name="load-return-"+name;shot.lifetime = .keepAlways;add(shot)
        }
    }
}
