import XCTest
import UIKit

final class ConversationPolishTests:XCTestCase {
    @MainActor func testLoadingCapsuleMatchesLiveAndCannotOpenProfile() {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--test-ready-delay=14"]
        app.launch();defer {app.terminate()}
        let loading=app.buttons["preparingIdentityButton"]
        XCTAssertTrue(loading.waitForExistence(timeout:10))
        let artwork=app.otherElements["conversationPreparingArtwork"]
        XCTAssertTrue(artwork.exists)
        XCTAssertEqual(artwork.frame.minY,app.frame.minY,accuracy:1)
        XCTAssertEqual(artwork.frame.height,app.frame.height,accuracy:1)
        XCTAssertLessThanOrEqual(artwork.frame.minX,app.frame.minX)
        XCTAssertGreaterThanOrEqual(artwork.frame.maxX,app.frame.maxX)
        let frame=loading.frame
        XCTAssertEqual(frame.minX,16,accuracy:1)
        XCTAssertEqual(frame.height,44,accuracy:1)
        loading.coordinate(withNormalizedOffset:CGVector(dx:0.35,dy:0.5)).tap()
        let hint=app.staticTexts["preparingIdentityHint"]
        XCTAssertTrue(hint.waitForExistence(timeout:3))
        XCTAssertGreaterThan(hint.frame.minY,loading.frame.maxY)
        XCTAssertEqual(loading.frame,frame,"Hint overlays the cover without moving its capsule")
        XCTAssertFalse(app.buttons["closeCharacterDetails"].exists)
        XCTAssertFalse(app.buttons["customizationButton"].exists)
        capture("full-screen-breathing-loading-hint")
        wait {!hint.exists}
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        let live=app.otherElements["conversationIdentityCapsule"]
        XCTAssertTrue(live.exists)
        XCTAssertEqual(live.frame.minX,frame.minX,accuracy:1)
        XCTAssertEqual(live.frame.minY,frame.minY,accuracy:1)
        XCTAssertEqual(live.frame.width,frame.width,accuracy:1)
        XCTAssertEqual(live.frame.height,frame.height,accuracy:1)
        app.buttons["customizationButton"].tap()
        XCTAssertTrue(app.buttons["closeCharacterDetails"].waitForExistence(timeout:5))
    }
    @MainActor func testReplyRightAlignmentBlankDismissAndContinuousAtmosphere() {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--smart-reply-layout-fixture"]
        app.launch();defer {app.terminate()}
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.waitForCharacter {$0["nativeHoldAvailable"] as? Bool == true}
        let open=app.buttons["smartReplyButton"],panel=app.otherElements["smartRepliesPanel"]
        for orientation in [UIDeviceOrientation.portrait,.landscapeLeft] {
            XCUIDevice.shared.orientation=orientation
            wait {(app.frame.width>app.frame.height)==orientation.isLandscape}
            open.tap();XCTAssertTrue(panel.waitForExistence(timeout:5))
            XCTAssertEqual(panel.frame.maxX,open.frame.maxX+4,accuracy:1,"Match the outer composer right edge")
            XCTAssertLessThanOrEqual(panel.frame.width,309) // Includes the subpixel border.
            capture("right-aligned-quick-replies-\(orientation.rawValue)")
            // Upper background, far from the composer, chips and the character's face.
            app.coordinate(withNormalizedOffset:CGVector(dx:0.09,dy:0.30)).tap()
            wait {!panel.exists}
        }
        XCUIDevice.shared.orientation = .portrait
        wait {app.frame.height>app.frame.width}
        open.tap();XCTAssertTrue(panel.waitForExistence(timeout:5))
        let rotations=app.characterRuntime["previewRotationCount"] as? Int ?? 0
        app.coordinate(withNormalizedOffset:CGVector(dx:0.2,dy:0.3)).press(forDuration:0.06,
            thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.45,dy:0.32)),withVelocity:.slow,thenHoldForDuration:0.1)
        app.waitForCharacter {($0["previewRotationCount"] as? Int ?? 0)>rotations}
        XCTAssertTrue(panel.exists,"A drag remains a model gesture, not a dismissing tap")
        app.coordinate(withNormalizedOffset:CGVector(dx:0.09,dy:0.30)).tap()
        wait {!panel.exists}
        app.openConversationSettings("atmosphere")
        let slider=app.sliders["atmosphereLevelSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout:5))
        for value in [0.0,0.25,0.5,0.75,1.0] {
            slider.adjust(toNormalizedSliderPosition:value)
            // Apple's native adjustment is best-effort, not exact: the iOS 26
            // thumb drag can land several percent from the requested target.
            wait {abs(self.intensity(of:slider)-value)<(value==0 || value==1 ? 0.01 : 0.09)}
        }
        slider.adjust(toNormalizedSliderPosition:0.37)
        wait {abs(self.intensity(of:slider)-0.37)<0.09}
        let actual=self.intensity(of:slider)
        XCTAssertGreaterThan(abs(actual*4-(actual*4).rounded()),0.04,"Intermediate values must not snap to an old detent")
        let saved=slider.value as? String
        capture("continuous-atmosphere-thumb")
        app.buttons["closeCharacterViewEditor"].tap()
        app.openConversationSettings("atmosphere")
        XCTAssertEqual(slider.value as? String,saved)
    }
    @MainActor func testLeftSwipeInlineActionsAndDeletionConfirmation() {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch();defer {app.terminate()}
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.buttons["tab-messages"].tap()
        let row=app.buttons["message-anime-kipfel"],remove=app.buttons["deleteConversation-anime-kipfel"]
        XCTAssertTrue(row.waitForExistence(timeout:6));let initial=row.frame
        row.swipeRight()
        XCTAssertFalse(remove.exists,"Rightward swipes never reveal conversation actions")
        XCTAssertEqual(row.frame,initial)
        row.swipeLeft()
        XCTAssertTrue(remove.waitForExistence(timeout:5));XCTAssertTrue(remove.isHittable)
        let hide=app.buttons["hideConversation-anime-kipfel"]
        XCTAssertGreaterThanOrEqual(hide.frame.minX,row.frame.maxX)
        XCTAssertGreaterThan(remove.frame.minX,hide.frame.maxX)
        XCTAssertEqual(remove.frame.maxX,initial.maxX,accuracy:1)
        XCTAssertEqual(row.frame.minX,initial.minX,accuracy:1)
        let redPoint=CGPoint(x:remove.frame.minX+9,y:remove.frame.minY+9)
        assertRed(at:redPoint,app:app)
        capture("left-swipe-inline-actions")
        remove.tap()
        XCTAssertTrue(app.alerts["删除对话和记忆？"].waitForExistence(timeout:5))
        assertRed(at:redPoint,app:app)
        capture("deletion-confirmation-keeps-inline-actions")
        app.alerts.buttons["取消"].firstMatch.tap()
        wait {!remove.exists && abs(row.frame.width-initial.width)<1}
        XCTAssertTrue(row.exists)
        row.swipeLeft()
        app.buttons["hideConversation-anime-kipfel"].tap()
        XCTAssertTrue(app.buttons["undoHideConversation"].waitForExistence(timeout:5))
        XCTAssertFalse(row.exists)
        app.buttons["undoHideConversation"].tap()
        XCTAssertTrue(row.waitForExistence(timeout:5))
        row.tap();XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:12))
    }
    @MainActor func testComposerPromptsShareLayoutAcrossInputModes() {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--voice-atmosphere-check"]
        app.launch();defer {app.terminate()}
        let input=app.textViews["chatInput"],mode=app.buttons["inputModeButton"]
        XCTAssertTrue(input.waitForExistence(timeout:10))
        let frame=input.frame,toggle=mode.frame
        capture("composer-keyboard-prompt")
        mode.tap()
        let hold=app.buttons["holdToTalkButton"]
        XCTAssertTrue(hold.waitForExistence(timeout:5))
        XCTAssertEqual(hold.frame.minX,frame.minX,accuracy:1)
        XCTAssertEqual(hold.frame.midY,frame.midY,accuracy:1)
        XCTAssertEqual(hold.frame.width,frame.width,accuracy:1)
        XCTAssertEqual(mode.frame,toggle)
        capture("composer-hold-prompt")
        mode.tap();XCTAssertTrue(input.waitForExistence(timeout:5))
        XCTAssertEqual(input.frame,frame)
    }
    @MainActor private func assertRed(at point:CGPoint,app:XCUIApplication,file:StaticString=#filePath,line:UInt=#line) {
        guard let image=XCUIScreen.main.screenshot().image.cgImage else {XCTFail("Screenshot missing",file:file,line:line);return}
        let width=image.width,height=image.height
        var pixels=[UInt8](repeating:0,count:width*height*4)
        let context=CGContext(data:&pixels,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        let x=Int(point.x/app.frame.width*Double(width)),y=Int(point.y/app.frame.height*Double(height))
        let offset=(y*width+x)*4,r=Double(pixels[offset]),g=Double(pixels[offset+1]),b=Double(pixels[offset+2])
        XCTAssertTrue(r>g*1.45 && r>b*1.25,"Red action must remain visible, RGB=\(r),\(g),\(b)",file:file,line:line)
    }
    @MainActor private func wait(_ predicate:@escaping ()->Bool) {
        let check=XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in MainActor.assumeIsolated {predicate()}},object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[check],timeout:7),.completed)
    }
    @MainActor private func intensity(of slider:XCUIElement)->Double {
        let text=slider.value as? String ?? ""
        if text=="关闭" {return 0}
        return (Double(text.replacingOccurrences(of:"%",with:"")) ?? -100)/100
    }
    @MainActor private func capture(_ name:String) {
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
    }
}
