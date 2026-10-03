import XCTest

/// Real cloud tickets + OSS + Unity unload/reinstall; private synthetic account.
final class CharacterResourceDownloadUITests:XCTestCase {
    @MainActor func testDeleteActiveDownloadedRoleAndDownloadAgain() throws {
        continueAfterFailure=false
        struct Account:Decodable {let username,password:String}
        guard let url=Bundle(for:Self.self).url(forResource:"DownloadTestAccount",withExtension:"json") else {throw XCTSkip("Requires STARRY_OSS_UI_TESTS=1 and private test credentials")}
        let credentials=try JSONDecoder().decode(Account.self,from:Data(contentsOf:url))
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--shell-discover","-starry.app.language.v1","zh-Hans"]
        app.launch();defer {app.terminate()}
        XCTAssertTrue(app.buttons["tab-mine"].waitForExistence(timeout:60));app.buttons["tab-mine"].tap();app.buttons["accountCenterButton"].tap()
        if app.buttons["connectPlatformAccount"].exists {app.buttons["connectPlatformAccount"].tap()}
        XCTAssertTrue(app.textFields["passwordUsername"].waitForExistence(timeout:10))
        app.textFields["passwordUsername"].tap();app.textFields["passwordUsername"].typeText(credentials.username)
        app.secureTextFields["passwordCredential"].tap();app.secureTextFields["passwordCredential"].typeText(credentials.password);app.buttons["passwordSignIn"].tap()
        let signedIn=NSPredicate {_,_ in MainActor.assumeIsolated {!app.textFields["passwordUsername"].exists && !app.buttons["passwordSignIn"].exists}}
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:signedIn,object:nil)],timeout:60),.completed)
        if app.buttons["closeAccountButton"].exists {app.buttons["closeAccountButton"].tap()}
        // A restored last role may show an upgrade prompt instead of opening a
        // chat. Authentication success is independent of that download choice.
        if app.buttons["closeCharacterDownload"].waitForExistence(timeout:3) {app.buttons["closeCharacterDownload"].tap()}
        for name in ["fiona","mizuki","ramune"] {
            openRole(name,app)
            app.openCharacterDeveloper();app.buttons["profilePerformanceButton"].tap()
            XCTAssertTrue(app.buttons["closeCharacterPerformance"].waitForExistence(timeout:8),name)
            XCTAssertTrue(app.buttons["performanceReset"].isEnabled,name)
            app.buttons["performanceReset"].tap();app.closeCharacterPerformance()
            let shot=XCTAttachment(screenshot:app.screenshot());shot.name="v096-downloaded-"+name;shot.lifetime = .keepAlways;add(shot)
        }
        app.buttons["tab-mine"].tap();app.buttons["profileSettingsButton"].tap();app.buttons["cacheSettingsButton"].tap()
        app.buttons["characterResourceSettingsButton"].tap()
        let remove=app.buttons["removeCharacterResource-anime-ramune"]
        XCTAssertTrue(remove.waitForExistence(timeout:15));let original=app.staticTexts["characterResourceTotal"].label
        XCTAssertNotEqual(original,"0 KB")
        remove.tap();XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout:5));app.alerts.buttons["取消"].tap();XCTAssertTrue(remove.exists)
        remove.tap();app.alerts.buttons["删除资源"].tap()
        XCTAssertTrue(app.staticTexts["characterResourceResult"].waitForExistence(timeout:25))
        XCTAssertTrue(app.staticTexts["characterResourceResult"].label.contains("已移除"),app.staticTexts["characterResourceResult"].label)
        XCTAssertFalse(remove.exists)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="download-manager-ramune-removed";shot.lifetime = .keepAlways;add(shot)
        app.navigationBars["角色资源"].buttons.firstMatch.tap();app.navigationBars["存储与缓存"].buttons.firstMatch.tap();app.buttons["closeSettingsButton"].tap()
        openRole("ramune",app)
        app.buttons["tab-mine"].tap();app.buttons["profileSettingsButton"].tap();app.buttons["cacheSettingsButton"].tap();app.buttons["characterResourceSettingsButton"].tap()
        XCTAssertTrue(remove.waitForExistence(timeout:15));XCTAssertNotEqual(app.staticTexts["characterResourceTotal"].label,"0 KB")
    }
    @MainActor private func openRole(_ name:String,_ app:XCUIApplication) {
        app.buttons["tab-discover"].tap()
        XCTAssertTrue(app.textFields["discoverSearch"].waitForExistence(timeout:10))
        if app.buttons["clearDiscoverSearch"].exists {app.buttons["clearDiscoverSearch"].tap()}
        let id="anime-"+name
        let card=app.buttons["discover-open-"+id]
        for _ in 0..<18 {
            let list=app.scrollViews.firstMatch
            if card.exists && card.isHittable {break}
            if card.exists && card.frame.minY<list.frame.minY {list.swipeDown()}else {list.swipeUp()}
        }
        if !card.isHittable {
            let shot=XCTAttachment(screenshot:app.screenshot());shot.name="unreachable-"+name;shot.lifetime = .keepAlways;add(shot)
            let tree=XCTAttachment(string:app.debugDescription);tree.name="unreachable-hierarchy-"+name;tree.lifetime = .keepAlways;add(tree)
        }
        XCTAssertTrue(card.isHittable,name);card.tap()
        let download=app.buttons["downloadCharacter-"+id]
        if download.exists {download.tap()}
        else {
            app.buttons["profileChatButton"].tap()
            if download.waitForExistence(timeout:5) {download.tap()}
        }
        // Already installed roles can require a newer immutable release. The
        // profile opens the same confirmation after checking the live catalog.
        let confirm=app.buttons["confirmCharacterDownload"]
        if confirm.waitForExistence(timeout:8) {confirm.tap()}
        app.waitForCharacter({$0["modelId"] as? String==id && ($0["stableRenderedFrames"] as? Int ?? 0)>=3},timeout:240)
    }
}
