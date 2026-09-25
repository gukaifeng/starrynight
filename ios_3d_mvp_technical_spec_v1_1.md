# iOS 原生 App + 3D 示例角色
## V0 技术实施方案 · AI 审阅与开发交接版

**文档版本：** 1.1（双设备定向适配修订）  
**编制日期：** 2026-09-25  
**阶段目标：** 免费个人签名的 iPhone / iPad 双设备真机原型  
**唯一目标设备：** iPhone 17 标准版；11 英寸 iPad Pro（M4，2024 年款）。  
**状态：** 技术设计与实施要求；不是已编译或已通过真机测试的工程。

> **本版只交付一个最小闭环：打开原生 App → 点击“查看示例角色” → 显示本地 3D 模型与原生返回按钮 → 返回首页 → 可以再次进入。**
>
> 不接 AI，不录音，不播放语音，不做角色动作、口型、触摸部位识别、多角色、账号、服务端或上架。模型只用于验证集成链路，不代表最终产品的美术质量或复杂角色的性能。

本文中的“必须”是 V0 的验收约束，“建议”是可在审阅后调整的设计选择。外部事实以 [S01] 等编号标注，原始来源见文末。性能数值是工程目标，不是已测结果。

---

# 1. 范围与成功标准

## 1.1 必须实现

| 编号 | 需求 | 验收说明 |
|---|---|---|
| R01 | 真正的原生 iOS 宿主 App | 首页与关于页用 SwiftUI；不是 WebView，也不是 Unity 制作的假原生首页。 |
| R02 | 一个默认 3D 模型 | 使用本文指定的 RobotExpressive；允许静态姿势，不自行建模。 |
| R03 | 原生与 3D 页面切换 | 从首页进入全屏 Unity 展示页，点击原生“返回”回到首页。 |
| R04 | 原生覆盖控件 | 在 3D 画面上方显示返回、重置视角及调试信息。 |
| R05 | 可重复进入 | 同一进程反复进入、退出 20 次，不重复启动 Unity，不崩溃。 |
| R06 | 本地资源 | 模型、材质、场景随应用打包；运行展示不访问模型下载地址。 |
| R07 | 免费真机测试 | 使用 Xcode Personal Team，同一宿主 App 分别在用户的 iPhone 17 标准版和 11 英寸 iPad Pro（M4，2024）上 Run。 |
| R08 | 可交接工程 | 保留原生与 Unity 源工程、版本锁定、构建步骤、授权记录、两台设备各自的测试记录。 |
| R09 | 两种屏幕的原生适配 | iPad 使用真正的 iPad 界面尺寸，不以 iPhone 兼容放大模式代替；两端均正确显示首页、模型与覆盖按钮。 |

## 1.2 明确不做

本版不实现 AI 聊天、ASR/TTS、麦克风权限、摄像头权限、动作播放、面部表情系统、触摸部位识别、云端资源下载、多角色切换、资源热更新、后台服务、登录、订阅、支付、消息推送、TestFlight、App Store、Android 或本版指定两款之外的 iPhone / iPad 机型适配。iPad 横屏专项优化、分屏/台前调度、多窗口、外接屏与 Apple Pencil 专项功能也不列入本版交付。

不安装 UniVRM、动画控制平台、实时语音 SDK、Addressables、Firebase、跨平台 UI 框架、在线分析 SDK 或广告 SDK。后续需要时再增加，不提前搭建空架构。

**诊断例外：** 可提供一个默认关闭的“相机缓慢环绕”开关，用来观察连续渲染；它不是角色动画。关闭后模型必须静止。

## 1.3 本次验证的边界

V0 验证的是“原生宿主 + Unity 嵌入 + 本地模型 + 个人签名 + 生命周期”的可行性。一个轻量示例模型达到高帧率，不能证明未来高精度人物、头发、面部动画和实时语音一起运行也能达到相同帧率。

未来的高画质、高流畅度目标保留，但不要把“最终精修人物达到 120 FPS”混入本版完成定义。

## 1.4 唯一目标设备与支持边界（v1.1 新增）

用户已确认实际持有下列两台设备；它们是本版唯一必测、必适配机型，不再使用“任意一台 iPhone”作为验收条件。

| 设备 ID | 正式机型 | 与本次适配相关的官方规格 |
|---|---|---|
| D01 | iPhone 17 标准版 | A19；6.3 英寸显示屏；2622 × 1206 像素；ProMotion 最高 120Hz。[S17] |
| D02 | 11 英寸 iPad Pro（M4，2024 年款） | M4；2420 × 1668 像素；ProMotion 10–120Hz。[S18] |

**型号确认：** 2024 年 M4 iPad Pro 的小尺寸款，正式名称为“11 英寸 iPad Pro（M4）”，不是 10 英寸或 10.9 英寸。Apple 的矩形对角线测量注释写 11.1 英寸，这是同一款产品的测量说明，不是另一款待适配机型。[S18]

**范围约束：** iPhone 17 指标准版，不是 iPhone 17 Pro / Pro Max / Air；iPad 指上述 2024 年 M4 的 11 英寸款，不扩展到 13 英寸款或其他代际。这里定义的是研发与测试范围，不要求编写按硬件型号拒绝启动的白名单。

**系统与容量：** 两台设备实际安装的 iOS / iPadOS 版本、iPad 容量和内存档位尚未提供，实施者从设备读取后记录，不得按型号推断为某个当前系统或最高内存配置。Apple 对 M4 iPad Pro 列有不同存储对应的芯片/内存配置，不能默认用户持有 16GB 版本。[S18]

**本版显示策略：** 两台设备均以单个 App 场景、全屏竖屏作为基础验收条件，沿用 V0 的低复杂度展示方式。iPad 首页使用合理内容宽度；3D 场景覆盖当前完整展示区域；取景与按钮适配实际宽高比和安全区。横屏专项优化与多任务窗口体验暂不作为交付目标，不得借此省略 iPad 全屏适配。

**完成门槛：** D01 与 D02 分别完成安装、显示、返回、20 次循环、前后台及性能记录。只验证其中一台，整体状态只能是“部分完成”。基础模型、无语音、无角色动作的范围保持不变。

# 2. 免费真机运行：可以不付费，但不能完全不签名

## 2.1 采用的方式

使用 Xcode 登录普通 Apple Account，在宿主 App 的 Signing & Capabilities 中选择 **Personal Team**，启用自动签名，然后分别连接自己的 iPhone 17 标准版与 11 英寸 iPad Pro（M4，2024），逐台选择设备并执行 Run。

这不要求购买付费 Apple Developer Program，也不要求 App Store Connect 或 TestFlight。但仍需要 Apple Account、必要协议确认、设备配对和开发签名；不存在通用的“什么账号也不登录、随便安装未签名 App”的测试模式。[S01]

## 2.2 当前个人签名限制

Apple 当前说明：个人团队最多注册 10 个 App ID、3 台设备，每台设备最多安装 3 个此类 App；相关期限及个人 provisioning profile 为 7 天。过期后需要重新构建并安装。[S01]

本项目只使用一个稳定的宿主 Bundle Identifier。不要为了排错反复随机生成新标识，也不要为了显示不同模型创建不同 App ID。

本版不是他人长期安装的分发方案。个人开发签名到期并不等于项目坏了，也不应通过修改业务代码来“修复”到期问题。

## 2.3 人工操作与安全

账号登录、双重验证、设备信任、开发者模式确认由用户本人完成。不要把 Apple 密码、验证码、私钥、证书或 provisioning profile 发给 AI 或提交到仓库。

真机需按 Apple 指引启用 Developer Mode；开关位置和确认流程以设备系统提示为准。[S02]

Unity 编辑器账号、编辑器授权与 Apple 个人签名是不同事项。实现者仍需使用自己所在地可合法获得、许可适用的引擎版本；本方案不承诺任何用途都天然享有免费 Unity 授权。[S16]

# 3. 技术选择与环境冻结

## 3.1 唯一主路线

| 层次 | 选型 | 原因与约束 |
|---|---|---|
| 原生普通界面 | SwiftUI | 首页、关于页以代码实现，便于 AI 修改和预览。 |
| App 生命周期与窗口 | UIKit AppDelegate + SceneDelegate | 将窗口、场景和引擎生命周期集中管理；SwiftUI 通过 UIHostingController 显示。 |
| 原生引擎桥接 | 少量 Objective-C++ + Swift 接口 | Mach-O header、UnityFramework 和 C 回调隔离在桥接模块中。 |
| 3D 引擎 | Unity 6.3 LTS，具体补丁版在环境检查后锁定 | 官方存在 iOS 原生嵌入路径；本版不追 Update/Beta 版本。[S03][S04] |
| 渲染 | URP + Metal | 使用与引擎模板匹配的 URP 包，不使用 HDRP。 |
| 模型导入 | Unity glTFast 6.14.1 作为起始候选 | 仅用于编辑器内导入 GLB；必须先验证与选定引擎的兼容性。[S08][S09] |
| 模型 | three.js r180 示例 RobotExpressive | 固定来源标签，独立 GLB，来源 README 标注 CC0。[S07] |
| 打包 | Unity 导出 iOS 工程 + Xcode workspace | 最终运行目标是原生宿主，不是 Unity 自带 launcher。 |

采用 UIKit 入口不意味着普通页面都手写 UIKit。AppDelegate/SceneDelegate 只负责平台生命周期；首页仍是 SwiftUI。工程中不得同时保留两个 App 入口，例如同时使用 UIApplicationMain 和独立的 SwiftUI `@main App`。

**为什么本版仍保留 Unity：** 仅做静态模型时，苹果原生 3D 路线也可实现；但本版目的是验证此前确定的可扩展角色模块，所以不为了减少当前几行代码而换渲染架构。

## 3.2 工具版本不是“最新”两个字

Unity 官方当前列出 6.3 LTS 分支；Apple 列出了不同 Xcode 对 macOS、SDK 和真机系统的支持范围。[S03][S10] 这些资料并不等于本文已经验证过某一组完整组合。

开工先创建 `docs/environment.md`，至少记录：macOS 完整版本、芯片架构、Xcode 版本与 build number、D01 的 iOS 版本、D02 的 iPadOS 版本及实际容量/内存信息、Unity 完整补丁号、URP 版本、glTFast 版本、Swift language mode、Deployment Target。

产品设备范围固定为第 1.4 节的 **D01 + D02**；基础测试使用全屏竖屏和一个 App 场景。Deployment Target 暂沿用 iOS / iPadOS 17.0 作为配置起点，实施前需满足实际代码、引擎和 SDK 的要求。最低部署版本不等于设备实际系统，也不构成对其他旧机型/旧系统的支持承诺。Xcode 必须同时支持这两台设备当前安装的系统；不能仅修改 Deployment Target 来解决 SDK 不认识设备的问题。

在本机先通过“空白原生 App 免费安装”和“Unity 简单场景导出编译”两道检查，再冻结版本。锁定后提交 `ProjectVersion.txt`、`manifest.json`、`packages-lock.json`，不得留下浮动版本。任何升级先单独验证，不在排错途中连续升级所有组件。

若所在地区只能使用其他 Unity 发行版本，先验证相同的嵌入与导入链路并记录差异；不能把其他发行版与本方案的版本号混写成已验证组合。不要通过规避地区或许可限制获取引擎。

## 3.3 本阶段硬件与软件

开发仍需一台能运行所选 macOS/Xcode/Unity 的 Mac；测试设备直接使用用户已有的 iPhone 17 标准版和 11 英寸 iPad Pro（M4，2024），配可传输数据的连接线，允许逐台连接。无需额外购买测试手机或平板。现有 Mac 的型号和系统需另行记录，不推断用户已经拥有某款 Mac；GPU 服务器、动捕设备和第二套开发电脑均非本版要求。

安装 Xcode、Unity Hub、Unity 编辑器的 iOS Build Support、Git。资源获取辅助脚本使用 Python 3；没有 Python 时可按本文地址手动下载。模型制作软件、后端和云服务均非本版依赖。

# 4. 示例模型：确定来源、许可和获取方式

## 4.1 默认模型

使用 **RobotExpressive**，作者 Tomás Laulhé（Quaternius），Don McCurdy 对示例资源作过整理。来源 README 标注 CC0 1.0。[S07]

这是一个风格化机器人角色，不是精修真人。它适合验证人物形态、网格、材质、相机取景和嵌入显示；不能作为最终产品的美术质量承诺。

固定资源地址：

```text
仓库：https://github.com/mrdoob/three.js
标签：r180
模型：examples/models/gltf/RobotExpressive/RobotExpressive.glb
说明：examples/models/gltf/RobotExpressive/README.md
```

直接下载地址：

https://raw.githubusercontent.com/mrdoob/three.js/r180/examples/models/gltf/RobotExpressive/RobotExpressive.glb

许可与作者说明：

https://raw.githubusercontent.com/mrdoob/three.js/r180/examples/models/gltf/RobotExpressive/README.md

读取的是这个模型自己的许可，不能只因为它位于某个代码仓库，就推断模型自动采用仓库代码的 MIT 许可。

## 4.2 获取和保存

交接包附有 `reference/fetch_sample_asset.py`，用于在实现者电脑上下载模型与来源说明，检查 GLB 文件头和 JSON chunk，并生成 SHA-256 记录。脚本是辅助工具，不是 Unity 工程，也不能替代导入与真机测试。

**交接包不包含模型二进制文件。** 本次核实了模型来源与 README；没有在此环境中完成该 GLB 的下载、Unity 导入或上述两台设备的渲染测试。实现者必须实际下载、校验并将结果写入资产记录。

资源进入目标工程后建议保存为：

```text
unity/CharacterRuntime/Assets/ThirdParty/RobotExpressive/
    RobotExpressive.glb
    SOURCE_README.md
    asset-lock.json
    LICENSE_NOTICE.md
```

记录来源标签、下载地址、文件大小、SHA-256、获取日期、作者、许可与本项目修改内容。仓库可按许可保存模型；模型变大时再使用 Git LFS，本版不强制增加这一依赖。

资源无法下载时，应说明网络或来源问题并恢复获取路径。方块/胶囊可以临时定位引擎问题，但最终 R02 不得用方块、二维图片或视频替代。

# 5. 总体架构与页面

## 5.1 模块结构

```text
CharacterHost（原生 App，唯一安装包）
  AppDelegate / SceneDelegate
  SwiftUI HomeView / AboutView
  CharacterCoordinator（页面状态）
  UnityRuntimeBridge（原生与引擎边界）
  NativeOverlayView（返回、重置、调试标签）
               |
               v
UnityFramework（同一进程中的单个引擎实例）
  DemoScene
  AppBridgeReceiver
  ImportedRobotPrefab
  CameraRig / Light / Ground
  DemoDiagnostics
```

宿主通过 UnityFramework 接入引擎；不把每帧画面转换成 UIImage，不经 WebView，不以网络视频展示模型。Unity 官方 iOS 嵌入方案支持此类原生宿主，并以全屏渲染、单运行时为边界。[S04][S05]

## 5.2 页面定义

**首页 Home：** 标题“3D 角色原型”，简短说明，一个“查看示例角色”主按钮，一个“关于此原型”入口。首次打开时不启动 Unity 场景。

**关于页 About：** 显示版本、模型名、作者/许可说明、“暂未接入 AI”的说明和返回操作。模型来源可用系统浏览器打开，但 App 正常展示不依赖此页面联网。

**角色页 Viewer：** Unity 全屏画面为底层；左上是原生返回按钮，右上是原生重置视角按钮，底部小型状态条显示模型名和诊断信息。控件避开安全区，不制作聊天输入框。D01 检查灵动岛与底部手势区，D02 检查平板宽高比、四周边距与状态栏/手势区；禁止把 iPhone 固定像素位置直接放大到 iPad。

**加载/错误状态：** 提示“正在准备示例角色”；失败后给出可读原因、返回入口和日志编号。不要无限转圈，也不要用固定延时假装资源已就绪。

## 5.3 本版采用的嵌入形态

采用“Unity 全屏窗口 + 原生控件覆盖 + 返回宿主窗口”，参考官方 iOS 示例。示例明确演示在 Unity 画面中添加原生按钮。[S06]

不把 Unity 当作列表中的局部控件，不做 SwiftUI 任意尺寸 `UIViewRepresentable` 重挂 Unity rootView 的方案，不支持多个 Unity 窗口或多角色同时运行。

# 6. Unity 场景与模型导入

## 6.1 导入流程

创建 URP 项目，安装并锁定 glTFast，将 GLB 放入 `Assets/ThirdParty/RobotExpressive/`。glTFast 支持编辑器导入并生成 Unity 原生 Prefab 与相关子资源。[S08]

在编辑器内确认网格、材质和可见外观，再创建本项目的 `DefaultCharacter.prefab` 作为包装层。包装层保留对导入资源的引用，不直接覆盖原始 GLB。

场景直接引用包装 Prefab，使依赖随 Unity 构建进入应用。不得在运行时访问 GitHub、调用 AssetDatabase、从公网解析 GLB，或为了一个内置模型引入 Addressables。

只保留一个 `.glb` 默认导入器。发生导入器冲突时检查包依赖，不靠重复安装多个 glTF 插件碰运气。[S08]

## 6.2 场景对象

```text
DemoScene
  AppBridgeReceiver      # 唯一命名，供宿主发送命令
  SceneBootstrap         # 检查模型引用并通知场景就绪
  CharacterRoot
    DefaultCharacter     # 一个实例
  CameraRig
    MainCamera
  MainLight
  Ground
  DemoDiagnostics
```

禁止自动播放资源自带动画。关闭自动 Animator/Animation 播放，但保留渲染所需的骨骼与蒙皮数据。验收允许模型保持导入静态姿势；不要为了做待机动画扩大本版范围。

模型如果倒向、背对相机或大小不适合，优先在包装层调整旋转、位移和缩放，不修改网格顶点。不得对导入器已经转换过的坐标系再盲目重复翻转。

## 6.3 相机与材质

镜头需要完整显示头与脚，并留出原生覆盖按钮空间。建议根据所有有效 Renderer 的包围盒计算取景；只有一个已锁定模型时，也允许把验证过的镜头参数保存为配置，但必须分别验证 D01 与 D02 的取景。相机纵横比取当前实际渲染区域，模型保持等比缩放；不能拉伸模型来填满 iPad。

采用透视相机，禁止把模型裁成只剩局部。实现重置视角，使其恢复到同一套默认参数。可选环绕只改变相机，不播放角色动作。

先保留 glTFast 为 URP 导入的材质并验证真机。若要替换成 URP/Lit，需逐项映射基础色、法线、金属度与粗糙度约定，不能只改 Shader 名称就认为等价。缺失材质、粉色 Shader、全黑角色都视为失败。

## 6.4 最小渲染配置

| 设置 | V0 起点 |
|---|---|
| 图形 API | Metal |
| 脚本后端 / 架构 | IL2CPP / ARM64，目标为真机 |
| 渲染管线 | URP，Graphics 与 Quality 的有效管线配置一致 |
| 场景 | 单相机、单主要灯光、简单背景、简单地面 |
| MSAA | 2x 起步，按实际设备记录 |
| HDR / 后期 / SSAO | 首版关闭，不作为视觉卖点验证 |
| 阴影 | 可关闭或保留一个低成本主光阴影；不得动态改画质掩盖问题 |
| 渲染比例 | 1.0 起步，测试报告记录实际值 |
| 更新 | 持续渲染，诊断时不得偷偷设置隔帧渲染 |
| 默认目标帧率 | 60 基线；D01 / D02 均提供并测试 120 诊断档，结果单独记录 |

这些是为了获得可比较的 V0 基线，并非最终高品质人物场景的配置建议。

# 7. 原生工程与 UnityFramework 集成

## 7.1 工程布局

```text
project/
  README.md
  docs/
    technical-spec.md
    environment.md
    acceptance-report.md
    decisions.md
  ios/
    CharacterHost.xcodeproj/
    CharacterPrototype.xcworkspace/
    CharacterHost/
      AppDelegate.swift
      SceneDelegate.swift
      HomeView.swift
      AboutView.swift
      CharacterCoordinator.swift
      UnityRuntimeBridge.h
      UnityRuntimeBridge.mm
      NativeOverlayView.swift
    Config/
      Local.example.xcconfig
  unity/CharacterRuntime/
    Assets/Scenes/DemoScene.unity
    Assets/Scripts/Runtime/
    Assets/Editor/
    Assets/Plugins/iOS/DemoNativeBridge.h
    Assets/Plugins/iOS/DemoNativeBridge.mm
    Assets/ThirdParty/RobotExpressive/
    Packages/
    ProjectSettings/
  build/unity-ios/          # Unity 生成，可删除并重建
  scripts/
    fetch_sample_asset.py
    export_unity_ios.sh
    verify_export.py
  contracts/bridge-v1.schema.json
  THIRD_PARTY_NOTICES.md
```

这是实施工程的目标结构，不代表交接包里已存在这些可运行源码。实现者可以调整文件拆分，但不得改变职责和边界。

## 7.2 两个 Xcode 工程，一个 workspace

Unity 导出生成 `Unity-iPhone.xcodeproj`，其中包含 `UnityFramework` 库 target 与 `Unity-iPhone` launcher target。**导出目录中不一定已经有可用的 UnityFramework.framework；需要由 Xcode 构建库 target 产生。**[S04]

将原生 `CharacterHost.xcodeproj` 和生成的 Unity 工程加入同一 workspace。最终运行并签名的是 `CharacterHost` scheme，不是 Unity launcher。

**本方案选用显式链接路线：** 宿主链接 UnityFramework，同时在嵌入阶段执行 Embed & Sign；让 workspace 按依赖顺序构建框架。框架二进制随宿主装入不等于已启动 Unity 场景，真正的运行时初始化仍延迟到点击进入。

官方示例还包含通过 NSBundle 动态加载并移除 Link 项的做法。[S06] 本版不要把它与显式链接混在一起：既删掉链接又直接调用外部符号，会造成链接错误。改用动态加载属于架构变更，应完整实现并记录理由，而不是只复制示例中的某一步。

## 7.3 Data 目录是首要检查点

Unity 导出的 Data 默认归属 launcher。对于本版，把 Data 的 Target Membership 调整到 UnityFramework，并在启动运行时之前用 `setDataBundleId` 指定实际承载 Data 的 bundle。[S11]

不要盲目硬编码某个 bundle ID 后又在 Xcode 中改成另一个值。构建后必须在产物中确认 `UnityFramework.framework/Data` 真实存在。

将 Data 归属、桥接头文件可见性等可重复修改写入 Unity Editor 的 iOS 导出后处理脚本，优先使用 PBXProject API，而不是反复手改生成的 pbxproj。[S11]

重导出后应仍能构建。若第一轮使用 Xcode 图形界面配置，必须把操作记录下来，并至少把 Data 与桥接文件处理自动化；不要承诺未实现的一键全自动工程生成。

## 7.4 平台与签名设置

宿主和 UnityFramework 的设备架构、有效最低系统版本、SDK 配置应兼容。真机产物不能拿去链接模拟器，模拟器产物也不能装到真机。

宿主开启自动签名并选择 Personal Team。框架由构建与嵌入过程正确签名；不要给 framework 单独创建一个要安装的 App，也不要通过关闭最终宿主签名来绕过安装错误。

只构建本版需要的 target。不要让未使用的 Unity launcher 把无关 capability 或额外签名配置带入主路径。

## 7.5 iPhone / iPad Universal 构建与布局（v1.1 新增）

宿主 Target 的 Supported Destinations / Targeted Device Family 同时选择 iPhone 与 iPad（通常为 `TARGETED_DEVICE_FAMILY = "1,2"`）。由 Xcode 生成相应 `UIDeviceFamily`；不要手改产物里的键值伪装支持。Apple 说明该键由 Xcode 的设备族设置生成。[S19]

Unity iOS Player 的 Target Device 同样设为 iPhone + iPad；检查导出后与最终宿主一致。两台设备使用同一套原生/Unity 工程与宿主 Bundle Identifier，不维护两份 App，也不把 iPad 当作模拟器目标。

首页/关于页使用 SwiftUI 自适应约束：iPad 可将主要内容居中并设合理最大宽度，按钮保持正常点尺寸；Unity 展示区仍铺满完整角色页面。布局以当前窗口/容器尺寸及安全区为依据，不以屏幕规格表里的物理像素硬编码 UI。

本版全屏竖屏属于测试前提，不是对所有 iPadOS 窗口行为的保证。实施者应在实际 SDK / iPadOS 上核对方向和全屏配置，不假定某个旧的全屏标志可以永远禁止窗口变化。首次加载、回前台及容器尺寸变化后校验画面和覆盖层；本版不支持的展示模式应可返回或恢复，不得留下不可操作黑屏。[S05][S19]

最终检查实际宿主 App 的设备族、方向配置、Data、签名与 ProMotion 设置，不能只检查未运行的 Unity launcher。iPad 必须以真正的平板布局运行；iPhone 兼容放大显示不算通过。

# 8. 运行时生命周期：先求稳定，不做激进卸载

## 8.1 单一状态管理

由 `UnityRuntimeBridge` 持有运行时，`CharacterCoordinator` 管理页面意图。关键状态为：

```text
cold -> starting -> ready
                    |
                    + visible / paused-hidden
failed              # 记录具体错误，不无限循环初始化
```

另存 `desiredVisible` 和 `sceneActive`。所有显示、隐藏和 UIKit 操作在主线程执行。快速连点必须幂等，不能启动两个实例或叠加多个覆盖层。

## 8.2 首次进入

先保存宿主窗口与所属 UIWindowScene，设置 starting 状态，显示加载提示。初始化前注册桥接回调和 framework listener，再配置 Mach-O execute header、Data bundle 和启动参数。

在已有原生应用中使用 `runEmbeddedWithArgc`，不是再次调用 `runUIApplicationMainWithArgc`。[S04] 启动参数的有效内存和生命周期由桥接层负责；不得传递已释放的临时 argv 指针。

依据当前导出头文件取得 Unity 管理的窗口/root controller，使其使用正确的前台 UIWindowScene。不要拿任意 `connectedScenes.first` 假定为当前窗口，也不要偷偷删除 Scene 配置规避现代系统问题。

把原生覆盖按钮添加到 Unity 内容之上，再显示 Unity 窗口。场景检查完成后发送就绪事件。初始化可能占用主线程，V0 允许短暂首次启动等待；不能为了让进度条转动，把 UIKit 或 Unity 初始化随意搬到后台线程。

`sceneReady` 代表场景资源和脚本就绪，不等于已经证明 GPU 第一帧成功呈现。加载提示的撤除应结合渲染时机，最终以真机画面验收。超时必须可诊断，不能用“等两秒”代替就绪检测。

## 8.3 返回与再次进入

正常返回：标记 `desiredVisible=false`，暂停 Unity，恢复宿主窗口与原生首页，隐藏或撤下覆盖控件。保留一个已初始化的运行时，供下一次复用。

再次进入：恢复已有 Unity 窗口与覆盖层，取消暂停，不再次执行初始启动，不重复实例化模型。不要等待只在首次启动时发送的事件，否则第二次进入会永远加载。

**正常页面返回禁止调用 Application.Quit / quitApplication。** Unity 官方说明，iOS 上彻底退出后不能在同一 App 会话再次运行。[S05]

V0 默认不执行 unloadApplication。保留一定常驻内存是此阶段明确接受的取舍；未来再研究卸载。即使卸载，官方也不保证内存完全归零。[S05]

## 8.4 前后台与窗口

后台、锁屏或 scene inactive 时暂停更新；回前台只有在“用户仍处于角色页”时才恢复。用户已经回首页，就不能因为 App 重新 active 而让 Unity 抢回窗口。

原生覆盖控件只消耗自己可点击区域的触摸；空白透明区域不应变成全屏拦截层。本版不实现身体命中检测，但应避免留下阻断未来场景触摸的容器。

有疑问时记录窗口类型、scene 标识、关键状态和回调顺序，而不是同时在多个代理里重复启动/暂停引擎。

# 9. 最小通信协议

## 9.1 只保留必要命令

原生发送命令：`resetView`、`setTargetFrameRate`、`setDiagnosticOrbit`。最后两个属于调试功能。页面关闭直接由原生生命周期管理，不等待 Unity 业务消息。

Unity 回传事件：`sceneReady`、`error`、`stats`。诊断数据最多每秒回传一次，不每帧 JSON 序列化并触发 SwiftUI 更新。

```json
{
  "schemaVersion": 1,
  "kind": "command",
  "name": "resetView",
  "requestId": "request-001",
  "payload": {}
}
```

```json
{
  "schemaVersion": 1,
  "kind": "event",
  "name": "sceneReady",
  "requestId": "",
  "payload": {"modelId": "robot_expressive"}
}
```

协议是本项目设计，不是 Unity 自带 JSON API。未知名称、非法字段或未就绪命令必须安全拒绝并记录，不能执行任意方法名称。

## 9.2 传输实现

原生到 Unity 使用 UnityFramework 的 `sendMessageToGOWithName`，固定对象名 `AppBridgeReceiver` 和固定方法 `ReceiveCommand(string)`，消息体为 JSON。[S04]

Unity 到原生采用一个小型 iOS native plugin：插件实现位于 UnityFramework 中，宿主注册一个 C 函数指针回调，C# 调用插件导出的 `DemoEmitNativeEvent`。必须使用 C linkage、正确的符号可见性和有效的字符串生命周期。

桥接头作为 framework 的公开头或通过显式头搜索路径使用。插件实现只编译进一个 target，不能同时在宿主和框架中各放一份，避免重复符号和两份状态。

回调收到字符串后立即复制，再转主线程更新 UI。不要保存一个已失效的 `const char*`。C# 的 iOS P/Invoke 用条件编译隔离；在编辑器内使用日志替代，不让 Play 模式因找不到原生符号而报错。[S12]

不使用每帧桥接、反射消息总线、WebSocket 或本地 HTTP 服务。模型一直存在场景里，不通过该协议加载公网资产。

# 10. 可重复构建与工程管理

## 10.1 Unity 自动化要求

实现 Editor 工具 `DemoProjectSetup`，负责创建或校验场景、唯一桥接对象、模型包装层、相机和灯光。重复运行不能重复添加对象；已有人工调整应能选择保留，而不是无提示覆盖。

实现 `BuildIos.Export`，仅导出指定场景与 iOS 配置；失败时返回失败状态并保存日志。模型不存在、导入失败或关键 Shader 缺失时，应停止构建，而不是悄悄改用方块。

下列命令是实施后的调用约定，不代表对应 C# 方法已经随本文交付：

```bash
"$UNITY_EDITOR" -batchmode -quit \
  -projectPath "$ROOT/unity/CharacterRuntime" \
  -buildTarget iOS \
  -executeMethod BuildIos.Export \
  -logFile "$ROOT/build/unity-export.log"
```

先在编辑器 GUI 中完成许可、包解析和首轮导入，再验证批处理。不要把许可登录失败误判为业务代码错误。

## 10.2 Xcode 构建

首次运行以 Xcode GUI 为准：打开 workspace、选择 CharacterHost scheme、分别选择 D01 / D02、配置 Personal Team，逐台执行 Run。

签名与配对已经配置后，可使用以下构建约定：

```bash
xcodebuild \
  -workspace ios/CharacterPrototype.xcworkspace \
  -scheme CharacterHost \
  -configuration Debug \
  -destination "id=$DEVICE_UDID" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  build
```

`build` 只代表构建动作，不自动等于已安装运行。最终真机启动由 Xcode Run 或经过验证的设备部署命令完成。

可以另做禁用签名的编译检查，但这种结果只能写“编译检查通过”，不能写“已在 iPhone / iPad 运行”。

## 10.3 仓库规则

提交源工程、场景、Prefab、`.meta` 文件、包锁、共享 scheme、workspace、后处理脚本、资产许可和测试记录。

忽略 Unity `Library/Temp/Logs/Obj`、Xcode `DerivedData`、构建输出、用户私有配置、签名材料和个人设备标识。源代码与工程中不得硬编码实现者自己的绝对路径。

团队标识与 Bundle Identifier 可以通过本机配置填写；提供示例，不包含账号秘密。一个干净目录重新克隆后，另一位实现者应能依照 README 重建，而不依赖原作者的 Library 缓存。

# 11. 免费签名的逐步操作清单

1. 在 Mac 安装并启动 Xcode，完成附加组件安装；检查所选 Xcode 能连接 D01 的实际 iOS 和 D02 的实际 iPadOS。[S10]
2. 在 Xcode 账号设置中添加普通 Apple Account。用户本人完成登录与必要协议确认。
3. 创建原生宿主工程，使用最终稳定的 Bundle Identifier；先不接 Unity，选择 Personal Team 与自动签名。
4. 连接、解锁并信任这台 Mac；在设备管理中分别确认 D01 和 D02 已配对。
5. 按系统提示启用 Developer Mode，完成重启和设备端确认。[S02]
6. 先把只有首页的原生 App 分别 Run 到 D01 和 D02。此步骤失败时只排查签名/工具链，不继续堆 Unity 代码。
7. 完成模型导入、Unity iOS 导出及 workspace 集成。
8. 使用同一个宿主标识和 Personal Team，逐台 Run 到 iPhone 17 标准版和 11 英寸 iPad Pro（M4，2024）。
9. 按需完成系统的开发者 App 信任提示；只有系统确实出现该要求时才处理，菜单名称以系统为准。
10. 在两台设备上分别验证首页、角色页、原生覆盖、返回及重复进入；iPad 另查是否为真正平板布局。设备开发授权已完成后，再检查本地展示不依赖网络。
11. 个人签名过期后连接 Xcode 重新 Run。需要登录或更新签名时按提示完成，不删除源工程。[S01]

不需要注册付费会员、不需要 Archive 上传、不需要 TestFlight、不需要企业证书或第三方签名平台。

# 12. 性能与诊断

## 12.1 60 FPS 基线与 120 FPS 探索分开

默认 `Application.targetFrameRate = 60`，保留 V0 的基础功能与性能门槛。D01 和 D02 的显示屏均支持最高 120Hz，因此两台都必须提供并尝试 120 诊断档，而不是把其中一台按“无高刷硬件”记为 N/A。[S17][S18] 必须启用并核实相应 ProMotion 配置。Unity 的实际帧率受设备能力和系统调度限制；硬件支持 120Hz 不等于 App 已达到持续 120 FPS，设置目标值也不是实测证明。[S13]

对于 Unity as a Library，影响宿主进程的 Info.plist 设置应检查最终宿主 App 的 Info.plist，不要只修改未运行的 Unity launcher。

首次加载与 Shader 预热阶段单独记录，不与稳定运行混为一谈。诊断时可缓慢环绕相机，让持续更新在视觉上可见。静态截图不能证明 60/120 FPS。

## 12.2 V0 建议门槛

| 项目 | 验收方式 |
|---|---|
| 功能基础 | 所有必须需求通过，不能只交一个 Unity 独立播放器。 |
| 稳态 60 档 | D01 / D02 分别在固定配置下预热并连续采样 5 分钟；每台平均帧率目标不低于 58。 |
| 卡顿记录 | 记录帧时间中位数、P95、P99与明显长帧；不能只显示平均 FPS。 |
| 120 档 | 两台均测量，注明实际帧率与限制；无真机执行写 NOT TESTED。测量完成不等于持续 120 达标，本版不将未达到 120 偷写为通过。 |
| 持续运行 | 两台分别展示 10 分钟不崩溃，记录温度状态及后半程帧率。 |
| 页面循环 | 每台各 20 次进入/返回，不出现重复模型、多个覆盖层或不断增长的回调数量。 |
| 内存趋势 | 对比预热后循环中的占用趋势，区分一次性缓存与持续泄漏；不要求退出后归零。 |

数值是本项目的起始验收目标。若手头设备无法满足，需要报告设备与瓶颈，并将“功能通过”和“性能未通过”分开，而不是把目标偷偷改为 30 FPS。

## 12.3 测量要求

必须在 D01 和 D02 两台用户实机上分别测；一台的结果不能代替另一台，也不以 Mac 编辑器或模拟器结果代替。Unity 官方强调目标设备上的性能分析。[S14]

调试标签中的 FPS 来自 Unity 帧循环，标明它不是独立验证过的最终屏幕呈现帧率。需要时用 Instruments / Metal 性能工具或目标机 Profiler 辅助确认。若设备、工具或个人签名权限不支持某项诊断，写“未测”和替代证据，不编造读数。

使用 Development Build 定位问题；另用关闭 Script Debugging、Deep Profiling、密集日志等额外开销的构建复测。首次验收不要求开 Deep Profiling。

测试记录应包含设备 ID、正式机型、实际 iOS / iPadOS 版本、iPad 容量/内存档位（不能读取则注明未知）、应用构建、目标帧率、屏幕上限、实际渲染宽高、渲染比例、场景配置、是否充电/录屏/连接调试器、采样区间。先完成干净测量，再录制功能演示，避免把录屏额外负载混入基线。

# 13. 分阶段实施任务

| 阶段 | 交付物 | 通过后再继续 |
|---|---|---|
| A 环境门槛 | environment.md；同一空白原生宿主免费签名运行 | D01 和 D02 上分别出现原生首页。 |
| B 模型与场景 | 资源许可记录、Prefab、DemoScene、Editor 校验工具 | 编辑器可见真实 RobotExpressive，无自动动画和材质错误。 |
| C 嵌入构建 | Unity 导出、Data 后处理、workspace、framework 依赖 | 运行的是宿主 App，点击后显示场景。 |
| D 生命周期 | 返回、再进入、前后台、窗口与覆盖层 | 两台各 20 次循环通过，单设备进程内只有一个运行时。 |
| E 可交接 | 构建文档、干净重建记录、双设备性能与功能报告 | 两台记录完整；另一位实现者能复现，未测项明确列出。 |

不要在 A 未通过时购买素材；不要在 C 未通过时添加语音 SDK；不要在 D 未通过时扩展多角色。遇到失败，应在对应层保存最小复现，而不是同时改动签名、引擎版本和素材。

# 14. 验收用例

| ID | 操作 | 预期 |
|---|---|---|
| T01 | 首次打开 App | 出现原生首页，不直接跳进 Unity。 |
| T02 | 进入关于页并返回 | 导航可用，显示模型来源与许可。 |
| T03 | 点击查看角色 | 加载后出现真实 3D RobotExpressive，不是图片/方块。 |
| T04 | 检查外观 | 材质正常、角色完整、无明显裁切，无自动播放的动作。 |
| T05 | 点击原生重置按钮 | 视角恢复默认位置，确认原生到 Unity 通信。 |
| T06 | 点击原生返回 | 回到原生首页，角色更新暂停。 |
| T07 | 再次进入 | 同一模型正常显示，不黑屏、不等待永不重发的首次 ready。 |
| T08 | 快速连续点击入口/返回 | 不创建重复实例，状态可恢复。 |
| T09 | 重复进入退出 20 次 | 不崩溃、不叠层、不持续增加回调。 |
| T10 | 角色页切后台后回前台 | 返回角色页并恢复显示。 |
| T11 | 首页切后台后回前台 | 留在首页，Unity 不抢窗口。 |
| T12 | 角色页锁屏再解锁 | 正确恢复，无错误窗口或失效按钮。 |
| T13 | 开发授权已就绪后断网 | 模型展示不需要访问远程资源。 |
| T14 | 临时移除模型引用后构建 | 校验工具报错，不静默以方块完成。 |
| T15 | 重建 Unity 导出目录 | 脚本恢复 Data 与桥接配置，workspace 仍可构建。 |
| T16 | 干净目录重建 | 不依赖作者机器上的缓存、绝对路径和私有文件。 |
| T17 | 60 FPS 性能测试 | 保存采样与设备信息，按第 12 节判断。 |
| T18 | 两台设备的 120 诊断档 | D01 / D02 均执行并保存实测记录；不能以无高刷硬件为由写 N/A，未执行写 NOT TESTED。 |
| T19 | 检查权限与外部依赖 | 不请求麦克风/摄像头，不要求后端或 API Key。 |
| T20 | 个人签名到期后重新 Run | 可更新安装；若未等待实际到期，仅验证流程并标记未实测到期。 |
| T21 | 检查双设备安装与设备族 | 同一宿主工程可在 D01 / D02 运行；D02 不是 iPhone 兼容放大模式。 |
| T22 | 检查两端布局、安全区和取景 | 全屏竖屏时按钮正常、头脚完整、模型不变形；从后台恢复后布局仍正确。 |
| T23 | 检查设备范围及独立报告 | 仅承诺 D01 / D02；每台有实际系统、功能、20 次循环和帧率记录，未测不冒充通过。 |

验收报告按 D01 / D02 分列，状态只允许：PASS、FAIL、NOT TESTED、N/A，并附证据或理由。T14–T16 等共用构建证据可以引用同一记录；设备运行与性能用例必须逐台执行。T18 的 PASS 只表示诊断流程执行且证据完整，是否达到持续 120 FPS 必须另列实测结论。截图、编译成功、模拟器运行和真机运行不能相互冒充。

# 15. 常见失败与排查顺序

| 症状 | 优先检查 |
|---|---|
| Xcode 不能安装原生空白 App | Apple Account、Personal Team、设备支持、签名额度、Developer Mode。 |
| 找不到 UnityFramework 模块/头文件 | 是否从 workspace 构建、库 target 是否生成、头搜索路径与依赖是否正确。 |
| Library not loaded / 签名错误 | framework 是否 Embed & Sign、真机架构是否匹配、最终宿主签名。 |
| 找不到 Data / metadata | Data 的归属、最终 framework 内部文件、setDataBundleId 是否匹配且在启动前设置。 |
| 原生 C 函数 undefined / duplicate symbol | C linkage、可见性、文件 target membership、是否同时编译进两个 target。 |
| 首页消失但模型黑屏 | Unity 初始化与 sceneReady、窗口所属 UIWindowScene、相机、模型引用、灯光及有效管线。 |
| 粉色材质 | 当前 URP、glTFast 导入器、Shader 依赖/编译日志与构建剥离。 |
| 模型太小/倒向/背对 | 导入坐标系、包装层变换、取景参数；不要再装一个导入器。 |
| 第二次进入失败 | 是否调用 Quit、是否重复启动、是否错误等待一次性 ready。 |
| 返回按钮不可用 | 覆盖层层级、安全区、窗口 active 状态和透明视图的 hitTest。 |
| 后台回来强行跳角色页 | desiredVisible 与 sceneActive 是否在同一处判断。 |
| 目标 120 实际 60/30 | 设备上限、最终宿主 ProMotion 配置、系统状态、实际负载，不仅查看代码设置。 |
| 页面循环内存持续增长 | 重复 overlay、事件订阅、Timer/DisplayLink、模型实例；区分有意保留的引擎缓存。 |
| 每次导出后又坏 | 修改是否只做在生成文件中，后处理是否幂等且可验证。 |

不得把“关闭所有安全检查”“禁用最终签名”“忽略编译错误”作为解决方案。

# 16. 最终工程交付要求

实现者交付的是原生源工程、Unity 源工程与可重建步骤，不是一个截图或过期的个人签名安装包。

至少包含：README、版本环境记录、资产来源与 hash、Unity 包锁与场景、桥接协议、导出后处理、workspace/共享 scheme、故障说明、验收报告、功能演示及必要日志。证书、账号秘密和私人设备标识必须排除。

README 应按“从一台干净 Mac 开始”的顺序说明安装依赖、获取模型、打开项目、生成 Unity iOS 工程、配置个人签名和 Run。人工点击步骤可以存在，但必须明确列出。

无法在 Mac 和这两台指定设备上执行的 AI，应交付代码与静态检查结果，并明确哪些步骤仍需真机确认。不得写“已完成功能”“已稳定 120 FPS”而没有相应运行证据。

# 17. 给审阅 AI 的任务

先检查本方案是否有会阻止实际实现的矛盾，不优先讨论最终产品的语音、支付或美术。

审阅重点：D01 / D02 唯一设备范围与 Universal 构建；iPad 全屏布局、安全区、模型取景与实际窗口行为；双设备独立验收；免费签名与设备限制；Unity 6.3 与本机 Xcode 的实际兼容性；显式链接路线是否贯彻；Data 与桥接符号归属；UIKit Scene/窗口切换；暂停与再次进入；glTFast 的 URP 导入；唯一模型与离线资源；帧率观测是否真实；干净重建是否可行。

按“阻塞问题 / 高风险 / 可优化”分类。每项给出理由、证据和最小修改方案。区分事实错误、版本差异、个人偏好和未验证假设。没有实际设备时，不把推理写成实测。

不得在没有新约束的情况下，把范围扩大为 UE5、跨平台 UI、后端、语音或多角色平台。提出替代架构时，应说明解决的是哪一个已证实的问题以及迁移代价。

# 18. 给实施 AI 的任务

阅读本文后，先输出需求复述、环境检查结果和阶段 A 的具体动作。按照 A→B→C→D→E 推进，每阶段列出改动文件、执行命令、实际结果和剩余阻塞。

可以生成文件、脚本与工程，但不要把用户必须完成的 Apple 登录或设备确认伪装为已完成。不得获取、保存或要求用户发送密码与验证码。

使用指定模型与明确的导入路径。先交付静态展示，不写 AI 聊天、角色动作、口型、触摸部位或多角色功能。不用截图、视频、方块或纯 Unity launcher 代替最终验收。

对生成目录的必要修改必须可重复执行；对平台 API 以选定版本的真实头文件和官方说明为准，不能编造 UnityFramework 或 Apple 方法。

最终汇报分成“已实现”“已验证”“未验证”“已知限制”，并分别给出 D01 / D02 结果。只把有证据的项目列入已验证。

# 19. 后续扩展接口保留，但不提前实现

V0 仅保留清晰的角色 Prefab 包装、原生协调器、桥接模块和版本化消息格式。后续更换精细模型应主要改变资产、材质、镜头和性能配置，而不是重写整个首页。

多角色、触摸、动画、实时语音和记忆分别进入后续阶段。届时重新进行高品质资产真机评估；V0 的机器人性能不作为承诺。

**本阶段的完成定义始终是：同一原生 App 使用个人签名，分别安装到 iPhone 17 标准版与 11 英寸 iPad Pro（M4，2024），两台均能可靠地进入、显示一个本地示例 3D 角色、返回并再次进入。缺少任一设备验证，不算双设备适配完成。**

# 20. 来源与核实范围

以下来源核对日期均为 2026-09-25。网页说明验证了接口、许可或官方支持边界，不等于整套工程经过实际编译。涉及版本变化时，实施者应再次核对并更新环境记录。

**[S01] Apple — Developer account overview / Personal Team。** 个人账号测试、7 天签名及数量限制。  
https://developer.apple.com/help/account/basics/about-your-developer-account

**[S02] Apple — Enabling Developer Mode on a device。** 设备开发模式。  
https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device

**[S03] Unity — Unity 6 release support。** 6.3 LTS 分支与支持期限。  
https://unity.com/releases/unity-6

**[S04] Unity 6.3 — Integrating Unity into native iOS applications。** workspace、framework 与运行时控制接口。  
https://docs.unity3d.com/6000.3/Documentation/Manual/UnityasaLibrary-iOS.html

**[S05] Unity 6.3 — Using Unity as a Library。** 全屏、单实例、退出和内存限制。  
https://docs.unity3d.com/6000.3/Documentation/Manual/UnityasaLibrary.html

**[S06] Unity Technologies — uaal-example iOS。** 官方嵌入示例、原生覆盖按钮及动态加载样例。注意示例年代与所选版本差异。  
https://github.com/Unity-Technologies/uaal-example/blob/master/docs/ios.md

**[S07] three.js r180 — RobotExpressive README。** 模型作者、整理者及 CC0 许可声明。  
https://raw.githubusercontent.com/mrdoob/three.js/r180/examples/models/gltf/RobotExpressive/README.md

**[S08] Unity glTFast 6.14 — Editor Import。** GLB 编辑器导入与导入器冲突。  
https://docs.unity3d.com/Packages/com.unity.cloud.gltfast@6.14/manual/ImportEditor.html

**[S09] Unity glTFast 6.14 — Installation。** 包安装与依赖。  
https://docs.unity3d.com/Packages/com.unity.cloud.gltfast@6.14/manual/installation.html

**[S10] Apple — Xcode SDK and system requirements。** Xcode、macOS、设备与 SDK 的支持矩阵。  
https://developer.apple.com/xcode/system-requirements

**[S11] Unity 6.3 — Structure of a Unity Xcode project。** launcher、framework、Data 与工程后处理。  
https://docs.unity3d.com/6000.3/Documentation/Manual/StructureOfXcodeProject.html

**[S12] Unity 6.3 — iOS native plug-ins callbacks。** iOS 原生/托管交互参考；具体双向协议为本方案自行设计。  
https://docs.unity3d.com/6000.3/Documentation/Manual/ios-native-plugin-call-back.html

**[S13] Unity 6.3 — Application.targetFrameRate。** 移动端目标帧率及 ProMotion 相关行为。  
https://docs.unity3d.com/6000.3/Documentation/ScriptReference/Application-targetFrameRate.html

**[S14] Unity 6.3 — Collecting performance data。** 目标设备上的性能验证。  
https://docs.unity3d.com/6000.3/Documentation/Manual/profiling-collect-data-introduction.html

**[S15] RobotExpressive GLB 资源位置。** 固定 r180 标签；二进制需由实施者下载、校验并记录 hash。  
https://raw.githubusercontent.com/mrdoob/three.js/r180/examples/models/gltf/RobotExpressive/RobotExpressive.glb

**[S16] Unity Editor Software Terms。** 编辑器使用资格与许可；正式商业分发前另行确认。  
https://unity.com/legal/editor-terms-of-service/software

**[S17] Apple — iPhone 17 技术规格。** 标准版正式名称、A19、6.3 英寸、分辨率与最高 120Hz ProMotion。  
https://www.apple.com.cn/iphone-17/specs/

**[S18] Apple Support — 11 英寸 iPad Pro（M4）技术规格。** 2024 年款、正式尺寸名称、M4、分辨率、10–120Hz 与存储/内存差异。  
https://support.apple.com/zh-cn/119892

**[S19] Apple — Information Property List Key Reference / iOS Keys。** 设备族由 Xcode 生成，支持设备与界面方向的基础配置；此为归档说明，具体窗口行为仍需核对实际 SDK。  
https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/iPhoneOSKeys.html
