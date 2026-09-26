# Luma：画质与高刷新率交付

更新：2026-09-26。此报告对应 Luma 升级，首版 RobotExpressive 证据保留在原模拟器报告中。

## 已实现的画质与交互

- 原创 Luma：70,980 三角面、35 个 Renderer、6 种共享 PBR 材质；陶瓷外壳、金属关节、玻璃面罩、微光眼睛。
- 原生分辨率 renderScale=1，4× MSAA，HDR 内部缓冲及 ACES 色调映射。HDR 缓冲并非屏幕 HDR 显示认证。
- 4096 主光阴影图、两级级联、高质量软阴影；补光、轮廓光及预生成棚拍环境反射。阴影距离 50，覆盖最大缩远视角。
- 默认构图为完整动作留空间；可旋转、缩放、复位。挥手 / 跳跃 / 跳舞可点击播放，触碰头部摇头，身体和空白不触发。
- 模型、连续动作和反射均由项目脚本生成，不需要再下载高容量模型或贴图。

[场景配置证据](verification/luma/scene.json)；[动作边界证据](verification/luma/action-framing.json)。后者是 Unity Editor 对每条动画 61 个时刻的 Renderer bounds 投影检查，覆盖 iPhone 和 iPad 纵横屏比例，不替代 iPad 运行测试。

## 120 FPS 支持与测量口径

默认请求 120 FPS，可在查看器切换为 60。Unity ProMotion 与宿主 `CADisableMinimumFrameDurationOnPhone` 都开启，按需跳帧关闭，动画每渲染帧连续求值。显示链采用 Unity 导出的 iOS 实现。

界面分开显示实测 FPS、目标 FPS 和当前屏幕上限。事件同时记录 requested target、Unity applied target、refreshHz、分辨率、帧数、窗口时长、平均 FPS、P95 / P99 / 最慢帧和超预算数量。指标来源为 Unity player-loop 墙钟间隔，不是 GPU 完成或屏幕实际呈现时间。配置、焦点或暂停恢复后的首秒为明确排除的预热；其余慢帧不删除。每两秒汇总一次，无逐帧 JSON / 文件写入。

16.67ms 阈值附近的正常调度抖动也会被计入 `over16_7ms`；这个字段不等同于“严重掉帧比例”。120 的请求值不当作 120 的实测值。

## 最终模拟器结果

最终用例：`ViewerFlow-20260926-084457`，**3 tests passed、0 failures、0 skipped**。102 条引擎事件断言通过：22 次展示、24 次复位、仅一次 sceneReady、四种动作均开始和完成、触头命中一次、身体 / 空白 / 拖动无误触、后台动作恢复、60／120 两档均产生测量事件。

| 请求目标 | 模拟器报告上限 | Unity 应用值 | 采样帧数 / 时长 | 平均 FPS | 最差窗口 P99 | 最慢单帧 |
|---|---:|---:|---:|---:|---:|---:|
| 60 | 60 Hz | 60 | 479 / 8.033s | 59.63 | 33.505ms | 39.749ms |
| 120 | 60 Hz | 60 | 3119 / 52.233s | 59.71 | 44.580ms | 105.340ms |

保持 1206×2622 原生分辨率和上述完整画质。采样来自包含截图、手势、菜单及动作录像的功能自动化流程，并非独立的真机持续性能基准；不能把期间的慢帧全部归因于渲染，也没有将它们删除。**本次模拟器测量不满足“每帧严格高于 60”要求；平均接近 60 不能视为该要求已通过。**

- [实测性能 JSON](verification/luma/performance.json)、[原始事件](verification/luma/events.jsonl)、[引擎断言](verification/luma/verification.json)
- [XCTest 汇总](verification/luma/xctest-summary.json)、[构建与二进制校验](verification/luma/build.json)
- [首页](media/luma/01-home.png)、[查看器](media/luma/03-viewer-initial.png)、[挥手](media/luma/13-wave.png)、[触头摇头](media/luma/16-head-shake.png)
- [11.26 秒真实模拟器动作录像](media/luma/iphone17-actions.mp4)，1206×2622，未经补帧；录像本身不证明 120 FPS。

`.xcresult` 和构建日志保留在 `.local/checks/`、`.local/logs/`。

## 真机验收状态

**持续严格高于 60 FPS：尚未验收。120 FPS 的实际持续表现：尚未验收。**

本轮没有连接 iPhone 17 / iPad Pro M4 真机，当前模拟器向应用报告 60 Hz，Unity 会把请求的 120 限制为 60。不能据此证明 120，也不能据此推断真机跑不到 120。

后续应在两台指定真机上使用同一画质，分别测待机、连续动作、拖动旋转、拉近观察与动作切换；持续运行至少 15 分钟，记录平均 / P95 / P99 / 最慢帧、温度、低电量模式和系统帧率限制。将动作期间每帧间隔小于 16.67ms 单独作为“严格高于 60”验收，将 8.33ms 预算作为 120 目标检查，同时用 Instruments / Metal 验证 GPU 与显示呈现。视频录制不是 120 FPS 验收证据。

Apple 会综合设备能力、低电量、温度和系统偏好决定可用刷新率，应用无法对所有运行条件强制保证最低帧率。依据：[Apple 刷新率策略](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink/preferredframeraterange)、[Unity 移动平台帧率规则](https://docs.unity3d.com/6000.3/Documentation/ScriptReference/Application-targetFrameRate.html)。指定硬件的最高 120 Hz 规格见 [iPhone 17](https://www.apple.com/iphone-17/specs/) 与 [iPad Pro 11 英寸 M4](https://support.apple.com/en-us/119892)。

## 复现

```bash
python3 scripts/export_unity_ios.py --platform simulator
bash scripts/build_host.sh
bash scripts/run_simulator.sh
bash scripts/test_simulator.sh
python3 scripts/summarize_performance.py .local/checks/<本轮>-events.jsonl
```

仅查看现有构建可运行 `bash scripts/run_simulator.sh`。修改 Unity 内容后必须先导出并重新构建。关键决策与错误处理见 [开发记录](development-notes.md)，帧率事件契约见 [运行结构](runtime-architecture.md)。
