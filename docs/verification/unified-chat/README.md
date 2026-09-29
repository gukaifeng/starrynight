# 统一聊天入口与横向角色卡片 · 0.14.0 / build 26

2026-09-28。源码已实现；本轮完整 App 构建、模拟器运行和手机安装受当前 Codex 会话系统权限限制，尚未完成。此前 0.13.2 的截图、测试成功和安装记录不作为本版验证证据。

## 用户可见变化

- 图片、角色介绍、聊天按钮均调用同一 `openCompanion` 入口，保留当前选人状态；首页不再提供独立动作舞台入口。
- 首页保持固定标题与横向分页。竖屏把角色图、温和渐变、介绍和聊天主按钮组合在同一卡片；横屏左侧预览、右侧介绍与聊天。角色设定、外观、背景和光影放进卡片右上角省略号菜单。
- 聊天工具栏新增半透明挥手图标，默认折叠。采用系统 `Menu`，单击展开，选择后关闭；没有另开页面或改变模型取景范围。
- 列表来自角色包中 `button=true` 的动作，并与已保存姿势的声明取交集。小夏站立提供挥手、鞠躬、致意；坐/蹲不提供站立鞠躬；侧躺和小乐坐姿没有适用的手动动作时显示说明。初音保留七个动作。
- 手动动作复用 `action.request`，不写入聊天消息、不取消对话轮次、不停止语音。姿势过渡期仍由引擎校验并返回已有提示。动作播放状态由引擎事件更新，不以按钮点击伪造成功。
- 内部性能/角色诊断预览仍可通过原有调试参数运行；不出现在普通首页入口中。

原生菜单用法参考 [Apple SwiftUI Menu](https://developer.apple.com/documentation/swiftui/menu)。未指定 primaryAction，因此轻点打开菜单，不要求长按。

## 已完成检查

1. 直接编译并运行实际生产 `ModelCatalog.swift`、`CharacterPosture.swift`、`CharacterSignal.swift` 与 `CharacterActionMenuTests.swift`：**16 项通过**。覆盖四角色动作、坐/蹲/躺过滤、旧姿势偏好回退、无姿势的旧角色包、非按钮动作排除、请求角色及对话轮次契约。
2. `swiftc -frontend -parse`：**39 个 App Swift 文件语法解析通过**。这不是完整类型检查或链接构建。
3. 使用本机 iPhoneOS SDK、XCTest Swift overlay，全部 UI 测试源码 **Swift 6 类型检查通过**。这不是 UI 测试实际运行通过。
4. 已更新首页用例：四个角色各三种入口都须进入聊天；动作默认折叠、展开播放须收到引擎计数/目标回报；横向切换、纵向不滚动、横竖屏和设定弹窗仍有覆盖。迁移历史动作专项至新菜单，保留诊断预览的帧率目标测试。
5. 工程生成成功，workspace 保持 device，版本 0.14.0 / 26。没有重新导出 Unity；本次使用现有角色协议和动作资源。

可复现的核心检查：

```bash
xcrun swiftc -swift-version 6 -module-cache-path .local/build/SwiftModuleCache \
  ios/CharacterHost/Features/Home/ModelCatalog.swift \
  ios/CharacterHost/Features/Companion/CharacterPosture.swift \
  ios/CharacterHost/Features/Companion/CharacterSignal.swift \
  scripts/tests/CharacterActionMenuTests.swift \
  -o .local/checks/character-action-menu-tests
.local/checks/character-action-menu-tests
```

## 未完成验证及原因

- `simctl` 连接 CoreSimulatorService 失败，系统报告服务连接 invalid、日志访问 Operation not permitted。
- workspace 构建在编译开始前失败，包含 CoreSimulator 服务错误和 “is not a workspace file”；workspace 文件与引用可读且已重新生成，不能据此宣称工程构建通过。
- 直接 App 类型检查被 Swift Observation 宏插件的 `sandbox-exec: sandbox_apply: Operation not permitted` 阻止；保留生产宏及正常工具权限，没有禁用编译器沙箱或修改 App 来掩盖失败。
- UI 测试直接类型检查首次缺少 XCTest Swift overlay 搜索路径；补上平台 `Developer/usr/lib` 后通过。该项是编译命令修正，不是产品代码问题。
- 全仓 diff 检查另有既存 Unity 自动导出 YAML 的空白警告，本次未改这些导出文件。

原始日志：`.local/logs/unified-chat-build.log`、`unified-chat-typecheck.log`、`unified-chat-parse.log`、`unified-chat-uitest-typecheck.log`。结构化状态见 [results.json](results.json)。

待会话可正常连接 Xcode 系统服务后，先运行 `HomeCarouselTests` 的 iPhone 17 / iPad 两设备用例，实际复查卡片、菜单和旋转截图，再构建签名安装。当前最近确认的手机安装仍为 **0.13.2 / 25**；本版没有新截图或安装成功记录。
