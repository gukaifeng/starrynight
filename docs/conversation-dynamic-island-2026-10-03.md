# 对话中的灵动岛陪伴

日期：2026-10-03。客户端版本：0.102.0（133）。本阶段采用 Apple ActivityKit + WidgetKit；没有新增服务端、图片生成或付费 AI 调用。

## 产品设计

一轮正在进行的对话适合成为实时活动：用户等待回复、听语音，或者暂时离开 App，都可以看到角色正在做什么。它与这轮任务一起结束，不为了保持屏幕上常驻头像而无限续期。

| 状态 | 收起时 | 展开与锁屏 |
| --- | --- | --- |
| 正在思考 | 角色圆头像 + 小省略号 | 角色名、正在想怎么回答你、回到原会话的入口 |
| 语音播放 | 角色圆头像 + 倒计时 | 角色名、语音进度、情绪符号与柔和月白/薄荷/浅粉色彩 |
| 回复已到 | 角色圆头像 + 小勾号 | 这句话，留给你；点击回到对应消息 |
| 播放暂停 | 角色圆头像 + 暂停符号 | 提醒声音已暂停，可回到会话继续 |
| 系统判断过期 | 角色圆头像 + 月亮 | 回到星夜，接着聊；避免继续宣称正在播放 |

实现了 compact leading/trailing、minimal、expanded 和锁屏布局。倒计时及进度条使用系统原生时间视图；语音长度优先取脚本里的时长，缺少时长时是估计值。没有把进度写入每帧渲染，也没有把 Unity 放入扩展。

设置入口：我的 → 设置 → 灵动岛陪伴。陪伴功能默认开启；「显示这句对话」默认关闭，默认仅传角色名、头像、状态和跳转定位信息。开启后最多显示 90 字的简短台词；关闭时立即移除正在展示的台词。

## Apple 边界与实现选择

依据 [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)、[Creating custom views for Live Activities](https://developer.apple.com/documentation/activitykit/creating-custom-views-for-live-activities) 和 [Human Interface Guidelines: Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities)。

- 主 App 前台创建本地活动，不使用 APNs。Widget 无网络访问，不接触账号令牌、服务器密钥或完整聊天记录。
- 属性与状态合计受 4 KB 限制；用自动检查验证上限和精简数据结构。既有头像生成 96 像素缩略图，16 个头像扩展资源约 148 KB，源图保持不变。
- 自定义持续动画受系统限制。因此采用原生计时进度、状态符号替换与柔和彩色细节；不承诺可在灵动岛里播放连续 3D 动画或实时音频波形。
- 系统实时活动权限关闭或创建失败时，普通聊天继续工作。用户手动移除某轮活动后，同一轮不反复创建。
- 完成或暂停后约 12 秒收起；主动停止、切换角色及结束活动按轮次标识处理，旧任务不能关闭新任务。
- 无灵动岛的设备使用系统支持的锁屏实时活动展示。没有把顶端摄像头区域当作 App 自绘区域。

## 后台完成与跳转

过去 `ViewerCoordinator.deactivate()` 直接停止整轮对话。这次改为暂停可见播放，并对已发起的一轮请求申请 `UIApplication.beginBackgroundTask` 的有限完成时间。它没有后台新建聊天、闲聊或预取任务，也没有无限后台运行能力。

切回前台释放后台任务；一轮完成后等待活动短暂展示再释放。iOS 如果提前结束后台时间，会保留已收消息或为未完成的用户气泡记录明确的可重发原因。App 强制退出、系统挂起、网络延迟超过系统允许时间后，不能保证持续更新；如未来需要云端在 App 完全挂起后仍更新，需在独立服务端仓库增加 APNs Live Activity 推送，另行配置证书和权限。

扩展只发 `starrynight://conversation` 链接。主 App 校验协议、角色 ID 格式、当前角色名册和当前账号的会话，再定位已有消息；冷启动等待账号和页面初始化完成后处理，不切换到其他账号内容，不凭链接发起新问候。

## 关键问题与处理

1. Swift 6 对 ActivityKit 的异步框架调用报非 Sendable 跨隔离错误。框架使用 `@preconcurrency import ActivityKit`，所有业务更新仍由 MainActor 单一队列串行执行；没有把状态并发写入 UIKit 或 ActivityKit。
2. 首次后台测试中，普通回复已完成并存档，灵动岛却提前消失。根因是语音引擎在后台停止时发出 `idle`，被误当成网络回复完成。现在生成中的语音 `idle` 保持思考状态；释放后台完成时间只由真正的请求/播放任务结束触发。
3. 系统确认活动结束是异步过程，测试不能读取前一帧的数量。测试页观察真实 `Activity.activities`；这个轮询仅存在显式开启的 Debug 模拟器测试页，产品没有后台轮询。
4. 展开的系统灵动岛可能覆盖刚激活 App 的测试控件。测试先关闭系统展开区域，再等待前台按钮可点击；这属于系统 UI 自动化同步，不改动产品布局。
5. 既有页面连续性测试用 `typeText("Wait\\n")` 同时输入与发送，曾未进入预期的延迟响应分支。改为先断言输入确为 `Wait`，再点系统键盘发送键；没有放宽产品断言。

## 验证记录

在 iPhone 17 / iOS 26.4 模拟器执行 `Island133-FinalVerified`：5 项通过、0 失败、0 跳过。覆盖：

- 隐藏页面的回复完成与存档、灵感接话只发送一次；
- 切换页面后仍在思考、完成后回复只出现一次；
- 真正离开 App 后，14 秒延迟的合成回复继续完成，真实系统灵动岛展示已到达，点击回到对应会话，未重新问候、未重复存档；
- ActivityKit 真实创建、紧凑展示、长按展开、主动结束。核心检查同时验证默认隐私、载荷体积、计时区间、去重、旧轮次隔离和三种语言；
- 真正 PCM 播放、缓存回放及后台缓存链路。

另在 `Island133-Regression` 中验证失败请求的有界重试、原气泡重发、保留新草稿，该项通过；该次测试组有一项上述测试输入问题，修正后才得到最终 5/5 结果，不把先前失败的整个组标记为通过。

以上运行使用既有角色资源和合成响应/PCM，付费对话、TTS、图片生成调用均为零。不是云端请求的速度测试，也不是真机后台时间/功耗测试。

最后增加了展开/锁屏角色名旁的小情绪符号，开心、亲近或俏皮的语音显示小爱心，普通语音使用小声音符号。只更新扩展布局后，`Island133-PresentationFinal` 的真实系统展示与生命周期测试再次通过（1/1），并人工核对截图。

系统截图保存在 `.local/checks/island133-verified-images/`；最终展开效果为 `.local/checks/island133-final-presentation/59018892-7873-468A-AE12-DB3A91FF7AAA.png`，紧凑效果为同目录 `C477ADA8-D466-42C8-BA78-4ECB6DC7F76F.png`。扩展仅依赖共享协议、SwiftUI/WidgetKit 和头像缩略图。

最终 `host-device-20261003-183730.log` 为 `BUILD SUCCEEDED`。host 和嵌入的 `ConversationIsland.appex` 都是 0.102.0 / 133，自动签名及 `ValidateEmbeddedBinary` 通过，`codesign --verify --deep --strict` 返回 0。

尝试安装 iPhone 17 失败：CoreDevice 列表中手机为 `unavailable`，实际安装命令返回 1011（找不到设备），工具初始化还报告 1002（No provider was found）。没有把编译成功描述为安装成功，本阶段真机安装及真机锁屏/后台功耗验证未完成。已按照约定继续模拟器，不等待设备而阻塞交付。

## 维护入口

- `ios/Shared/ConversationActivityAttributes.swift`：带版本的共享展示协议、语言文案、链接编解码。
- `ios/ConversationIsland/`：独立 Widget 扩展和各系统展示布局。
- `ios/CharacterHost/Features/Companion/ConversationLiveActivity.swift`：权限、偏好、去重、轮次归属、创建/更新/结束。
- `CompanionSession.swift` 与 `ViewerCoordinator.swift`：对话、语音和有限后台生命周期。
- `SceneDelegate.swift`：前后台与链接路由。
- `scripts/generate_host.py`：host/extension 依赖、嵌入和一致版本号。
- `scripts/stage_island_avatars.py`：既有头像缩略资源生成，产物只留 `.local/`。
- `scripts/tests/ConversationIslandFixture.swift`、`ios/CharacterHostUITests/ConversationIslandTests.swift`：核心检查与真实系统 UI 测试。

原始头像、转换模型和系统验证截图均未公开提交。角色名册和服务端接口保持既有版本。
