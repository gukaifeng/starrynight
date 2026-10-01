import XCTest
import UIKit

final class ConversationPolishTests:XCTestCase {
    @MainActor func testLoadingCapsuleMatchesLiveAndCannotOpenProfile() {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--test-ready-delay=14"]
        app.launch();defer {app.terminate()}
        let loading=app.otherElements["preparingIdentityCapsule"]
        XCTAssertTrue(loading.waitForExistence(timeout:10))
        let frame=loading.frame
        XCTAssertEqual(frame.minX,16,accuracy:1)
        XCTAssertEqual(frame.height,44,accuracy:1)
        loading.coordinate(withNormalizedOffset:CGVector(dx:0.35,dy:0.5)).tap()
        XCTAssertFalse(app.buttons["closeCharacterDetails"].exists)
        XCTAssertFalse(app.buttons["customizationButton"].exists)
        capture("dimmed-loading-shared-capsule")
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
    @MainActor func testReplyRightAlignmentBlankDismissAndAtmosphereDetents() {
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
        for (value,name) in [(0.0,"关闭"),(0.25,"轻盈"),(0.5,"适中"),(0.75,"浓郁"),(1.0,"绚烂")] {
            slider.adjust(toNormalizedSliderPosition:value)
            wait {slider.value as? String == name}
        }
        capture("continuous-atmosphere-thumb")
        slider.adjust(toNormalizedSliderPosition:0.5)
        app.buttons["closeCharacterViewEditor"].tap()
        app.openConversationSettings("atmosphere")
        XCTAssertEqual(slider.value as? String,"适中")
    }
    @MainActor func testSwipeDeleteStaysRevealedUntilCancelAndHideStillWorks() {
        continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--companion-testing","--auth-testing"]
        app.launch();defer {app.terminate()}
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.buttons["tab-messages"].tap()
        let row=app.buttons["message-anime-kipfel"],remove=app.buttons["deleteConversation-anime-kipfel"]
        XCTAssertTrue(row.waitForExistence(timeout:6));let initial=row.frame
        for leading in [true,false] {
            if leading {row.swipeRight()} else {row.swipeLeft()}
            XCTAssertTrue(remove.waitForExistence(timeout:5));XCTAssertTrue(remove.isHittable)
            let redPoint=CGPoint(x:remove.frame.minX+9,y:remove.frame.minY+9)
            assertRed(at:redPoint,app:app)
            capture(leading ? "right-swipe-red-delete" : "left-swipe-red-delete")
            remove.tap()
            XCTAssertTrue(app.alerts["删除对话和记忆？"].waitForExistence(timeout:5))
            assertRed(at:redPoint,app:app) // Still red behind the alert, not an auto-closed row.
            capture("deletion-confirmation-keeps-reveal")
            app.alerts.buttons["取消"].firstMatch.tap()
            wait {!remove.exists && abs(row.frame.minX-initial.minX)<1}
            XCTAssertTrue(row.exists)
        }
        row.swipeRight()
        app.buttons["hideConversation-anime-kipfel"].tap()
        XCTAssertTrue(app.buttons["undoHideConversation"].waitForExistence(timeout:5))
        XCTAssertFalse(row.exists)
        app.buttons["undoHideConversation"].tap()
        XCTAssertTrue(row.waitForExistence(timeout:5))
        row.tap();XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:12))
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
    @MainActor private func capture(_ name:String) {
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
    }
}
