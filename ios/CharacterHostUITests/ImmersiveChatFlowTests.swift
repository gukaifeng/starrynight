import XCTest
import UIKit

final class ImmersiveChatFlowTests: XCTestCase {
    @MainActor func testContentFadeScrollKeyboardAndRotation() {
        continueAfterFailure=false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--preview-companion","--preview-human"]
        app.launch();XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        wait {self.state(app)["framingMotionActive"] as? Bool == false}
        let messages=app.scrollViews["chatMessages"]
        XCTAssertGreaterThan(messages.frame.height,app.frame.height*0.24)
        XCTAssertGreaterThanOrEqual(app.buttons["customizationButton"].frame.minY,messages.frame.maxY-1)
        capture("01-invitation")
        app.buttons["starter-hello"].tap()
        XCTAssertTrue(app.staticTexts.matching(identifier:"assistantMessage").firstMatch.waitForExistence(timeout:20))
        wait {!app.buttons["stopReplyButton"].exists}
        let input=app.textFields["chatInput"].exists ? app.textFields["chatInput"] : app.textViews["chatInput"]
        for (index,text) in ["今天工作有点累，想安静地待一会儿","今天和朋友分享了一件开心的事","你平时喜欢做什么？"].enumerated() {
            input.tap();input.typeText(text);app.buttons["sendMessageButton"].tap()
            if index==0 && app.otherElements["streamingReply"].waitForExistence(timeout:2) {capture("02-streaming")}
            wait {!app.buttons["stopReplyButton"].exists && !app.keyboards.firstMatch.exists}
        }
        XCTAssertGreaterThanOrEqual(app.staticTexts.matching(identifier:"assistantMessage").count,3)
        capture("03-conversation")
        let gestures=number(state(app),"gestureCount")
        messages.swipeDown()
        XCTAssertTrue(app.buttons["returnLatestButton"].waitForExistence(timeout:5))
        XCTAssertLessThanOrEqual(app.buttons["returnLatestButton"].frame.width,44)
        XCTAssertFalse(app.staticTexts["回到最近"].exists,"The floating button only draws its arrow")
        XCTAssertEqual(number(state(app),"gestureCount"),gestures)
        capture("04-earlier-messages")
        // Manually returning to the bottom must dismiss the arrow without tapping it.
        for _ in 0..<6 {
            if !app.buttons["returnLatestButton"].exists { break }
            messages.swipeUp()
        }
        wait { !app.buttons["returnLatestButton"].exists }
        messages.swipeDown()
        XCTAssertTrue(app.buttons["returnLatestButton"].waitForExistence(timeout:5))
        app.buttons["returnLatestButton"].tap()
        wait { !app.buttons["returnLatestButton"].exists }
        XCTAssertTrue(app.buttons["customizationButton"].isHittable)
        XCTAssertTrue(app.buttons["customizationButton"].isHittable)
        XCUIDevice.shared.orientation = .landscapeLeft
        wait {app.frame.width>app.frame.height && self.number(self.state(app),"cameraAspect")>1 && self.state(app)["framingMotionActive"] as? Bool == false}
        capture("05-landscape")
        input.tap();input.typeText("保留这段草稿")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5))
        wait {input.frame.maxY <= app.keyboards.firstMatch.frame.minY+1}
        XCTAssertTrue(app.buttons["sendMessageButton"].isHittable)
        capture("06-landscape-keyboard")
        app.buttons["dismissChatKeyboardButton"].tap()
        XCUIDevice.shared.orientation = .portrait
        wait {app.frame.height>app.frame.width && self.number(self.state(app),"cameraAspect")<1 && self.state(app)["framingMotionActive"] as? Bool == false}
        XCTAssertTrue((input.value as? String ?? "").contains("保留这段草稿"))
        XCTAssertEqual(app.descendants(matching:.scrollBar).count,0)
        capture("07-restored-portrait")
    }

    @MainActor func testOtherCharacterHeadsRemainInteractive() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for model in ["studio-robot","hatsune-miku"] {
            app.launchArguments = ["--ui-testing","--companion-testing","--preview-companion"]
            if model == "hatsune-miku" { app.launchArguments.append("--preview-miku") }
            app.launch()
            XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
            wait { self.state(app)["name"] as? String == "state" && self.state(app)["modelId"] as? String == model }
            let initial = state(app), headY = number(initial,"headY") * app.frame.height
            XCTAssertGreaterThan(headY,app.buttons["viewerBackButton"].frame.maxY)
            XCTAssertLessThan(headY,app.buttons["customizationButton"].frame.minY)
            let taps = number(initial,"headTapCount")
            app.coordinate(withNormalizedOffset:CGVector(dx:number(initial,"headX"),dy:number(initial,"headY"))).press(forDuration:0.12)
            wait { self.number(self.state(app),"headTapCount") > taps }
            capture(model + "-full-stage")
            app.terminate()
        }
    }
    @MainActor func testStageKeyboardConversationAndNight() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--companion-testing","--preview-companion","--preview-human"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        wait { self.state(app)["name"] as? String == "state" }
        let stage = app.images["characterStage"]
        XCTAssertGreaterThan(stage.frame.height,app.frame.height * 0.95,"The room must extend behind the conversation")
        XCTAssertGreaterThan(stage.frame.width,app.frame.width * 0.95)
        let chat = app.descendants(matching:.any)["companionPanel"].firstMatch
        let messages = app.scrollViews["chatMessages"]
        XCTAssertEqual(chat.frame.height / app.frame.height,0.5,accuracy:0.02,"Conversation should occupy half the screen")
        XCTAssertGreaterThan(messages.frame.height,app.frame.height * 0.24,"History must retain useful space after the controls")
        capture("01-full-stage")

        let initial = state(app), taps = number(initial,"headTapCount")
        let headY = number(initial,"headY") * app.frame.height
        XCTAssertLessThan(headY,app.buttons["customizationButton"].frame.minY,"The chat overlay must leave the face exposed")
        app.coordinate(withNormalizedOffset:CGVector(dx:number(initial,"headX"),dy:number(initial,"headY"))).press(forDuration:0.12)
        wait { self.number(self.state(app),"headTapCount") > taps }

        let input = app.textViews["chatInput"].exists ? app.textViews["chatInput"] : app.textFields["chatInput"]
        input.tap(); input.typeText("hello")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5))
        XCTAssertLessThanOrEqual(input.frame.maxY,app.keyboards.firstMatch.frame.minY)
        XCTAssertGreaterThan(input.frame.minY,headY,"Typing must leave the character's face visible")
        capture("02-keyboard")
        app.buttons["sendMessageButton"].tap()
        XCTAssertTrue(app.staticTexts.matching(identifier:"assistantMessage").firstMatch.waitForExistence(timeout:20))
        wait { !app.keyboards.firstMatch.exists }
        wait { !app.buttons["stopReplyButton"].exists }
        for text in ["今天有点累","分享一件开心的事"] {
            input.tap();input.typeText(text);app.buttons["sendMessageButton"].tap()
            wait { !app.buttons["stopReplyButton"].exists }
        }
        capture("03-conversation")
        let beforeScroll = state(app)
        messages.swipeDown()
        XCTAssertEqual(number(state(app),"gestureCount"),number(beforeScroll,"gestureCount"),"History scrolling must not rotate the character")
        XCTAssertTrue(app.buttons["returnLatestButton"].waitForExistence(timeout:3))
        capture("03a-earlier-messages")
        app.buttons["returnLatestButton"].tap()

        app.openCustomization("appearance")
        XCTAssertTrue(app.buttons["closeStudioButton"].waitForExistence(timeout:5))
        app.segmentedControls["studioTabs"].buttons["空间"].tap()
        app.segmentedControls["studio-背景"].buttons["静夜"].tap()
        app.closeCustomizationPage("closeStudioButton")
        wait { (self.state(app)["studio"] as? [String:Any])?["room"] as? String == "evening" }
        capture("04-night-conversation")
        XCTAssertTrue(app.buttons["customizationButton"].isHittable)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            wait { app.frame.width > app.frame.height }
            XCTAssertGreaterThan(stage.frame.width,app.frame.width * 0.95)
            XCTAssertGreaterThan(stage.frame.height,app.frame.height * 0.95)
            XCTAssertTrue(input.isHittable)
            capture("05-ipad-landscape")
            input.tap(); input.typeText("hello")
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5))
            XCTAssertLessThanOrEqual(input.frame.maxY,app.keyboards.firstMatch.frame.minY)
            XCTAssertGreaterThan(input.frame.minX,app.frame.midX,"Landscape typing must leave the central face unobstructed")
            capture("06-ipad-landscape-keyboard")
        }
    }
    @MainActor private func state(_ app:XCUIApplication) -> [String:Any] {
        guard let raw = app.buttons["customizationButton"].value as? String,let data = raw.data(using:.utf8),
            let event = try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return [:] }
        return event
    }
    private func number(_ value:[String:Any],_ key:String) -> Double { (value[key] as? NSNumber)?.doubleValue ?? -999 }
    @MainActor private func wait(_ condition:@escaping () -> Bool) {
        let predicate = NSPredicate { _,_ in MainActor.assumeIsolated { condition() } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:nil)],timeout:12),.completed)
    }
    @MainActor private func capture(_ name:String) {
        let attachment = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let app = XCUIApplication()
        let panel = app.descendants(matching:.any)["companionPanel"].firstMatch.frame
        let history = app.scrollViews["chatMessages"].frame
        let metrics: [String:Double] = ["screenHeight":app.frame.height,"panelTop":panel.minY,
            "panelHeight":panel.height,"messagesTop":history.minY,"messagesHeight":history.height]
        if let data = try? JSONSerialization.data(withJSONObject:metrics,options:[.prettyPrinted,.sortedKeys]) {
            let geometry = XCTAttachment(data:data,uniformTypeIdentifier:"public.json")
            geometry.name = name + "-geometry"; geometry.lifetime = .keepAlways; add(geometry)
        }
    }
}
