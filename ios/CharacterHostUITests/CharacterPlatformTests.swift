import XCTest
import UIKit
final class CharacterPlatformTests: XCTestCase {
    @MainActor func testIndependentPackageAndSemanticConversation() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing","--companion-testing"]
        app.launch()
        let card = app.buttons["card-sample-robot"]
        XCTAssertTrue(app.buttons["chat-real-woman"].waitForExistence(timeout:20))
        app.selectHomeModel("sample-robot")
        XCTAssertTrue(card.isHittable); card.tap()
        XCTAssertTrue(app.buttons["characterActionsMenu"].waitForExistence(timeout:60))
        app.performCharacterAction("ThumbsUp")
        wait(app) { (($0["characterPlatform"] as? [String:Any])?["lastAction"] as? String) == "ThumbsUp" }
        capture("01-package-action")
        app.openCustomization("appearance")
        let color = app.buttons["parameter-body-tone-2"]
        XCTAssertTrue(color.waitForExistence(timeout:8)); color.tap()
        app.closeCustomizationPage("closeStudioButton")
        XCTAssertTrue(app.buttons["viewerBackButton"].waitForExistence(timeout:6))
        capture("02-declared-appearance")
        app.buttons["viewerBackButton"].tap()
        let chat=app.buttons["chat-sample-robot"]
        app.selectHomeModel("sample-robot"); chat.tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:45))
        send("今天有点难过",app)
        wait(app) { event in
            let state=event["characterPlatform"] as? [String:Any] ?? [:]
            return (state["expressionCues"] as? Int ?? 0)>0 && (state["effectCues"] as? Int ?? 0)>0
        }
        capture("03-care-expression-and-effect")
        let previous=platform(app)["effectCues"] as? Int ?? 0
        send("今天成功完成了计划，很开心",app)
        wait(app) { event in ((event["characterPlatform"] as? [String:Any])?["effectCues"] as? Int ?? 0)>previous }
        capture("04-joy-reply")
        send("跳舞吧",app)
        wait(app) { (($0["characterPlatform"] as? [String:Any])?["lastAction"] as? String)=="Dance" }
        // An accepted animation is insufficient: the camera must keep the actual actor in view.
        wait(app) { event in
            guard let target=event["framingDistanceTarget"] as? Double else { return false }
            return target>0 && target<25
        }
        capture("05-semantic-dance")
        app.buttons["viewerBackButton"].tap()
        let old=app.buttons["chat-real-woman"]
        app.selectHomeModel("real-woman"); old.tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:30))
        send("你好",app)
        wait(app) { event in
            let state=event["characterPlatform"] as? [String:Any] ?? [:]
            return (state["lastAction"] as? String)=="Greet" && (state["bodyCues"] as? Int ?? 0)>1
        }
        capture("06-legacy-character-contract")
    }
    @MainActor private func send(_ text:String,_ app:XCUIApplication) {
        let input=app.textViews["chatInput"]
        XCTAssertTrue(input.waitForExistence(timeout:8)); input.tap(); input.typeText(text); app.buttons["sendMessageButton"].tap()
    }
    @MainActor private func event(_ app:XCUIApplication)->[String:Any] {
        guard let value=app.buttons["customizationButton"].value as? String,let data=value.data(using:.utf8),let json=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return [:] }
        return json
    }
    @MainActor private func platform(_ app:XCUIApplication)->[String:Any] { event(app)["characterPlatform"] as? [String:Any] ?? [:] }
    @MainActor private func wait(_ app:XCUIApplication,_ condition:@escaping ([String:Any])->Bool) {
        let predicate=NSPredicate { _,_ in MainActor.assumeIsolated { condition(self.event(app)) } }
        expectation(for:predicate,evaluatedWith:app);waitForExpectations(timeout:30)
    }
    @MainActor private func capture(_ name:String) {
        let image=XCTAttachment(screenshot:XCUIScreen.main.screenshot());image.name=name;image.lifetime = .keepAlways;add(image)
    }
}
