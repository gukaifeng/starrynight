import XCTest

final class OfflineSpeechLifecycleTests: XCTestCase {
    @MainActor private func launch(_ extra:[String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--preview-companion","--preview-human","--voice-fixture"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["recognizeFixtureButton"].waitForExistence(timeout:45))
        XCTAssertTrue(app.staticTexts["speechStatus"].label.contains("离线语音已就绪"))
        return app
    }
    @MainActor private func wait(_ predicate:String,_ object:Any,timeout:TimeInterval = 45) {
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:predicate),object:object)],timeout:timeout),.completed)
    }
    @MainActor private func segments(_ app:XCUIApplication) -> Int {
        Int((app.staticTexts["speechStatus"].value as? String ?? "").split(separator:":").last ?? "") ?? 0
    }
    @MainActor private func capture(_ name:String) {
        let attachment = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testMultipleSentencesCancellationRecognitionAndBackground() {
        let app = launch()
        app.openCustomization("music")
        app.buttons["musicTrack-IslandAfternoon"].tap()
        app.closeCustomizationPage("closeMusicButton")
        app.buttons["你好"].tap()
        wait("value MATCHES 'audioSegments:([2-9]|[1-9][0-9]+)'",app.staticTexts["speechStatus"],timeout:80)
        capture("offline-two-sentences")
        let music = app.musicEvidence
        let values = (try? JSONSerialization.jsonObject(with:Data(music.utf8))) as? [String:Any]
        XCTAssertGreaterThan((values?["duckedSamples"] as? NSNumber)?.intValue ?? 0,0)
        if app.buttons["stopSpeechButton"].exists { app.buttons["stopSpeechButton"].tap() }

        // Cancel queued/prefetched synthesis, then immediately switch model to ASR.
        app.messageAction("readMessageButton")
        XCTAssertTrue(app.buttons["stopSpeechButton"].waitForExistence(timeout:5))
        app.buttons["stopSpeechButton"].tap()
        let before = segments(app)
        app.buttons["recognizeFixtureButton"].tap()
        wait("value CONTAINS '时间'",app.textFields["chatInput"])
        XCTAssertEqual(segments(app),before,"Cancelled speech must not play after ASR starts")
        XCTAssertFalse(app.buttons["stopSpeechButton"].exists)
        capture("offline-cancel-and-asr")

        app.messageAction("readMessageButton")
        wait("value MATCHES 'audioSegments:([3-9]|[1-9][0-9]+)'",app.staticTexts["speechStatus"],timeout:60)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["stopSpeechButton"].exists)
        let afterBackground = segments(app)
        let lateAudio = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in
            MainActor.assumeIsolated { self.segments(app) != afterBackground || app.buttons["stopSpeechButton"].exists }
        },object:nil)
        lateAudio.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for:[lateAudio],timeout:3),.completed)
        // The model can load again after background memory release.
        app.messageAction("readMessageButton")
        wait("value MATCHES 'audioSegments:([4-9]|[1-9][0-9]+)'",app.staticTexts["speechStatus"],timeout:60)
        app.buttons["stopSpeechButton"].tap()
        capture("offline-resumed-explicitly")
    }
    @MainActor func testSilenceDoesNotInventTranscript() {
        let app = launch(["--voice-silent-fixture"])
        app.buttons["recognizeFixtureButton"].tap()
        XCTAssertTrue(app.staticTexts["没有识别到清晰的人声，请靠近麦克风后重试。"].waitForExistence(timeout:10))
        XCTAssertFalse(app.staticTexts.matching(identifier:"assistantMessage").firstMatch.exists)
        XCTAssertFalse(app.buttons["stopSpeechButton"].exists)
        capture("offline-silence")
    }
    @MainActor func testInvalidAudioRecoversForSpeech() {
        let app = launch(["--voice-invalid-fixture"])
        app.buttons["recognizeFixtureButton"].tap()
        XCTAssertTrue(app.staticTexts["手机内的语音识别失败，请重新录音后重试。"].waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["stopSpeechButton"].exists)
        app.buttons["你好"].tap()
        wait("value MATCHES 'audioSegments:[1-9][0-9]*'",app.staticTexts["speechStatus"],timeout:60)
        app.buttons["stopSpeechButton"].tap()
        capture("offline-invalid-audio-recovered")
    }
}
