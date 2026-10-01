# 按住说话 · 验证记录

日期 2026-10-01；源码 0.72.0（99）。本记录明确区分规则测试、SDK 类型检查和真实 App 运行。

## 已通过

- `bash scripts/test_voice_capture.sh --interpret`：**47 项断言通过**。使用生产 `VoiceCaptureState.swift` 与同一份 `VoiceCaptureStateTests.swift`，通过 Swift 解释器执行。覆盖识别先/后完成与编辑/发送的四种排列、hover 不提前编辑、返回普通发送、重复回调、人工修改后迟到结果、删除全部文字、网络失败与空结果、取消后回包、文字上限、手机/平板落点与边缘回滞。
- 原生 `VoiceHoldSurface` 与状态模型通过真实 iPhoneOS 26.4 SDK、iOS 17 最低目标、Swift 6 的类型检查；仅 Theme.ink 用颜色替身。
- 实际录音卡片、ChatComposerInput、命中区域、手势和状态源文件一起通过同一 SDK 的类型检查。CompanionSession、CloudSpeech、主题提供类型检查替身，绕开未参与本检查的整应用依赖；**这不是整 App 编译或视觉验收**。
- 全部 11 个新增/修改 Swift 源文件通过 Swift 6 语法解析；两个生成的 Xcode 工程都准确包含新增状态与手势源文件，工作区 XML 合法。
- `git diff --check` 通过。未调用任何付费 AI、ASR 或 TTS。

## 未完成及具体原因

- 原始独立 Swift 测试编译成功，生成的 arm64 可执行文件通过 `codesign --verify --strict`；运行被系统 `SIGKILL`（9）结束，原因未进一步确认。随后使用同一代码的解释执行完成上述 47 项检查，不将原始进程失败记作通过。
- 直接检查 Observable 宏时，Swift 宏插件的 `sandbox-exec` 返回 `sandbox_apply: Operation not permitted`。因此核心状态拆成可独立执行的纯值模型，观察包装层仍保留在正式 App 中；未通过关闭系统沙箱来绕开权限。
- `xcrun simctl list devices booted` 失败：CoreSimulatorService 连接无效/拒绝，日志目录访问返回 `Operation not permitted`。`xcrun devicectl list devices --timeout 10` 也因 CoreDevice XPC 连接无效而超时。没有本轮模拟器截图或手机安装回执。
- 通过工作区构建时，Xcode 在系统服务异常后报“not a workspace file”；工作区文件存在且 XML 校验成功。改用 Xcode 支持的直接 project 构建后可以加载工程，但 Unity GameAssembly 的 Bee/IL2CPP 在建立本地通信 socket 时返回 `SocketException (13): Permission denied`，构建失败。未将旧 App 当作本轮新包。
- 新增 `testHoldSurvivesEarlyRecognitionAndReleasesIntoEditor`、`testCaptureFailureKeepsHeldWordsForReview`；既有编辑、键盘草稿和横屏用例同步更新。**这些 XCTest 本轮没有运行通过**，等待模拟器服务可用。测试专用识别会在按住约 340 ms 时完成或失败，用来重现界面提前消失；设备 Release 不包含该分支。
- 当前会话的 `.git` 为只读。已查看工作区和暂存区差异；对本轮 18 个文件执行精确 `git add -- …` 时，创建 `.git/index.lock` 返回 `Operation not permitted`（退出码 128）。因此本轮**未提交、未推送**，改动保留在工作区；不使用复制 Git 目录或改写权限来规避。

本机原始构建与 SDK 检查日志保存在 `.local/checks/voice-capture/`，不提交缓存、测试替身及大文件。实际手感、帧率、真实麦克风和服务端网络路径均仍需安装后验证。

设计与处理见 [按住说话交互修复](../../design/2026-10-01-hold-to-talk.md)。

## 2026-10-01 后续进展

用户切换为完整执行权限后，系统服务恢复。0.73.0（100）已通过完整 iPhone Release 编译和签名，包含本轮按住说话修复；先前的权限阻塞不再适用。用户随后要求优先安装当前进度，因此新的 XCTest 与实机手感检查仍留待后续。与预制开场和删除会话一并交付，见 [本阶段记录](../../design/2026-10-01-first-meetings-and-reset.md)。

## 0.74.0（101）实际模拟器复验

2026-10-01，iPhone 17 模拟器运行 `VoiceAtmosphereTests` 中与本阶段相关的 5 条 XCTest，全部通过，53.121 秒。其中 4 条用真实原生触摸与键盘验证按住、拖动、松手和编辑，1 条验证包内开场、真实音频混音及持久化重置：

- 按下约 340 ms 后模拟识别提前完成，手指继续按住、上滑到编辑落点、停留后松开，编辑器保留文字且没有提前发送；普通松手只发送一次。
- 模拟识别中断后保留已识别内容，允许修改后发送。
- 横屏弹出系统键盘后，编辑区、发送与取消都在可用区域内，实际输入与发送通过。
- 语音/键盘切换、语音编辑/取消/发送均保留原键盘草稿。

首轮失败定位并分别处理：父视图的 accessibility identifier 传播到了子控件，导致 XCTest 找不到实际已经出现的编辑框，现以 `children: .contain` 保留各控件独立身份；开场检查夹具补充生产环境本来就有的音频场景激活；草稿用例改为比较键盘实际输入的内容，避免把系统自动纠正空格误判为草稿丢失。没有关闭断言、跳过失败用例或改动生产输入法设置。

完整证据：`.local/checks/character-openings/Completion-101.xcresult`、同名日志与 `review-101/` 内截图；失败首轮 `Voice-101.xcresult` 同样保留。这些识别结果由测试夹具提供，**不等于已测试真实麦克风、百炼网络延迟或手机持续帧率**；本轮没有付费 ASR/TTS 调用。
