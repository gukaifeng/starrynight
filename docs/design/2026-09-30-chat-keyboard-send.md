# 聊天键盘发送修复（2026-09-30）

> 后续更新（2026-09-30）：本机权限恢复后已完成相应补验、AI 网关部署和 iPhone v0.54.0（76）安装。实际通过项及尚未覆盖范围见[交付记录](../verification/device-v054/README.md)。下文保留此前阶段的失败与限制，不将历史受限结果改写为通过。

## 问题与实现

聊天输入原来使用 `TextField(axis: .vertical)`，配置了 `.submitLabel(.send)` 和 `.onSubmit`。多行编辑路径仍把回车消费为换行；仅修改键盘按钮标题不能建立可靠的发送动作。

改为原生 `UITextView` 的 SwiftUI 包装 `ChatComposerInput`。由 `UITextViewDelegate` 在实际文本插入前识别回车，再调用 `CompanionChatView.send()`；页面发送按钮、键盘发送共用原有会话逻辑，不增加网络请求路径。

- 普通回车/键盘“发送”发送当前草稿；空内容、纯空白不发送，也不插入无意义的换行。
- 长文字仍自动折行；竖屏常规区域最多显示三行，紧凑区域一行，更多内容在输入框内部滚动。字体、颜色沿用聊天设置与主题。
- 中文、日文等输入法存在 `markedTextRange` 时，确认操作交还输入法；SwiftUI 更新和 500 字长度限制都不覆盖尚未提交的组合文本。
- 外接键盘 `Shift + Return` 明确换行。粘贴/拖入文本经 `UITextPasteDelegate` 的最终插入回调保留原有换行，包括只粘贴一个换行符的情况。不能简单地监听草稿出现 `\n` 就发送，那会把粘贴和编辑误当成提交。
- 发送后同步原生草稿与绑定，避免下一次回车在 SwiftUI 刷新前重复提交旧内容。原有登录拦截或写入失败需要保留草稿时仍沿用会话层结果。
- UIKit 编辑状态与聊天布局状态双向同步；点击外部收起键盘保留草稿，进入角色位置编辑时禁用输入。

没有为此引入外部库。检查了现有技能目录；本次属于 UIKit 输入语义修复，没有合适的专用技能需要安装。API 依据为本机 Xcode iOS SDK 中的 `UITextView.h`、`UITextInput.h`、`UITextPasteDelegate.h` 与 SwiftUI `UIViewRepresentable`。对应 Apple 入口：[文本替换代理](https://developer.apple.com/documentation/uikit/uitextviewdelegate/textview(_:shouldchangetextin:replacementtext:))、[输入法组合范围](https://developer.apple.com/documentation/uikit/uitextinput/markedtextrange)、[SwiftUI 自适应尺寸](https://developer.apple.com/documentation/swiftui/uiviewrepresentable/sizethatfits(_:uiview:context:))。网页正文在当前浏览工具不能展开，实际核对使用安装 SDK 的公开声明和注释。

## 回归覆盖与验证边界

`scripts/tests/ChatComposerInputTests.swift` 对生产组件和代理建立输入契约：回车三种编码、重复回车、空白草稿、输入法组合、仅换行/多行粘贴、Shift-Return、长度边界、emoji、焦点与禁用状态。`--chat-input-check` 仅存在于 DEBUG 模拟器启动分支，直接执行该检查，不初始化 Unity、账户或 AI 会话。

`ChatKeyboardTests` 另外覆盖真实软件键盘发送、收起后保留草稿及再次回车发送。普通自动化未传 `--live-ai`，付费调用继续关闭；本次未消耗百炼额度。

无障碍标识仍是 `chatInput`，元素类型现在是原生 `textViews`。现有 UI 用例的输入框查询已同步修改，其他断言和流程保留；这不表示历史 UI 套件已经通过运行。

已完成：

- 新输入组件及原生契约检查：Swift 6、iOS Simulator SDK、最低 iOS 17 类型检查通过。
- 49 个 UI 测试 Swift 文件整模块类型检查通过。
- 98 个 App Swift 文件语法检查通过。
- 模拟器和真机两个 Xcode 工程重新生成，检查组件/用例引用完整，原生契约检查文件仅加入模拟器工程。
- 生成脚本 Python 语法检查及 `git diff --check` 通过。

编译检查输出保存在忽略目录 `.local/checks/chat-keyboard/`。本轮 `xcrun simctl list devices booted` 仍报 `CoreSimulatorService connection became invalid` 与 `Operation not permitted`，无法启动模拟器执行 UIKit/UI 测试；以上是源码与编译检查，不能代替真机输入法、键盘动画或实际触屏验证。没有声称完成完整 App 构建或安装，手机上已安装版本也未更新。

恢复可用的构建环境后，执行 `CharacterHostUITests/ChatKeyboardTests`，并在 iPhone 中文拼音键盘验证选词、发送及长草稿滚动。工作区另有此前尚未导出的 Unity revision 8 修改，完整构建仍应按原有导出守卫更新引擎，不能修改导出标记冒充已导出。

当前会话 `.git` 为只读，本轮改动保留在工作区，未提交或推送。后续同步需保留本轮之前的服务端、AI 连接和角色旋转修改，不将未执行的设备验证写成通过。
