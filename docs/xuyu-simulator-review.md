# 栩屿 0.2 · 品牌与动作修正版验收

2026-09-27。此轮遵循用户最新要求，只在模拟器开发与验证，不更新真机。App 显示名为“栩屿”，英文标记 XUYU，版本 0.2 / build 3；保留原有应用标识和数据容器。

## 直接查看

- [当前 iPhone 17 角色画面](verification/xuyu/iphone17-final.png)
- [约 46 秒动作演示](verification/xuyu/iphone17-actions.mp4)：H.264，1206×2622；性能采样结束后单独录制。视频编码帧率不代表 Unity 实际渲染帧率，性能以 JSONL 为准。原始录屏保留在 `.local/checks/xuyu-actions-original.mp4`。
- 目前 iPhone 17 模拟器运行 Xcode Release 编译版本，停在初音查看器；可直接拖动、缩放、触头，底部动作栏可横向滑动。
- 再次打开现有版本：`bash scripts/run_simulator.sh --release`。

## 实际变更

- 首页、关于页、加载页换用新名称和瓷玉对话环 Logo，系统 App 图标为 1024×1024 不透明 PNG。角色操作统一深青 / 玉色。品牌原图及提示词都已落盘。
- 七个初音动作改为真实骨架的手脚协同轨迹，加入准备、保持、回收、下蹲及落地缓冲。双手致意保持距离，前臂路线避开身体。运行时加入 0.24 秒动作渐变和 14 段双马尾弹簧 / 胶囊避让。
- 新增 120 Hz 全动作姿态采样及三视角检查。4,173 个采样姿态通过针对性约束检查，81 张动作检查图保存在 `.local/checks/miku-motion-review/`。
- 导出脚本复用原任务重试状态查询，模拟器就绪检查有超时边界。两类恢复都不把“工具能响应”替代为“App 已验收”。

## iPhone 17 / iOS 26.4 Simulator

完整原生 UI 测试 **PASS**，结果为 `.local/checks/Xuyu-Motion2-Phone.xcresult`。实际引擎事件再次独立校验：

| 检查 | 结果 |
|---|---|
| 初始化期间取消、重新打开 | PASS |
| 加载超时后恢复 | PASS |
| Luma 旋转、缩放、复位、动作、触头、后台恢复 | PASS |
| Luma 22 次展示、24 次复位、引擎只初始化一次 | PASS |
| Luma → 初音 → Luma，动作中退出 | PASS |
| 初音七种按钮动作开始并完成 | PASS |
| 初音头部命中；身体、背景、拖动负例 | PASS |
| 初音缩放、复位、60／120 目标切换 | PASS |
| 包内显示名、版本、图标资源 | 栩屿 / 0.2 / 3 / AppIcon |

证据位于 `verification/xuyu/` 的原始 JSONL 与各自 verification.json。手机测试中的 iPad 专项按设计跳过，在独立 M4 iPad 目的地运行。

## iPad Pro 11 英寸 M4 / iOS 26.4 Simulator

横竖屏专项 **PASS**，结果为 `.local/checks/Xuyu-Motion2-iPad-Retry.xcresult`：竖屏进入初音、切横屏、应援按钮可点击且动作执行、复位、返回角色首页。实际引擎事件确认只初始化一次，应援开始 / 完成齐全，渲染尺寸分别为 1668×2420 和 2420×1668。

第一次 XCTest 冷启动停在应用的 15 秒加载超时页；当时 Mac 的负载显著偏高。随后相同 App 直接启动成功，关闭另一台模拟器后，未修改业务代码、未放宽超时或断言，复跑此项通过。原失败结果保留在 `.local/checks/Xuyu-Motion2-iPad.xcresult`，不能把该次失败当作已通过。现有证据支持瞬时启动环境问题，尚不能单凭负载数据证明具体底层原因。

[iPad 竖屏](verification/xuyu/ipad-portrait.png)、[横屏](verification/xuyu/ipad-landscape.png)、[横屏动作](verification/xuyu/ipad-landscape-action.png)、[角色首页](verification/xuyu/ipad-home.png)均来自通过的测试。独立事件核验见 `verification/xuyu/ipad-events.verification.json`。

## 画面与性能边界

[首页](verification/xuyu/iphone17-home.png)、[关于](verification/xuyu/iphone17-about.png)、[角色查看](verification/xuyu/iphone17-viewer.png)、[拉近查看](verification/xuyu/iphone17-close.png)为运行中的 App 截图。XCTest 截图时包含 UI 自动化与调试负载，图中 FPS 不能代替真机验收。

在 XCTest 停止、未录屏的独立 Debug 采集中，七个动作在 120 / 60 两种目标下各执行一遍，均有开始和完成事件。1206×2622 分辨率下平均为 34.31 / 34.37 FPS，模拟器报告刷新率 60 Hz；这次没有达到稳定 60 FPS。宿主机负载偏高，测量也不代表物理显示呈现或真机性能。原始数据与报告分别为 `verification/xuyu/simulator-performance-events.jsonl`、`verification/xuyu/simulator-performance.json`。

额外完成 Xcode **Release** 构建并重新安装。保持相同模型、纹理、阴影、原生分辨率及 Unity Development 导出，停止 XCTest 与录屏后，七个动作各在两种目标下完整执行一次：

| 编译配置 | 请求目标 | 实测平均 FPS | 屏幕报告上限 |
|---|---:|---:|---:|
| Debug | 60 | 34.37 | 60 Hz |
| Debug | 120 | 34.31 | 60 Hz |
| Release | 60 | 34.07 | 60 Hz |
| Release | 120 | 33.99 | 60 Hz |

**功能验收通过，当前模拟器稳定 60 FPS 的性能验收未通过。** Release 没有显著改善这次观察，不能断言仅由调试配置或宿主负载造成；需要进一步 CPU / GPU 帧时分析。未降低画质以制造通过结果。Release 原始数据和慢帧统计在 `verification/xuyu/simulator-release-performance-events.jsonl`、`verification/xuyu/simulator-release-performance.json`。两组采样均是 Unity player-loop 墙钟间隔，不是物理屏幕呈现测量。

新动作的真机 120 FPS 尚未复测。`verification/miku/initial-device-performance.json` 是用户反馈前的初版动作结果，明确保留其历史范围。胶囊包络与离散姿态检查可以发现已知动作问题，不等于任意连续切换中所有网格表面永不穿插；饰带 / 衣物尚无完整布料物理。

聊天、性格、语气与外观编辑尚未接入。本次没有接入付费 API 或虚构聊天回复。产品路线见 [产品方向](product-direction.md)，失败根因与关键决策见 [开发记录](development-notes.md)。
