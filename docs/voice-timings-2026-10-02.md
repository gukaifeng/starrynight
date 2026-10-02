# 语音逐次耗时追踪 · 客户端

开发版入口：**我的 → 开发者 → 语音耗时**，查看当前账户的所有角色；也可在角色资料的**角色开发者 → 语音耗时**查看这个角色。详情显示客户端时间轴、收到的服务端快照、追踪 ID、缓存来源、失败/取消状态和完整 JSON 分享。入口由 `STARRY_TEST_TOOLS` 控制，不随正式发行项目分发。

## 拆解范围

每次生成、内置首句、本地缓存重播、远程重播和按住说话分别记一次。以本机单调时钟计时，墙钟只用于显示日期。后台预生成在服务端另记一次，前台日志携带关联 ID。

| 阶段 | 实际测量 |
|---|---|
| 请求准备 | 整理对话、请求体、任务开始、内置问候上下文注册、JSON 编码 |
| 网络 | 等响应头、首段音频/末段音频到达、完整流接收；URLSessionTaskMetrics 细分 DNS/TCP/TLS/上传/首响应等待/下载，并标记连接复用 |
| 事件 | 每条 SSE 解码与分发；逐段音频从网络到有界播放队列的等待 |
| 播放准备 | 上一段 drain、音频会话激活、创建和启动 AVAudioEngine |
| 每块音频 | Base64 解码、PCM 格式转换、播放缓冲提交、字节数和 beat ID |
| 缓存 | 读取内置 PCM / 持久缓存、WAV 打包与写入、缓存未命中 |
| 播放 | 首次缓冲提交、首次混音器输出、逐段实际输出、最后缓冲播放完成、逐段 drain、播放结束 |
| 语音输入 | 权限等待、音频会话、麦克风引擎启动、识别连接就绪、逐块上传、首识别文字、用户松手和最终识别完成 |

初始问候使用内置资源、本地语音缓存重播时没有服务端调用，界面明确说明此情况；网络中断时已收齐的语音仍保存在原有持久缓存，不因埋点重新请求生成。

“首次输出”来自 AVAudioEngine 混音器的真实幅值回调，含音频线程→主线程回调延迟；不是耳边的物理声学测量。静音、隐藏页面或无音频输出时不填一个虚假的 0 ms。正常音频长度、扬声器播放等待和生成延迟分别展示。

## 日志存储与开销

`Application Support/VoiceDiagnostics-v1/traces.json` 留存最近最多 200 次，文件最多 16 MiB，单次最多 1024 个环节，达到限制会显示遗漏计数。重启后记录仍在，未完成记录标为 interrupted。目录不进入 iCloud 备份，文件使用 Apple 的首次解锁后文件保护。

文件读取、JSON 解码、写入均在串行 utility 队列；主线程只维护有界元数据。写入合并，避免逐块音频写盘。恢复旧记录时合并已经开始的新请求，不覆盖运行中记录。日志不含对话正文、音频、密码、请求头或访问令牌。查看时按当前账户过滤。

服务端事件增加 `voice.trace` / `trace_id` / `server_at_ms`；客户端保存服务端完整的已支持结构，忽略未知扩展字段，保留未来兼容。用追踪 ID 到管理平台搜索即可对照，不相减 Mac、手机与云主机的墙钟时间。

## 验证与边界

模拟器通过独立 NativeUI 项目编译所有 Swift 界面，真实 AVAudioEngine 回归检查包括输出幅值、PCM 转换、缓存写入、真实 drain、重播、隐藏页面和取消。测试音频来自本地正弦 PCM，不使用用户对话，不调用付费 AI。

角色资源本身未修改。模拟器 Unity 导出与当前角色目录不一致，构建检查正确阻止普通模拟器构建；本轮使用独立 NativeUI 模拟器验证这次纯 Swift / 音频改动，手机构建仍使用通过完整目录校验的 device 导出。该验证不等同于新增角色的真机画质/帧率测试。

新增 `--voice-timeline-review` 仅供 Debug 模拟器查看上一次音频回归的真实日志；启动/前台恢复均保持隔离，不启动 Unity 或付费 AI。

界面设计和语音链路根据 [Apple URLSessionTaskTransactionMetrics](https://developer.apple.com/documentation/foundation/urlsessiontasktransactionmetrics) 的实际网络观测；服务端使用 [HTTPcore trace 扩展](https://github.com/encode/httpcore/blob/master/docs/extensions.md)。并行时间轴遵循 [OpenTelemetry 的 traces/spans 概念](https://opentelemetry.io/docs/concepts/signals/traces/)，当前未增加外部遥测平台或后台常驻采集器。

## 2026-10-02 完成结果

- NativeUI 模拟器与完整签名 iPhone Release 构建均通过；最终版本再次运行真实 AVAudioEngine 回归，输出 PASS。重启测试 App 后可以读取之前的详细时间轴并打开详情，已检查页面截图。
- 新版成功安装到已配对的 iPhone 17，`devicectl` 返回 `App installed`，应用标识 `com.gukaifeng.xiaoban.dev`。本轮没有远程启动手机上的真实 AI 对话来制造计费样本，也没有把安装成功描述为手机端慢请求的性能结论。
- 云端发布 `20261002T113118Z-21b210181c7a`，API / AI / 管理平台 / HTTPS 入口均 active，两端健康检查为 200。升级前备份 PostgreSQL 与 AI SQLite，原有账户和对话保留。
- 云端只重播一条已有的完整 PCM 缓存，禁止付费调用，得到 21 个实际环节；生产端首音频交付为 2.253 ms、总生产时间 3.048 ms。该数字仅证明云端缓存读取与记录链路可用，不包含手机网络或播放，也不是新 TTS 的生成速度。
- 管理平台真实 HTTPS 页面完成桌面 1512×1050 与手机 390×844 检查、完整 JSON 导出，无浏览器错误或横向溢出。服务端 Python 252 passed / 4 skipped，Go vet/race/build、真实 PG/Redis 集成、TypeScript/Vite/Vitest 均通过。

第一次使用更新后的 App 后，新的生成、问候、互动预缓存、重播和语音输入会逐次积累记录；旧版本未埋点的历史延迟无法补回。取同一慢请求的客户端与服务端追踪 ID，可以区分模型等待、缓存未就绪、网络传输及本机播放准备，后续再据实优化。
