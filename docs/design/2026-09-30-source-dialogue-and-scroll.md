# v0.59 · 新消息跟随与对话生成源头调整

版本 **0.59.0 / 85**。本轮处理加载中消息不滚到底、重复回复频繁中断、所有场景必须由真实 AI 生成三个问题。保留角色、原作资源、两套已批准音色和 timeline-v2 协议。

## 聊天实际布局跟随

此前 `latestContent` 不包含 `generating`，因此单独出现加载中的三个点不会触发滚动。`scrollTo` 只排到下一次主线程执行，消息展开、字体换行和键盘过渡可能还未完成；原 bottom ID 后又有额外的 18pt padding。

现在加载开始／结束、新消息、消息内容和分段展开共用跟随入口：清除历史搜索焦点，恢复最新窗口，滚向包含全部底部留白的锚点。实际内容高度或视口高度变化时继续校准，450ms 后在同一底部位置完成一次无额外动画的收尾。新事件取消旧滚动任务，离开取消任务，手动看历史也取消跟随；下一条新内容仍会按用户要求回到底部。

首次测试发现历史焦点刚建立时会收到旧的“已到底”测量值，重新开启跟随并抢回底部。增加 `resumeFollowing`：存在历史焦点时，布局测量不能擅自恢复自动跟随。新消息清除焦点后正常恢复。另一次测试的 `<40pt` 断言遗漏气泡 12pt 内边距，实际距离为 40pt，截图和几何值均已确认；测试改为完整的 40pt 加 2pt 浮点容差，而非放宽到任意可见位置。

## 生成源头

按 `find-skills` 检索了 Qwen 角色提示相关技能，没有安装不能直接解决本项目问题的通用优化工具。实现依据阿里云的[角色扮演多轮消息说明](https://help.aliyun.com/zh/model-studio/role-play)与[文本生成参数](https://help.aliyun.com/zh/model-studio/qwen-api-via-openai-chat-completions)。iOS 保持现有 iOS 17 兼容方案，没有为了使用新的 SwiftUI API 提高最低系统要求。本轮无 Unity 资产操作或重新导出。

主要变化：

- **默认对话模型改为 `qwen-plus-character`**。此前的 Flash 快照在真实重复提问中仍会忽略约束，复述相同偏好，甚至复制新增内容摘要；多次格式修正还使用错误枚举。不是只靠提高温度就宣布解决。Plus 的同平台小样本对比后才决定替换。可在私有配置中显式指定模型；本机原配置未指定模型，因此部署后采用新默认。TTS／ASR 和已有声音绑定不变。
- 人设及运行规则放 system，真实历史拆成独立 user／assistant 消息，最后一条是本轮新输入。删除重复铺陈的 24 条旧台词反例库，不再把被拒草稿伪装成一条已经发生的 assistant 回复。记录完整原始上下文的测试检查页仍保留。
- 压缩、整理提示词，角色以自己的身份交流。所有表演分组仍可选，同一 intent 的资产变体在请求中合并，最终仍由资源导演选择真实资源。没有删减作者分组来降低难度。
- 新生成要求先写 `response_focus`：本轮新增内容的一句摘要，再写台词和表演。每账号／角色保留最近 12 个已发布摘要；未发布草稿不进入记录。摘要不会作为消息或语音发送，清空聊天同步删除。检测到相同用户问题时，明确要求补充此前没讲过的具体内容。
- 首次生成 `temperature=0.95`、`presence_penalty=0.8`，不固定随机种子。格式修复使用 0.2／0，优先纠正结构；修复后的台词仍经过质量检查。有限的声音语义别名映射到支持枚举，例如 playful delivery → teasing；未知值不任意透传。
- 初次见面事件与回来见面的任务文本分开。旧任务即使 has_met=false 也说“重新进入”，曾让模型误说“好久不见”；现在首次见面明确无共同历史。

普通聊天、故事、启动、初见、切换、待机主动发言、晃动吐槽继续统一调用 Provider。没有回复库、固定台词或失败时拼装的本地回答。空聊天占位从类似角色对白的两句话改为界面说明“开启对话／写下此刻想说的话”。短待机调度可以决定安静，幂等重放和历史语音播放使用已有结果；这些不生成新的角色发言。

## 内部修订与语义边界

原文／近似措辞仍检查本账号历史。BGE 是相关内容召回模型，0.58 的晃动阈值并不是“同义”的可靠证明；此前低分命中也反复强制拦截，导致主题相同的新回应经常失败。

低分语义命中最多引导一次内部修订，不再据此无限拒绝；原文近似或 >=0.86 的高相似仍可继续修订。保留最多 **3 个候选（原始一次＋最多两次修订）**，候选不显示、不存为聊天、不合成语音。发布事务若发现另一请求抢先发布相同内容，会共享剩余预算重新生成。每次生成本身仍最多修正一次 JSON 格式，故最坏 6 次 Plan 调用，而非无限扣费。

用户不再收到 REPLY_REPEATED／GREETING_REPEATED，也不被要求换个说法。真正网络、超时或供应商异常仍按可用性错误处理，费用是否已产生不明时不盲目重试。若所有候选都无效，主动事件保持安静，直接问题仅使用普通回复未完成提示，不泄漏内部拦截原因，也不用预设台词冒充 AI。此边界不应被描述为“任何错误都不会发生”。

去重检索、摘要及模型都有范围和能力边界，不能承诺无限轮次永久零相似。语义相关不等于重复，事实也不能为了求新而改错。后续上线应扩展多主题、长会话和不同角色的评测，本轮小样本不能代替它。

## 验证结果

| 范围 | 实际结果 |
| --- | --- |
| Python | **116 项通过**，包括 3 项真实本地 BGE 推理。覆盖所有触发类型、两次不可见修订、最终发布碰撞、幂等重放不重付费、语义相关误判、强相似继续修订、摘要隔离和不重试不明费用的网络错误 |
| iPhone 17 模拟器 | **3 条 XCTest 通过**：加载点＋持续增长长消息回到底并允许再看历史；用户／AI／补充内容从历史位置返回；真实音频播放期间分阶段展开。断言几何位置、最新状态和可点击性，截图已查看 |
| Release | 0.59.0 / 85 真机构建和严格签名通过；iPhone 17 无线安装成功，设备回读「星夜」版本 0.59.0／85，自动启动成功。实际手指操作仍以用户体验为准 |
| 本机服务 | 23 个部署模块／元数据与源码逐一一致，health 200；运行实例只读请求预览确认 `qwen-plus-character`、0.95／0.8 和完整 27 区检查报告，不产生额外付费调用 |
| 最终真实 AI | Plus 最终 **8 轮全部得到有效新回复**，覆盖同问题连续 3 次、appLaunch、连续晃动 2 次、idle 主动发言及另一角色 firstMeeting。5 轮直接通过，3 轮内部修订一次；整体 12 次 Plan（包括格式修复）＋1 次 TTS。未出现重复拦截对外错误；有效表演每轮 6–9 项 |

早期 Flash 试验确实出现格式失败和同义复述，未计入最终模型成功结果。过程中尝试独立 macOS Swift 数值测试二进制，编译完成但执行被宿主终止（exit 137），不能记为数值测试通过；相关实际滚动行为已由上述 iOS XCTest 覆盖。本轮没有新增真机持续 FPS、真机触摸或 iPad 验收。

隔离开发账本本轮合计 **42 次 Plan、2 次 TTS（本地计量 113 字符）**，包含失败、结构修正及模型对比，实际费用以供应商账单为准。没有 Narrator、付费向量、ASR 或音色设计调用。测试使用合成会话，测试和请求原始内容留在忽略目录；用户正常打开手机触发的问候不混入此隔离账号统计。

## 部署与复跑

本机网关按现有 `scripts/install_character_ai_agent.py` 部署，无新 Python 依赖，无额外模型下载。默认模型读取 `Settings.character_model`；旧机器若在私有 settings.json 显式固定了 Flash，需将 `character_model` 更新为 `qwen-plus-character` 后再部署，保留密钥和已批准音色。Plus 与 Flash 的价格不同，选择质量升级时应结合真实用量账单，不将新模型描述为同价。

```bash
STARRY_SEMANTIC_MODEL_CACHE="$HOME/Library/Application Support/StarryNight/CharacterAI/data/models/reply-novelty" \
  .local/character-ai-venv/bin/python -m pytest services/character_ai/tests -q
zsh scripts/test_companion.sh EFA3B59D-3939-4659-B60B-123516393F43 \
  'ConversationPresentationTests/testLoadingAndGrowingReplyStayAtMeasuredBottom(),ConversationPresentationTests/testNewMessagesAndLateNarrationReturnFromHistory(),ReplyFlowTests/testAsidesArriveBetweenLinesWhileVoiceIsPlaying()' conversation-source/recheck
```

上述 XCTest 和 Python 套件不调用付费 API。真实验证原文、费用计数、截图、XCTest、部署／安装结果分别在本机 `.local/checks/conversation-source/` 和 `.local/logs/conversation-source/`。最终模型证据以 `plus.json`、`plus-scenes.json` 和 `plus-scenes-usage.json` 为准，其他名称含 final 的文件也是开发过程中被继续修正的候选，不能混作最终结果。

本轮替代 [0.58 记录](2026-09-30-conversation-flow.md)中的重复拦截策略；分段协议、普通轻晃触发和模型资源保持既有实现。
