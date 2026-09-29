# v0.7.0 / build11 离线语音验收

2026-09-28，Xcode 26.4，iOS 26.4 模拟器。验证前关闭 Mac 语音 launchd 服务，验证后再次确认 `127.0.0.1:18765` 无监听者。App 不再有语音 HTTP 调用，也没有 localhost ATS 例外。本轮没有关闭 Mac 全局网络，不能将本记录称为物理断网测试。

| 环境 | 用例 | 结果 |
| --- | --- | --- |
| iPhone 17 独立 QA 模拟器 | 实际录音样本识别 → 可编辑草稿 → 确认发送；实际朗读及停止 | 2 / 2 通过，测试体 26.327 秒 |
| iPhone 17 独立 QA 模拟器 | 多句播放、取消后 ASR、背景停止与恢复、音乐避让；无效输入恢复；静音不编造文字 | 3 / 3 通过，测试体 51.720 秒 |
| iPad Pro 11 英寸 M4 QA 模拟器 | 上述全部五项 | 5 / 5 通过，测试体 79.789 秒 |
| 已配对 iPhone 17 真机 | Release 签名、深度验签、更新安装、启动 | 成功，0.7.0 / build11 |

完整 `.xcresult` 路径、包含安装与启动在内的会话耗时、包体统计和签名结果在 [results.json](results.json)。构建和设备安装原始输出保留于项目 `.local/logs/`、`.local/checks/`，文档不复制用户签名身份或配置。

测试实际运行了 App 内的 ONNX 模型，没有桩回复或网络 fallback。播放器非零音量事件验证合成结果确实进入播放；不把“按钮变成停止”单独作为播放成功。识别样本长 5.592 秒，首轮 iPhone 模拟器转写约 1.145 秒；首句合成约 3.109 秒，后一句约 0.772 秒。其他采样见两台模拟器的 `speech-events.jsonl`。这些是开发机上的耗时，不代表真机速度。

## 截图与事件

- [iPhone：识别结果成为草稿](iphone17/11-real-asr-editable-draft.png)
- [iPhone：真实多句朗读](iphone17/offline-two-sentences.png)
- [iPhone：取消朗读后切换识别](iphone17/offline-cancel-and-asr.png)
- [iPhone：静音提示](iphone17/offline-silence.png)
- [iPhone 诊断事件](iphone17/speech-events.jsonl)
- [iPad：识别草稿](ipad-pro-11/11-real-asr-editable-draft.png)
- [iPad：多句朗读](ipad-pro-11/offline-two-sentences.png)
- [iPad 诊断事件](ipad-pro-11/speech-events.jsonl)

截图中的“识别测试录音”只在 DEBUG 显式启动测试参数时出现；手机 Release 没有这个入口。普通模式 iPhone17 模拟器已安装新版并打开小夏聊天。两台独立 QA 模拟器已关闭，workspace 保持 device 配置。

## 体积与验证边界

- 手机 Release `.app` 逻辑文件合计 673,130,408 字节，约 **641.9 MiB / 673 MB**，为未压缩构建目录，含角色和语音资源；不是 App Store 下载大小，也不是“设置”里统计的存储占用。
- `VoiceModels` 合计 431,168,102 字节，约 **411.2 MiB / 431 MB**，共 30 个模型、字典、说明及许可文件和一个清单。推理二进制另计入可执行文件。
- 真机已安装、启动，但本轮未自动操作真机麦克风、未测量真机语音推理延迟或同时渲染时的持续帧率。用户可拔掉数据线并关闭 Wi-Fi／蜂窝网络，实际录音与朗读验证；首次使用麦克风需系统授权。
- 通用聊天大模型未接入，文字仍来自本地情景库。语音推理本身是真实模型执行。

关键决策和错误处理见 [设计记录](../../design/2026-09-28-offline-speech.md)，依赖许可见 [第三方说明](../../../THIRD_PARTY_NOTICES.md)。
