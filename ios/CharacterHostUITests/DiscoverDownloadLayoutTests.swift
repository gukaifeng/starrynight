import XCTest

final class DiscoverDownloadLayoutTests:XCTestCase {
    @MainActor func testCompleteRosterHasAudibleDefaultsAndMigratesOldPreviewData() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--model-review-core-check"]
        app.launch();defer {app.terminate()}
        let result=app.staticTexts["modelReviewCoreResult"]
        XCTAssertTrue(result.waitForExistence(timeout:15))
        XCTAssertTrue(result.label.hasPrefix("PASS:"),result.label)
        XCTAssertTrue(result.label.contains("16 complete conversation characters"),result.label)
        XCTAssertTrue(result.label.contains("16 audible defaults"),result.label)
    }
    @MainActor func testRemoteCardsMatchBundledCardGeometry() {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--shell-discover","-starry.app.language.v1","zh-Hans"]
        app.launch();defer {app.terminate()}
        let bundled=app.buttons["discover-open-anime-chiffon"]
        let remote=app.buttons["discover-open-anime-fiona"]
        let next=app.buttons["discover-open-anime-hikarun"]
        XCTAssertTrue(bundled.waitForExistence(timeout:25));XCTAssertTrue(remote.exists);XCTAssertTrue(next.exists)
        for card in [remote,next] {
            XCTAssertEqual(card.frame.width,bundled.frame.width,accuracy:0.5)
            XCTAssertEqual(card.frame.height,bundled.frame.height,accuracy:0.5)
            XCTAssertEqual(card.frame.minY,bundled.frame.minY,accuracy:0.5)
        }
        XCTAssertFalse(app.staticTexts["下载后相处"].exists)
        XCTAssertFalse((remote.value as? String ?? "").isEmpty,"The small icon retains accessible download status")
        capture("discover-equal-cards")
    }
    @MainActor func testWiderConfirmationCancelsOutsideAndStartsOnlyAfterConsent() {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--download-confirmation-check","-starry.app.language.v1","zh-Hans"]
        app.launch();defer {app.terminate()}
        let open=app.buttons["showDownloadConfirmationCheck"]
        XCTAssertTrue(open.waitForExistence(timeout:10));open.tap()
        let card=app.otherElements["characterDownloadConfirmationCard"]
        let confirm=app.buttons["confirmCharacterDownload"]
        let shown=confirm.waitForExistence(timeout:5)
        if !shown {capture("download-confirmation-missing");print(app.debugDescription)}
        XCTAssertTrue(shown)
        XCTAssertGreaterThan(card.frame.width,330)
        XCTAssertLessThanOrEqual(card.frame.width,350)
        XCTAssertTrue(app.frame.insetBy(dx:27,dy:12).contains(card.frame))
        capture("download-confirmation-balanced-margins")
        app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.12)).tap()
        XCTAssertTrue(open.waitForExistence(timeout:5));XCTAssertEqual(app.staticTexts["downloadConfirmationAccepted"].label,"0")
        XCTAssertFalse(confirm.exists)
        open.tap();XCTAssertTrue(confirm.waitForExistence(timeout:5));app.buttons["cancelCharacterDownloadConfirmation"].tap()
        XCTAssertTrue(open.waitForExistence(timeout:5));XCTAssertEqual(app.staticTexts["downloadConfirmationAccepted"].label,"0")
        open.tap();XCTAssertTrue(confirm.waitForExistence(timeout:5));confirm.tap()
        let started=NSPredicate(format:"label == %@","1")
        expectation(for:started,evaluatedWith:app.staticTexts["downloadConfirmationAccepted"])
        waitForExpectations(timeout:5)
        XCTAssertFalse(confirm.exists)
    }
    @MainActor private func capture(_ name:String) {
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
    }
}
