# Mac 语音开发对照服务

> 自小伴 v0.7.0 起，App 已内置 iOS 推理库和模型，不再调用此服务。以下为历史服务维护说明；日常手机和模拟器使用无需启动它。见[端上方案](../../docs/design/2026-09-28-offline-speech.md)。

macOS Apple Silicon + Python 3.11，使用 sherpa-onnx 1.13.8 加载 SenseVoiceSmall int8 与 MeloTTS zh_en ONNX。仅监听 `127.0.0.1:18765`，不依赖云端语音 API。

首次准备：`scripts/setup_voice.sh`。日常启动：`scripts/start_voice.sh`。停止：`scripts/stop_voice.sh`。服务通过当前用户的 launchd 会话管理；运行时和 plist 位于 `~/Library/Application Support/Xuyu/Voice/`，未安装到登录自动启动目录。服务属于前台交互所依赖的推理任务，因此设置 `ProcessType=Interactive`，避免默认后台任务资源限制；这不保证在主机高负载时仍有低延迟。首次部署复制固定模型与依赖到该目录，避开后台服务不适合使用的 Documents 工作目录。健康检查：`curl http://127.0.0.1:18765/health`。实际推理验证：`.local/voice-venv/bin/python scripts/test_voice.py`。

依赖精确版本与包哈希在 `requirements.lock`；模型上游 commit、大小、下载后 SHA-256 在 `models.lock.json`；随附许可证位于 `licenses/`。下载的是 ONNX 数据文件，不执行模型仓库的 Python 脚本。权重缓存位于 `.local/voice-models/`，不提交 Git。

API：`GET /health`；`POST /v1/tts` 接收 `{text,speed}` 返回 PCM WAV；`POST /v1/asr` 接收 WAV 返回 `{text}`。录音限制 31 秒与 4 MB，语音请求串行执行，忙碌时异步排队最多 45 秒，超时返回 503；已断开客户端的排队请求被丢弃；无访问日志与内容落盘。调用取消会丢弃客户端过期结果，已经开始的 ONNX 推理通常仍会在服务端完成。

模拟器访问的是 Mac 的回环地址。旧版真机的 localhost 指向真机自身，不能直接复用此配置。v0.7.0 已用原生 iOS 推理替代这一调用链；保留服务仅作开发对照。

文字对话独立于此服务，来自 App 包中的 `LocalDialogue.json`。当前 App 的文字和语音均不受此服务启停影响。

许可证：sherpa-onnx Apache-2.0；模型分发包中的 SenseVoice 与 MeloTTS 为 MIT，保留随附原文。普通预训练声音，无声纹克隆。
