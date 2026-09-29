import XCTest
import UIKit

final class AccountFlowTests: XCTestCase {
    @MainActor func testThreeMethodsShareDataAndSessionRestores() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--auth-testing","--companion-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["signInButton"].waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["accountCenterButton"].exists)
        capture("01-wechat-login")
        var preference: String?
        for method in ["wechat","email","phone"] {
            app.buttons["loginMethod-"+method].tap()
            if method != "wechat" {
                let field = method == "email" ? "loginEmail" : "loginPhone"
                XCTAssertEqual(app.textFields[field].value as? String,method == "email" ? "hello@xiaoban.example" : "13800000000")
                XCTAssertEqual(app.textFields["loginCode"].value as? String,"123456")
                capture(method == "email" ? "03-email-login" : "05-phone-login")
            }
            XCTAssertTrue(app.buttons["signInButton"].isHittable,"Prefilled login must be reachable without scrolling")
            app.buttons["signInButton"].tap()
            XCTAssertTrue(app.buttons["accountCenterButton"].waitForExistence(timeout:10))
            app.selectHomeModel("real-woman"); app.buttons["chat-real-woman"].tap()
            app.openCustomization("profile")
            let concise = app.switches["conciseToggle"]
            XCTAssertTrue(concise.waitForExistence(timeout:5))
            if method == "wechat" { concise.tap(); preference = concise.value as? String }
            else { XCTAssertEqual(concise.value as? String,preference,"Login methods must share existing character preferences") }
            app.closeCustomizationPage("closeProfileButton")
            app.buttons["viewerBackButton"].tap()
            XCTAssertTrue(app.buttons["accountCenterButton"].waitForExistence(timeout:8))
            if method == "wechat" {
                app.buttons["chat-real-woman"].tap()
                XCTAssertTrue(app.buttons["viewerBackButton"].waitForExistence(timeout:60))
                XCTAssertTrue(app.textFields["chatInput"].exists || app.textViews["chatInput"].exists)
                capture("02-signed-in-character")
                app.buttons["viewerBackButton"].tap()
                XCTAssertTrue(app.buttons["accountCenterButton"].waitForExistence(timeout:10))
            }
            app.buttons["accountCenterButton"].tap()
            XCTAssertTrue(app.staticTexts["accountID"].waitForExistence(timeout:5))
            XCTAssertEqual(app.staticTexts["accountID"].label,"XB-000001")
            XCTAssertTrue(app.otherElements["accountLink-wechat"].exists || app.staticTexts["accountLink-wechat"].exists)
            let expected = ["wechat":"微信","email":"邮箱","phone":"手机号"][method]!
            XCTAssertTrue(app.staticTexts["accountLoginMethod"].label.contains(expected))
            capture("account-"+method)
            if method != "phone" { logout(app) }
            else { app.buttons["closeAccountCenterButton"].tap() }
        }
        app.terminate()
        app.launchArguments += ["--keep-auth-data","--keep-companion-data"]
        app.launch()
        XCTAssertTrue(app.buttons["accountCenterButton"].waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["signInButton"].exists)
        app.buttons["accountCenterButton"].tap()
        XCTAssertEqual(app.staticTexts["accountID"].label,"XB-000001")
        XCTAssertTrue(app.staticTexts["accountLoginMethod"].label.contains("手机号"))
        capture("06-session-restored")
        logout(app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["signInButton"].waitForExistence(timeout:10),"Sign out must survive relaunch")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            defer { XCUIDevice.shared.orientation = .portrait }
            wait { app.frame.width > app.frame.height }
            app.buttons["loginMethod-phone"].tap()
            XCTAssertTrue(app.buttons["signInButton"].isHittable)
            capture("07-ipad-landscape-login")
        }
    }
    @MainActor func testInvalidCodeAndRestoreFixtures() {
        continueAfterFailure = false
        let app = XCUIApplication();app.launchArguments = ["--ui-testing","--auth-testing","--companion-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["signInButton"].waitForExistence(timeout:10))
        app.buttons["loginMethod-email"].tap()
        let code = app.textFields["loginCode"]
        code.tap(); code.typeText("0")
        let finish = app.buttons["finishLoginInput"]
        if finish.exists { finish.tap() }
        if !app.buttons["signInButton"].isHittable { app.swipeUp() }
        app.buttons["signInButton"].tap()
        XCTAssertTrue(app.staticTexts["loginError"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["accountCenterButton"].exists)
        capture("08-invalid-code")
        app.buttons["requestLoginCode"].tap()
        XCTAssertEqual(code.value as? String,"123456")
        XCTAssertTrue(app.staticTexts["loginCodeHint"].label.contains("没有发送"))
        app.buttons["restoreLoginFixtures"].tap()
        XCTAssertEqual(app.textFields["loginEmail"].value as? String,"hello@xiaoban.example")
        app.buttons["signInButton"].tap()
        XCTAssertTrue(app.buttons["accountCenterButton"].waitForExistence(timeout:10))
        app.buttons["accountCenterButton"].tap(); logout(app)
    }
    @MainActor func testSettledLoginPresentation() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing","--auth-testing","--companion-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["signInButton"].waitForExistence(timeout:10))
        for method in ["wechat","email","phone"] {
            app.buttons["loginMethod-"+method].tap()
            // Accessibility queries can finish before the intentionally animated crossfade.
            // Wait only for these presentation artifacts, not in the behavior assertions.
            Thread.sleep(forTimeInterval:1)
            XCTAssertTrue(app.buttons["signInButton"].isHittable)
            capture("login-"+method+"-settled")
        }
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            defer { XCUIDevice.shared.orientation = .portrait }
            wait { app.frame.width > app.frame.height }; Thread.sleep(forTimeInterval:1)
            capture("login-ipad-landscape-settled")
        }
    }
    @MainActor private func logout(_ app:XCUIApplication) {
        let button = app.buttons["signOutButton"]
        for _ in 0..<3 { if button.isHittable { break }; app.swipeUp() }
        button.tap()
        XCTAssertTrue(app.buttons["signInButton"].waitForExistence(timeout:10))
    }
    @MainActor private func wait(_ check:@escaping ()->Bool) {
        let expectation = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in MainActor.assumeIsolated { check() } },object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[expectation],timeout:10),.completed)
    }
    @MainActor private func capture(_ name:String) {
        let shot = XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
    }
}
