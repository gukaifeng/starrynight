# iOS / iPadOS 3D 原型

当前实施依据：[第一版完整开发方案](docs/design/2026-09-25-v1-development-plan.md)。目标是在 iPhone 17 标准版与 2024 年 11 英寸 iPad Pro 上运行同一个原生 App：从首页打开内置 RobotExpressive 模型，支持用户已确认的**旋转、缩放、复位**，并可返回和再次查看。原始[交接技术方案 v1.1](ios_3d_mvp_technical_spec_v1_1.md)保留作为基础技术参考，差异以新方案说明为准。

本机基础开发环境与模型依赖准备已完成，Unity URP 工程已通过导入、iOS 导出和框架编译验证。第一版方案、架构图、页面流程和验收清单已建立；正式原生宿主、桥接、查看场景与触摸交互尚待开发。

## 当前就绪状态

- Mac、Xcode 26.4、iOS SDK 26.4、Swift、Clang、Metal Toolchain、Rosetta 2、Git、Python 可用。
- Unity Hub 3.21.3、Unity 6000.3.25f1 Apple Silicon、iOS Build Support 已安装，用户已完成 Unity Personal 激活，编辑器实际运行通过。
- **URP 17.3.0 + glTFast 6.16.1** 已通过包解析、C# 编译、GLB 导入及材质引用检查。Unity 已生成真实的 `Packages/packages-lock.json`：7 项本地包归档、16 项编辑器内置包。
- RobotExpressive 已导入 14 个渲染器，模型来源、许可、原始文件 hash 已记录。
- **iOS 导出与 UnityFramework 的 iOS ARM64 未签名编译均已通过**：Xcode 返回 `BUILD SUCCEEDED`，二进制最低 iOS 17.0、SDK 26.4，Universal 配置覆盖 iPhone / iPad。详见 [环境记录](docs/environment.md)。
- Unity CLI 1.0.0-beta.6 已安装；后续优先用于 Unity 开发自动化。编辑器交互所需 Unity Pipeline 尚未安装验证，列入新方案 P0。
- 两台指定真机尚未连接；Personal Team 签名、安装运行和性能均未验收。

交接文档的 glTFast 6.14.1 是起始候选，实际导入复现了骨骼多子网格异常，因此调整为包含官方修复的稳定版 6.16.1。Test Framework 和 NUnit 使用当前编辑器自带的 1.6.0 / 2.0.5，避免旧测试框架与 Unity 6.3 的接口不兼容。原始交接文档保留，调整依据记录在 [环境记录](docs/environment.md)。

## 在本机开始开发

在 Unity Hub 打开 `unity/CharacterRuntime`，选择 **6000.3.25f1**。也可以运行：

```bash
unity open unity/CharacterRuntime
```

Unity 基础工程已登记到 Hub。当前 `SampleScene` 和渲染配置来自编辑器自带 URP 模板；模型尚未摆入正式查看场景，模板设置也尚未完成 V1 画质、方向和双设备适配。

后续按新方案 P0 → A → B → C → D → E 推进：开发基线与 CLI 接入、原生宿主、Unity 场景、真机集成、交互/生命周期、体验与验收。原生宿主先在两台指定设备上逐台完成 Personal Team Run。账号确认、设备信任及开发者模式由用户操作；未连接设备时可推进独立源码工作，运行结果仍保持 NOT TESTED。

逐设备记录见[验收报告模板](docs/acceptance-report.md)，包含原 T01–T23 与本版新增 NV01–NV12。

## 复查环境

关闭此工程的 Unity Editor 后执行：

```bash
python3 scripts/check_environment.py
bash scripts/check_unity_dependencies.sh
```

第二个命令校验包归档，再实际检查 iOS 模块、C# 编译、glTFast 导入、14 个模型渲染器及材质引用、URP 资产和包锁文件。日志为 `.local/logs/unity-dependency-check.log`，状态为 `.local/checks/unity-dependencies.json`。CLI 与 Hub 可以有独立登录状态；以编辑器实际执行结果判断许可是否可用。

完整 iOS 工具链复查：

```bash
python3 scripts/check_ios_toolchain.py
```

该命令临时创建包含模型的场景，以 iOS 17.0、Universal、IL2CPP 导出到 `.local/build/ios-dependency-probe`，随后用 Xcode 对 iOS ARM64 编译未签名的 UnityFramework。临时场景在结束时清理，探针修改的项目设置恢复。输出、日志及 DerivedData 都在 `.local/`，不会作为正式宿主工程提交。

此检查验证构建依赖，不代表 Unity as a Library 集成、真机画面、App 功能或性能已通过。正式导出仍需按方案开发 Data 后处理和 workspace 集成。

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

模型已作为本地资源保存，无须重复下载。仅在模型文件缺失时执行：

```bash
python3 scripts/fetch_sample_asset.py --output unity/CharacterRuntime/Assets/ThirdParty/RobotExpressive
```

资源脚本拒绝覆盖已有资源。重新下载后须补做 Unity 导入检查，不能沿用旧验证结果。

## 目录

- `docs/`：完整 V1 方案与图示、环境、依赖下载清单、双设备验收模板。
- `scripts/`：资源获取、包准备、环境检查、Unity 导入和 iOS 构建检查。
- `unity/CharacterRuntime/`：Unity URP 基础工程、内置模型、包锁与编辑器验证脚本。
- `.local/`：本机安装包、包缓存、导出、检查结果和日志，已忽略，不提交。

SwiftUI、UIKit、Objective-C++ 与 iOS SDK 由 Xcode 提供；本阶段不需要额外安装 CocoaPods、Carthage、独立 Swift/.NET SDK、Android SDK、语音 SDK或服务器依赖。
