# 模型空间：运行结构与维护入口

更新：2026-09-26。本文描述当前源码，覆盖最初方案中尚未实现和不含动画的早期状态。

## 两套源码，一个 App

原生宿主管首页、关于、加载 / 错误反馈、窗口切换、按钮和生命周期。Unity 管 URP 渲染、镜头、触摸与角色动作。UnityFramework 通过跨工程依赖先构建，再链接并嵌入宿主；场景 Data 属于该框架，运行时按框架实际 bundle ID 加载。

| 源码入口 | 用途 |
|---|---|
| `ios/CharacterHost/App/` | UIApplication / UIWindowScene 生命周期与 SwiftUI 首页 |
| `Features/Home/`、`Features/About/` | 原生界面、模型描述和来源 |
| `Features/Viewer/ViewerCoordinator.swift` | 单一主线程状态、初始化、超时、暂停恢复和消息关联 |
| `Features/Viewer/ViewerOverlayController.swift` | UIKit 返回、复位、动作按钮；其余触摸透传 Unity |
| `Bridge/UnityRuntimeBridge.mm` | Swift ↔ Objective-C++ ↔ UnityFramework |
| `Assets/Scripts/Runtime/ViewerController.cs` | 固定接收对象、手势、相机边界和事件 |
| `Assets/Scripts/Runtime/CharacterActions.cs` | 连续插值动画、头部精确点击、动作中断 / 完成 |
| `Assets/Plugins/iOS/ModelSpaceNative.mm` | Unity C ABI 事件回调，只由框架编译 |
| `Assets/Editor/StudioRobotBuilder.cs` | 原创圆角模型、PBR 材质、棚拍反射与连续动作生成 |
| `Assets/Scripts/Runtime/RenderPerformance.cs` | 60／120 目标与两秒一次的实测帧间隔统计 |
| `Assets/Editor/BuildIos.cs` | 场景生成、校验、SDK 分离、Data 后处理和缩略图 |

## 生命周期

首页 → loading → sceneReady → 关联本次 presentation 的立即复位 → viewReset → 展示 Unity 窗口及原生控件。首次初始化在 80 ms 后开始，使加载页先提交显示；Unity 初始化本身仍含主线程同步工作。

返回只清空触摸并暂停引擎，不 unload / quit。再次打开复用同一实例，恢复引擎、复位相机和角色后展示。加载期间返回会取消展示意图；迟到的 sceneReady 不得抢回前台。再次进入时即使尚未 ready 也先恢复引擎，以便完成初始化。

失活 / 后台时暂停 Unity，恢复后依据页面意图显示首页或查看页。加载超时累计前台定时器 15 次，后台不计数；超时显示可返回的错误页。该计时不是主线程被阻塞时也能强制中断 Unity 的硬超时。

## JSON 桥接契约

接收对象固定为 `AppBridgeReceiver.ReceiveCommand`，不接受由外部指定的对象或方法名。schemaVersion 为 1，消息上限 8,192 个字符。原生回调复制 UTF-8 文本后进入主线程，页面状态由 MainActor 管理。

```json
{"schemaVersion":1,"kind":"command","name":"playAction","requestId":"view-1-8","presentationId":1,"payload":{"action":"Wave"}}
```

| 命令 | 作用 |
|---|---|
| `getState` | 回传相机状态 |
| `resetView` | 恢复默认相机和 Idle；payload.immediate 决定立即或 0.24 秒平滑复位 |
| `configureViewport` | 按当前 Camera.aspect 重算取景，保留相对缩放比例 |
| `configurePerformance` | payload.targetFPS 选择 60 或 120；每次展示与恢复重设请求值 |
| `clearInput` | 清除手势采样，防止返回 / 失活后的跳变 |
| `playAction` | 允许 Wave / Jump / Dance / No，未知名称拒绝 |

事件公共字段为 schemaVersion、kind、name、requestId、modelId、presentationId、yaw、pitch、distance、defaultDistance、message、action、source。`performance` 事件单独携带 targetFPS（请求）、appliedFPS（引擎当前值）、refreshHz、fps、frameCount、windowSeconds、p95Ms、p99Ms、worstMs、over16_7ms、over8_3ms、width、height，不带相机字段。

其他事件名包括 sceneReady、viewReset、state、actionStarted、actionCompleted、actionIdle、headTapped、error。

旧 presentation 命令丢弃；viewReset 需同时匹配 presentation 和 pending request 才结束本次加载。频繁的旋转 / 缩放计算留在 Unity，每帧不穿越桥接；松手后才回报 settled state。

## 相机与角色交互

默认 yaw 155°、pitch 12°；按模型边界、35° FOV 与宽高比计算默认距离。俯仰限制 -8° 到 65°，距离下限在包围球之外，上限为默认距离的 2.2 倍。复位考虑系统 Reduce Motion，开启时原生请求立即复位。

Idle 为基础待机动画；Wave / Jump / Dance / No 播放一次后回到 Idle。新动作取消旧完成协程，避免旧回调打断新动作。复位及每次重新进入都重置动作。后台引擎暂停，动画计时随引擎暂停。

触头只接受小于 0.4 秒、位移不超过短边 2.5% 的单指短按。双指序列和拖动不转成头部点击。抬起时将射线变换到当前头部局部空间，对 Luma 的静态网格做双面三角形相交；旧蒙皮头部兼容路径仍可按需 BakeMesh 并重算 bounds。触头播放 No，带 0.35 秒重复触发间隔。点击身体和空白不播放动作。

## 画质与帧率

场景使用原生 renderScale=1、4× MSAA、HDR 内部缓冲、ACES、4096 主光阴影图、两级级联、高质量软阴影、无阴影补光与轮廓光、预生成棚拍反射。HDR 缓冲不代表输出到屏幕的 HDR 显示认证。

PlayerSettings 的 appleEnableProMotion 通过 SerializedObject 设置，宿主 CADisableMinimumFrameDurationOnPhone=true，运行时 targetFrameRate 默认 120，OnDemandRendering.renderFrameInterval=1。Unity 自身的 iOS 显示链负责设置刷新请求并受屏幕及系统限制；不另建竞争的 CADisplayLink。

动画以连续曲线逐渲染帧求值；frameRate=120 是资产采样设置，不是性能保证。RenderPerformance 用预分配数组记录真实墙钟帧间隔，每两秒排序和发一次事件。每次配置、焦点或暂停恢复后首秒为预热，不采样；后续慢帧不丢弃。该统计衡量 Unity player loop，不替代 Metal GPU 捕获或真机实际呈现测量。

## 构建和测试约束

模拟器与 Device SDK 分别导出到 `build/unity-simulator`、`build/unity-device`；两者都使用 ARM64，但 Mach-O 平台不同，不能混用。`generate_host.py` 为当前选定平台生成一个 workspace，原生业务源码保持一致。

宿主关闭 ENABLE_DEBUG_DYLIB，使 `_mh_execute_header` 指向实际主程序。Run / Test 关闭 `disablePerformanceAntipatternChecker` 所对应的线程性能检查器：此项与 Unity 自身导出设置一致，具体冲突栈见开发记录。其他编译和 UI 测试继续执行。

Pipeline 0.7.0-exp.1 仅供 Editor / Development Build 控制；本轮 Unity 导出使用 BuildOptions.None。测试专用 ready 延迟与事件文件仅在原生 DEBUG + `--ui-testing` 时开启。测试不会用替代模型、假动作或静态图片代替 Unity 画面。

## 参考依据

- [Unity 官方 CLI skill](../.agents/skills/unity-cli/SKILL.md)：通过运行中的 Editor 操作对象和导出。
- [Unity Animation.CrossFade](https://docs.unity3d.com/6000.3/Documentation/ScriptReference/Animation.CrossFade.html)：动作结束后的混合。
- [Unity SkinnedMeshRenderer.BakeMesh](https://docs.unity3d.com/6000.3/Documentation/ScriptReference/SkinnedMeshRenderer.BakeMesh.html)：当前蒙皮姿态快照及局部空间。
- [Paul Hudson SwiftUI Pro](https://github.com/twostraws/SwiftUI-Agent-Skill)：SwiftUI 数据流、可访问性和 API 审查。
