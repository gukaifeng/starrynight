# 栩屿 v0.3 · 本地伙伴原型验收

2026-09-27，Xcode 26.4 / iOS Simulator 26.4 / Apple Silicon，Debug 构建，App 0.3 (4)，Unity 内容版本 3。仅模拟器验证，没有安装或更新真机。

## 实现结果

| 模块 | 这版可用的能力 |
|---|---|
| 双角色聊天舞台 | Luma 与初音；iPhone 上下布局，iPad 横竖屏左右布局；保留原查看器 |
| 塑造角色 | 昵称、背景、三种性格、三种语气、简短偏好；按角色保存 |
| 外观与空间 | 三种点缀配色、三种光照氛围；修改真实 Unity 材质参数 |
| 文字对话 | 本地情景库，逐字呈现、停止、重答、快捷话题、点赞、简短偏好 |
| 共同记忆 | 手动保存、消息存入、编辑、删除、角色隔离；回复实际引用已保存内容 |
| 历史与资料 | 本机最近 1,000 条消息、搜索、JSON 导出、确认清空聊天；不连云同步 |
| 真实 ASR | SenseVoiceSmall int8，结果进入可编辑草稿，用户确认后发送 |
| 真实 TTS | MeloTTS zh_en，单一音色、语速调整、分句合成／预取、播放与停止 |
| 3D 表达 | 允许列表动作联动、倾听／思考／说话状态；实际音量驱动口型／灯光 |
| 数据与启动 | 原子写入、损坏文件保留恢复副本；服务只监听本机回环，启动／停止脚本 |

这些是原型功能，不代表已完成真实大模型训练、商业发布或实时通话。

## 实际验证

| 验证 | 结果与证据 |
|---|---|
| iPhone 完整场景 | 通过，292.476 秒；设置、记忆回忆、聊天动作、重答、真实朗读／停止、重启恢复。`Companion-Phone-Final-summary.json` |
| 初音与资料控制 | 通过，172.653 秒；真实发色变更、记忆编辑／删除、导出、清空、角色切换隔离。`Companion-Controls-ASR-summary.json` |
| ASR 到界面 | 通过，75.770 秒；真实上游 WAV 经本机识别，草稿编辑后确认发送。不是麦克风真人录音测试 |
| iPad 横竖屏与查看器 | 重试通过，96.874 秒；`Companion-iPad-Retry-summary.json`；真实 Unity 事件确认挥手开始与完成 |
| 初音实际发声与启动连接 | 局部修正后通过，健康检查、实际非零音频采样和停止；`Companion-Final-Voice-Startup-summary.json` |
| 核心逻辑 | 可执行 Swift 测试通过；持久化、隔离、回忆／删除、人设、变体、简短模式、动作白名单、损坏档案拒绝。`core-tests.txt` |
| 实际落盘与导出 | `persistence.json` / `export.json`，读取合成测试档案和真实导出文件检查，不读取用户生产资料 |
| 播放链路 | `phone-speech-events.json` 记录真实 HTTP 200、AVAudioPlayer 启动与非零音量采样；没有用按钮文字冒充发声 |

最终五条主要 UI 场景通过，完整 xcresult 保留在 `.local/checks/`。iPad 第一次冷启动因 15 秒加载保护失败，相同二进制重新启动后通过；失败证据 `Companion-iPad-Final.xcresult` 保留，首次启动可靠性尚需优化。

## 实际截图

- [iPhone 聊天与记忆回忆](screenshots/04-memory-recalled.png)
- [交付时 iPhone 模拟器画面](screenshots/16-final-iphone.png)
- [角色设定](screenshots/02-profile.png)
- [初音真实配色](screenshots/13-miku-purple-chat.png) / [真实语音专项](screenshots/17-miku-real-speech.png)
- [识别结果进入草稿](screenshots/11-real-asr-editable-draft.png)
- [资料导出](screenshots/14-history-export.png)
- [iPad 横屏](screenshots/08-ipad-landscape.png) / [iPad 竖屏](screenshots/09-ipad-portrait.png)
- [原查看器回归](screenshots/10-explorer-regression.png)

截图均来自实际模拟器，不是界面效果图。已审查聊天、设置、初音配色、ASR 草稿及 iPad 横竖屏。

## 语音材料与边界

最终独立回环测量：ASR 约 **0.55 秒**；合成约 **3.15 秒**音频耗时 **4.61 秒**。本句回环字符误差率 **6.67%**，主要为“小屿”→“小雨”，不是总体准确率评估。确认推理已开始后的取消恢复测试通过，下一句约 **3.23 秒**返回。完整汇总见 `acceptance.json`。


`voice-inference.json` 保存真实 ASR/TTS 回环测量、原始转写、字符误差率和静音／损坏音频处理；`melo-sample.wav` 为实际合成输出。`voice-cancellation.json` 验证前一请求取消后下一句仍能合成。`voice-interactive-probe.json` 是独立短句测量；`kokoro-benchmark.json` / `kokoro-voice-*.wav` 是未采用的对比方案。

- 文字是明确标注的本地情景对话，不是开放域 LLM。点赞只保存反馈；简短偏好修改配置，不是训练模型。
- ASR/TTS 在 Mac 上真实离线推理；当前仅模拟器可以使用此 localhost 服务，尚未把模型打包进 iPhone。真人麦克风采集未验证。
- ASR 出现同音字误差（例如“小屿”→“小雨”），所以保留用户确认步骤。回环测量不代表全面识别准确率。
- Melo 短句在独立测量中约 4–5 秒；模拟器与 XCTest 活跃时出现 22–62 秒，完整手机流程的一句约 49 秒才开始播放。分句预取与调度调整已实现，但实时通话体验未达标；服务端已启动的 ONNX 推理暂不能硬取消。
- 口型按音量驱动，尚非音素级同步。当前 UI 回归不等于对所有表情、动作、服装完全无穿模的证明。
- 本轮没有新的真机帧率验收，不能声称稳定 60／120 FPS。前一版模拟器约 34 FPS 的负面结果仍有效，不能挪用旧版真机数据。
- 商业化仍需原创或完整商业授权角色、真实模型服务、隐私／同步／成本方案，以及真机长时验收。初音当前为个人非商业演示素材。

## 复现入口

```bash
scripts/start_voice.sh
scripts/test_companion.sh 99F5FAC6-A73A-4C59-A723-D57D648B342E CompanionFlowTests/testCompanionConversationMemoryAndPersistence Companion-Phone-New
scripts/test_companion.sh 99F5FAC6-A73A-4C59-A723-D57D648B342E 'CompanionControlsTests,SpeechFixtureFlowTests' Companion-Controls-New
scripts/test_companion.sh 70821D30-E342-464C-B5E4-2D86BE218D58 CompanionFlowTests/testTabletLayoutAndExplorerRegression Companion-iPad-New
.local/voice-venv/bin/python scripts/test_voice.py
.local/voice-venv/bin/python scripts/test_voice_queue.py
```

每次使用新的结果名称，避免覆盖历史 xcresult。测试与推理基准串行运行；性能数字应附带具体环境。开发决策和错误处理见 [开发记录](../../development-notes.md)，分期和竞争力判断见 [实施规划](../../design/2026-09-27-companion-plan.md)。
