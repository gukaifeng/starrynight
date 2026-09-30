# v0.54.0 / build 76：设备交付与恢复验证

2026-09-30，执行环境恢复本机与系统服务访问后，先完成 v0.53.0 / build 74 的构建、签名、iPhone 安装及启动；随后按新增要求完成 v0.54.0 / build 76。当前设备读回为 **星夜 0.54.0（76）**，包标识沿用现有开发安装，聊天存档未清空。设计见[80° 与分层对话](../../design/2026-09-30-conversation-presentation.md)。

## 实际完成的验证

| 项目 | 结果与范围 |
|---|---|
| Unity 6000.3.25f1 实际 Editor 场景审查 | **146,195 项断言通过**；两个发布角色、五种手机视口，检查 ±80° 俯仰、水平连续旋转、固定身体轴心、保存恢复、临时偏转回弹；这是几何与状态审查，不是 FPS 测量 |
| Unity 导出 | 真机、模拟器均实际重新导出，交互 revision **10**；构建守卫通过，未手改 stamp |
| C# 临时旋转独立回归 | **2,206 项通过**，含 30/60/120 Hz 数值时间步；不代表真机达到这些帧率 |
| iPhone 17 模拟器 UI | 选定的 **6 个用例最终分别通过**：80° 与存档恢复、普通临时旋转回弹、持久化/隔离核心、UIKit 输入契约、真实软件键盘发送/草稿保留、从历史回到底部及旁白后补/三类文字渲染 |
| 原生输入契约 | **32 项通过**；另在独立 UIKit 容器与完整模拟器测试入口执行。软件键盘用例在最后一次单独重跑通过；未声称覆盖真机所有中文/日文输入法 |
| 聊天滚动/加载纯 Swift 状态 | **24 项通过**；完整 SwiftUI 场景另验证用户消息、AI 消息、后补旁白都能离开历史焦点并回到真实底部 |
| AI 服务免费回归 | **27 项通过**；新增角色事实隔离、无依据描写剔除、三类正文持久化/重放、TTS 不读心声/旁白、语音生成中及时交付旁白与任务取消 |
| 真实 AI | 两位角色分别获得含台词、心声、旁白的完整返回。此阶段累计 **5 个短测试回合 / 10 次模型请求**；没有测试 TTS、ASR、重新设计音色，使用独立测试身份。手机正常启动的真实问候属于正常使用，未计入该脚本次数 |
| iOS Release | 完整真机工程编译成功、`codesign --verify --deep --strict` 通过，CoreDevice 安装和启动成功，设备读回 **0.54.0 / 76** |
| 已部署 AI 网关 | 私有代码、配置和 SQLite 先备份再更新；`/health` 读回 revision **3**，正常聊天限额关闭，已有 Key、音色和用户数据保留；health 的 `paid_calls:false` 仅表示健康请求不计费 |
| 之前受限的账户后端回归 | 环境恢复后 `make check`、API/迁移工具 `make build` 通过，真实 PostgreSQL/Redis 集成通过，原生同步核心 **14 项通过**；不是正式服务器上线，也没有新增真机账户同步或吞吐上限结论 |

## 关键故障与处理

- Unity 首次更新卡在旧 Licensing Client 的 IPC。确认本机 Personal 许可有效、没有其他正在工作的 Editor 后，结束本次挂起 Editor 与旧授权客户端，再用 Unity CLI 重试成功；没有删除许可证或重置账号。
- 可见内容标记的嵌套 Swift 数组表达式触发编译器类型推断超时。拆成明确的逐段数组拼接后 Release 编译通过。
- 第一组 UI 6 项中有 2 项失败，保留原结果：临时旋转用例默认从聊天上方的透明穿透区发起 swipe，修改为从可读聊天区域拖动后通过；键盘用例错误期待“禁用付费 API 导致失败”后草稿为空，实际会保留重试文字。校正场景、隔离两段输入验证后通过，没有改掉失败后保留草稿的功能。
- 真实 AI 第一次两角色检查中，琪宝成功、豆日向旁白被剔除；后续两次定位发现“准确外貌 + 不存在的光线”混写，甚至全句改写却引用正确事实。补齐短句提取及审核引文呈现后，最后一次豆日向检查三类内容齐全；失败记录未覆写，没有拿首次失败当通过。
- `devicectl` 打印的 provisioning provider 提示不影响实际安装、启动和应用版本读回；以动作退出码和设备返回为依据。

## 本机证据与复跑

原始大文件/模型图像均在忽略目录，公开仓库只存此记录、源码和可重跑用例：

- `.local/logs/install-v054-unity-{device,simulator}.log`、`docs/verification/conversation-refinement/runtime-review.json`。
- `.local/checks/install-v054-ui.xcresult`（首次，含失败与成功）、`install-v054-ui-rerun.xcresult`（临时旋转通过）、`install-v054-keyboard-final.xcresult`（软件键盘通过）。
- `.local/checks/install-v054-ui-all/` 中的 `narration-thought-dialogue` 截图已人工查看：灰色旁白、暖色心声和主要台词在同一气泡内清楚区分；这是隔离 SwiftUI 呈现用例，不冒充完整 3D 场景截图。
- `.local/checks/conversation-presentation-live/` 与 `.local/logs/install-v054-live-presentation*.log` 保留每轮独立结果；真实内容不提交。
- `.local/checks/{install,launch,installed,running}-v054-device.json`，以及此前 v0.53 对应文件。
- `.local/checks/install-v054-ai-tests.xml`、`backend/.local/logs/integration-v053.log`、`.local/checks/install-v053-keyboard/result.txt`。

`scripts/live_conversation_presentation_smoke.py --allow-paid` 默认只做两个不带语音的短回合；可用 `--character` 限制到一位角色。普通 pytest、Swift 与 UI 用例不调用付费模型。本轮没有进行真机帧率、温度、耗电或 iPad 验证。
