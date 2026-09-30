# 普通会话临时旋转 · 2026-09-30

> 后续更新（2026-09-30）：本机权限恢复后已完成相应补验、AI 网关部署和 iPhone v0.54.0（76）安装。实际通过项及尚未覆盖范围见[交付记录](../device-v054/README.md)。下文保留此前阶段的失败与限制，不将历史受限结果改写为通过。

源码实现：普通状态下单指小范围旋转，松手平滑回到已保存姿态；只在右上角编辑模式支持移动和缩放。完整约定见[设计记录](../../design/2026-09-30-conversation-preview-rotation.md)。

## 已执行

| 验证 | 实际结果 |
|---|---|
| `python3 scripts/test_preview_rotation.py` | PASS，2,206 项断言；直接执行本轮 C# 源码，使用安装的 Unity 托管数学库；覆盖 30/60/120 Hz 时间步、角度界限、两向拖动、非法输入、回弹重抓、精确回零、角色重置、不同刷新率下的响应差异 |
| Unity 运行时代码编译 | PASS；使用本机 Unity 6000.3.25f1 Roslyn 与现有 Editor 编译依赖重新编译全部运行时代码；只有既有的两条 `camera` 成员遮蔽警告 |
| Unity Editor 代码编译 | PASS，包含新增的临时旋转/存档隔离/身体轴心回归断言；场景断言尚未执行 |
| `CharacterTouchSurface.swift` | iPhone Simulator SDK 下 Swift 类型检查 PASS |
| 原生 App + UI 测试源码 | 145 个 Swift 文件语法解析 PASS |
| UI 测试模块 | 48 个 Swift 测试文件在 iPhone Simulator SDK + XCTest Swift overlay 下类型检查 PASS；这不是模拟器执行结果 |
| 真多指事件合成辅助代码 | Objective-C 编译检查 PASS |
| 旧导出检查 | 预期拒绝：现有模拟器导出为旧能力，`check_export_content.py --platform simulator` 要求临时旋转能力 v8。没有修改旧 stamp 或已安装 App |

原始日志保存在本机 `.local/checks/preview-rotation/`，不公开上传二进制、模型或授权日志。

本机 Unity 的 `csc` 包装脚本包含构建机的失效路径。数值测试脚本改为通过已安装的 Mono 直接运行 Unity 随附的编译器程序集，并引用随附的 `netstandard` facade；无需安装第三方替代数学库，也没有模拟或重写被测旋转算法。

## 已加入但未运行的集成回归

- `CharacterViewEditorReview`：在两个发布角色、五种手机视口的原有回归中加入临时旋转；检查固定身体轴心、持续保持保存的平移/比例/角度、回到自定义姿态、从临时拖动进入编辑不误保存。
- `CharacterViewEditorTests.testNormalDragReturnsToSavedPoseWithoutOpeningEditor`：真实单指触摸、默认及自定义姿态回弹、存档不变、聊天滚动仍可用。
- `CharacterViewEditorTests.testNormalTwoFingerGestureIsRejectedAndCancelsAnActiveDrag`：双指起手不能变换、拖动中加入第二指触发回弹、剩余单指不能续转、没有缩放或移动。

## 当前阻塞与后续验证入口

本轮执行环境限制访问系统服务，未完成新 App 导出、安装和交互验收：

- `unity status` 没有可连接的 Pipeline；`unity pipeline list` 没有显示可用的目标 Editor，也没有发现 Safe Mode 编译错误。通过 Unity CLI 启动项目做场景验证后，授权客户端 IPC / 系统 XPC 无法正常连接，并出现只读数据库错误，45 秒超时退出。没有改动授权数据或绕过许可证。
- `xcrun simctl list devices booted` 无法连接 CoreSimulatorService。
- `xcrun devicectl list devices --timeout 10` 无法连接 CoreDeviceService，10 秒超时。
- 当前 `.git` 为只读，没有提交或推送本轮改动；之前的账户后端工作也保持原样，没有重写历史。

具备正常 Unity 授权服务与 Xcode 设备服务的会话中，应先运行 `CharacterViewEditorReview.ReviewAndExportSimulator`，再构建 `ios/StarryNight-Simulator.xcworkspace` 的 `CharacterHost`，在 iPhone 17 跑上述两个 UI 用例以及既有位置编辑回归。真机可用时再安装体验小范围转动和回弹手感。所有 UI 测试沿用 `--ui-testing`，没有调用付费 AI。

测试命令只覆盖数值和编译的部分已经通过；**不把本记录视为模拟器已通过、手机已更新或 120 FPS 性能结论**。
