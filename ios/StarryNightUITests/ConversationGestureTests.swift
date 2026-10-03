import XCTest

final class ConversationGestureTests:XCTestCase {
    @MainActor private func launch()->XCUIApplication {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--conversation-gesture-fixture","-starry.app.language.v1","zh-Hans"]
        app.launch()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:65))
        app.waitForCharacter {($0["inspectionGestureRevision"] as? Int ?? 0)>=11}
        XCTAssertTrue(app.staticTexts["手势测试：最后一条角色消息，可以在这段文字上拖动。"].waitForExistence(timeout:8))
        // The blocked paid greeting shows a test-only notice below the list.
        // Dismiss it before deriving touch coordinates from visible messages.
        let notice=app.buttons.matching(NSPredicate(format:"label == %@","关闭提示")).firstMatch
        if notice.exists {notice.tap()}
        let latest=NSPredicate { _,_ in app.scrollViews["chatMessages"].value as? String == "最新消息" }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:latest,object:nil)],timeout:5),.completed)
        return app
    }
    @MainActor private func count(_ app:XCUIApplication)->Int {app.characterRuntime["previewRotationCount"] as? Int ?? 0}
    @MainActor private func point(_ app:XCUIApplication,_ position:CGPoint)->XCUICoordinate {
        app.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:position.x,dy:position.y))
    }
    @MainActor private func drag(_ app:XCUIApplication,from:CGPoint,dx:CGFloat,dy:CGFloat) {
        point(app,from).press(forDuration:0.06,thenDragTo:point(app,CGPoint(x:from.x+dx,y:from.y+dy)),withVelocity:.slow,thenHoldForDuration:0.15)
    }
    @MainActor private func assertRotates(_ app:XCUIApplication,from:CGPoint,dx:CGFloat,dy:CGFloat) {
        let before=app.characterRuntime,started=count(app)
        let saved=before["viewPoseSaved"] as? [String:Double]
        let returns=before["previewRotationReturnCount"] as? Int ?? 0
        let latest=app.staticTexts["手势测试：最后一条角色消息，可以在这段文字上拖动。"]
        let oldY=latest.frame.minY
        XCTAssertTrue(app.scrollViews["chatMessages"].frame.contains(from),"Start inside the actual chat viewport")
        drag(app,from:from,dx:dx,dy:dy)
        app.waitForCharacter {($0["previewRotationReturnCount"] as? Int ?? 0)>returns}
        XCTAssertEqual(count(app),started+1)
        XCTAssertEqual(app.characterRuntime["viewPoseSaved"] as? [String:Double],saved)
        XCTAssertEqual(latest.frame.minY,oldY,accuracy:1,"Character pans must not move the chat list")
        XCTAssertEqual(app.characterRuntime["viewEditorOpen"] as? Bool,false)
    }
    @MainActor func testWhitespaceAndHorizontalMessagesRotate() {
        let app=launch();defer {app.terminate()}
        let chat=app.scrollViews["chatMessages"]
        let blank=CGPoint(x:app.frame.maxX-10,y:chat.frame.maxY-55)
        assertRotates(app,from:blank,dx:-85,dy:0)
        assertRotates(app,from:blank,dx:0,dy:-85)
        for text in ["手势测试：最后一条角色消息，可以在这段文字上拖动。","手势测试：最后一条用户消息"] {
            let frame=app.staticTexts[text].frame
            assertRotates(app,from:CGPoint(x:frame.midX,y:frame.midY),dx:80,dy:0)
        }
        let user=app.staticTexts["手势测试：最后一条用户消息"].frame
        assertRotates(app,from:CGPoint(x:40,y:user.midY),dx:160,dy:0)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="chat-pans-return-without-scroll";shot.lifetime = .keepAlways;add(shot)
    }
    @MainActor func testVerticalAndDiagonalMessagesScrollAndControlsStillWork() {
        let app=launch();defer {app.terminate()}
        let chat=app.scrollViews["chatMessages"],started=count(app)
        for dx:CGFloat in [0,30] {
            let frame=app.staticTexts["手势测试：最后一条角色消息，可以在这段文字上拖动。"].frame
            drag(app,from:CGPoint(x:frame.midX,y:frame.midY),dx:dx,dy:110)
            let history=NSPredicate { _,_ in chat.value as? String == "历史消息" }
            XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:history,object:nil)],timeout:5),.completed)
            XCTAssertEqual(count(app),started,"Vertical/diagonal message drags belong to native scrolling")
            let latest=app.buttons["returnLatestButton"]
            XCTAssertTrue(latest.waitForExistence(timeout:4));latest.tap()
            let bottom=NSPredicate { _,_ in chat.value as? String == "最新消息" }
            XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:bottom,object:nil)],timeout:5),.completed)
        }
        let voice=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","messageVoice-")).allElementsBoundByIndex.last!
        voice.tap()
        XCTAssertEqual(count(app),started,"Audio controls are not rotation handles")
        let input=app.textViews["chatInput"];input.tap();input.typeText("Keep draft")
        XCTAssertEqual(input.value as? String,"Keep draft")
        XCTAssertEqual(count(app),started,"Text entry keeps its own touches")
    }
    @MainActor func testInitialDirectionStaysLockedWhenFingerChangesDirection() {
        let app=launch();defer {app.terminate()}
        let chat=app.scrollViews["chatMessages"]
        let text=app.staticTexts["手势测试：最后一条角色消息，可以在这段文字上拖动。"]
        func turn(horizontalFirst:Bool) {
            let from=CGPoint(x:text.frame.midX,y:text.frame.midY)
            let bend=CGPoint(x:from.x+(horizontalFirst ? 50 : 0),y:from.y+(horizontalFirst ? 0 : 70))
            let end=CGPoint(x:bend.x+(horizontalFirst ? 0 : 65),y:bend.y+(horizontalFirst ? -110 : 0))
            let done=expectation(description:"drag changes direction after recognition")
            SNSynthesizeConversationTurn(from,bend,end) {error in XCTAssertNil(error);done.fulfill()}
            wait(for:[done],timeout:8)
        }
        let before=app.characterRuntime,started=count(app),oldY=text.frame.minY
        let returns=before["previewRotationReturnCount"] as? Int ?? 0
        turn(horizontalFirst:true)
        app.waitForCharacter {($0["previewRotationReturnCount"] as? Int ?? 0)>returns}
        XCTAssertEqual(count(app),started+1)
        XCTAssertEqual(text.frame.minY,oldY,accuracy:1,"A horizontal start keeps rotating after a vertical bend")
        XCTAssertEqual(chat.value as? String,"最新消息")
        turn(horizontalFirst:false)
        let history=NSPredicate { _,_ in chat.value as? String == "历史消息" }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:history,object:nil)],timeout:5),.completed)
        XCTAssertEqual(count(app),started+1,"A vertical start keeps scrolling after a horizontal bend")
        XCTAssertGreaterThan(text.frame.minY-oldY,30,"Verify real content movement, not only a scroll-state flag")
        XCTAssertEqual(app.characterRuntime["viewPoseSaved"] as? [String:Double],before["viewPoseSaved"] as? [String:Double])
    }
}
