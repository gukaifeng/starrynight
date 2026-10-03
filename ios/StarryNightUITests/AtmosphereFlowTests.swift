import XCTest
import UIKit

final class AtmosphereFlowTests: XCTestCase {
    @MainActor func testWarmRoomAndMusicLifecycle() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["chat-studio-robot"].waitForExistence(timeout:15))
        capture("01-welcome",app,button:"accountCenterButton")
        app.buttons["chat-studio-robot"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:50))
        XCTAssertFalse(flag(app,"enabled")); XCTAssertFalse(flag(app,"playing"))
        XCTAssertEqual(app.descendants(matching:.scrollBar).count,0)
        capture("02-luma-room",app)
        app.openCustomization("music")
        XCTAssertTrue(app.buttons["musicTrack-IslandAfternoon"].waitForExistence(timeout:5))
        app.buttons["musicTrack-IslandAfternoon"].tap()
        wait(app,button:"musicToggleButton") { self.bool($0,"playing") && self.number($0,"samples") > 3 }
        app.buttons["musicTrack-MoonlitTide"].tap()
        app.buttons["musicQuietButton"].tap()
        wait(app,button:"musicToggleButton") { $0["track"] as? String == "MoonlitTide" && self.number($0,"volume") == 0.15 && self.bool($0,"playing") }
        capture("03-music",app,button:"musicToggleButton")
        app.closeCustomizationPage("closeMusicButton")
        let input = app.textViews["chatInput"]
        input.tap(); input.typeText("你好")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertLessThan(app.staticTexts["写下此刻想说的话"].frame.maxY,input.frame.minY)
        capture("04-keyboard",app)
        app.buttons["sendMessageButton"].tap()
        XCTAssertTrue(app.staticTexts.matching(identifier:"assistantMessage").firstMatch.waitForExistence(timeout:20))
        // Actual TTS focus must coexist with a measured, quieter music player.
        wait(app,timeout:110) { self.number($0,"duckedSamples") > 0 && self.number($0,"minimumDuckedVolume") < 0.04 && self.voiceSamples(app) > 0 }
        capture("05-speech-duck",app)
        if app.buttons["stopSpeechButton"].exists { app.buttons["stopSpeechButton"].tap() }
        wait(app) { self.bool($0,"playing") && abs(self.number($0,"outputVolume")-0.15) < 0.001 }
        capture("06-conversation",app)
        app.openCustomization("music"); app.buttons["musicToggleButton"].tap()
        wait(app,button:"musicToggleButton") { !self.bool($0,"playing") && !self.bool($0,"enabled") }
        app.buttons["musicToggleButton"].tap(); app.closeCustomizationPage("closeMusicButton")
        let samples = number(values(app),"samples")
        XCUIDevice.shared.press(.home)
        app.activate()
        wait(app) { self.bool($0,"playing") && self.number($0,"samples") > samples && self.number($0,"lifecyclePauses") >= 1 }
        app.buttons["viewerBackButton"].tap()
        XCTAssertTrue(app.buttons["chat-studio-robot"].waitForExistence(timeout:10))
        wait(app,button:"accountCenterButton") { !self.bool($0,"playing") && !self.bool($0,"active") && self.bool($0,"enabled") }
        capture("06b-left-room",app,button:"accountCenterButton")
        app.terminate()
        app.launchArguments = ["--ui-testing","--companion-testing","--keep-companion-data","--preview-companion"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:50))
        wait(app) { self.bool($0,"playing") && $0["track"] as? String == "MoonlitTide" && self.number($0,"volume") == 0.15 }
        capture("07-restored",app)
        app.openCustomization(); app.openCustomization("memory")
        XCTAssertTrue(app.buttons["closeMemoryButton"].waitForExistence(timeout:5))
        XCTAssertEqual(app.descendants(matching:.scrollBar).count,0)
        app.closeCustomizationPage("closeMemoryButton")
        app.openCustomization("framing")
        XCTAssertTrue(app.buttons["closeFramingButton"].waitForExistence(timeout:5))
        app.buttons["framingAngleRight"].tap(); app.closeCustomizationPage("closeFramingButton")
        wait(app,button:"customizationButton") { self.number($0,"framingAngle") == 20 }
        app.openCustomization("music"); app.buttons["musicToggleButton"].tap(); app.closeCustomizationPage("closeMusicButton")
    }
    @MainActor func testSpaceToolsNavigation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--preview-companion"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:50))
        app.openCustomization()
        XCTAssertTrue(app.buttons["customize-memory"].waitForExistence(timeout:5))
        capture("11-space-tools",app)
        app.openCustomization("memory")
        XCTAssertTrue(app.buttons["closeMemoryButton"].waitForExistence(timeout:5))
        capture("12-memory-surface",app)
        app.closeCustomizationPage("closeMemoryButton")
        app.openCustomization(); app.openCustomization("profile")
        XCTAssertTrue(app.textFields["profileName"].waitForExistence(timeout:5))
        capture("13-profile-surface",app)
        app.closeCustomizationPage("closeProfileButton")
        app.openCustomization(); app.openCustomization("history")
        XCTAssertTrue(app.buttons["closeHistoryButton"].waitForExistence(timeout:5))
        capture("14-history-surface",app)
        app.closeCustomizationPage("closeHistoryButton")
        app.buttons["viewerBackButton"].tap()
        XCTAssertTrue(app.buttons["accountCenterButton"].waitForExistence(timeout:5))
        app.buttons["accountCenterButton"].tap()
        XCTAssertTrue(app.buttons["closeAccountCenterButton"].waitForExistence(timeout:5))
        capture("15-account-surface",app)
        app.buttons["closeAccountCenterButton"].tap()
        app.openAccountAbout()
        XCTAssertTrue(app.buttons["closeAccountCenterButton"].waitForExistence(timeout:5))
        capture("16-about-surface",app)
        app.buttons["closeAccountCenterButton"].tap()
    }
    @MainActor func testIPadWarmRoom() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad only") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--preview-companion","--preview-miku"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:50))
        XCTAssertGreaterThan(app.images["characterStage"].frame.width,app.images["characterStage"].frame.height)
        capture("08-ipad-portrait",app)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:10))
        app.openCustomization("music")
        app.buttons["musicTrack-IslandAfternoon"].tap()
        wait(app,button:"musicToggleButton") { self.bool($0,"playing") && self.number($0,"samples") > 2 }
        app.closeCustomizationPage("closeMusicButton")
        XCTAssertLessThanOrEqual(app.images["characterStage"].frame.maxX,app.otherElements["companionPanel"].frame.minX)
        XCTAssertTrue(app.textViews["chatInput"].isHittable)
        capture("09-ipad-landscape",app)
        app.openCustomization(); app.openCustomization("profile")
        XCTAssertTrue(app.textFields["profileName"].waitForExistence(timeout:5))
        XCTAssertEqual(app.descendants(matching:.scrollBar).count,0)
        capture("10-ipad-profile",app)
    }
    @MainActor private func values(_ app: XCUIApplication, button: String = "customizationButton") -> [String:Any] {
        let element = app.buttons[button]
        guard element.exists,let raw = element.value as? String,let data = raw.data(using:.utf8),let value = try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return [:] }
        if let raw = value["soundscape"] as? String,
           let music = try? JSONSerialization.jsonObject(with:Data(raw.utf8)) as? [String:Any] {
            return value.merging(music,uniquingKeysWith:{ _, new in new })
        }
        return value
    }
    private func number(_ values:[String:Any],_ key:String) -> Double { (values[key] as? NSNumber)?.doubleValue ?? -1 }
    private func bool(_ values:[String:Any],_ key:String) -> Bool { values[key] as? Bool ?? false }
    @MainActor private func voiceSamples(_ app:XCUIApplication) -> Int {
        let value = app.staticTexts["speechStatus"].value as? String ?? ""
        return Int(value.split(separator:":").last ?? "") ?? 0
    }
    @MainActor private func flag(_ app:XCUIApplication,_ key:String) -> Bool { bool(values(app),key) }
    @MainActor private func wait(_ app:XCUIApplication,button:String="customizationButton",timeout:TimeInterval=12,_ test:@escaping ([String:Any])->Bool) {
        let predicate = NSPredicate { _,_ in MainActor.assumeIsolated { test(self.values(app,button:button)) } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:nil)],timeout:timeout),.completed,"Music state: \(values(app,button:button))")
    }
    @MainActor private func capture(_ name:String,_ app:XCUIApplication,button:String="customizationButton") {
        let shot = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        if let data = try? JSONSerialization.data(withJSONObject:values(app,button:button),options:[.prettyPrinted,.sortedKeys]) {
            let state = XCTAttachment(data:data,uniformTypeIdentifier:"public.json"); state.name = name + "-audio"; state.lifetime = .keepAlways; add(state)
        }
    }
}
