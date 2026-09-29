# 统一定制、干净气泡与首页显示模式 · 0.15.0 / build 28

2026-09-28。20:14 更新：用户调整会话权限后，完整真机 Release 签名构建、深度严格验签、无线安装和自动启动均成功；手机 App 列表回读确认为 **0.15.0 / build 28**。本版 UI 自动化、实际画面与持续帧率尚未验收。见[本版安装证据](device-installation.json)。

## 页面与入口

角色页顶部保留返回、角色名和一个半透明定制图标。原取景、外观、小锁头、音乐及“我们的空间”独立入口已移除；动作仍通过聊天区的挥手菜单选择。

统一定制窗口采用固定的预览尺寸、分组卡片和同窗子页，避免切换设置时反复开关弹窗、改变模型构图。

| 位置 | 功能 |
| --- | --- |
| 顶部开关 | 锁定角色位置，默认开启；关闭后才允许直接拖动和缩放，头部触碰仍可用 |
| 角色 | 外观与姿势；性格与声音（包括原首页昵称、背景关系、性格、语气、点缀配色、空间氛围、自动朗读与语速） |
| 画面 | 背景与光影；取景与大小 |
| 聊天 | 背景音乐；聊天区域高度与字号；共同记忆；搜索、导出和清空聊天资料 |

子页左上返回先验证并保存，再回分组页；分组页返回关闭窗口。点击窗口外会先验证并保存当前子页，然后直接关闭整个窗口。没有“完成”按钮。每次进入子页使用独立关闭上下文，避免旧页淡出时的清理误删新页保存回调；失败时留在原页，连续点击不会重复提交。统一窗口沿用半屏渐变、铺满时实色的既有背景规则。

## 气泡

气泡下不再摆放记忆、朗读、喜欢、重新回答或省略号按钮。

- 自己的消息长按：复制、记住这句。
- AI 消息长按：复制、记住这句、朗读、喜欢/取消喜欢、以后回复简短一点；只有最新的 AI 回复且未生成时提供重新回答。
- 移除消息正文的独立文字选择手势，避免与自定义长按菜单争抢；整条复制由菜单提供。历史导出页仍保留文字选择。
- 不删除既有消息、喜欢、记忆或语音行为。菜单选项调用原来的会话方法。

菜单选择遵循 [Apple Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus) 对项目相关操作的设计；使用 SwiftUI 原生 contextMenu，无新依赖。

## 首页

- 默认单卡，左右翻页；竖屏卡片最大 360 × 460 pt，横屏最大 680 × 290 pt，受实际可用空间限制。图片和说明重新分区，标题、文字与聊天按钮缩紧，保留页边留白。
- 显示模式菜单可切为每页四个，2 × 2 固定网格；横屏采用紧凑的图文横排。目录超过四个时按四个一组继续横向分页，不引入首页纵向滚动。
- 模式偏好保存在本机。会话中切换模式和从角色返回保留当前选择；网格选中某角色后切回单卡会显示该角色。当前不把最后所选角色写入持久化偏好。
- 图片、名称区、聊天按钮都进入聊天。首页的“塑造角色”和定制菜单已移除，功能迁入角色页定制面板。
- 顶部只有一个“我的”入口；同一个窗口内以“账号 / 关于小伴”两页切换。登录方式、账号信息、退出、模型/语音许可和来源链接均保留。

## 验证与未完成项

- **32 项实际生产代码检查通过**：单卡/四卡分页、空与未来扩展目录、模式间定位、定制栏目无遗漏、保存拒绝/重试/防重复、外部关闭验证和子页关闭上下文隔离。
- **46 个 App Swift 文件语法解析通过**，包含 DEBUG 分支；此检查不代表完整类型检查。
- **23 个 UI 测试文件 Swift 6 类型检查通过**；新增单卡/四宫格、横屏、选人后切换模式、账号页切换、统一面板保存、长按记忆与重新回答等实际 UI 用例，但尚未运行。
- 已迁移历史测试中的旧入口和消息按钮操作；部分历史帧率/动画时间基准需要实际运行后重新评估，不将源码适配宣称为全量 UI 回归通过。
- 工程生成成功，device workspace，48 个原生源文件，版本 0.15.0 / 28；没有重导 Unity，没有改变角色包协议或引入依赖。
- 早先完整 App 类型检查被 `sandbox-exec: sandbox_apply: Operation not permitted` 阻断。用户调整会话权限后，未修改生产代码或观察机制，完整真机 Release 构建成功，包含 Swift 类型检查、Unity 链接和签名。
- iPhone 17 已通过同一网络更新安装并自动启动，App 列表确认 **0.15.0 / 28**。沿用原 Bundle ID，未卸载或清空数据。没有新模拟器截图、完整交互验收或持续性能数据。

原始记录：`.local/logs/unified-controls-typecheck.log`、`unified-controls-parse.log`、`unified-controls-ui-tests.log`；结构化状态见 [results.json](results.json)。

核心检查复现：

```bash
xcrun swiftc -swift-version 6 -module-cache-path .local/build/SwiftModuleCache \
  ios/CharacterHost/Features/Home/HomeDisplayMode.swift \
  ios/CharacterHost/Features/Companion/CustomizationDestination.swift \
  ios/CharacterHost/Features/Home/PanelCloseRequest.swift \
  scripts/tests/HomeCompositionTests.swift -o .local/checks/home-composition-tests
.local/checks/home-composition-tests
```

待后续执行 UnifiedControlsTests 与 HomeCarouselTests 的 iPhone 17 / iPad 版本，复查面板关闭、首页四卡横屏和气泡长按截图。本次按用户要求优先完成手机安装，不将安装及启动成功等同于全量 UI 回归通过。
