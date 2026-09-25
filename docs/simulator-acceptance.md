# iPhone 17 模拟器验收 · 模型空间 V1

完成于 2026-09-26，验证范围是用户授权的无人值守本机开发和 **iPhone 17 模拟器完整运行**。包含后续追加的动作按钮与触头摇头。构建标记：V1-sim-20260926.1，App 版本 1.0（1）。

**结论：PASS。XCTest 3 个测试通过、0 失败、0 跳过；实际 Unity 相机 / 动作事件断言 PASS。** 原始测试执行使用真实 UnityFramework 和真实 GLB 模型，没有用替代渲染器、静态图片或假动作绕过集成。

## 直接看效果

- [11 秒实际动作录像](media/iphone17-actions.mp4)：挥手、跳跃、跳舞、点头部后摇头。原始 simctl 录像经 H.264 压缩，保留 1206 × 2622 分辨率，无内容合成。
- [首页](media/01-home.png)、[3D 初始画面](media/03-viewer-initial.png)、[旋转后](media/04-viewer-rotated.png)、[缩放后](media/05-viewer-zoomed.png)、[复位](media/06-viewer-reset.png)。
- [挥手](media/13-wave.png)、[跳跃](media/14-jump.png)、[跳舞](media/15-dance.png)、[触头摇头](media/16-head-shake.png)。
- [加载反馈](media/09-loading.png)、[取消后重新进入](media/10-cancel-recovered.png)、[超时反馈](media/11-timeout.png)、[超时后恢复](media/12-timeout-recovered.png)。

所有 PNG 均直接来自本轮 XCTest 截图附件。截图与录像展示模拟器结果，不代表真机画质和性能验收。

## 验证结果

| 项目 | 结果 | 证据与范围 |
|---|---|---|
| 正式 Unity 场景生成、验证、Simulator 导出 | PASS | 固定接收对象、相机边界、模型材质、5 段所需动画齐全；导出 0 errors |
| 原生 + UnityFramework 完整构建 | PASS | Xcode test 的构建阶段成功；ARM64 Simulator SDK，Data 随框架嵌入 |
| 首页、模型预览、打开入口和关于页 | PASS | 实际截图、XCTest 按钮查询和点击 |
| 真实 3D、灯光、材质和原生覆盖控件 | PASS | 直接屏幕复核，模型正常着色，操作按钮与模型同时显示 |
| 单指旋转 | PASS | yaw 155 → 56.907°、pitch 12 → 2.969°；旋转期间距离保持默认 |
| 双指缩放 | PASS | 相机距离 21.3562 → 7.5713，实际模型画面放大 |
| 复位及再次进入的初始状态 | PASS | 24 条 viewReset 全部回到默认角度、俯仰和距离 |
| 挥手、跳跃、跳舞、触头摇头 | PASS | Wave / Jump / Dance / No 均有真实开始、完成事件，截图 / 录像复核姿态变化 |
| 触头与拖动区分 | PASS | 有效触头 1 次 → headTapped 1 次；身体、空白和从头部开始拖动均无额外触发 |
| 动作快速切换和播放中返回 | PASS | Wave → Dance → Jump，播放 Dance 时返回并重新进入；页面和后续操作正常 |
| 连续进出 20 次 | PASS | 完整流程共 22 次 presentation，sceneReady 仅 1 次，复用同一场景 |
| 首页后台恢复 | PASS | Home 键进入后台再激活，首页可操作 |
| 查看页与播放中动画后台恢复 | PASS | Dance 播放中进入后台，激活后查看页恢复并收到动作完成事件 |
| 加载中取消、再打开 | PASS | 测试延迟 ready 4 秒，操作真实返回按钮后再次打开成功 |
| 加载超时与重试 | PASS | 测试延迟 ready 18 秒，实际超时错误页可返回并恢复查看 |
| 数值边界 | PASS | Editor 验证俯仰上下限、缩放上下限和横竖宽高比取景公式；非逐项设备手势极限测试 |

测试专用延迟只改变首个 ready 事件的到达时间；Unity 的真实初始化、渲染和暂停恢复仍执行。最后一个完整流程不注入延迟。该流程收集 **72 条事件**；机器可读结果见[参数和动作断言](verification/simulator-verification.json)、[原始事件](verification/simulator-events.jsonl)、[XCTest 摘要](verification/simulator-xctest-summary.json)、[构建标识与哈希](verification/simulator-build.json)。

## 本机原始证据和复现

环境：Apple M3 Pro / ARM64、macOS 26.3.1、Xcode 26.4（17E192）、iOS Simulator 26.4（23E244）、iPhone 17、Unity 6000.3.25f1。

- `.local/checks/ViewerFlow-20260926-002150.xcresult`：3 个用例及全部附件。
- `.local/logs/ViewerFlow-20260926-002150.log`：本轮完整编译和测试日志，结尾 TEST SUCCEEDED。
- `.local/checks/ViewerFlow-20260926-002150-events.jsonl`：完整流程原始事件。
- `.local/checks/ViewerFlow-20260926-002150-attachments/`：16 张原始 PNG 及 manifest。
- `.local/checks/actions-demo-final.mp4`：原始 simctl 动作录像。
- `.local/logs/export-simulator.log`：正式 Unity 导出完成，内部 success=true。

在仓库根目录执行 `bash scripts/test_simulator.sh` 可重跑，结果以新时间戳保存。运行现有构建用 `bash scripts/run_simulator.sh`。完整维护说明见 [README](../README.md)。

## 未验收范围与已知限制

1. iPhone 17 真机和 2024 年 11 英寸 iPad Pro 真机：**NOT TESTED**，未连接设备、未配置 Personal Team 签名。
2. iPad 的 Universal 目标、横竖方向和宽屏布局已编码；本轮未运行 iPad 模拟器，因此不能宣称完成 iPad 视觉和生命周期验收。
3. 真机帧率、120 Hz、长时间内存、发热、耗电：**NOT TESTED**。代码目标帧率 60，不以模拟器表现推断实机性能。
4. App Store / TestFlight、发布签名、完整 VoiceOver 与各档动态字体、分屏窗口压力测试：本轮未执行。
5. Unity 首次初始化仍含主线程同步工作；前台 15 秒计时提供可恢复错误页，不能中断引擎内部的同步阻塞。
6. 动作为本地预设动画，触头为本地命中检测；没有语音、对话、云服务或额外 AI 运行成本。

当前构建保留 Unity 导出代码的部分 Apple API 弃用警告和每次执行 GameAssembly 构建脚本提示，未产生编译错误。线程性能检查器与 Unity 初始化的冲突已在工程生成器中固定关闭，详细依据见[开发记录 E03](development-notes.md)。
