import XCTest

final class SelectedRosterUITests:XCTestCase {
    @MainActor func testSelectedNamesAndStandingPreviews() throws {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--shell-discover"]
        defer{app.terminate()}
        for (role,name) in [("mao","Mao"),("mizuki","Mizuki")] {
            app.launch()
            let search=app.textFields["discoverSearch"]
            XCTAssertTrue(search.waitForExistence(timeout:60))
            if app.buttons["clearDiscoverSearch"].exists {app.buttons["clearDiscoverSearch"].tap()}
            search.tap();search.typeText(name+"\n")
            let card=app.buttons["discover-open-anime-"+role]
            XCTAssertTrue(card.waitForExistence(timeout:10));card.tap()
            XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:10));app.buttons["profileChatButton"].tap()
            XCTAssertTrue(app.staticTexts["localModelPreview"].waitForExistence(timeout:75))
            XCTAssertFalse(app.textViews["chatInput"].exists)
            let image=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
            image.name="standing-preview-"+name;image.lifetime = .keepAlways;add(image)
            app.terminate()
        }
    }
}
