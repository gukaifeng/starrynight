# 小伴 v0.7.0：手机内置语音

## 问题和交付范围

旧版 LocalSpeech 通过 HTTP 调用 `127.0.0.1:18765`。模拟器的回环地址可到达 Mac 服务，真机的回环地址指向手机，所以脱离电脑后无法识别或朗读。本次直接去掉这条服务调用链，把模型和原生推理库随 App 安装。

| 能力 | v0.7 实现 | 运行时外部依赖 |
| --- | --- | --- |
| 录音转文字 | SenseVoiceSmall int8，自动语言识别，16 kHz 原生录音 | 无；首次录音需要系统麦克风授权 |
| 回复朗读 | MeloTTS zh_en，单一预训练音色，语速可调 | 无 |
| 模型嘴部运动 | 实际播放音量 → Unity speechFrame | 无；尚非音素级口型 |
| 文字聊天 | 内置 LocalDialogue.json 与角色档案、记忆 | 无；不是通用聊天大模型 |
| 背景音乐、角色、取景、资料与历史 | 已有内置素材和本机存储 | 无 |

## 选择依据

- 先查找技能：`find-skills` 检索 `sherpa onnx ios` 无结果，没有为了使用技能引入不相关工作流。使用现用开源项目的官方 C API、iOS 文档与固定版本 Swift Package 定义。
- 复用已经验证过的 SenseVoice / Melo 权重，降低端上迁移的变量；不改为需要服务器的系统识别，也不暗中回退到 Mac。
- 固定 sherpa-onnx 1.13.8、ONNX Runtime 1.28.1 官方静态 XCFramework，包含真机与模拟器切片。上游 onnxruntime-libs 的包标签是 1.28.2，其二进制版本是 1.28.1，两者不是笔误。
- 模型与附属资源约 411 MiB，首装即可用。资源不复制到 Documents，不在用户启动后再次下载。开发机大文件保存在忽略目录 `.local/speech-ios/`；源码中保留准备脚本、固定 URL、哈希与许可。

## 推理、内存与交互

Objective-C++ 桥接持有串行后台队列，识别和合成各使用两个 CPU 线程。任何时刻仅保持一个语音模型实例：从听切换到说时销毁 ASR，从说切换到听时销毁 TTS。代价是模型切换会有加载等待，收益是避免两个模型与 Unity 同时常驻。

沿用最多 30 秒录音、识别后先编辑再发送。解析器限制 4 MiB WAV、8–48 kHz 采样率、0.15–31 秒长度；RMS 小于 0.001 的静音直接返回空文字。错误恢复后仍能继续朗读。

回复按句及最多 55 字分块，首句播放时预备下一句。点击停止立即停止播放器和口型，使后台任务的代数失效。已进入 ONNX 的计算可能运行到本次调用结束，回调与 Swift token 会共同丢弃旧结果，防止停止后又响起来。进入后台、系统中断及返回聊天外部沿用停止路径；后台和内存警告额外释放推理模型，释放与解码从不并发。

AVAudioSession 仍只由 CompanionSoundscape 配置，朗读时音乐降至用户音量的 18%，录音时暂停音乐。后台推理不设置音频会话。

## 打包与离线保证

`prepare_ios_speech.py` 下载并验证上游固定 SHA-256，组装原始模型、词典、FST 和许可；支持显式 `--proxy`，代理只用于开发机下载。`--check` 从不请求网络。Xcode 内容检查阶段校验全部模型文件哈希，App 启动检查打包文件数量和尺寸，再显示“离线语音已就绪”。

LocalSpeech 不再含 URLSession、HTTP endpoint 或健康检查；删除 Info.plist 的 localhost 明文例外。Mac FastAPI 服务保留为开发对照工具，本轮验证前关闭。普通运行不记录识别文字、录音或请求日志；DEBUG 显式 UI 测试仅记录阶段、耗时、字节数和播放器非零音量事件。

## 错误处理与边界

- GitHub 直连超时／不稳定时，使用系统已配置的 `127.0.0.1:7897` 代理完成官方库下载；未读取或转发 Codex API 凭据。两个模型复用此前下载且校验通过的缓存。
- 首次 Xcode 构建发现其脚本环境使用 Python 3.9，缺少 `hashlib.file_digest`；改用分块 SHA-256，兼容系统 Python，避免依赖终端 PATH 才能构建。
- 官方完整 TTS 预编译库链接了 eSpeak NG / Piper，不能因为 sherpa 主项目是 Apache-2.0 就将全部二进制视为相同许可。已补原始许可与源码定位、App 内离线许可入口；当前个人原型之外的分发需按 [第三方说明](../../THIRD_PARTY_NOTICES.md) 处理。
- CPU 推理的耗时、内存及与 Unity 共存时的持续帧率必须真机测量。模拟器通过不意味着手机上保证 60／120 FPS。模型包下载大小、未压缩 App 体积和设备实际存储占用分别统计。
- 通用聊天大模型属于后续独立推理模块；本次没有把预设对话包装成通用 LLM，也没有为不存在的云端调用新增密钥或代理配置。

## 复现与验收

准备：`python3 scripts/prepare_voice.py`、`python3 scripts/prepare_ios_speech.py`。本工作区已完成，普通构建无需再下载。模拟器：`bash scripts/build_host.sh`；手机：`bash scripts/build_device.sh`。

真实引擎 UI 验证：`zsh scripts/test_companion.sh SIMULATOR_UUID SpeechFixtureFlowTests,SpeechPlaybackTests,OfflineSpeechLifecycleTests RESULT_NAME`。使用独立测试资料，不读取用户聊天。Mac 服务必须停止；验收包括实际识别草稿、人工确认发送、播放器非零音量、多句朗读、停止后立即 ASR、音乐避让、后台释放恢复、静音与无效录音。

本轮实际结果、截图和诊断事件：[验收记录](../verification/offline-speech/README.md)。

## 官方来源

- [sherpa-onnx iOS 文档](https://k2-fsa.github.io/sherpa/onnx/ios/index.html)
- [sherpa-onnx v1.13.8 Package.swift](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/Package.swift)
- [ONNX Runtime 库包 v1.28.2 定义](https://github.com/csukuangfj/onnxruntime-libs/blob/v1.28.2/Package.swift)
- [固定 C API](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/c-api/c-api.h)
