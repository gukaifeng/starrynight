import XCTest
import UIKit

extension XCUIApplication {
    @MainActor func performCharacterAction(_ id:String,file:StaticString = #filePath,line:UInt = #line) {
        if buttons["characterActionsMenu"].exists { buttons["characterActionsMenu"].tap() }
        let action = buttons["action" + id + "Button"]
        XCTAssertTrue(action.waitForExistence(timeout:5),file:file,line:line)
        action.tap()
    }
    @MainActor var characterRuntime: [String:Any] {
        guard let raw = buttons["customizationButton"].value as? String,
              let json = try? JSONSerialization.jsonObject(with:Data(raw.utf8)) as? [String:Any] else { return [:] }
        return json
    }
    @MainActor func waitForCharacter(_ condition:@escaping ([String:Any]) -> Bool,timeout:TimeInterval = 12,file:StaticString = #filePath,line:UInt = #line) {
        let predicate = NSPredicate { _,_ in MainActor.assumeIsolated { condition(self.characterRuntime) } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:nil)],timeout:timeout),.completed,file:file,line:line)
    }
    @MainActor func selectHomeModel(_ id:String,file:StaticString = #filePath,line:UInt = #line) {
        let cardID = ["real-woman":"humanModelCard","studio-robot":"modelCard","hatsune-miku":"mikuModelCard"][id] ?? "card-"+id
        XCTAssertTrue(otherElements["homeGallery"].waitForExistence(timeout:15),file:file,line:line)
        for _ in 0..<8 {
            if buttons[cardID].exists && buttons[cardID].isHittable {
                let settled = NSPredicate { _,_ in MainActor.assumeIsolated {
                    self.buttons["chat-"+id].exists && self.frame.contains(self.buttons["chat-"+id].frame)
                } }
                XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:settled,object:nil)],timeout:5),.completed,file:file,line:line)
                return
            }
            let pages = buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","homePage-")).allElementsBoundByIndex
            let current = pages.firstIndex { $0.value as? String == "已选中" } ?? 0
            if !pages.isEmpty { pages[(current+1)%pages.count].tap() }
        }
        XCTFail("Character is not reachable: "+id,file:file,line:line)
    }
}

final class HomeCarouselTests:XCTestCase {
    @MainActor func testEveryPortraitIntroductionAndChatButtonOpenChat() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing","--companion-testing"]
        app.launch()
        for (id,card,action) in [("real-woman","humanModelCard","Wave"),("studio-robot","modelCard","Jump"),
                                 ("hatsune-miku","mikuModelCard","Cheer"),("sample-robot","card-sample-robot","ThumbsUp")] {
            app.selectHomeModel(id)
            for entry in [card,"intro-" + id,"chat-" + id] {
                XCTAssertTrue(app.buttons[entry].isHittable); app.buttons[entry].tap()
                XCTAssertTrue(app.buttons["characterActionsMenu"].waitForExistence(timeout:60))
                XCTAssertTrue(app.textFields["chatInput"].exists || app.textViews["chatInput"].exists)
                XCTAssertFalse(app.scrollViews["characterActionsScroll"].exists)
                XCTAssertFalse(app.buttons["action" + action + "Button"].exists)
                app.waitForCharacter { $0["modelId"] as? String == id }
                if entry == "chat-" + id {
                    let messages = app.staticTexts.matching(identifier:"assistantMessage").count
                    let count = app.characterRuntime["actionCount"] as? Int ?? 0
                    app.performCharacterAction(action)
                    app.waitForCharacter {
                        ($0["actionCount"] as? Int ?? 0) > count &&
                        ($0["characterPlatform"] as? [String:Any])?["lastAction"] as? String == action
                    }
                    XCTAssertFalse(app.buttons["action" + action + "Button"].exists)
                    XCTAssertEqual(app.staticTexts.matching(identifier:"assistantMessage").count,messages)
                    capture("chat-" + id)
                }
                app.buttons["viewerBackButton"].tap()
                XCTAssertTrue(app.buttons["chat-" + id].waitForExistence(timeout:6))
                XCTAssertTrue(app.buttons["chat-" + id].isHittable)
            }
        }
    }
    @MainActor func testFixedHomePagingSelectionAndNavigation() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing"]
        app.launch();app.selectHomeModel("real-woman")
        let header=app.buttons["accountCenterButton"].frame
        XCTAssertTrue(app.buttons["modelCard"].isHittable)
        XCTAssertTrue(app.buttons["mikuModelCard"].isHittable)
        XCTAssertTrue(app.buttons["card-sample-robot"].isHittable)
        XCTAssertFalse(app.buttons["homeDisplayModeButton"].exists)
        capture("01-adaptive-portrait")
        for (id,card) in [("real-woman","humanModelCard"),("studio-robot","modelCard"),("hatsune-miku","mikuModelCard"),("sample-robot","card-sample-robot")] {
            XCTAssertTrue(app.frame.contains(app.buttons["chat-"+id].frame))
            XCTAssertLessThanOrEqual(app.buttons[card].frame.width,156)
            app.buttons[card].tap()
            XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
            app.waitForCharacter { $0["modelId"] as? String == id }
            app.buttons["viewerBackButton"].tap()
            XCTAssertTrue(app.buttons[card].waitForExistence(timeout:8))
            XCTAssertTrue(app.buttons[card].isHittable)
        }
        app.buttons["humanModelCard"].swipeUp()
        XCTAssertEqual(app.buttons["accountCenterButton"].frame,header)
        for orientation in [UIDeviceOrientation.landscapeLeft,.landscapeRight] {
            XCUIDevice.shared.orientation=orientation
            wait { app.frame.width>app.frame.height }
            for id in ["real-woman","studio-robot","hatsune-miku","sample-robot"] {
                app.selectHomeModel(id)
                XCTAssertTrue(app.frame.contains(app.buttons["chat-"+id].frame))
            }
            capture(orientation == .landscapeLeft ? "02-adaptive-landscape-left" : "03-adaptive-landscape-right")
        }
        XCUIDevice.shared.orientation = .portrait
        wait { app.frame.height>app.frame.width }
        app.openAccountAbout();app.buttons["closeAccountCenterButton"].tap()
        XCTAssertTrue(app.buttons["humanModelCard"].waitForExistence(timeout:5))
        capture("04-return-home")
    }
    @MainActor func testPagedHomePreservesSelection() {
        continueAfterFailure=false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["homePage-1"].waitForExistence(timeout:20))
        app.selectHomeModel("hatsune-miku")
        capture("05-paged-home")
        app.buttons["mikuModelCard"].swipeUp()
        XCTAssertTrue(app.buttons["mikuModelCard"].isHittable,"A vertical brush must not open a character")
        app.otherElements["homeGallery"].swipeLeft()
        wait { app.buttons["card-sample-robot"].exists && app.buttons["card-sample-robot"].isHittable }
        app.buttons["card-sample-robot"].tap()
        XCTAssertTrue(app.buttons["viewerBackButton"].waitForExistence(timeout:60))
        app.buttons["viewerBackButton"].tap()
        XCTAssertTrue(app.buttons["card-sample-robot"].waitForExistence(timeout:8))
        XCUIDevice.shared.orientation = .landscapeLeft
        wait { app.frame.width>app.frame.height && app.buttons["card-sample-robot"].isHittable }
        capture("06-paged-landscape-selection")
        XCUIDevice.shared.orientation = .portrait
        wait { app.frame.height>app.frame.width && app.buttons["card-sample-robot"].isHittable }
    }
    @MainActor private func wait(_ condition:@escaping () -> Bool) {
        let p=NSPredicate { _,_ in MainActor.assumeIsolated { condition() } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:p,object:nil)],timeout:10),.completed)
    }
    @MainActor private func capture(_ name:String) {
        let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)
    }
}
