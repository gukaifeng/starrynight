import XCTest

/// Uses the real model viewer and shipping roster; preserves existing user data.
final class CharacterModelReviewUITests:XCTestCase {
    @MainActor func testEveryPreviewModelOpensWithoutAIComposer() throws {
        continueAfterFailure=false
        struct Roster:Decodable {let characters:[String]}
        struct Entry:Decodable {
            struct Display:Decodable {let originalName:String}
            let id:String;let display:Display
        }
        struct Catalog:Decodable {let characters:[Entry]}
        struct Collection:Decodable {let modelID:String;let previewOnly:Bool?}
        struct Collections:Decodable {let collections:[Collection]}
        let path=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"active-roster",withExtension:"json"))
        let roles=try JSONDecoder().decode(Roster.self,from:Data(contentsOf:path)).characters
        let catalogPath=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"CharacterCatalog",withExtension:"json"))
        let catalog=try JSONDecoder().decode(Catalog.self,from:Data(contentsOf:catalogPath)).characters
        let collectionPath=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"CharacterCollections",withExtension:"json"))
        let collections=try JSONDecoder().decode(Collections.self,from:Data(contentsOf:collectionPath)).collections
        let previews=Set(collections.filter {$0.previewOnly == true}.map(\.modelID))
        XCTAssertFalse(roles.isEmpty)
        XCTAssertFalse(previews.isEmpty)
        XCTAssertLessThan(previews.count,roles.count,"Complete characters must remain available")
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--shell-discover","--keep-companion-data"]
        app.launch();defer {app.terminate()}
        for role in roles where previews.contains(role) {
            let search=app.textFields["discoverSearch"]
            XCTAssertTrue(search.waitForExistence(timeout:60),role)
            if app.buttons["clearDiscoverSearch"].exists {app.buttons["clearDiscoverSearch"].tap()}
            let entry=try XCTUnwrap(catalog.first {$0.id==role})
            search.tap();search.typeText(entry.display.originalName+"\n")
            let card=app.buttons["discover-open-"+role]
            XCTAssertTrue(card.waitForExistence(timeout:10),role);card.tap()
            let open=app.buttons["profileChatButton"]
            XCTAssertTrue(open.waitForExistence(timeout:8),role);open.tap()
            XCTAssertTrue(app.staticTexts["localModelPreview"].waitForExistence(timeout:75),role)
            XCTAssertFalse(app.textViews["chatInput"].exists,role)
            XCTAssertTrue(app.buttons["viewerBackButton"].exists,role)
            let screenshot=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
            screenshot.name="model-review-"+role;screenshot.lifetime = .keepAlways;add(screenshot)
            app.buttons["viewerBackButton"].tap()
        }
    }
}
