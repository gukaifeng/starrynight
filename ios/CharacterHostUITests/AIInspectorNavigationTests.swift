import XCTest

final class AIInspectorNavigationTests:XCTestCase {
    @MainActor func testLocalSettingsRemainReadableWhenServerCannotBeInspected() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","-starry.app.language.v1","zh-Hans"]
        app.launch();defer{app.terminate()}
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:65))
        app.openCharacterDeveloper();app.buttons["openAIInspector"].tap()
        XCTAssertTrue(app.staticTexts["aiInspectorError"].waitForExistence(timeout:20))
        XCTAssertTrue(app.staticTexts["aiInspectorError"].label.contains("本机资料"))
        app.buttons["aiInspectionSection-local"].tap()
        let content=app.staticTexts["aiInspectionContent-local"]
        XCTAssertTrue(content.waitForExistence(timeout:5));XCTAssertTrue(content.label.contains("称呼解析"))
        XCTAssertTrue(content.label.contains("本机展示与声音设置"))
        app.buttons["closeAIInspectionSection"].tap()
        XCTAssertTrue(app.buttons["refreshAIInspector"].isHittable)
    }
    @MainActor func testDistinctSectionsAndScenePreviewRemainReadable() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--companion-testing","--auth-testing","--inspector-layout-fixture","-starry.app.language.v1","zh-Hans"]
        app.launch();defer{app.terminate()}
        XCTAssertTrue(app.buttons["customizationButton"].waitForExistence(timeout:65))
        app.openCharacterDeveloper();app.buttons["openAIInspector"].tap()
        for (id,text) in [("persona","角色专属设定"),("prompts","对话规划与叙述规则"),("context","user_message")] {
            let row=app.buttons["aiInspectionSection-"+id]
            XCTAssertTrue(row.waitForExistence(timeout:5));row.tap()
            let content=app.staticTexts["aiInspectionContent-"+id]
            XCTAssertTrue(content.waitForExistence(timeout:5));XCTAssertTrue(content.label.contains(text))
            XCTAssertEqual(app.staticTexts["aiInspectionSectionID"].label,"分区 · "+id)
            app.buttons["closeAIInspectionSection"].tap()
        }
        app.segmentedControls["aiInspectorTrigger"].buttons["待机"].tap()
        let context=app.buttons["aiInspectionSection-context"]
        XCTAssertTrue(context.waitForExistence(timeout:5));context.tap()
        XCTAssertTrue(app.staticTexts["aiInspectionContent-context"].label.contains("idle"))
        app.buttons["closeAIInspectionSection"].tap()
        app.buttons["aiInspectionSection-latency"].tap()
        XCTAssertTrue(app.staticTexts["「最近回复耗时」暂无记录"].waitForExistence(timeout:5))
        app.buttons["closeAIInspectionSection"].tap()
        app.buttons["copyAllAISettings"].tap()
        XCTAssertEqual(app.buttons["copyAllAISettings"].value as? String,"已复制")
        app.buttons["closeAIInspector"].tap()
        XCTAssertTrue(app.buttons["openAIInspector"].waitForExistence(timeout:5))
    }
}
