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
        XCTAssertTrue(last.isHittable)
        XCTAssertTrue(!first.isHittable || first.frame.minY<top-50)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'deleteConversation-'")).count,0)
        // A mostly vertical diagonal still belongs to the list.
        list.coordinate(withNormalizedOffset:CGVector(dx:0.52,dy:0.20)).press(forDuration:0.08,
            thenDragTo:list.coordinate(withNormalizedOffset:CGVector(dx:0.62,dy:0.83)))
        XCTAssertTrue(first.isHittable)
        first.swipeLeft()
        let remove=app.buttons["deleteConversation-anime-chiffon"]
        XCTAssertTrue(remove.waitForExistence(timeout:3));XCTAssertTrue(remove.isHittable)
        // Even when actions are open, a vertical drag can scroll the list.
        let previous=first.frame.minY
        first.coordinate(withNormalizedOffset:CGVector(dx:0.35,dy:0.7)).press(forDuration:0.08,
            thenDragTo:list.coordinate(withNormalizedOffset:CGVector(dx:0.35,dy:0.02)))
        XCTAssertTrue(!first.isHittable || first.frame.minY<previous-20)
        list.swipeDown();XCTAssertTrue(first.isHittable)
        first.swipeRight()
        let closed=NSPredicate { _,_ in !remove.exists }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:closed,object:nil)],timeout:4),.completed)
        XCTAssertTrue(app.otherElements["messagesPage"].exists)
    }
}
