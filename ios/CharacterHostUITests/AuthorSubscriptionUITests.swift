import XCTest

final class AuthorSubscriptionUITests: XCTestCase {
    @MainActor func testCoreMigrationAndSocialContracts() {
        let app = XCUIApplication(); app.launchArguments = ["--social-core-check"]; app.launch()
        let result = app.staticTexts["socialCoreResult"]
        XCTAssertTrue(result.waitForExistence(timeout:25)); XCTAssertTrue(result.label.hasPrefix("PASS:"),result.label)
        XCTAssertTrue(result.label.contains("collection, guest budget"),result.label)
        let item = XCTAttachment(string:result.label); item.name = "social-core-results"; item.lifetime = .keepAlways; add(item)
    }
    @MainActor func testIndependentRelationshipsAndAuthorNavigation() {
        let app = launch()
        func assertAuthorIdentity(matching roleName:CGRect,relationship roleRelationship:CGRect,header roleHeader:CGRect) {
            let authorName = app.staticTexts["authorProfileName"]
            let follow = app.buttons["followAuthor-starry-studio"]
            XCTAssertTrue(authorName.waitForExistence(timeout:5))
            XCTAssertTrue(follow.waitForExistence(timeout:5))
            XCTAssertEqual(authorName.frame.midY,follow.frame.midY,accuracy:1,"作者名字和关注按钮应在同一行")
            XCTAssertGreaterThan(follow.frame.minX,authorName.frame.maxX,"关注入口应在作者名字右侧")
            XCTAssertEqual(authorName.frame.minX,roleName.minX,accuracy:1,"作者和角色资料应沿用同一名称列")
            XCTAssertEqual(authorName.frame.height,roleName.height,accuracy:1,"作者和角色名称应沿用相同字号与行高，封面不影响身份行布局")
            XCTAssertEqual(follow.frame.minX-authorName.frame.maxX,roleRelationship.minX-roleName.maxX,accuracy:1,
                           "关注与订阅按钮应沿用同一名称间距")
            XCTAssertEqual(follow.frame.height,roleRelationship.height,accuracy:1,"关系按钮应保留一致的点击高度")
        }
        app.buttons["discover-open-studio-robot"].tap()
        let subscribe = app.buttons["characterSubscribeButton"]
        XCTAssertTrue(subscribe.waitForExistence(timeout:5)); XCTAssertEqual(subscribe.value as? String,"未订阅")
        XCTAssertFalse(app.buttons["followAuthor-starry-studio"].exists,"角色资料只提供订阅，关注入口在作者页")
        let name = app.staticTexts["profileName"]
        XCTAssertTrue(name.waitForExistence(timeout:5))
        capture("01-role-card-before-author")
        let headerFrame = app.buttons["closeCharacterDetails"].frame
        XCTAssertEqual(name.frame.midY,subscribe.frame.midY,accuracy:1,"角色名字和订阅按钮应在同一行")
        XCTAssertGreaterThan(subscribe.frame.minX,name.frame.maxX,"订阅入口应在角色名字右侧")
        let roleNameFrame = name.frame
        let roleSubscribeFrame = subscribe.frame
        app.buttons["characterAuthorButton"].tap()
        assertHeader(app,"closeAuthorProfile",matching:headerFrame)
        assertAuthorIdentity(matching:roleNameFrame,relationship:roleSubscribeFrame,header:headerFrame)
        app.buttons["followAuthor-starry-studio"].tap()
        XCTAssertEqual(app.buttons["followAuthor-starry-studio"].value as? String,"已关注")
        app.buttons["closeAuthorProfile"].tap()
        assertHeader(app,"closeCharacterDetails",matching:headerFrame)
        assertAbsent(app.buttons["followAuthor-starry-studio"])
        XCTAssertEqual(subscribe.value as? String,"未订阅")
        subscribe.tap(); XCTAssertEqual(subscribe.value as? String,"已订阅")
        app.buttons["characterAuthorButton"].tap()
        assertHeader(app,"closeAuthorProfile",matching:headerFrame)
        XCTAssertEqual(app.buttons["followAuthor-starry-studio"].value as? String,"已关注")
        capture("02-author-works")
        scrollTo(app.buttons["authorWork-real-woman"],app:app)
        app.buttons["authorWork-real-woman"].tap()
        assertHeader(app,"closeCharacterDetails",matching:headerFrame)
        XCTAssertTrue(app.buttons["characterSubscribeButton"].waitForExistence(timeout:5))
        XCTAssertEqual(app.buttons["characterSubscribeButton"].value as? String,"未订阅")
        assertAbsent(app.buttons["followAuthor-starry-studio"])
        app.buttons["closeCharacterDetails"].tap()
        assertHeader(app,"closeAuthorProfile",matching:headerFrame)
        XCTAssertEqual(app.buttons["followAuthor-starry-studio"].value as? String,"已关注")
        scrollTo(app.buttons["authorFollowersButton"],app:app)
        app.buttons["authorFollowersButton"].tap()
        assertHeader(app,"closeAuthorsButton",matching:headerFrame)
        app.buttons["closeAuthorsButton"].tap()
        assertHeader(app,"closeAuthorProfile",matching:headerFrame)
        app.buttons["closeAuthorProfile"].tap()
        assertHeader(app,"closeCharacterDetails",matching:headerFrame)
        XCTAssertEqual(subscribe.value as? String,"已订阅")
        for visit in 1...2 {
            scrollTo(app.buttons["characterCreditsButton"],app:app)
            app.buttons["characterCreditsButton"].tap()
            assertHeader(app,"closeCharacterCredits",matching:headerFrame)
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","素材原始署名")).firstMatch.exists)
            if visit == 1 { capture("02a-character-source-credits") }
            app.buttons["closeCharacterCredits"].tap()
            assertHeader(app,"closeCharacterDetails",matching:headerFrame)
            assertAbsent(app.buttons["closeCharacterCredits"])
        }
        app.buttons["closeCharacterDetails"].tap()
        tab(app,"mine")
        XCTAssertEqual(app.buttons["mySubscriptionsButton"].label,"2 订阅")
        XCTAssertEqual(app.buttons["myFollowsButton"].label,"1 关注"); capture("03-my-relations")
        app.buttons["mySubscriptionsButton"].tap()
        XCTAssertTrue(app.buttons["unsubscribe-studio-robot"].waitForExistence(timeout:5)); app.buttons["unsubscribe-studio-robot"].tap()
        app.buttons["closeSubscriptionsButton"].tap()
        XCTAssertEqual(app.buttons["mySubscriptionsButton"].label,"1 订阅")
        XCTAssertEqual(app.buttons["myFollowsButton"].label,"1 关注")
        app.buttons["myFollowsButton"].tap()
        XCTAssertTrue(app.buttons["followAuthor-starry-studio"].waitForExistence(timeout:5)); capture("04-followed-authors")
        app.buttons["followAuthor-starry-studio"].tap(); app.buttons["closeAuthorsButton"].tap()
        XCTAssertEqual(app.buttons["myFollowsButton"].label,"0 关注")
        XCTAssertEqual(app.buttons["mySubscriptionsButton"].label,"1 订阅")
        tab(app,"messages"); XCTAssertTrue(app.buttons["message-hatsune-miku"].waitForExistence(timeout:8)); XCTAssertFalse(app.buttons["message-studio-robot"].exists)
        tab(app,"home"); XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:60))
        app.waitForCharacter { $0["framingMotionActive"] as? Bool == false }
        let camera = app.characterRuntime
        app.buttons["customizationButton"].tap()
        XCTAssertTrue(app.buttons["closeCharacterDetails"].waitForExistence(timeout:5))
        capture("04a-live-character-profile")
        let liveHeaderFrame = app.buttons["closeCharacterDetails"].frame
        let liveNameFrame = app.staticTexts["profileName"].frame
        let liveSubscribeFrame = app.buttons["characterSubscribeButton"].frame
        XCTAssertFalse(app.buttons["followAuthor-starry-studio"].exists)
        app.buttons["characterAuthorButton"].tap()
        assertHeader(app,"closeAuthorProfile",matching:liveHeaderFrame)
        assertAuthorIdentity(matching:liveNameFrame,relationship:liveSubscribeFrame,header:liveHeaderFrame)
        capture("04b-live-author-profile")
        XCTAssertTrue(app.buttons["authorFollowersButton"].waitForExistence(timeout:5))
        app.buttons["authorFollowersButton"].tap()
        assertHeader(app,"closeAuthorsButton",matching:liveHeaderFrame)
        capture("04c-live-author-followers")
        app.buttons["closeAuthorsButton"].tap()
        assertHeader(app,"closeAuthorProfile",matching:liveHeaderFrame)
        app.buttons["closeAuthorProfile"].tap()
        assertHeader(app,"closeCharacterDetails",matching:liveHeaderFrame)
        app.buttons["closeCharacterDetails"].tap()
        let actual = app.characterRuntime
        for key in ["distance","framingSize","framingAngle","pitch","yaw","cameraFov"] {
            XCTAssertEqual((camera[key] as? NSNumber)?.doubleValue ?? -1,(actual[key] as? NSNumber)?.doubleValue ?? -2,accuracy:0.0001,key)
        }
        XCTAssertEqual(actual["framingMotionActive"] as? Bool,false)
    }
    @MainActor func testAuthorEditingPublicationAndOtherIdentity() {
        let app = launch(); tab(app,"mine")
        app.buttons["myAuthorProfileButton"].tap(); app.buttons["editAuthorProfile"].tap()
        XCTAssertTrue(app.textFields["authorNameInput"].waitForExistence(timeout:6))
        app.buttons["authorAvatar-leaf"].tap()
        replace(app.textFields["authorNameInput"],with:"月光作者")
        app.buttons["closeAuthorEditor"].tap()
        XCTAssertTrue(app.staticTexts["authorProfileName"].waitForExistence(timeout:5)); XCTAssertEqual(app.staticTexts["authorProfileName"].label,"月光作者")
        capture("05-my-author-profile"); app.buttons["closeAuthorProfile"].tap()
        XCTAssertTrue(app.staticTexts["月光作者"].exists)
        tab(app,"create")
        XCTAssertTrue(app.buttons["create-base-studio-robot"].waitForExistence(timeout:8)); app.buttons["create-base-studio-robot"].tap()
        scrollTo(app.textFields["createName"],app:app); replace(app.textFields["createName"],with:"晚风伙伴")
        scrollTo(app.buttons["createPublic"],app:app); app.buttons["createPublic"].tap()
        scrollTo(app.buttons["createCharacterButton"],app:app); app.buttons["createCharacterButton"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:65))
        app.waitForCharacter { $0["framingMotionActive"] as? Bool == false }
        tab(app,"mine"); app.buttons["myCreationsButton"].tap()
        let publication = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'publish-'")).firstMatch
        XCTAssertTrue(publication.waitForExistence(timeout:8)); let roleID = String(publication.identifier.dropFirst("publish-".count))
        app.buttons["closeCreationsButton"].tap(); switchIdentity(app)
        tab(app,"discover"); XCTAssertFalse(app.segmentedControls["discoverMode"].exists)
        let search = app.textFields["discoverSearch"]; search.tap(); search.typeText("月光")
        let discoveredRole = app.buttons["discover-open-"+roleID]
        XCTAssertTrue(discoveredRole.waitForExistence(timeout:8)); discoveredRole.tap()
        XCTAssertTrue(app.buttons["characterAuthorButton"].waitForExistence(timeout:5)); app.buttons["characterAuthorButton"].tap()
        assertAbsent(app.buttons["closeCharacterDetails"])
        let author = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'followAuthor-author-'")).firstMatch
        XCTAssertTrue(author.waitForExistence(timeout:8)); let authorID = String(author.identifier.dropFirst("followAuthor-".count))
        capture("06-find-public-author-through-role")
        XCTAssertTrue(app.buttons["followAuthor-"+authorID].waitForExistence(timeout:5)); app.buttons["followAuthor-"+authorID].tap()
        scrollTo(app.buttons["authorWork-"+roleID],app:app); app.buttons["authorWork-"+roleID].tap()
        assertAbsent(app.buttons["closeAuthorProfile"])
        let role = app.otherElements["characterDetails-"+roleID]
        let roleName = role.staticTexts["profileName"]
        let subscribe = role.buttons["characterSubscribeButton"]
        let ready = NSPredicate { _,_ in MainActor.assumeIsolated {
            role.exists && roleName.exists && roleName.label == "晚风伙伴" && subscribe.exists && subscribe.isHittable
        } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:ready,object:nil)],timeout:5),.completed,
                       "目标角色资料尚未准备好：\(app.debugDescription)")
        subscribe.tap()
        let subscribed = XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@","已订阅"),object:subscribe)
        XCTAssertEqual(XCTWaiter.wait(for:[subscribed],timeout:5),.completed,"订阅未生效：\(app.debugDescription)")
        capture("07-subscriber-role-card")
        app.buttons["closeCharacterDetails"].tap()
        XCTAssertTrue(app.buttons["closeAuthorProfile"].waitForExistence(timeout:5)); app.buttons["closeAuthorProfile"].tap()
        assertAbsent(app.buttons["closeAuthorProfile"])
        XCTAssertTrue(app.buttons["closeCharacterDetails"].waitForExistence(timeout:5)); app.buttons["closeCharacterDetails"].tap()
        tab(app,"mine"); XCTAssertEqual(app.buttons["myFollowsButton"].label,"1 关注"); XCTAssertEqual(app.buttons["mySubscriptionsButton"].label,"2 订阅")
        switchIdentity(app); tab(app,"mine"); app.buttons["myAuthorProfileButton"].tap()
        XCTAssertEqual(app.staticTexts["authorProfileName"].label,"月光作者")
        XCTAssertEqual(app.buttons["authorFollowersButton"].label,"1 位关注者")
        app.buttons["authorFollowersButton"].tap(); XCTAssertTrue(app.staticTexts["星夜体验者 B"].waitForExistence(timeout:5)); capture("08-local-follower")
        app.buttons["closeAuthorsButton"].tap(); app.buttons["closeAuthorProfile"].tap()
        app.buttons["myCreationsButton"].tap(); app.buttons["publish-"+roleID].tap(); app.buttons["closeCreationsButton"].tap()
        switchIdentity(app); tab(app,"mine"); app.buttons["mySubscriptionsButton"].tap()
        XCTAssertTrue(app.staticTexts["暂不可用的角色"].waitForExistence(timeout:6)); capture("09-withdrawn-role")
        app.buttons["unsubscribe-"+roleID].tap(); app.buttons["closeSubscriptionsButton"].tap()
        XCTAssertEqual(app.buttons["mySubscriptionsButton"].label,"1 订阅"); XCTAssertEqual(app.buttons["myFollowsButton"].label,"1 关注")
        app.terminate(); app.launchArguments = ["--ui-testing","--companion-testing","--keep-companion-data","--keep-auth-data","--shell-discover"]; app.launch()
        XCTAssertTrue(app.buttons["tab-mine"].waitForExistence(timeout:20)); tab(app,"mine")
        XCTAssertEqual(app.buttons["myFollowsButton"].label,"1 关注"); XCTAssertEqual(app.buttons["mySubscriptionsButton"].label,"1 订阅")
    }
    @MainActor func testUnsubscribeCurrentRoleShowsPersistentEmptyHome() {
        let app = launch(home:true)
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:65))
        app.buttons["customizationButton"].tap()
        XCTAssertTrue(app.buttons["characterSubscribeButton"].waitForExistence(timeout:5)); app.buttons["characterSubscribeButton"].tap()
        app.buttons["closeCharacterDetails"].tap()
        XCTAssertTrue(app.buttons["emptyStateAction"].waitForExistence(timeout:12)); capture("10-no-subscriptions")
        tab(app,"messages"); XCTAssertTrue(app.buttons["emptyStateAction"].waitForExistence(timeout:5))
        app.terminate(); app.launchArguments = ["--ui-testing","--companion-testing","--keep-companion-data","--keep-auth-data"]; app.launch()
        XCTAssertTrue(app.buttons["emptyStateAction"].waitForExistence(timeout:25)); XCTAssertFalse(app.buttons["customizationButton"].exists)
    }
    @MainActor func testAuthorWorksOpenConversationsAfterDismissal() {
        let app = launch()
        XCTAssertFalse(app.segmentedControls["discoverMode"].exists)
        XCTAssertTrue(app.buttons["discover-open-studio-robot"].waitForExistence(timeout:5))
        capture("11-discover-authored-roles")
        app.buttons["discover-open-studio-robot"].tap()
        XCTAssertTrue(app.buttons["characterAuthorButton"].waitForExistence(timeout:5)); app.buttons["characterAuthorButton"].tap()
        assertAbsent(app.buttons["closeCharacterDetails"])
        XCTAssertTrue(app.buttons["authorWork-studio-robot"].waitForExistence(timeout:5))
        capture("12-public-author-profile")
        app.buttons["authorWork-studio-robot"].tap()
        XCTAssertTrue(app.buttons["characterSubscribeButton"].waitForExistence(timeout:5))
        XCTAssertEqual(app.buttons["characterSubscribeButton"].value as? String,"未订阅")
        capture("13-role-subscription-card")
        app.buttons["profileChatButton"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:65))
        app.waitForCharacter { $0["modelId"] as? String == "studio-robot" && $0["framingMotionActive"] as? Bool == false }
        XCTAssertFalse(app.buttons["closeAuthorProfile"].exists)
        app.buttons["customizationButton"].tap(); app.buttons["characterAuthorButton"].tap()
        XCTAssertTrue(app.buttons["authorWork-real-woman"].waitForExistence(timeout:5))
        app.buttons["authorWork-real-woman"].tap()
        XCTAssertTrue(app.buttons["profileChatButton"].waitForExistence(timeout:5))
        app.buttons["profileChatButton"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:65))
        app.waitForCharacter { $0["modelId"] as? String == "real-woman" && $0["framingMotionActive"] as? Bool == false }
        XCTAssertFalse(app.buttons["closeAuthorProfile"].exists)
        tab(app,"mine")
        XCTAssertEqual(app.buttons["mySubscriptionsButton"].label,"3 订阅")
        XCTAssertEqual(app.buttons["myFollowsButton"].label,"0 关注")
        capture("14-my-independent-relations")
        app.buttons["mySubscriptionsButton"].tap()
        XCTAssertTrue(app.buttons["unsubscribe-studio-robot"].waitForExistence(timeout:5))
        capture("15-subscribed-roles")
    }
    @MainActor private func launch(home:Bool = false) -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing","--companion-testing"] + (home ? [] : ["--shell-discover"])
        app.launch(); XCTAssertTrue(app.buttons["tab-discover"].waitForExistence(timeout:65)); return app
    }
    @MainActor private func tab(_ app:XCUIApplication,_ id:String) {
        XCTAssertTrue(app.buttons["tab-"+id].waitForExistence(timeout:65)); app.buttons["tab-"+id].tap()
    }
    @MainActor private func switchIdentity(_ app:XCUIApplication) {
        app.buttons["profileSettingsButton"].tap(); XCTAssertTrue(app.buttons["switchDemoIdentity"].waitForExistence(timeout:6)); app.buttons["switchDemoIdentity"].tap()
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:65))
    }
    @MainActor private func replace(_ field:XCUIElement,with value:String) {
        field.tap(); let previous = field.value as? String ?? ""
        field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:previous.count)); field.typeText(value)
    }
    @MainActor private func scrollTo(_ item:XCUIElement,app:XCUIApplication) {
        for _ in 0..<10 { if item.isHittable { return }; app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(item.isHittable,item.identifier)
    }
    @MainActor private func assertHeader(_ app:XCUIApplication,_ identifier:String,matching expected:CGRect,file:StaticString = #filePath,line:UInt = #line) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout:5),identifier,file:file,line:line)
        let aligned = NSPredicate { _,_ in MainActor.assumeIsolated {
            let actual = button.frame
            return button.isHittable && abs(actual.minX-expected.minX) <= 1 && abs(actual.minY-expected.minY) <= 1
                && abs(actual.width-expected.width) <= 1 && abs(actual.height-expected.height) <= 1
        } }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:aligned,object:nil)],timeout:5),.completed,
                       "\(identifier) 应沿用同一弹窗头栏：expected \(expected), actual \(button.frame)",file:file,line:line)
        XCTAssertEqual(button.frame.minX,expected.minX,accuracy:1,identifier + " x",file:file,line:line)
        XCTAssertEqual(button.frame.minY,expected.minY,accuracy:1,identifier + " y",file:file,line:line)
        XCTAssertEqual(button.frame.width,expected.width,accuracy:1,identifier + " width",file:file,line:line)
        XCTAssertEqual(button.frame.height,expected.height,accuracy:1,identifier + " height",file:file,line:line)
    }
    @MainActor private func assertAbsent(_ element:XCUIElement,file:StaticString = #filePath,line:UInt = #line) {
        let absent = XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:element)
        XCTAssertEqual(XCTWaiter.wait(for:[absent],timeout:5),.completed,element.identifier,file:file,line:line)
    }
    @MainActor private func capture(_ name:String) {
        // Unity's display loop can report idle while SwiftUI is crossfading;
        // let the short page transition settle before preserving visual evidence.
        Thread.sleep(forTimeInterval:0.7)
        let item = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
