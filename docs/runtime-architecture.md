> v0.41 当前直接操作：长按 1 秒，经实际模型网格命中认可后允许临时双轴旋转，左右 ±180°、上下 ±20°，松手回正。UIKit 认可反馈包含一次轻震和独立覆盖层方向图标，摄像机和持久取景不变。构建要求 `nativeGestureRevision >= 2` 与 `inspectionGestureRevision >= 2`；详见[旋转反馈说明](verification/inspection-feedback/README.md)。
>
> v0.26 历史补充：统一圆形头像与角色资料卡。发现页先展示资料，顶部头像/名字也进入同一资料；定制在资料的子页。iOS直接手势改由`CharacterTouchSurface`识别，经`nativeGesture`传入Unity；原始方案见[角色资料与手势](design/2026-09-29-character-identity.md)。旧的开放 pan/pinch 取景控制已不作为当前产品入口。

> v0.25 补充：NativeWindowHandoff统一新角色、驻留角色与返回菜单。Unity窗口保持不透明；原生透明窗口固定在上方，只动画其内容alpha，进入对话完成后保留alpha=0并关闭触摸，避免结束时重排窗口导致跳帧。未播放语音使用无动画的独立子树，时长不显示“约”，实测值与估值的存储区分不变。见 [设计](design/2026-09-29-message-handoff.md)。

> v0.24 补充：进程启动先提交独立 Core Animation 品牌窗口，再初始化账号/目录与Unity；开场与内容并行，等待时循环流光呼吸，完成后淡出并释放。首次启动不叠加角色入场动画。宿主揭开角色时不再自动发 session.enter，直接保持已经准备的最终构图；主动动作不变。气泡正文上下留白均12pt。见 [设计](design/2026-09-29-startup-composition.md)。

> v0.23 补充：新角色采用 `selectModel → 配置外观/空间/姿势/取景 → prepareReveal → presentationReady → 窗口淡入`。准备阶段宿主窗口高于Unity窗口，Unity照常渲染；运行时连续三帧环境、姿势和镜头稳定后应答，并以presentationId/modelId/requestId校验。初始化空间使用immediate提交，实时换房使用深色遮罩。导出要求immersionRevision 2；旧模型包无需迁移。气泡语音改成同一个轮廓内的左上凸起区域。见 [设计](design/2026-09-29-arrival-bubbles.md)。

> v0.22 补充：定制入口合并进角色名字区域，静音移入定制页；聊天状态提示移除但会话预算及声音引擎保留。回到最近使用不参与布局的双下箭头浮层；品牌使用同源SVG/PDF矢量与PNG桌面图标。见 [极简方案](design/2026-09-28-minimal-starry.md)。

> v0.21 补充：角色名字右侧的静音控件与聊天共用驻留会话，语音挂件位于气泡外。消息搜索只接收当前账号记录和可访问角色 ID，稳定消息 UUID 跨导航定位，历史视图保持60条有界窗口。默认主题改月白，个人列表由统计数字打开。见 [本轮方案](design/2026-09-28-quiet-chat.md)。

> v0.20 补充：名字保持星夜。首页会话跨菜单保留，暂停渲染后直接恢复；按账户保存的 Markov 访问记录在空闲时驱动隔离副本预热，导出要求 immersionRevision 1。气泡语音使用有界缓存和可选实测时长元数据。详见 [沉浸方案](design/2026-09-28-starry-immersion.md)。

# 近伴运行时架构

更新：2026-09-28，v0.19.0。以 [角色集合标准](character-standard/character-collections.md) 与 [本轮设计](design/2026-09-28-nearby-collections.md) 为本轮入口；下文包含历史演进。

`CharacterCollection` 为基础模型绑定动作允许表、空间允许表、声音预设和音乐列表。`ModelDescriptor.collection` 解析基础清单或自建角色快照；UI、实时预览及保存都经集合归一化。`CompanionSoundscape` 继续单一管理 AVAudioSession，但音乐启停、选曲、音量已迁入 CharacterProfile.audio；创建会话加载当前账号与实例的偏好，切换停止旧播放器。ThemeSettings 是设备级外观偏好，不改变角色资源。

游客使用独立 guest 命名空间。`CompanionArchive.guestTurns` 与被接受的用户消息一次原子写入，五轮后阻止第六条写入；中断仍消耗已预留额度，重启/换角色/清空历史不回补。五轮后保留可读历史和登录入口。首次登录新账号导入游客记录一次、默认关注初始角色；已有账号只恢复自己的关注/最近角色，空关注继续保持空。账号切换先关闭并取消旧会话，再切换存储作用域。

新旧版本的 application bundle ID、原体验账号键保持不变。新增音频字段、集合快照、游客计数为可选，旧档无需破坏性重写；新增主题默认深海蓝，提供暖夜/松林/月白和轻透/沉静。主题通过 SwiftUI observation 更新，UIKit 渐变与原生按钮另由主题通知重绘。

# 小伴：运行结构与维护入口

## v0.18 星夜导航、角色实例与本机目录

`AppRootView` 是五页壳层，`Features/Social/` 提供 AppDock、MessagesPage、DiscoverPage、CreateCharacterPage、MyPage 和 CharacterLibrary。`HomeView` / CharacterHomeCard 是之前画廊版本的保留实现，不是当前生产入口。

原生与 Unity 各自 UIWindow 复用 AppDock。ViewerCoordinator 统一处理 tab、loading、viewer、closing：离开 Unity 保留实时图层淡出，之后暂停会话；进入消息中的角色先保存最近选择，再开对应实例。Unity 前台时关闭后方原生窗的辅助功能遍历，返回后恢复，防止两个底栏同时出现在 VoiceOver/XCTest 中。输入键盘显示时隐藏 Unity 底栏并抬高输入区域；聊天布局为底栏预留高度，不直接缩放 Metal 视图。

`ModelDescriptor.id` 是宿主实例 ID，`runtimeID` 是原模型包 ID。现有四个内置角色两者相同，自建角色使用 `character-UUID`，继续引用原 `packageId`、能力、动作和姿势。仅发给 Unity 的 selectModel、signal.actorId 及回执匹配使用 runtimeID；会话、外观、记忆、头像使用实例 ID。没有修改 Character API / Environment API。

`CharacterLibrary` schema 1 单独落盘账号关注、最近角色、作者、底座与公开快照；解析任意 ID 都检查作者/公开权限。`CompanionStore` 对原体验身份保留原字符键，对其他身份使用 `accountID:instanceID`。现有聊天按最后消息时间初始化关注和最近角色，之后不再自动补默认关注；空关注是有效持久状态。发布快照只含 CharacterProfile，不含 CharacterRecord 的消息和记忆。目录解析失败/未来版本停止覆盖，原文件保留。未来接服务端需要真实鉴权、同步、内容审查与模型许可处理，本地模拟不声称具备这些服务。


更新：2026-09-28，v0.13.0。角色平台当前设计以[标准化架构](character-standard/01-architecture.md)和[接口规范](character-standard/04-character-api.md)为准；下文保留宿主/Unity 集成基础维护入口。

## 两套源码，一个 App

原生宿主管首页、关于、加载 / 错误反馈、窗口切换、按钮和生命周期。Unity 管 URP 渲染、镜头、触摸与角色动作。UnityFramework 通过跨工程依赖先构建，再链接并嵌入宿主；场景 Data 属于该框架，运行时按框架实际 bundle ID 加载。

| 源码入口 | 用途 |
|---|---|
| `ios/CharacterHost/App/` | UIApplication / UIWindowScene 生命周期与 SwiftUI 首页 |
| `Features/Home/`、`Features/About/` | 原生界面、模型描述和来源 |
| `Features/Viewer/ViewerCoordinator.swift` | 单一主线程状态、初始化、超时、暂停恢复和消息关联 |
| `Features/Viewer/ViewerOverlayController.swift` | UIKit 返回、取景面板、动作按钮及聊天 viewport；角色区域触摸透传 Unity |
| `Features/Companion/` | 角色资料、聊天、记忆、开源本地语音及可保存取景 |
| `Assets/Scripts/Runtime/FramingMath.cs` | 双端参数约束的 Unity 实现、透视投影安全边界 |
| `Bridge/UnityRuntimeBridge.mm` | Swift ↔ Objective-C++ ↔ UnityFramework |
| `Assets/Scripts/Runtime/ViewerController.cs` | 固定接收对象、短按识别、对话构图和事件 |
| `Assets/Scripts/Runtime/CharacterActions.cs` | 连续插值动画、头部精确点击、动作中断 / 完成 |
| `Assets/Plugins/iOS/ModelSpaceNative.mm` | Unity C ABI 事件回调，只由框架编译 |
| `Assets/Editor/StudioRobotBuilder.cs` | 原创圆角模型、PBR 材质、棚拍反射与连续动作生成 |
| `Assets/Scripts/Runtime/RenderPerformance.cs` | 60／120 目标与两秒一次的实测帧间隔统计 |
| `Assets/Editor/BuildIos.cs` | 场景生成、校验、SDK 分离、Data 后处理和缩略图 |

## 生命周期

首页 → loading → sceneReady → selectModel → 关联本次 presentation/request/modelId 的 modelSelected → 展示 Unity 窗口及原生控件、应用本角色偏好。首次初始化在 80 ms 后开始，使加载页先提交显示；Unity 初始化本身仍含主线程同步工作。

返回只清空触摸并暂停引擎，不 unload / quit。再次打开复用同一实例，恢复引擎、重置动作并恢复本角色取景后展示。加载期间返回会取消展示意图；迟到的 sceneReady 不得抢回前台。再次进入时即使尚未 ready 也先恢复引擎，以便完成初始化。

失活 / 后台时暂停 Unity，恢复后依据页面意图显示首页或查看页。加载超时累计前台定时器 30 次，后台不计数；超时显示可返回的错误页。该计时不是主线程被阻塞时也能强制中断 Unity 的硬超时。

## JSON 桥接契约

接收对象固定为 `AppBridgeReceiver.ReceiveCommand`，不接受由外部指定的对象或方法名。schemaVersion 为 1，消息上限 8,192 个字符。原生回调复制 UTF-8 文本后进入主线程，页面状态由 MainActor 管理。

```json
{"schemaVersion":1,"kind":"command","name":"playAction","requestId":"view-1-8","presentationId":1,"payload":{"action":"Wave"}}
```

| 命令 | 作用 |
|---|---|
| `getState` | 回传相机状态 |
| `selectModel` | 切换内置角色，初始化动作，回报 modelSelected |
| `resetView` | 兼容内部默认相机及 Idle 重置；用户界面的恢复推荐走 configureFraming 并提交偏好 |
| `configureFraming` | framingShot（conversation/full）、framingSize（0.9–1.1）、framingAngle（±20°），immediate 支持 Reduce Motion |
| `conversationViewport` | 原生布局传入归一化矩形，镜头适配实际区域，保留取景选择 |
| `configureCompanion` / `companionState` / `speechFrame` | 外观氛围、聊天状态与口型幅度 |
| `configureViewport` | 按当前 Camera.aspect 重算投影，保留用户景别、大小和角度 |
| `configurePerformance` | payload.targetFPS 选择 60 或 120；每次展示与恢复重设请求值 |
| `clearInput` | 提交已改变的构图后清除手势采样，防止返回 / 失活后的跳变 |
| `nativeGesture` | iOS手势适配：`action`为`tap/pan/pinch`，`state`为`began/changed/ended/cancelled`。点击用宿主全屏归一化`viewportX/Y`（左上原点），引擎转换到当前Screen分辨率；拖动`deltaX`为宽度归一化增量；捏合`scale`为上次回调以来的倍率。只在`nativeGestures && gesturesEnabled`处理，后两者还须`framingGesturesEnabled`；有限值/范围检查，仍用FramingMath、CameraFramingMotion和一次结束提交。宿主使用UIKit原生识别器，触摸面位于聊天控件下方，聊天/弹窗不发送模型手势。 |
| `configureGestures` | 可选`nativeGestures`默认false保持旧宿主输入；新iOS宿主显式true，停用Unity直接轮询以免重复处理。 `gesturesEnabled` 控制所有直接触摸（弹窗期间关闭）；新增可选 `framingGesturesEnabled` 只控制拖动旋转/捏合缩放，不影响轻触头部。宿主每次显式发送两者，默认锁定取景；引擎启动也锁定。缺省新字段按旧客户端的可操控行为解释。精细面板命令不受取景锁影响；锁切换提交已完成的有效变更并清除在途触摸，剩余手指抬起后才开始新手势。`state` 等事件回报两项实际状态。 |
| `nativeGesture` 的 `inspect` 扩展 | 长按识别后发送 `began` 和全屏归一化 `viewportX/Y`，Unity真实射线命中才回 `inspectionBegan`。`changed` 传 `deltaX/Y`：相对本次长按成立位置的绝对位移，分别除以宽/高，Y沿UIKit向下为正。yaw映射为−360×deltaX并夹紧±180°，pitch映射为−80×deltaY并夹紧±20°；重新按住未完全归零的模型时从当前偏移继续。`ended/cancelled`结束，回`inspectionEnded`和完成回正的`inspectionReturned`；命中失败回`inspectionRejected`。只使用整体根旋转，不写角色骨骼或持久化取景。宿主按角色/presentation/当前可见与长按状态筛选后才反馈，不逐帧震动。 |
| `playAction` | 按角色动作白名单播放，初音另含 Bow / Spin / Greet / Cheer，未知名称拒绝 |

事件公共字段为 schemaVersion、kind、name、requestId、modelId、presentationId、yaw、pitch、distance、defaultDistance、message、action、source。`performance` 事件单独携带 targetFPS（请求）、appliedFPS（引擎当前值）、refreshHz、fps、frameCount、windowSeconds、p95Ms、p99Ms、worstMs、over16_7ms、over8_3ms、width、height，不带相机字段。

其他事件包括 sceneReady、modelSelected、framingConfigured、framingGestureEnded、companionViewport、viewReset、state、actionStarted、actionCompleted、actionIdle、headTapped、error。取景事件包含用户 framingShot/framingSize/framingAngle 及临时 effectiveShot/actionFraming。

旧 presentation 命令丢弃；modelSelected 需匹配当前 presentation、modelId 和 pending request 才结束加载。每帧构图留在 Unity，不跨桥传相机变化；配置或手势结束后延迟回报 settled state。

## 相机与角色交互

默认正面 yaw 180°、pitch 4°；上方受限预览自动增加俯角，使低姿态角色取景时镜头保持在地板上方，俯角、位置与距离共用连续弹簧。用户可选对话近景（默认）或全身互动、90%–110% 大小、左右各 20°。相机按角色包围盒自动取景；沉浸聊天时向上调整近景构图以让出底部对话区，可直接左右拖动和双指缩放到上述范围；构图仍自动居中，不提供任意平移或俯仰。按 35° FOV 对包围盒八个角点求透视安全距离，每帧做常量数量计算。近景可自然裁掉下半身；全身依据构建时 30 Hz 采样的逐动作 FramingEnvelope，保留动作空间。大动作暂时全身，结束平滑恢复偏好。取景资料为旧 schema 1 中新增的可选字段，按角色保存。

Idle 为基础待机动画；Wave / Jump / Dance / No 播放一次后回到 Idle。新动作取消旧完成协程，避免旧回调打断新动作。每次重新进入重置动作；取景面板恢复推荐仅预览相机，完成后提交。后台引擎暂停，动画计时随引擎暂停。

触头只接受小于 0.4 秒、位移不超过短边 1.8% 的单指短按。双指序列和拖动不转成头部点击。抬起时将射线变换到当前头部局部空间，对 Luma 的静态网格做双面三角形相交；旧蒙皮头部兼容路径仍可按需 BakeMesh 并重算 bounds。触头播放 No，带 0.35 秒重复触发间隔。点击身体和空白不播放动作。

## 画质与帧率

场景使用原生 renderScale=1、4× MSAA、HDR 内部缓冲、ACES、4096 主光阴影图、两级级联、高质量软阴影、无阴影补光与轮廓光、预生成棚拍反射。HDR 缓冲不代表输出到屏幕的 HDR 显示认证。

PlayerSettings 的 appleEnableProMotion 通过 SerializedObject 设置，宿主 CADisableMinimumFrameDurationOnPhone=true，运行时 targetFrameRate 默认 120，OnDemandRendering.renderFrameInterval=1。Unity 自身的 iOS 显示链负责设置刷新请求并受屏幕及系统限制；不另建竞争的 CADisplayLink。

动画以连续曲线逐渲染帧求值；frameRate=120 是资产采样设置，不是性能保证。RenderPerformance 用预分配数组记录真实墙钟帧间隔，每两秒排序和发一次事件。每次配置、焦点或暂停恢复后首秒为预热，不采样；后续慢帧不丢弃。该统计衡量 Unity player loop，不替代 Metal GPU 捕获或真机实际呈现测量。

## 构建和测试约束

v0.4 宿主构建要求 Unity contentVersion 4 / framingProtocol 1，防止新宿主误连旧引擎。

模拟器与 Device SDK 分别导出到 `build/unity-simulator`、`build/unity-device`；两者都使用 ARM64，但 Mach-O 平台不同，不能混用。`generate_host.py` 为当前选定平台生成一个 workspace，原生业务源码保持一致。

宿主关闭 ENABLE_DEBUG_DYLIB，使 `_mh_execute_header` 指向实际主程序。Run / Test 关闭 `disablePerformanceAntipatternChecker` 所对应的线程性能检查器：此项与 Unity 自身导出设置一致，具体冲突栈见开发记录。其他编译和 UI 测试继续执行。

Pipeline 0.7.0-exp.1 仅供 Editor / Development Build 控制；本轮 Unity 导出使用 BuildOptions.None。测试专用 ready 延迟与事件文件仅在原生 DEBUG + `--ui-testing` 时开启。测试不会用替代模型、假动作或静态图片代替 Unity 画面。

## 参考依据

- [Unity 官方 CLI skill](../.agents/skills/unity-cli/SKILL.md)：通过运行中的 Editor 操作对象和导出。
- [Unity Animation.CrossFade](https://docs.unity3d.com/6000.3/Documentation/ScriptReference/Animation.CrossFade.html)：动作结束后的混合。
- [Unity SkinnedMeshRenderer.BakeMesh](https://docs.unity3d.com/6000.3/Documentation/ScriptReference/SkinnedMeshRenderer.BakeMesh.html)：当前蒙皮姿态快照及局部空间。
- [Paul Hudson SwiftUI Pro](https://github.com/twostraws/SwiftUI-Agent-Skill)：SwiftUI 数据流、可访问性和 API 审查。


## v0.5：角色空间与音频焦点

`HomeView` 负责角色邀请，`CompanionChatView` 独立负责聊天布局、开场、真实状态、无滚动条的消息浏览。`CompanionViews` 保留设定、记忆、历史面板；省略号进入“我们的空间”。v0.6.1 的聊天模式让 Unity viewport 覆盖全屏；`TouchThroughView` 绘制顶部导航与底部聊天渐变，不再把聊天区域后方的 3D 画面裁掉。SwiftUI 聊天最多320pt高、700pt宽，键盘只调整原生浮层；裸露区域触摸透传。`immersive` 近景构图使用静止包围盒而非逐帧头部追踪，因此键盘和呼吸不会驱动相机跳动。独立模型查看页仍使用原有视口。

“我们的空间”使用同一个大尺寸 sheet 内切换目的页，不在 onDismiss 中接力呈现另一个 sheet。音乐独立呈现；`SoundscapeEntry` 单独观察音乐状态，DEBUG 电平证据的刷新不要求整个聊天界面重新求值。

`ViewerCoordinator` 持有唯一 `CompanionSoundscape`，传给每个聊天会话与 `LocalSpeech`。音乐偏好是全局空间偏好，角色聊天/记忆/取景仍按角色隔离。普通偏好使用 UserDefaults 的 `xuyu.soundscape.v1`；UI 测试使用独立 suite，普通启动不读取测试状态。

音频焦点优先级：录音 > 语音 > 音乐。录音使用 playAndRecord 并暂停音乐，语音使用 playback/spokenAudio 并将音乐降到用户音量的18%，无语音时音乐使用 ambient。AVAudioSession 只有这个协调者配置；LocalSpeech.stop() 释放焦点，由协调者决定恢复音乐或停用会话。背景、返回首页和错误页面均暂停音乐。系统中断与耳机移除不自动复播，用户可点继续。无后台音频声明。

内置 PCM 由 AVAudioPlayer 循环，曲目切换使用短交叉淡化，音量变化使用系统 fadeDuration。没有每帧解码/合成音乐；4Hz 音频电平计量的测试计数仅在显式 --ui-testing 模式通过辅助功能导出，不上传遥测、不记录对话。

Unity `CompanionAvatarDriver` 的 AtmosphereRevision1 统一调整背景、雾色与地面材质属性块，不改变角色贴图或有界取景算法。新导出 contentVersion5 / atmosphereRevision1 / framingProtocol1 / companionProtocol1；构建检查拒绝旧导出。同步 eval 的5秒主线程预算不足时，导出就绪探测改走可跟踪后台只读任务，避免重复执行构建。

当前 v0.6.2 宿主门禁要求 contentVersion6 / studioProtocol1 / framingProtocol3 / atmosphereRevision1 / companionProtocol1。framingProtocol2 增加全屏沉浸构图，版本3增加有界直接手势、结束回传和精细面板输入隔离。

直接手势在Unity中逐帧应用，松手后framingGestureEnded回传用户景别／大小／角度。宿主按角色自动持久化，只更新取景字段，不覆盖聊天和人物设定；不反向重发相同配置。双指尾指、三指和系统取消不会落入单指点击分支。

## v0.7 设备内语音

`LocalSpeech → OfflineSpeechEngine（ObjC++ 串行后台队列）→ sherpa-onnx C API → ONNX Runtime CPU`。输入输出均在 App 内存中传递；识别输入是原生录制的 PCM16 WAV，输出为可编辑草稿；合成输出为内存 WAV，交给现有 AVAudioPlayer 与音频焦点协调者。识别、合成不再访问 HTTP，已移除 localhost ATS 例外。

模型由 `prepare_ios_speech.py` 从已锁定的下载缓存组装，Xcode 将 `VoiceModels` 作为文件夹资源复制，以保留字典层级。两份静态 XCFramework 仅链接到宿主，无新的常驻服务、嵌入 Python 或动态下载代码。构建时校验模型哈希；启动时检查资源尺寸；首次使用在后台载入模型。

引擎单例保证进出角色不会产生多个推理线程池，每种模型使用两个 CPU 线程。识别与合成串行、切换前销毁另一模型；内存警告或进入后台使当前任务失效并在队列中释放模型。`cancel()` 的原子代数阻止已排队任务启动、阻止旧输出回放；TTS 进度回调可终止后续句子，但正在执行的 ONNX kernel 不能保证立即中止。Swift 的任务与会话 token 再次过滤过期结果。

通用文字大模型尚未接入；`LocalDialogue.json` 继续提供本地情景回复。详见[端上语音方案](design/2026-09-28-offline-speech.md)。

场景系统现由 EnvironmentDirector / EnvironmentStage 管理，角色工作室桥接只保留兼容入口；新场景通过 XEP 源包导入。当前架构以 [场景平台](environment-standard/02-architecture.md) 为准，旧文中的三个硬编码背景属于历史实现。

持续姿势和对话配置由 [Character API 1.1 姿势标准](character-standard/05-posture-standard.md) 定义。运行时 CharacterPosture 负责参数/转换，CharacterActions 回当前姿势待机，Swift PostureDialogue 负责本地意图解析。

## 横竖屏与窗口适配

原生 AdaptiveViewerLayout 统一计算聊天列、编辑侧栏及模型 compositionArea。方向权限在 AppDelegate 和项目生成器中同时维护；iPhone 支持竖屏/左右横屏，iPad 保留全部方向。Unity 保持全屏 Camera.rect，复用既有 Compose 和 CameraFramingMotion，不新增模型包协议。布局规则与验收见[横屏方案](design/2026-09-28-responsive-landscape.md)。

## 聊天显示与面板退出

原生 `ChatDisplaySettings` 的全局偏好与角色制作契约分离，存为归档可选字段；`AdaptiveViewerLayout` 接收高度偏好，`ConversationContentMask` 给出清晰区域起点，消息列表据此提供顶部滚动余量。`SoftPanelCloseRequest` 统一返回、窗外与滑动退出前的保存，透明窗外按钮只拦截面板外点击，避免传递给 Unity。详见 [0.13 验证](verification/chat-display/README.md)。
