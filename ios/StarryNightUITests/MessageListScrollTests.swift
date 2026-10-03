import XCTest

final class MessageListScrollTests:XCTestCase {
    @MainActor func testVerticalScrollingAndHorizontalActionsFromWholeRows() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--message-scroll-fixture","-starry.app.language.v1","zh-Hans"]
        app.launch();defer {app.terminate()}
        let list=app.scrollViews["messageList"]
        XCTAssertTrue(list.waitForExistence(timeout:30))
        let first=app.buttons["message-anime-chiffon"]
        XCTAssertTrue(first.isHittable)
        let top=first.frame.minY
        // Start on a real row, including its text, not only empty list padding.
        let start=list.coordinate(withNormalizedOffset:CGVector(dx:0.55,dy:0.75))
        start.press(forDuration:0.08,thenDragTo:list.coordinate(withNormalizedOffset:CGVector(dx:0.55,dy:0.18)))
        let last=app.buttons["message-anime-torao"]
        XCTAssertTrue(!first.isHittable || first.frame.minY<top-50)
        // The current 41-role roster needs several drags; do not assume one
        // screen-height gesture reaches the last row of an older small roster.
        for _ in 0..<8 {if last.exists && last.isHittable {break};list.swipeUp()}
        XCTAssertTrue(last.isHittable)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'deleteConversation-'")).count,0)
        // A mostly vertical diagonal still belongs to the list.
        list.coordinate(withNormalizedOffset:CGVector(dx:0.52,dy:0.20)).press(forDuration:0.08,
            thenDragTo:list.coordinate(withNormalizedOffset:CGVector(dx:0.62,dy:0.83)))
        for _ in 0..<8 {if first.exists && first.frame.minY>=list.frame.minY-1 {break};list.swipeDown()}
        XCTAssertTrue(first.isHittable)
        first.swipeLeft()
        let remove=app.buttons["deleteConversation-anime-chiffon"]
        XCTAssertTrue(remove.waitForExistence(timeout:3));XCTAssertTrue(remove.isHittable)
        // Even when actions are open, a vertical drag can scroll the list.
        let previous=first.frame.minY
        // Keep x identical after opening shrinks the content's frame. Using
        // different row/list coordinate spaces can accidentally drag sideways
        // or start above a partially clipped row instead of on its content.
        let verticalStart=first.coordinate(withNormalizedOffset:CGVector(dx:0.35,dy:0.7))
        verticalStart.press(forDuration:0.08,thenDragTo:verticalStart.withOffset(CGVector(dx:0,dy:-100)))
        XCTAssertTrue(!first.isHittable || first.frame.minY<previous-20)
        list.swipeDown();XCTAssertTrue(first.isHittable)
        first.swipeRight()
        let closed=NSPredicate { _,_ in !remove.exists }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:closed,object:nil)],timeout:4),.completed)
        XCTAssertTrue(app.otherElements["messagesPage"].exists)
    }
}
