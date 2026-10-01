import XCTest
import UIKit

/// Real catalog, renderer, covers and native touch routing. No paid AI calls.
final class CharacterPortraitCompletionTests:XCTestCase {
    @MainActor func testRosterPortraitsAndBidirectionalZoom() {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch();defer{app.terminate()}
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:75))
        let roles=[("anime-kipfel","琪宝"),("anime-mamehinata","豆日向"),("anime-chiffon","戚风"),
            ("anime-karin","卡琳"),("anime-torao","小虎"),("anime-ichigo","草莓"),("anime-mafuyu","真冬"),
            ("anime-lime","青柠"),("anime-nozomi","望"),("anime-siska","西卡"),("anime-plum","小梅")]
        for (id,name) in roles {
            app.buttons["tab-discover"].tap()
            let search=app.textFields["discoverSearch"]
            XCTAssertTrue(search.waitForExistence(timeout:8))
            if app.buttons["clearDiscoverSearch"].exists {app.buttons["clearDiscoverSearch"].tap()}
            search.tap();search.typeText(name)
            let card=app.buttons["discover-open-"+id]
            XCTAssertTrue(card.waitForExistence(timeout:8));capture(id+"-cover",app)
            card.tap();XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:8))
            capture(id+"-profile",app)
            app.buttons["profileChatButton"].tap()
            app.waitForCharacter({$0["modelId"] as? String == id && ($0["inspectionGestureRevision"] as? Int ?? 0)>=14 && ($0["stableRenderedFrames"] as? Int ?? 0)>=3},timeout:60)
            app.buttons["characterPositionButton"].tap()
            XCTAssertTrue(app.buttons["resetCharacterView"].waitForExistence(timeout:8))
            app.buttons["resetCharacterView"].tap()
            app.waitForCharacter {abs(self.scale($0)-1)<0.002 && $0["inspectionMoving"] as? Bool == false}
            app.buttons["closeCharacterViewEditor"].tap()
            app.waitForCharacter {$0["viewEditorOpen"] as? Bool == false}
            let state=app.characterRuntime
            let y=(state["headY"] as? NSNumber)?.doubleValue ?? -1
            XCTAssertGreaterThan(y,0.09,"Face cannot hide behind the Dynamic Island")
            XCTAssertLessThan(y,0.48,"Default face must stay in the upper portrait")
            let voice=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","messageVoice-")).firstMatch
            XCTAssertTrue((voice.value as? String ?? "").contains("durationSource:measured"),"Packaged introductions already know their audio duration, including English")
            capture(id+"-portrait",app)
            app.buttons["characterPositionButton"].tap()
            app.waitForCharacter {$0["viewEditorOpen"] as? Bool == true}
            pinch(app,ratio:1.22)
            app.waitForCharacter {self.scale($0)>1.10 && $0["inspectionMoving"] as? Bool == false}
            app.buttons["resetCharacterView"].tap()
            app.waitForCharacter {abs(self.scale($0)-1)<0.002}
            pinch(app,ratio:0.72)
            app.waitForCharacter {self.scale($0)<0.90 && $0["inspectionMoving"] as? Bool == false}
            capture(id+"-wider",app)
            app.buttons["resetCharacterView"].tap()
            app.waitForCharacter {abs(self.scale($0)-1)<0.002}
            app.buttons["closeCharacterViewEditor"].tap()
        }
        app.buttons["tab-messages"].tap()
        let row=app.buttons["message-anime-plum"]
        XCTAssertTrue(row.waitForExistence(timeout:8));row.swipeRight()
        app.buttons["deleteConversation-anime-plum"].tap()
        XCTAssertTrue(app.alerts["删除对话和记忆？"].waitForExistence(timeout:5))
        capture("conversation-delete-confirmation",app)
        app.alerts.buttons["取消"].tap()
        XCTAssertTrue(row.exists,"Cancelling must preserve the conversation")
    }
    private func scale(_ state:[String:Any])->Double {
        (state["inspectionPose"] as? [String:Double])?["scale"] ?? -1
    }
    @MainActor private func pinch(_ app:XCUIApplication,ratio:CGFloat) {
        let done=expectation(description:"Adjust portrait scale")
        SNSynthesizePreviewPinch(CGPoint(x:app.frame.midX,y:app.frame.height*0.34),ratio) {error in
            XCTAssertNil(error);done.fulfill()
        }
        wait(for:[done],timeout:8)
    }
    @MainActor private func capture(_ name:String,_ app:XCUIApplication) {
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
        if !app.characterRuntime.isEmpty,let data=try? JSONSerialization.data(withJSONObject:app.characterRuntime,options:[.prettyPrinted,.sortedKeys]) {
            let state=XCTAttachment(data:data,uniformTypeIdentifier:"public.json");state.name=name+"-runtime";state.lifetime = .keepAlways;add(state)
        }
    }
}
