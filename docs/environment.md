# 开发环境与依赖准备记录

检查日期：2026-09-25。任务范围：准备后续开发所需的工具、库和示例资源。

**状态：本机开发依赖已准备就绪。Unity 许可证、包解析、C# 编译、模型导入、iOS 导出及 UnityFramework 的 iOS ARM64 未签名编译全部通过。两台真机均 NOT TESTED。**

## 本机环境

| 项目 | 实际结果 |
|---|---|
| 芯片 / 架构 | Apple M3 Pro / arm64 |
| 内存 | 36 GiB（38654705664 字节） |
| macOS | 26.3.1，Build 25D2128 |
| 准备前磁盘可用空间 | 约 218 GiB |
| 准备后磁盘可用空间 | 约 185 GiB；含安装包缓存、Unity Library、构建探针及 iOS 运行时 |
| Xcode | 26.4，Build 17E192 |
| Developer Directory | `/Applications/Xcode.app/Contents/Developer` |
| iOS SDK | 26.4 |
| iOS 平台组件 | 已补装 iOS 26.4（23E244）arm64 组件并启用平台，下载约 8.46 GB |
| Xcode 初次启动 | `xcodebuild -checkFirstLaunchStatus` 返回 0；`-runFirstLaunch -checkForNewerComponents` 返回无新增更新 |
| Swift 编译器 | Apple Swift 6.3，swiftlang-6.3.0.123.5 |
| Swift language mode | 原生编译探针使用 Swift 5；正式宿主工程待创建 |
| Clang | Apple clang 21.0.0，clang-2100.0.123.102 |
| Metal Toolchain | 已新增下载，Xcode component 17E188；metal 版本 32023.883 |
| Rosetta 2 | 已有；x86_64 执行探针成功 |
| Git | 2.49.0 |
| Python | 3.14.2；项目脚本仅使用标准库 |
| Unity Hub | 3.21.3，Apple Silicon |
| Unity CLI | 1.0.0-beta.6，Homebrew 管理；仅为辅助工具，编辑器使用 LTS 正式版 |
| Unity Editor | 6000.3.25f1，Apple Silicon，revision e1dba0a9aba4 |
| Unity Editor 路径 | `/Applications/Unity/Hub/Editor/6000.3.25f1/Unity.app` |
| iOS Build Support | 模块已安装，编辑器确认支持 iOS，并成功导出 IL2CPP 工程 |
| Unity 许可证 | 用户已在 Hub 激活 Unity Personal；实际 batchmode 执行通过 |
| Deployment Target | 原生探针与 Unity iOS 导出探针均使用 iOS 17.0；正式宿主配置待开发 |

本机满足 Unity 6.3 的基础硬件和操作系统要求。[官方系统要求](https://docs.unity3d.com/6000.3/Documentation/Manual/system-requirements.html)

选定 6000.3.25f1 是对方案中“6.3 LTS 补丁待定”的具体化。版本锁定于 `unity/CharacterRuntime/ProjectSettings/ProjectVersion.txt`，真机表现尚待后续确认。[官方版本说明](https://unity.com/releases/editor/whats-new/6000.3.25f1)

## 最终 Unity 依赖

| 依赖 | 版本 | 来源及验证 |
|---|---|---|
| Universal RP | 17.3.0 | 编辑器内置，解析及编译通过 |
| Render Pipelines Core | 17.3.0 | 编辑器内置 |
| Shader Graph | 17.3.0 | 编辑器内置 |
| Universal RP Config | 17.0.3 | 编辑器内置 |
| glTFast | **6.16.1** | 官方归档，完整性、编译及 RobotExpressive 导入通过 |
| Burst | 1.8.24 | 官方归档，完整性及编译通过 |
| Collections | 2.4.3 | 官方归档，采用 URP Core 所需版本 |
| Mathematics | 1.3.2 | 官方归档，采用 URP Core 所需版本 |
| Searcher | 4.9.5 | 官方归档，Shader Graph 依赖 |
| Test Framework | **1.6.0** | 当前编辑器内置 |
| NUnit | **2.0.5** | 当前编辑器内置 |
| Test Framework Performance | 3.0.3 | 官方归档，Collections 依赖 |
| Mono Cecil | 1.11.4 | 官方归档，Collections 依赖 |
| uGUI | 2.0.0 | 编辑器内置 |
| 所需引擎模块 | 1.0.0 | 编辑器内置 |

Unity Package Manager 实际解析出 **23 项包：7 项 local-tarball、16 项 builtin**。真实结果位于 [packages-lock.json](../unity/CharacterRuntime/Packages/packages-lock.json)，未手工生成或伪造依赖锁。

7 个外部包的版本、官方地址与 SHA-1 在 [package-downloads.json](package-downloads.json)；本机 SHA-256 及大小在 `.local/dependencies/upm/verified.json`。manifest 使用相对于 `Packages/` 的本地归档路径。干净目录先运行 `python3 scripts/prepare_packages.py` 恢复归档，再由 Unity 导入；不依赖已有 Library。[Unity 本地包说明](https://docs.unity3d.com/6000.3/Documentation/Manual/upm-localpath.html)

### 实测后做出的兼容性调整

1. **Test Framework 1.4.3 → 编辑器内置 1.6.0，NUnit 2.0.3 → 内置 2.0.5。** Collections 的旧依赖声明被提前固定为本地包后，旧 TestRunner 对 `IsRenamingItemAllowed` 的 override 在 Unity 6.3 编译失败。当前编辑器已自带配套测试框架，改用内置版本后编译通过。失败原始证据保留在 `.local/logs/unity-import-incompatible-test-framework.log`。
2. **glTFast 6.14.1 → 6.16.1。** 候选版本导入 RobotExpressive 时复现 `SortAndNormalizeBoneWeightsJob` / NativeArray 并发访问异常。官方 6.15.0 起修复多 primitive 骨骼网格导入，最终选用包含该修复及后续材质修复的稳定版 6.16.1，实测导入成功。没有修改包源代码或模型二进制。证据保留在 `.local/logs/unity-import-gltfast-6.14.1-failed.log`。[官方变更记录](https://docs.unity3d.com/Packages/com.unity.cloud.gltfast@6.16/changelog/CHANGELOG.html)
3. **许可同步。** 首次执行因无有效 Editor license 退出 198；用户完成 Hub 登录、激活后，许可同步完成，后续检查已实际运行通过。CLI 和 Hub 可能有独立会话，检查脚本不再把 CLI 的登录布尔值直接当作 Editor 许可结论。
4. **Xcode 平台检查。** SDK 存在、Swift / Metal 可独立编译，仍不能证明完整 Xcode 构建可用。首次 UnityFramework 构建报告 iOS 平台未安装，已通过官方命令下载 iOS 26.4（23E244）arm64 组件，并在 Xcode Components 启用 iOS 平台。补装后完整构建通过，运行时 isAvailable=true。[Apple 组件管理文档](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)

原始交接文档不改写；上述调整是对候选组合的实际验证结果。

## 模型资源

- RobotExpressive，three.js r180，解析 commit 为 `0af9729d0c143a86a1d725d6e2c3ad83301f3f34`。
- 原始文件 463988 字节，SHA-256：`047f5e5fb3bb6d378bd1df16ca6137f2a596c99b3a1b5690b4020c05aaf6f319`。
- GLB 容器、来源许可记录、Unity 导入通过；导入得到 14 个 Renderer，材质和 Shader 引用有效。
- 本地来源记录位于 `Assets/ThirdParty/RobotExpressive/asset-lock.json`，作者 / CC0 声明及上游说明一并保存。
- **尚未完成真机画面验收**。材质引用检查不等同于无粉色、无全黑、正确光照和取景的视觉验证。

## 已执行验证

| 检查 | 结果 | 本机证据 |
|---|---|---|
| SwiftUI / UIKit 对 iOS ARM64 类型检查 | PASS | `.local/checks/native-results.json` |
| Objective-C++ / UIKit 对 iOS ARM64 语法检查 | PASS | 同上 |
| Metal iOS Shader 编译 | PASS | `.local/checks/probe.air`、`metal-result.txt` |
| Unity Hub 代码签名 | PASS | 安装前 codesign 验证 |
| 编辑器、iOS 模块官方文件完整性 | PASS | 官方 MD5 匹配；安装包签名为 Unity Technologies SF |
| Unity Editor / iOS 模块安装 | PASS | `.local/logs/unity-install.log`、`unity-ios-install.log`，实际 iOS 导出 |
| 7 项外部归档完整性及包身份 | PASS | `.local/dependencies/upm/verified.json` |
| 工程静态完整性 | PASS | `.local/checks/unity-project-verify.json` |
| 包解析、C# 编译、GLB 导入、URP / 材质引用 | PASS | `.local/checks/unity-dependencies.json`、对应导入日志 |
| 含 RobotExpressive 的临时场景导出 iOS | PASS，0 errors / 0 warnings | `.local/checks/unity-ios-export.json` |
| UnityFramework iOS ARM64 未签名编译 | PASS，`BUILD SUCCEEDED`，退出码 0 | `.local/checks/ios-toolchain.json`、`.local/logs/unityframework-build.log` |
| 框架二进制平台与部署版本 | PASS：Mach-O arm64，platform IOS，minos 17.0，SDK 26.4 | `.local/checks/unityframework-binary.txt` |
| 真机安装运行与画面 | NOT TESTED | 等待阶段 A 及后续双设备验收 |

`python3 scripts/check_ios_toolchain.py` 创建临时场景，使用 iOS 17.0、Universal、IL2CPP 和 Mobile URP 导出，再调用 Xcode 编译未签名 UnityFramework。临时场景及设置在结束后清理 / 恢复。导出结果在 `.local/build/ios-dependency-probe/`，不是正式宿主的导出产物，不包含方案要求的 Data 后处理或 workspace 集成。

URP 起步工程仍保留模板默认配置。Unity 已把模板过旧的最低 iOS 版本迁移为 15.0；构建探针明确临时设置 17.0。正式开发时需按方案把宿主与 Unity 的部署目标统一为 17.0，并完成方向、全屏、质量档及设备布局配置。

## 设备与签名边界

`xcrun devicectl list devices` 返回 0 台设备。没有导出签名材料。

| 项目 | D01 | D02 |
|---|---|---|
| 设备 | iPhone 17 标准版 | 11 英寸 iPad Pro（M4，2024） |
| 实际系统版本 | 未读取 | 未读取 |
| 容量 / 内存 | 未读取 | 未读取，不默认顶配 |
| 配对 / Developer Mode | NOT TESTED | NOT TESTED |
| Personal Team Run | NOT TESTED | NOT TESTED |
| 布局 / 生命周期 / 性能 | NOT TESTED | NOT TESTED |

[双设备验收模板](acceptance-report.md) 继续保留 NOT TESTED。开发环境验证没有代替技术方案阶段 A → E，当前没有原生宿主、桥接或完整 V0 功能。
