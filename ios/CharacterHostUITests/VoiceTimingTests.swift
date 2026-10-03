import XCTest
final class VoiceTimingTests:XCTestCase {
    @MainActor func testMutedNonPlaybackTimingsAndPersistence() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--voice-timing-check"]
        app.launch();defer {app.terminate()}
        let result=app.staticTexts["voiceTimingCheckResult"]
        XCTAssertTrue(result.waitForExistence(timeout:15))
        let done=NSPredicate {_,_ in MainActor.assumeIsolated {result.label.hasPrefix("PASS:") || result.label.hasPrefix("FAIL:")}}
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:done,object:nil)],timeout:20),.completed)
        XCTAssertTrue(result.label.hasPrefix("PASS:"),result.label)
    }
}
