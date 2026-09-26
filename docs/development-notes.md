# V1 开发记录：决策、问题与验证

## 当前交付范围（2026-09-25）

用户授权无人值守完成开发，本轮以 **Xcode iPhone 17 / iOS 26.4 模拟器中的完整 App** 为交付目标，不连接手机或 iPad。实现原生首页、关于、实际 Unity 3D 模型、旋转/缩放/复位、返回与重新进入。双设备真机运行和性能继续保持 NOT TESTED。

2026-09-26 用户追加：动作按钮，以及触碰头部触发摇头。本轮纳入挥手、跳跃、跳舞和触头摇头，覆盖原方案“不做动画”的早期范围约束；其余目标保留。

原方案第 11.3 节的“暂不承诺模拟器”由本轮要求更新：增加独立的 Simulator SDK / ARM64 导出路径，不能把 Device SDK 框架直接用于模拟器。真机路径保留，iPad 原生布局保留。

## 决策记录

### D01 · 同一源码，独立平台产物

Unity 源码与宿主源码分别维护；模拟器和真机导出到不同目录，重导出可恢复 Data、框架头文件和桥接配置。Xcode workspace 是完整 App 的运行入口。运行时始终单实例，返回只暂停。

### D02 · 工具基线与可恢复性

已建立本地 Git 基线，缓存、构建和个人信息被忽略。Unity CLI 1.0.0-beta.6 安装 Pipeline 0.7.0-exp.1，连接 Editor、查询模型及动作、执行正式导出均通过。项目内 C# 工具是构建逻辑的唯一来源，CLI 用于调用，支持 batchmode。

### D03 · 界面方向

产品名“模型空间”。真实机器人缩略图作为首页视觉主体，背景为冷灰白，蓝色控件与模型原本的金黄色搭配；以展品观看为核心，采用大面积留白与安静的操作栏。首次实际渲染发现模型是金黄色，已据实修正初始文案中的颜色描述，保留原始模型材质。

视觉令牌：背景 #F5F7FB、正文 #142338、次级 #65758C、强调 #3563E9、分隔 #DCE3EE。中文与正文使用系统字体，英文模型名和辅助标记使用等宽字。首页一张模型卡片，宽屏按可用宽度调整；不加入无用导航、虚假模型和技术信息。

### D04 · 验证边界

以真实模拟器运行、实际屏幕截图和 UI 自动化验证完整流程。Unity Editor、未签名编译、模拟器结果与实机结果独立记录，不相互冒充。原始日志保存 `.local/logs/`；本文只保留能影响后续维护的发现。

### D05 · 复用模型动作，区分触碰与拖动

通过官方 Unity CLI 查询实际导入资源，确认模型含 14 段 Legacy Animation：本轮采用 Idle、Wave、Jump、Dance、No。动作由单一 `CharacterActions` 控制，一次播放后返回 Idle，新动作打断旧动作，复位和重新进入恢复待机。用户主动操作才播放大幅动作。

再次检索动画 skill，找到社区 `gamedev-skills/.../unity-animation`，但其范围是 Animator/Mecanim，与 GLB 自带的 Legacy Animation 不符，未安装。沿用 Unity 官方 CLI skill，并查阅 Unity 6.3 官方 Animation.CrossFade、SkinnedMeshRenderer.BakeMesh 文档。

触头交互只接受短按、低位移、完整的单指触摸。拖动和双指序列不能误触动作；头部命中在按下后抬起时将当前头部姿态 BakeMesh，再做射线与三角形相交，不使用固定屏幕坐标热区。每次点击才生成网格快照，避免逐帧烘焙。状态通过 JSON 回传，原生按钮显示当前动作。

## 已解决问题

### 技能选择

每个主要环节先检查技能。采用本机 frontend-design、Unity 官方 CLI 内置的 unity-cli（随 1.0.0-beta.6 安装到 `.agents/skills/`）、Paul Hudson 的 swiftui-pro（MIT，源码暂存 `.local/reference-skills/`，检索时 GitHub 4,850 stars）。后者用于数据流、API 与可访问性复查，项目既定 UIKit / iOS 17 约束优先。

检索了 Sentry 的 XcodeBuildMCP（6,425 stars）；当前无该 MCP 连接，已有 Xcode / XCTest / simctl 足以构建与 UI 验证，本轮不为重复能力新增服务。技能搜索与原作者内容复核不替代实际编译测试。

### E01 · 模拟器宿主架构与调试动态库

首轮宿主链接失败：generic Simulator 默认同时请求 x86_64，而 Unity 产物仅含 ARM64。将宿主和 UI 测试目标固定 ARM64，与这台 Apple Silicon Mac 及 Unity 导出一致。另外关闭 Xcode 的 `ENABLE_DEBUG_DYLIB`，让 UaaL 所需 `_mh_execute_header` 位于实际宿主可执行文件中。设置保存在工程生成器，避免手改生成工程后丢失。修复后重新构建验证。

### E02 · 加载取消后的再次打开

状态审查发现：第一次初始化尚未 ready 就返回，会暂停引擎；若再次进入只恢复 ready 的引擎，初始化协程无法继续。改为已启动实例在再次进入时先恢复，ready 后再复位显示；仍不启动第二个实例。将异常时序列入后续 UI 测试。

### E03 · XCTest 启动白屏：诊断工具与 Unity 分配器冲突

前两轮 XCTest 在 `Setting up automation session` 后等待约 60 秒，随后报 `kAXErrorServerNotFound`；普通 simctl 启动可显示首页。对失败进程采样发现启动仍停在 dyld 初始化：`UnityRuntime operator new → InitializeMemory → libRPAC interposed_dispatch_semaphore_create → initializePrimitiveMap → operator new → InitializeMemoryLazily → pthread_cond_wait`。因此不是 SwiftUI 窗口缺失，而是线程性能检查器和 Unity 分配器初始化重入。

核对当前 Unity 自己导出的 `Unity-iPhone.xcscheme`，其 LaunchAction 已设置 `disablePerformanceAntipatternChecker="YES"`。将同一设置保存到原生工程生成器的 Run 和 Test 两处；保留其余测试。采样证据 `.local/checks/test-launch-sample.txt`，失败结果 `ViewerFlow-1/2.xcresult`。不把与症状同时出现的 LLDB version 警告误认作已证明的根因。

### E04 · 首页图片资源解析

系统日志明确报告 `No image named 'RobotThumbnail' found in asset catalog`。图片虽已复制到 App 根目录，SwiftUI 图片解析仍未找到。改为标准 `Assets.xcassets/RobotThumbnail.imageset`，项目生成器统一编译资产目录，Unity 的缩略图导出也指向该 imageset。App 图标通过项目内 AppKit 向量脚本绘制，避免新增图片来源及版权依赖。

### E05 · 加载覆盖层的可访问性标识继承

新增取消和超时测试找不到返回按钮。导出失败时的 UI hierarchy 后确认按钮实际存在，但 SwiftUI 将根覆盖层的 `loadingScreen` 标识传播给了子元素，覆盖子按钮的 `cancelLoadingButton`。移除无用的父标识，同时隐藏覆盖层下面首页的可访问性元素，并将返回按钮点击区域扩大到至少 48 点。此问题与引擎恢复无关；早期状态审查中的恢复修复仍保留，最终由异常时序测试确认。

### E06 · Editor 重载时 CLI 短暂离线

刷新 C# 后立即导出，Pipeline 在域重载期间暂时不出现在 `unity status`；最初脚本误用 batchmode，触发工程占用错误。脚本现在通过 `Temp/UnityLockfile` 的实际进程占用检查区分“没有 Editor”与“现有 Editor 正在重载”，后者等待连接恢复；仍不就绪时报告编译问题，不启动第二个 Editor。完成状态还必须含内部 `success=true` 才接受。

### E07 · 动画头部点击的包围盒

动作按钮已触发实际骨骼动画，但首轮触头没有事件。使用 CLI 在 Editor Play Mode 查询，确认 BakeMesh 输出 1,742 顶点 / 810 三角形，但新 Mesh.bounds 仍为零，提前筛选因此拒绝真实头部射线。在 BakeMesh 后显式 RecalculateBounds，再做局部射线与三角形相交。原始头部骨架缩放为 100，使用逆变换处理，不能混用世界射线与局部顶点。

附带视觉修复：原生图标首次使用三通道 NSBitmapImageRep 作为绘图上下文得到全黑，改用明确的 32 位 CGContext / noneSkipLast，视觉复核为蓝底立方体且无透明通道。场景阴影距离从 18 扩至 45，覆盖默认约 21.36 的相机距离，避免初始视角地面阴影被剔除。

## 交付证据（2026-09-26）

完整 App 已在 iPhone 17 / iOS 26.4 Simulator 运行。最终 `ViewerFlow-20260926-002150` 为 **3 tests passed、0 failures、0 skipped**；另有 72 条实际引擎事件的数值 / 动作断言通过。覆盖 22 次展示、24 次相机复位，sceneReady 只有 1 次；Wave / Jump / Dance / No 均开始和完成，头部命中 1 次，非头部操作没有误触。

复核了首页、查看页、关于、四种动作、取消与超时反馈的真实 PNG，以及 11.3 秒 simctl 动作录像。16 张截图与压缩录像保存在 `docs/media/`，可复查的结果摘要在 `docs/verification/`，大体积原始 `.xcresult` 与失败轮次保留于 `.local/checks/`。具体路径和验收边界见[模拟器报告](simulator-acceptance.md)。

开发入口已整理为 `export_unity_ios.py`、`build_host.sh`、`run_simulator.sh`、`test_simulator.sh`；README 说明日常修改、Xcode workspace 入口、从干净目录恢复和未来真机签名。原始交接文档保持原文，设计方案顶部注明新的模拟器 / 动作范围。

本轮未连接真机，iPad 仅完成源码布局和 Universal 配置；真机性能与 iPad 运行结果均保持 NOT TESTED。下一阶段可直接用现有 device 导出路径进行签名和逐设备测试。

## 2026-09-26 · Luma 画质与高刷新率升级

### D06：原创简单模型，把预算用于表面质量和实时渲染

用户新增要求为高清模型、阴影和高于 60 / 支持 120 FPS。保留原有查看器、生命周期与四种交互动作，将默认 GLB 替换为项目原创 Luma。几何体、PBR 材质、棚拍反射和连续动画都由 `StudioRobotBuilder.cs` 生成，无需外部美术服务、账号或新下载。当前模型 35 个 Renderer、70,980 个三角面，6 种共享材质。圆角采用解析法线；薄面板使用各轴独立半径，避免厚度小于圆角半径时翻折。静态关节模型用 Transform 动画，免去每帧蒙皮成本；触头只在点击时进行网格射线检测。

### D07：120 是请求，实测与验收单独保留

Unity 原先的 `Application.targetFrameRate=60` 和关闭的 `appleEnableProMotion` 都需修改；宿主已有的 `CADisableMinimumFrameDurationOnPhone=true` 保留。现默认请求 120，菜单可切 60，关闭按需跳帧，每个渲染帧连续求值动作。复用 Unity 的 iOS display link，不额外创建竞争的 display link，也不绕过系统热管理。

`RenderPerformance` 记录墙钟帧间隔：平均 FPS、P95/P99、最慢帧、8.33/16.67ms 超预算数量、请求值 / 引擎实际配置值 / 显示刷新率 / 分辨率。固定数组避免逐帧分配；每两秒统计一次。配置或焦点、暂停恢复后的首秒明确作为预热排除，其他慢帧全部保留。界面显示实测与目标两项，避免把 120 的设置值当作 120 的测量值。该统计是 Unity player loop，不是 Metal GPU 完成或屏幕真实呈现时间。严格每帧高于 60 不能靠限帧 API 保证；真机持续测试仍需单列验收。

画质配置为原生分辨率 renderScale=1、4× MSAA、HDR 内部缓冲、ACES、4096 主光阴影图、两级级联、高质量软阴影、补光和轮廓光、预生成反射。没有为了数字好看而降低分辨率或关闭阴影。

依据：
- [Unity 6.3 targetFrameRate](https://docs.unity3d.com/6000.3/Documentation/ScriptReference/Application-targetFrameRate.html)：移动设备刷新率上限与 ProMotion 开关。
- [Apple ProMotion](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays)：宿主 plist 与刷新请求。
- [Apple preferredFrameRateRange](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink/preferredframeraterange)：低电量、温度及系统策略会影响可用刷新率。
- [iPhone 17](https://www.apple.com/iphone-17/specs/)、[iPad Pro 11 英寸 M4](https://support.apple.com/en-us/119892)：指定型号支持最高 120 Hz。

Skill 检索执行 `npx skills find 'unity rendering'`。继续使用项目内 Unity 官方 `unity-cli` skill；检索到的 2D pixel-perfect 与当前 3D 需求不匹配，通用第三方渲染 skill 未采用。渲染 API 以本机固定 URP 包源码与 Unity / Apple 一手资料为准。

### E08：编译失败时，CLI 仍可能运行旧程序集

尝试通过公开属性设置软阴影与 ProMotion 时，当前版本报出只读属性 / 不存在 API 的错误。虽然 CLI eval 返回成功，实际执行的是此前加载的程序集。改用 Editor `SerializedObject` 设置真实字段，并将 `EditorUtility.scriptCompilationFailed` 纳入导出前探针和 Setup 检查；编译失败不能作为成功场景继续导出。

动画端点因浮点 sin(π) 略小于零，经分数次幂生成 NaN，使 SmoothTangents 失败。对包络先 clamp 到非负值，再计算幂，消除根因。

### E09：Mesh 的 CPU 数据更新，不代表 GPU 缓冲已经更新

薄面板几何修正后，CPU 顶点 / bounds / 三角形方向都正确，截图却仍出现面罩中央被壳体遮挡。逐个隔离 Renderer、着色诊断与重设网格缓冲确认：`EditorUtility.CopySerialized` 保留了旧 GPU 数据。生成器改为对已有 Mesh 调用 Clear，并显式赋值 vertices / normals / uv / triangles，刷新真实渲染缓存。Cubemap 同样通过 SetPixels / Apply 更新；普通 AnimationClip 继续序列化复制。重建时 GUID 不变，引用稳定，编辑器预览与打包数据一致。

### E10：导出等待的是 macOS 授权弹窗，不是编译

导出停在 shader 序列化后，采样主线程定位 `IsXcodeProjectOpen → ScriptingBridge → Apple Event`，界面为 Unity 请求控制 Xcode。拒绝额外自动化权限后，Unity 正常继续 IL2CPP 导出，命令行 Xcode 构建无需该授权。无需重启工程或重复发出导出命令。

### E11：新模型的真实触头坐标与验收边界

首轮升级测试 `ViewerFlow-20260926-082959` 的加载取消 / 超时恢复通过，完整流程在触头处失败。实际复位截图显示新模型头部位于屏幕高度约 21%–39%，旧用例点击 40% 已处于颈部。将真实点击与从头部开始拖动的坐标改为 31%，不放宽头部命中区域，也不删除身体 / 空白负例。此轮同时观察到目标 120、引擎应用值 60、显示刷新率 60；据此补充可见的屏幕上限，避免误解。

真机上的 120 或严格高于 60 尚未验收。Simulator 60 Hz 限制属于本轮实测边界，不用提高请求数字、丢弃慢帧或伪造统计绕过。

### D08：默认构图覆盖完整动作，阴影覆盖整个缩放范围

功能通过后，截图审查发现挥手外摆会被默认画面边缘裁掉。扩大默认横向 / 纵向动作留白，以每条动画 61 个时刻、每个 Renderer 的包围盒角点投影验证 iPhone 17、iPad 11 英寸纵横屏三种比例；这只是编辑器数值验证，不替代 iPad 实机 / 模拟器测试。最终 iPhone 默认取景下所有动作的横向范围约为 9%–92%，头部正例坐标随最终构图更新为屏幕高度 37%。同时将阴影距离设为 50，覆盖最大 2.2 倍缩远时的模型，避免只在默认视角有影子。

### Luma 最终证据

`ViewerFlow-20260926-084457`：3 tests passed / 0 failures / 0 skipped，102 条引擎事件校验 PASS，22 次展示、24 次复位、四动作与头部正负例通过。30 个性能窗口保留；请求 120 的组为 3119 帧 / 52.233s，平均 59.71 FPS，Unity 应用值与报告刷新率均为 60，最慢帧 105.340ms。该功能自动化样本不满足每帧严格高于 60，真机 120 / 长时性能仍 NOT_TESTED；没有将配置支持冒充性能验收通过。完整证据、新版 18 张截图与实际动作录像见 `docs/luma-quality-performance.md`。
