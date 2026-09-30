# v0.58 · 分段心声、回复去重与轻晃互动

> 后续 v0.59 已替代本页的生成模型、反例提示和重复拦截策略，见[生成源头与滚动修复](2026-09-30-source-dialogue-and-scroll.md)。本页保留当时的实现与失败证据，不能把 REPLY_REPEATED 流程恢复到新版。

版本 0.58.0 / 84。保留两位角色、原作资源和已批准音色。使用项目 Unity CLI 技能进行运行、导出和数值检查，沿用现有暗色聊天界面及括号斜体样式；本轮没有添加模型动画、重新设计音色或更换角色资产。

## 根因与改动

旧 progressive-v1 在首份文字之后另外请求 Narrator，旁白常在语音结束后才返回；SwiftUI 又固定先画所有旁白，再画心声和整段台词，因此出现“说完以后开头才补括号”。

新客户端协商 `timeline-v2`，规划同时生成有阶段的 `asides`，资源导演完成后即编译为有序 `parts`。台词切片、角色第一人称心声和真实激活资源的可见效果一起进入首份回复。动作说明取开始／第二阶段各一项，不再为这份回复追加 Narrator 调用。台词切片拼回原文，TTS 仍只读取原台词和声音事件；括号内容不进入语音。

- `stage=before/middle/after` 表达阶段，可选 `after_text` 表达精确位置。真实模型曾生成根本不在台词里的锚点，现回退到阶段位置；跟随前句标点，避免逗号单独成行。心声不再限定开头。
- 时间轴方案中的心声数组设为必填（纯台词可 hidden），并继续过滤非第一人称、过长心声和回复计划。测试中可选字段仅靠提示词会被整个漏掉，因此将要求落实为结构约束。
- iOS 以已实际播放的 PCM 推进段落并淡入。流式音频未收齐时使用阅读时长估计，收齐后使用实际时长；进度只前进，不收回已显示内容。静音按阅读节奏展开，取消、离开或历史重播显示完整记录。
- `at` 是台词进度分数，没有厂商逐字时间戳，因此这是阶段同步，不宣称字级精确同步。界面变化继续自动跟随底部；新字段可选，旧记录仍按原字段读取。

## 重复治理

此前只有见面问候检查最近少量句子，普通聊天、故事和晃动没有统一检查。现在所有新回复在显示、存档和 TTS 之前统一检查：

1. 本账号全部保留历史的标准化原文索引，忽略标点、全半角等表面差异。
2. SQLite FTS5 双字候选召回，加标准库 SequenceMatcher、Dice 和长句复用检查；老消息也迁入索引，同账号换角色不能靠换 ID 绕过原文检查。
3. [BAAI 中文 BGE small v1.5](https://huggingface.co/BAAI/bge-small-zh-v1.5) 经 [FastEmbed](https://qdrant.github.io/fastembed/examples/Supported_Models/) / ONNX Runtime 在本机 CPU 推理，检查最近 128 条账号回复的语义。中文模型 512 维，固定 Qdrant 转换版本和文件 SHA-256；约 94.8 MB ONNX，不放进 iPhone 包，不调用付费向量 API。向量随消息缓存，删除聊天同步删除索引及向量。
4. 确认重复后最多让真实 AI 重写一次；候选仍重复则返回 REPLY_REPEATED，不保存、不朗读，不无限重试。正常幂等请求和手动重播历史语音不触发新生成。

普通语义阈值 0.74；两次晃动反应之间使用 0.58，跨其他场景保持普通阈值，避免仅因为主题相同就把不同场景都视为晃动复述。阈值是本轮小样本校准，不代表全面语义评测。原文查重覆盖全部留存历史，近似召回及语义检查有范围，**不能承诺任意未来表达永远零相似**；用户清空历史后不会偷偷保留其全文来去重。

首次生成带最近 24 条同角色的避免重复提示。重写时保留用户信息、人设和能力，但不再重复铺出一整批旧 AI 台词，以免角色模型又照抄反例。以显式的最后一轮纠正指令要求新内容，首次采样温度从 0.45 调整到 0.8。检测到的其他角色文字不会作为本角色的上下文注入。付费配额政策不变，只记录实际调用。

索引与新消息发布在同一 SQLite 写事务中最终复核；原始历史迁移一次，清理操作覆盖新索引。CPU 推理在线程中执行，模型只从已准备的固定快照加载，请求期间不下载权重。未来服务器扩容可替换向量检索层；当前本机 worker 不是已经部署的远程生产集群。

## 晃动门槛与截断问题

普通临时旋转改为 5 秒窗口、运动量 1.5、两次反向、至少 0.35 秒，原门槛为 7 秒／5／三次／0.7 秒。约正负 30 点、1 秒的小幅来回已通过数值检查；模拟器真实触摸以正负 35 点、1.08 秒通过。Unity 和服务端冷却均由 35 秒降到 20 秒。保留普通单向转动、微小抖动、越界拖动、双指取消、聊天滚动及编辑模式的排除逻辑。

测试暴露窗口以旧手势起点计时，可能在下一次轻晃末尾重置。现超过短暂手势间隔便开启新窗口，仍允许紧邻的连续手势累计。

另一处根因是 `brief_shake_plan` 以前在首句达到 15 字就截断，即使后半句有新内容或心声锚点也被剪掉。现保留首个反应 beat 的完整短回应，按自然句界约 70 字收束；多余后续 beat 在校验前裁掉。没有添加本地预写吐槽。

## 实际验证和失败处理

| 范围 | 结果与边界 |
| --- | --- |
| Python 服务 | **101 项通过**，包含本地真实 BGE 推理的 3 项检查；覆盖全场景重复、旧库迁移、发布事务、跨角色／账号范围、索引清理、错误锚点、隐藏心声、标点及台词／TTS 分离 |
| Unity | 两平台正常导出；26 项数值断言通过，包含更小手势、噪声、冷却、复位及真实原作分组执行，不等同真机手感或帧率 |
| iPhone 17 模拟器 | 4 条独立 XCTest 通过：旧记录和滚动、真实小幅触摸与角色回执、真实 AVAudioEngine 播放／缓存／取消、音频中段穿插心声和说明。最终音频与分段两条复跑均通过；截图人工查看 |
| 真实 AI | 相同问题、两角色、反复晃动均实际调用；新候选能通过，重复或近似候选也确实在发布前被拦。最终豆日向新回复包含台词中段的真实心声。检测拦截不是一次成功聊天，不能算作每次都有新回应 |
| 真机 | Release 构建、严格签名、无线安装成功，回读星夜 0.58.0 / 84；设备启动成功。未代替用户逐项测真机手势或持续 FPS |

真实调用发现语音情绪 `soft` 被填到 emotion：按已知含义映射到 neutral，未知值仍拒绝；晃动多余 beat 不再因它的无关非法枚举触发付费格式修复。重复样本曾连续重写仍很接近，系统如实拒绝，没有拿本地台词充数，也没有放宽检查只为得到一条“成功”。有界重写依旧可能失败，用户会看到未发布提示；角色模型本身的创造性仍有质量边界。

一次分段 UI 测试失败来自独立测试夹具没有激活音频会话（XuyuAudio 1），补上夹具的声音生命周期后通过；正式播放链路的真实音频回归也再次通过。没有忽略失败或仅改测试超时。无关 Unity 场景 ID、材质和背景缩略图生成变化已恢复。

本轮隔离测试账号实际账本合计 **22 次 Plan、1 次 TTS**，含格式修复、重复重写和失败请求；没有额外 Narrator、付费向量调用、ASR 或音色设计。本机 BGE、单元测试和合成 PCM 测试均不调用付费 API。普通手机启动的用户问候不计入这个隔离测试账号统计。

## 新机器准备与复跑

本轮 AI venv 为 Python 3.14，依赖使用 `services/character_ai/requirements.lock`。先按既有流程配置私有 Key 并安装 worker，使配置指向 Application Support 的私有数据目录，再准备模型并重部署：

```bash
.local/character-ai-venv/bin/python scripts/prepare_reply_novelty.py
python3 scripts/install_character_ai_agent.py
STARRY_SEMANTIC_MODEL_CACHE="$HOME/Library/Application Support/StarryNight/CharacterAI/data/models/reply-novelty" \
  .local/character-ai-venv/bin/python -m pytest services/character_ai/tests -q
zsh scripts/test_companion.sh EFA3B59D-3939-4659-B60B-123516393F43 \
  'ReplyFlowTests/testAsidesArriveBetweenLinesWhileVoiceIsPlaying(),RealAIConversationTests/testAudioThreadPlaybackAndCachedVocalBeat()' conversation-flow/Final-native
```

模型准备脚本按 `novelty-model.lock.json` 的固定 Hugging Face 快照下载并校验，成功后才设置 `semantic_novelty=true`。没准备权重的 CI 会跳过 3 项本地模型集成检查，不能将此称为语义检查通过。普通测试禁止付费调用。运行目录代码、配置与本机数据不会提交到公开仓库。

本机 `.local/checks/conversation-flow/` 和 `.local/logs/conversation-flow/` 保存原始 SSE、费用汇总、语义校准、截图／XCTest、Unity 检查和设备结果。新协议见 [AI 表演适配标准](../character-standard/08-ai-performance-standard.md)。算法参考 [Python SequenceMatcher](https://docs.python.org/3.14/library/difflib.html) 与 [SQLite FTS5](https://www.sqlite.org/fts5.html)，权重／库来源与许可证见 [第三方说明](../../THIRD_PARTY_NOTICES.md)。
