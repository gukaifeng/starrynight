# 模型空间 · iOS / iPadOS 3D App

SwiftUI / UIKit 原生宿主与 Unity as a Library 组成的 Universal App。首页打开内置机器人，支持**单指旋转、双指缩放、复位、挥手 / 跳跃 / 跳舞按钮，以及轻触头部摇头**。模型、材质、动画和缩略图全部内置。

2026-09-26 画质升级：默认角色为原创 **Luma**，带圆润陶瓷外壳、金属关节、玻璃面罩、棚拍灯光与实时阴影。启用原生分辨率、4× MSAA、HDR 工作缓冲和 ACES 色调映射。默认请求 **120 FPS**，查看器支持 60／120 切换并显示实测帧率；目标值不等于已达到的帧率，持续高于 60 和 120 FPS 须以真机报告为准。

完整交互已在 **iPhone 17 / iOS 26.4 模拟器**交付；随后完成真机 Release 编译准备，当前安装进度见[真机安装说明](docs/device-installation.md)。iPhone 使用竖屏，iPad 源码支持横竖屏和宽屏首页。两台指定真机的运行 / 性能及 iPad 模拟器尚未验收，见[Luma 画质与性能报告](docs/luma-quality-performance.md)、[首版历史报告](docs/simulator-acceptance.md)与[真机验收表](docs/acceptance-report.md)。

## 直接运行

运行模拟器时，先用 `python3 scripts/generate_host.py --platform simulator` 切换 workspace，再在 Xcode 打开 **ios/CharacterPrototype.xcworkspace**，选择 **CharacterHost** scheme 和 **iPhone 17 模拟器**，点击 Run。必须从 workspace 的宿主 scheme 运行完整 App。这台机器已保留 Unity 模拟器导出和构建缓存，也可重新安装运行现有构建：

```bash
bash scripts/run_simulator.sh
```

模拟器中鼠标拖动旋转；按住 **Option（⌥）** 模拟双指后拖动缩放。点击头部摇头，底部按钮播放动作。每个动作播放一次后回到待机，可直接切换；复位同时恢复相机和待机姿态。

只运行现有 App 不需要一直打开 Unity Hub、Unity Editor 或 Unity CLI。

## 修改后构建

只修改 Swift / Objective-C++ / 原生资源：

```bash
bash scripts/build_host.sh
bash scripts/run_simulator.sh
```

修改 Unity C#、模型、材质或场景生成逻辑：

```bash
python3 scripts/export_unity_ios.py --platform simulator
bash scripts/build_host.sh
bash scripts/run_simulator.sh
```

导出脚本通过 Unity CLI 优先连接现有 Editor，未打开时使用 batchmode。Editor 重载代码时会等待 Pipeline 恢复，不重复打开同一工程。构建逻辑在 `Assets/Editor/BuildIos.cs`：重建正式场景、检查模型与动作、导出 IL2CPP、将 Data 放入 UnityFramework 并生成框架标识。**需要保留的场景修改应写入 Setup()，不要只修改生成的 ViewerScene。**

## 自动化验证

```bash
bash scripts/test_simulator.sh
```

XCTest 操作真实 App：加载取消及重试、15 秒前台等待超时及恢复、首页和关于、真实手势、四种动作、头部 / 身体 / 空白点击区别、动作切换、20 次进出、后台恢复。同时验证 60／120 帧率切换及原生分辨率。随后 Python 对 Unity 回传的实际相机参数、动作和性能事件断言。性能数据为渲染循环墙钟间隔，并非真机显示呈现的证明。

每轮日志、`.xcresult`、截图、事件证据分别保存在 `.local/logs/`、`.local/checks/`，保留历史。测试延迟注入与事件落盘只在 DEBUG 且显式传入 `--ui-testing` 时启用。

## 工程关系

| 路径 | 职责 |
|---|---|
| `unity/CharacterRuntime/` | Unity 源工程：URP、原创模型、动作、镜头和触摸交互 |
| `ios/CharacterHost/` | 原生源码：SwiftUI 首页、UIKit 控件、生命周期和桥接 |
| `build/unity-simulator/` | Unity 生成的 ARM64 Simulator SDK Xcode 工程 |
| `build/unity-device/` | 独立 Device SDK 导出，不与模拟器框架混用 |
| `ios/CharacterHost.xcodeproj` | 脚本生成的宿主和 UI 测试工程 |
| `ios/CharacterPrototype.xcworkspace` | 完整 App 入口，依赖、链接并嵌入 UnityFramework |

业务源码两套；Unity 导出的 Xcode 工程是可恢复产物。`scripts/generate_host.py` 生成 workspace 和跨工程依赖，不需要 CocoaPods / Carthage / XcodeGen。按 `--platform simulator` 或 `--platform device` 切换 workspace 引用，不要同时生成两个平台。

## 固定工具版本

Apple Silicon / ARM64，Unity **6000.3.25f1 LTS** + iOS Build Support，Xcode **26.4**，iOS SDK / Simulator **26.4**，URP **17.3.0**，glTFast **6.16.1**，Unity CLI **1.0.0-beta.6**，Pipeline **0.7.0-exp.1**。宿主与 Unity Simulator 架构一致。当前 Pipeline 已实际连接、查询场景、执行导出通过；不打入本轮非 Development Build 的 Unity 运行包。

## 从干净目录恢复依赖

1. 安装 Xcode 及适用 iOS SDK，完成 Xcode 初次启动配置，并在 Xcode → Settings → Components 安装 / 启用 iOS 平台。本机已补齐 iOS 26.4（23E244）arm64 组件。可用 `xcodebuild -downloadPlatform iOS -buildVersion 26.4 -architectureVariant arm64` 下载，再确认 Components 中 iOS 已启用。Metal 编译工具缺失时运行：

   ```bash
   xcodebuild -downloadComponent MetalToolchain
   ```

2. 安装 Unity Hub、**Unity 6000.3.25f1 Apple Silicon** 和 **iOS Build Support**，在 Hub 登录并激活适用许可证。如果使用官方 Unity CLI，可分两步安装：

   ```bash
   unity install 6000.3.25f1 -a arm64
   unity install-modules -e 6000.3.25f1 -m ios
   ```

   必须检查 iOS 模块实际安装完成；本次 CLI 组合安装仅完成编辑器，随后单独安装模块才齐备。

3. 在项目根目录执行：

   ```bash
   python3 scripts/prepare_packages.py
   bash scripts/check_unity_dependencies.sh
   ```

   准备脚本按 `docs/package-downloads.json` 下载固定版本到 `.local/dependencies/upm/`，校验官方 registry SHA-1、包名及版本，并记录 SHA-256。manifest 使用相对于 `Packages/` 的本地 tarball 路径，重新克隆后应先恢复这些文件。URP、Test Framework 等由固定版本编辑器提供。

4. 如需复查 Xcode / Unity 的完整编译组合，执行 `python3 scripts/check_ios_toolchain.py`。

当前 Luma 由 `StudioRobotBuilder.cs` 自动生成，无须下载模型或贴图。旧版 RobotExpressive 保留作历史资源，不进入当前场景；只有复查旧版本且其文件缺失时才需要：

```bash
python3 scripts/fetch_sample_asset.py --output unity/CharacterRuntime/Assets/ThirdParty/RobotExpressive
```

资源脚本拒绝覆盖已有资源。重新下载后须补做 Unity 导入检查，不能沿用旧验证结果。

## 后续真机测试

2026-09-26 已增加真机 Release 编译准备和个人测试安装入口；安装步骤与当前边界见[真机安装说明](docs/device-installation.md)。真机 / 模拟器导出和缓存分别保留，同一个 workspace 按平台切换。重新导出时：

```bash
python3 scripts/export_unity_ios.py --platform device
python3 scripts/generate_host.py --platform device
open ios/CharacterPrototype.xcworkspace
```

将 `ios/Config/Local.example.xcconfig` 复制为 Git 忽略的 `Local.xcconfig`（已有文件则保留），配置 DEVELOPMENT_TEAM；可用 MODELSPACE_DEVICE_BUNDLE_IDENTIFIER 配置自己的真机 App ID。个人测试可使用免费 Apple Account / Personal Team。连接、信任设备并启用开发者模式后，确认设备 UDID：

```bash
xcrun devicectl list devices
bash scripts/run_device.sh DEVICE_UDID
```

未连接设备时可用 `bash scripts/build_device.sh --unsigned` 提前完成 Release 编译；该产物必须经过开发签名才能安装。也可在 Xcode 中选择 CharacterHost、自己的 Team 和真实手机后 Run。切回模拟器时运行 `python3 scripts/generate_host.py --platform simulator`。

本轮没有进行真机签名、安装、帧率、发热或耗电验收，也没有发布到 TestFlight / App Store。

## 维护文档

- [开发记录](docs/development-notes.md)：关键决定、异常根因和修复。
- [模拟器验收](docs/simulator-acceptance.md)：最终结果、截图、录像和证据路径。
- [运行结构与桥接](docs/runtime-architecture.md)：源码入口、消息和生命周期。
- [最初 V1 方案](docs/design/2026-09-25-v1-development-plan.md)：保留设计背景，最新用户要求优先。
- [原始交接文档](ios_3d_mvp_technical_spec_v1_1.md)：保留前序 AI 原文。
