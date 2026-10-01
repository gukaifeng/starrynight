# Character API 1.1 · 小伴语义表现接口

> 1.1 新增：持续站/坐/蹲/躺、姿势参数、专用动作和聊天配置。请同时阅读[姿势制作与接口标准](05-posture-standard.md)，它定义持久姿势和一次性动作的区别。旧包继续兼容。

本文件定义当前实现的接口；模型作者主要编写 manifest 中的映射，应用/AI 提供方使用这里的语义信号。现有原生桥继续用 JSON，经 `MSUnityBridge` → Unity `ViewerController.ReceiveCommand` 进入角色调度器。

## 1. 外层展示会话与内层角色信号

```json
{
  "schemaVersion":1,
  "kind":"command",
  "name":"character.signal",
  "requestId":"view-8-12",
  "presentationId":8,
  "payload":{
    "signal":{
      "apiMajor":1,
      "apiMinor":0,
      "actorId":"sample-robot",
      "sequence":12,
      "eventId":"a-unique-uuid",
      "turnId":"turn-unique-uuid",
      "eventName":"dialogue.reply",
      "emotion":"care",
      "target":"",
      "intensity":0.7,
      "audioTime":0,
      "level":0,
      "visemes":[]
    }
  }
}
```

外层 `presentationId` 由宿主维护，区别同一角色多次打开。内层 `sequence` 每次选择角色后重新从 1 递增。`actorId` 必须等于当前角色 ID。UUID 推荐用于 eventId / turnId；同一轮的音频与语义必须携带相同 turnId。

普通无轮次的展示事件允许 turnId 为空，如 session.enter、用户动作按钮。对话开始必须先发非空 turnId 的 turn.begin；取消后不能继续给该轮发事件。音频每段播放器的 `audioTime` 从 0 起，通过 `state.thinking/idle` 释放前一段时间游标，再进入 state.speaking。

`apiMajor` 不同拒绝。更高 apiMinor 的信号可包含当前读者不认识的可选字段/事件，基础信号照常解析；需要改变必需语义时必须使用新 major 或协商必要能力，不能只递增 minor 强迫旧引擎猜测。

## 2. 已实现事件

| eventName | 来源和用途 | 主要字段 |
|---|---|---|
| session.enter | 进入聊天，按角色规则致意 | turnId 可空 |
| session.leave | 离开页面，清除瞬态表现 | turnId 可空 |
| turn.begin | 创建/替换对话生成轮次 | turnId 必需 |
| turn.cancel | 用户打断/新输入，取消当前轮 | 当前 turnId |
| state.listening | 正在录音/聆听 | 当前 turnId |
| state.thinking | 对话生成或下一段语音准备 | 当前 turnId |
| state.speaking | 音频实际开始播放 | 当前 turnId |
| state.idle | 暂无语音/思考 | 当前 turnId，或空展示级状态 |
| dialogue.greeting | 招呼回复 | emotion / intensity |
| dialogue.gratitude | 感谢回复 | emotion / intensity |
| dialogue.dance / dialogue.jump | 用户明确表达动作意图 | emotion / intensity |
| dialogue.reply | 通用回复及情绪表现 | emotion=neutral/joy/care 等 |
| action.request | 用户按钮或受控显式动作 | target=actions.id 或 semantic |
| expression.request | 受控表情请求 | target=expressions.id，缺失回 neutral |
| effect.request | 受控预设特效请求 | target=effects.id |
| posture.set | 设置可持续保持的姿势，见 05-posture-standard.md | posture.id / parameters |
| speech.frame | 音频时间同步的表现输入 | audioTime、level、visemes |
| performance.select / performance.reset | 选择原作表现／恢复默认 | target=选项／分组，见 06-performance-standard.md |
| performance.replace | 原子替换某组 AI 表演或恢复用户快照 | target=分组，selections=完整选中 ID 数组；0.83.2 增量扩展 |
| interaction.head.tap | 引擎精确头部点击产生 | 由角色 rule 决定动作，不写死摇头 clip |
| interaction.* | 声明的其他骨骼热点 | 自定义事件名，匹配同名 rule |

事件名本身可扩展。当前对话规则库只生成少量上述语义；新增情景应让对话提供方产生语义，并给角色配置对应 behavior，不能在 Swift 中增加“如果是角色 A 就播放某骨骼动画”的分支。

## 3. 表现通道与资源映射

- `body`：一个动作槽，连续时间采样，抢占时 CrossFade，完成回 Idle。身体 cue 的 `intensity` 当前不改变动作振幅或速度，制作方需准备不同动作变体。
- `expression`：命名 morph 组合，可同时作用多个 Renderer，按 intensity 混合并平滑恢复。
- `gaze`：camera/release，与动作自己的 follow/soft/release 策略相乘，保留生理范围和背向释放。
- `effect`：受控星光/爱心预设，与身体/表情独立。intensity 影响粒子尺寸；不会无限增加数量。
- `speech`：直接受 audioTime 驱动，不进入低频行为队列。level 0–1 用于开口；viseme 为至多 16 个 `{id,weight}`，没有真实 viseme 数据时使用幅度回退。
- `parameters`：持续保存的外观值，独立于瞬态表情。通过 `character.parameters` 设置，不被对话取消清空。

设置参数的命令：

```json
{"schemaVersion":1,"kind":"command","name":"character.parameters","presentationId":8,"requestId":"parameter-1","payload":{"parameters":[{"id":"body-tone","value":2}]}}
```

参数 ID 未识别时忽略；数值必须有限，并限制在角色声明的范围。未提供的参数恢复声明默认值，因此宿主每次预览应发送完整的该角色保存参数集合。宿主持久化原始稳定 ID；升级前必须通过兼容审查。

## 4. 调度顺序与取消语义

动画采样 → 外观参数（40）→ 语音小动作/口型（50）→ 表情（55）→ 视线（80）→ 旧初音头发适配器（100）。表达式每帧先还原上一帧动画基线，避免无关键帧的 morph 被累积写入。

规则可多通道同时执行，可延迟 0–15 秒。全局延迟队列最多 64 项。通道优先级更高者才能抢占更高优先级租约；同优先级允许新事件替换。规则 cooldown 与概率在排程前处理。

turn.begin、turn.cancel、session.leave 都清理瞬态队列和租约；turn.begin 同时建立新轮次。取消会平滑回待机、释放表情和视线、关闭嘴部，并清除特效。持久化外观、用户取景、历史和人格不会跟随取消消失。

## 5. 回执、能力与观测

普通信号产生外层 `characterReceipt` 事件，包含 `receipt` 和 `characterPlatform`。`receipt.status` 为 accepted / degraded / ignored / rejected。支持的能力通过 `capabilities` 数组返回，manifest 的 required 必须是其子集。

| code | 含义 |
|---|---|
| OK | 已接纳并处理 |
| SIGNAL_MISSING / SIGNAL_INVALID / SIGNAL_RANGE | 缺字段、身份格式错误或非有限/越界数值 |
| API_MAJOR_UNSUPPORTED | 不支持该协议主版本 |
| ACTOR_MISMATCH | 信号角色不是当前绑定角色 |
| DUPLICATE_EVENT | 已处理过 eventId |
| STALE_SEQUENCE | 当前展示内旧序号 |
| STALE_TURN | 已取消或已被替换的轮次 |
| TURN_ID_REQUIRED | turn.begin 缺少有效轮次 ID |
| STALE_AUDIO | 同一音频段播放时钟倒退 |
| VISEME_INVALID | 口型数据超过预算或权重非法 |
| ACTION_UNAVAILABLE | 当前角色没有请求动作 |
| CUE_UNAVAILABLE_OR_BUSY | 缺少目标/回退，或通道正被更高优先级占用 |
| COOLDOWN | 同规则尚在冷却 |
| QUEUE_FULL | 延迟表现项达到 64 条 |
| NO_RULE | 合法但没有匹配规则的可选语义 |

音频帧不产生完整桥接回执，避免每 50 ms 烘焙头部网格并传大段 JSON。调度器的直接返回值可以在引擎测试中观测音频接受/拒绝。

`characterPlatform` 提供包版本、最近事件/状态/错误、当前表情和效果、activeAction / lastAction、已接受/拒绝数量、身体/表情/效果计数，供调试和验收。正式用户界面不展示协议字段。`executed` 计数包括已接纳的延迟项；不能据此宣称对应帧已经渲染。

## 6. 原作表现能力

`core.performance@1` 已实现独立的作者预设目录和混合层，支持 `performance.select`、`performance.reset`。接口、单位、状态、回执和恢复语义见 [原作表现标准](06-performance-standard.md)。它不取代已有会话 `action.request`，也不等价于完整 VRChat FX / SDK。

## 7. 未来能力登记原则

建议命名空间：`core.animation.layers@1`、`core.ik.contacts@1`、`core.props@1`、`core.physics.spring@1`、`core.physics.cloth@1`、`core.material.hair@1`、`core.actors.multi@1`、`core.timeline@1`、`core.viseme.aligned@1`、`format.vrm@1`。这些是**架构规划名称，不在当前支持列表中**。

每个新增能力必须有：JSON Schema、单位/坐标/边界、执行器、资源预算、取消方式、旧引擎回退、最小样本、正反例测试和升级策略。只有实现并通过验收后才能放入运行时 capabilities。


### 星夜 v0.33 头部交互适配

`interaction.head.tap` 仍查当前角色的行为规则。现有7个包的 `body / No` 触头提示在本宿主中执行为独立、限幅的头颈叠加反应，不再争用整个身体动作租约；独立 `action.request / No` 保持作者完整动作。其他 target 仍遵守普通规则调度。接口与旧包继续兼容，此处是明确记录的宿主适配，不假定任意第三方同名动作都适合这一行为；将来引入非摇头触碰动作时应增加独立语义／能力协商，而非扩展同名特例。

`headTapped` 只在反应实际被接纳时发送；`headReactionCompleted` 在约1.8秒后报告结束。状态 `gaze.headReactionCount`、`headReactionPeak`、`headReactionYaw` 提供当前角色的次数和实际限幅后的水平偏转证据。手机原生工程要求 `nativeGestureRevision >= 2`，旧的 Unity 导出会被构建前检查拒绝。
