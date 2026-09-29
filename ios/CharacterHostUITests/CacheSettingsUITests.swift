import XCTest

final class CacheSettingsUITests: XCTestCase {
    @MainActor func testCacheFileContracts() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--cache-core-check"]; app.launch()
        let label = app.staticTexts["cacheCoreResult"]
        XCTAssertTrue(label.waitForExistence(timeout:15))
        let ready = NSPredicate { _,_ in MainActor.assumeIsolated { label.label.hasPrefix("PASS:") || label.label.hasPrefix("FAIL:") } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:ready,object:nil)],timeout:40),.completed)
        XCTAssertTrue(label.label.hasPrefix("PASS:"),label.label)
        let result = XCTAttachment(string:label.label); result.name = "cache-core-result"; result.lifetime = .keepAlways; add(result)
    }
    @MainActor func testSettingsSelectionCleanupAndRestart() {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--shell-discover","--cache-fixture"]
        app.launch(); openCache(app)
        let speech = app.buttons["cacheCategory-speech"], portraits = app.buttons["cacheCategory-portraits"], exports = app.buttons["cacheCategory-exports"]
        XCTAssertTrue(speech.waitForExistence(timeout:10))
        XCTAssertFalse(speech.label.contains("0 KB")); XCTAssertTrue(app.buttons["clearCacheButton"].isEnabled)
        XCTAssertTrue(app.staticTexts["cacheProtectedNote"].exists); capture("01-cache-overview")
        let originalPortraits = portraits.label, originalExports = exports.label
        portraits.tap(); exports.tap()
        XCTAssertEqual(portraits.value as? String,"未选择"); XCTAssertEqual(speech.value as? String,"已选择")
        app.buttons["clearCacheButton"].tap()
        XCTAssertTrue(app.staticTexts["cacheClearResult"].waitForExistence(timeout:10))
        XCTAssertTrue(speech.label.contains("0 KB")); XCTAssertEqual(portraits.label,originalPortraits); XCTAssertEqual(exports.label,originalExports)
        XCTAssertFalse(app.buttons["clearCacheButton"].isEnabled); capture("02-only-speech-cleared")
        portraits.tap(); exports.tap(); app.buttons["clearCacheButton"].tap()
        let done = NSPredicate { _,_ in MainActor.assumeIsolated { portraits.label.contains("0 KB") && !app.buttons["clearCacheButton"].isEnabled } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:done,object:nil)],timeout:10),.completed)
        XCTAssertFalse(exports.label.contains("0 KB")); XCTAssertTrue(app.staticTexts["cacheProtectedNote"].exists)
        capture("03-clear-completed-with-share-retained")
        app.buttons["refreshCacheButton"].tap()
        XCTAssertTrue(app.staticTexts["cacheTotalSize"].waitForExistence(timeout:5))
        app.navigationBars["存储与缓存"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["closeSettingsButton"].waitForExistence(timeout:5)); app.buttons["closeSettingsButton"].tap()
        XCTAssertEqual(app.buttons["mySubscriptionsButton"].label,"1 订阅")
        app.buttons["tab-home"].tap(); XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:65))
        app.waitForCharacter { $0["modelId"] as? String == "hatsune-miku" && $0["framingMotionActive"] as? Bool == false }
        let camera = app.characterRuntime
        XCTAssertGreaterThan((camera["greetingCount"] as? NSNumber)?.intValue ?? 0,0)
        capture("04-conversation-after-clear")
        openCache(app)
        XCTAssertTrue(speech.waitForExistence(timeout:10)); XCTAssertTrue(speech.label.contains("0 KB"))
        app.terminate()
        app.launchArguments += ["--keep-cache-fixture","--keep-companion-data","--keep-auth-data"]
        app.launch(); openCache(app)
        XCTAssertTrue(speech.waitForExistence(timeout:10)); XCTAssertTrue(speech.label.contains("0 KB")); XCTAssertTrue(portraits.label.contains("0 KB"))
        XCTAssertTrue(app.staticTexts["cacheProtectedNote"].exists); XCTAssertFalse(app.buttons["clearCacheButton"].isEnabled)
        capture("05-cache-after-restart")
    }
    @MainActor private func openCache(_ app:XCUIApplication) {
        XCTAssertTrue(app.buttons["tab-mine"].waitForExistence(timeout:65)); app.buttons["tab-mine"].tap()
        XCTAssertTrue(app.buttons["profileSettingsButton"].waitForExistence(timeout:5)); app.buttons["profileSettingsButton"].tap()
        XCTAssertTrue(app.buttons["cacheSettingsButton"].waitForExistence(timeout:5)); app.buttons["cacheSettingsButton"].tap()
    }
    @MainActor private func capture(_ name:String) {
        Thread.sleep(forTimeInterval:0.6)
        let item = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
