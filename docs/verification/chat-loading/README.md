# 聊天回到底部与角色加载过渡 · 0.14.1 / build 27

2026-09-28。源码已修改；本次尚未完成模拟器执行或手机安装，不使用历史截图代替本版效果验证。

## 修复与关键决策

- 返回最近消息的浮动按钮只绘制向下箭头。圆形背景 34 pt、62% 不透明度，点击范围仍为 44 pt；保留 VoiceOver 的“回到最近”名称。系统开启减少透明度时使用实色背景。
- 原实现只在向历史方向拖动时将 `followingLatest` 设为 false，手动滚到底部不会恢复。现在在 ScrollView 的独立坐标空间中测量完整消息内容底部，包括原有渐隐留白和底部间距；距离底部不超过 24 pt 时隐藏按钮并恢复自动跟随。
- 自动跟随与实际底部位置分别记录：新回复正在增长、程序滚动尚未完成时，不误显示箭头；用户阅读历史时不被新消息拉回。滚到底部、底部回弹、字体/视口调整、点击箭头和主动发送均有对应处理。按钮显隐保留柔和动画。
- 删除全屏实色加载页。等待时保留首页品牌、标题、选中的角色卡片，在下方叠加小型状态卡；加载期间暂停首页其他入口，状态卡可以取消。失败信息也使用这张卡片。
- 首次启动 Unity 前先提交状态卡；已就绪的引擎再次打开角色时，延迟 250 ms 才显示提示，提前完成则直接进入原有 320 ms 淡入。提示若已显示，最少保持 450 ms，避免刚出现就消失；引擎已耗时较久时不额外等待。
- 延迟启动、提示和揭示任务均可取消，使用本次 presentation 标识防止旧任务影响新打开。取消/错误/超时清理任务。取消加载时不再截取旧 Unity 模型并覆盖首页，仅从已经显示的聊天页返回时使用角色截图淡出。
- 沿用 frontend-design 对既有品牌、轻量反馈和连续过渡的指导；未引入第三方 UI 依赖。加载设计参考 [Apple Loading](https://developer.apple.com/design/human-interface-guidelines/loading)，滚动测量采用 [SwiftUI onPreferenceChange](https://developer.apple.com/documentation/swiftui/view/onpreferencechange(_:perform:))。

## 实际验证

| 项目 | 本次结果 |
| --- | --- |
| 实际生产滚动/加载状态代码编译并执行 | 21 项通过 |
| 加载卡片 + Theme，iPhoneOS SDK / Swift 6 类型检查 | 通过 |
| App 41 个 Swift 文件语法解析 | 通过；不等同完整类型检查 |
| 全部 22 个 UI 测试文件 Swift 6 类型检查 | 通过；未执行 UI 自动化 |
| Xcode device workspace 生成 | 43 个原生源文件，0.14.1 / 27 |
| 完整 Xcode 构建 | 未通过，系统环境错误，退出码 66 |
| 模拟器 / 手机安装 | 未完成 |

回归用例已补充：历史消息手动滚回底部自动隐藏箭头、再次上翻与点击箭头、只有图标和 44 pt 点击范围、加载提示位于下半区、取消后延迟到达的 sceneReady 不得重新打开页面。既有超时恢复、横竖屏和聊天渐隐用例保留。

本次检查再次发现当前受限会话无法连接 CoreSimulatorService，系统日志访问报 `Operation not permitted`；workspace 构建同时报告 `is not a workspace file`，在编译前停止。没有请求不可用的提权或绕过系统限制。构建日志见 `.local/logs/chat-loading-build.log`。其他日志为 `chat-loading-components.log`、`chat-loading-ui-tests.log`、`chat-loading-parse.log`；结构化状态见 [results.json](results.json)。

核心检查可复现：

```bash
xcrun swiftc -swift-version 6 -module-cache-path .local/build/SwiftModuleCache \
  ios/CharacterHost/Features/Companion/ConversationScrollState.swift \
  ios/CharacterHost/Features/Viewer/ModelLoadingPresentation.swift \
  scripts/tests/ChatAndLoadingStateTests.swift \
  -o .local/checks/chat-loading-state-tests
.local/checks/chat-loading-state-tests
```

仍需在能访问 Xcode 系统服务的会话中，运行 iPhone 17 / iPad 的聊天与加载专项、复查冷/热启动及取消动画，再编译签名安装。最近确认手机安装的版本为 0.13.2 / 25。
