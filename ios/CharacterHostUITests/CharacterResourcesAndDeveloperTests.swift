import XCTest

final class CharacterResourcesAndDeveloperTests:XCTestCase {
    @MainActor func testAccountScopedResourceDeletionAndReinstallation() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--character-resource-check"]
        app.launch();defer {app.terminate()}
        let result=app.staticTexts["characterResourceCheckResult"]
        XCTAssertTrue(result.waitForExistence(timeout:15))
        let completed=NSPredicate {_,_ in MainActor.assumeIsolated {result.label.hasPrefix("PASS:") || result.label.hasPrefix("FAIL:")}}
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:completed,object:nil)],timeout:30),.completed)
        XCTAssertTrue(result.label.hasPrefix("PASS:"),result.label)
    }
    @MainActor func testEveryCharacterPerformanceCatalogueCanOpenOutsideConversation() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--shell-discover","-starry.app.language.v1","zh-Hans"]
        app.launch();defer {app.terminate()}
        XCTAssertTrue(app.buttons["tab-mine"].waitForExistence(timeout:25));app.buttons["tab-mine"].tap()
        app.buttons["profileSettingsButton"].tap()
        let entry=app.buttons["openAppDeveloper"]
        for _ in 0..<4 {if entry.isHittable{break};app.scrollViews.firstMatch.swipeUp()}
        XCTAssertTrue(entry.waitForExistence(timeout:5));entry.tap()
        for id in ["chiffon","fiona","hikarun","ichigo","koharu","lime","mafuyu","meiyun","milfy","mao","mizuki","perula","plum","ramune","shinano","sio"] {
            let role=app.buttons["developerCharacter-anime-"+id]
            for _ in 0..<15 {
                let list=app.scrollViews.firstMatch
                if role.exists && role.isHittable && list.frame.insetBy(dx:0,dy:5).contains(role.frame) {break}
                if role.exists && role.frame.minY<list.frame.minY {list.swipeDown()}else{list.swipeUp()}
            }
            XCTAssertTrue(role.isHittable,id);role.tap()
            let performance=app.buttons["profilePerformanceButton"]
            XCTAssertTrue(performance.waitForExistence(timeout:5),id);performance.tap()
            XCTAssertTrue(app.buttons["closeCharacterPerformance"].waitForExistence(timeout:5),id)
            XCTAssertTrue(app.buttons["developerOpenConversation"].exists,id)
            XCTAssertTrue(app.scrollViews["performanceGroups"].exists,id)
            XCTAssertTrue(app.scrollViews["performanceOptions"].exists,id)
            if id=="hikarun" {let shot=XCTAttachment(screenshot:app.screenshot());shot.name="hikarun-developer-catalogue";shot.lifetime = .keepAlways;add(shot)}
            app.buttons["closeCharacterPerformance"].tap()
            app.buttons["closeCharacterDeveloper"].tap()

        }
    }
    @MainActor func testResourceManagementEntryAndEmptyState() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--shell-discover","-starry.app.language.v1","zh-Hans"]
        app.launch();defer {app.terminate()}
        XCTAssertTrue(app.buttons["tab-mine"].waitForExistence(timeout:25));app.buttons["tab-mine"].tap()
        app.buttons["profileSettingsButton"].tap();app.buttons["cacheSettingsButton"].tap()
        let entry=app.buttons["characterResourceSettingsButton"]
        XCTAssertTrue(entry.waitForExistence(timeout:8));entry.tap()
        XCTAssertTrue(app.staticTexts["characterResourceTotal"].waitForExistence(timeout:8))
        XCTAssertTrue(app.descendants(matching:.any)["characterResourcesEmpty"].waitForExistence(timeout:5))
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="role-resource-manager-empty";shot.lifetime = .keepAlways;add(shot)
    }
}
