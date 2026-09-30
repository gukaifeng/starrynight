# v0.57 · 丰富的对话表演与晃动回应

版本：0.57.0 / 83。角色仍为琪宝、豆日向，原始 ZIP、作者模型、动画曲线及已批准音色不修改。使用项目 VRChat 导入／原作表现技能检查能力，以 Unity CLI 导出与运行验证；字体呈现参考现有界面设计规范。

## 问题与实施决策

旧 AI 导演每 beat 只输出一个表情和一个动作；原生又限定四个分组，角色平台还限制六个固定组。单独提高提示词里的“频率”无法打通这些限制。本轮同时贯通资源目录、AI 编排、原生时间轴和 Unity 分组层。

- 从实际安装目录生成纯语义目录：琪宝 82 项、豆日向 48 项，包含全部六组。完整原作数据仍在忽略目录，公开语义没有骨骼路径、采样、贴图或几何。客户端提供实际可用 ID，与服务端交集后才执行。
- 新 `performance.cues` 支持多组并行及 offset；旧字段和历史消息继续兼容。普通回复目标 4–8 项，2.2–4.2 秒附近自然变换第二组，具体数量受情绪、可用资源、冷却和台词长度影响。导演补足不增加模型请求。
- 坐躺、睡眠、穿搭和整套耳朵显隐由明确意图使用；固定嘴型从说话候选过滤。不同组冲突、同组间隔、强度和冷却均在代码检查。临时 toggle 结束恢复原来的开关状态。不会为了丰富而在普通聊天里随机躺下或换装。
- `core.performance@2` 可声明最多 32 个作者分组，要求 required 能力协商；自动阶段最多轮选 8 组，每 beat 最多 24 cue。Unity 由组声明顺序建立独立层，iOS 无固定四组白名单。当前包继续 v1，不改作者资产。后续角色仍须登记人设／音色；分组扩展不等于自动生成新模型能力。
- 静态外貌不再进入旁白依据，新生成旁白仅保留实际表演或交谈节奏。旧外貌旁白在服务端缓存读取和 iOS 显示时隐藏，原始历史和音频保留。心声、动作旁白加括号，采用专门的斜体字形与颜色；CJK 缺少斜体字库时用字体矩阵保证真实倾斜。TTS 输入仍只包含台词和支持的声音事件。

## 晃动互动

只统计普通单指临时旋转的已接受位移，位置编辑器不参与。7 秒窗口、运动量至少 5、反向至少 3 次、持续至少 0.7 秒；松手触发。拖到限制之外不会继续积累，微抖和一次轻拖不触发，双指取消不触发，聊天垂直滚动仍归聊天。

Unity 与服务端各有 35 秒冷却。原生等待现有生成／语音结束，最多等 15 秒，编辑、录音、切角色等优先。事件调用真正的 AI，随机撒娇或轻微生气，保留 AI 首句，不伪造用户聊天；先鼓脸／不满、后缓和，其他手势和耳尾按实际资源组合。依照用户的朗读音量播放；静音不被擅自解除。不会计作用户一轮或写成用户长期记忆。

## 真实验证及纠错

| 范围 | 结果 |
|---|---|
| Python AI 服务 | 78 项通过：多组两阶段、真实目录绑定、姿势／开关、未来 14 组轮选、冲突／预算、缓存、晃动冷却及账户隔离、旧外貌隐藏、旁白和台词边界 |
| 制作 SDK | 56 项通过，含 v2 required 协商、扩展分组、AI 元数据边界；当前两份真实 XCP 校验通过 |
| Unity | 正常 simulator/device 导出成功；`ExpressiveConversationReview.Run` 26 项数值断言通过，含实际原作片段重映射到临时扩展组、独立层并行、复位，以及抖动／越界／冷却门槛 |
| iPhone 17 模拟器 | 3 条 XCTest 共 73.897 秒通过：八项原生时间轴与 Unity 回执、复位、真实单指晃动与冷却、聊天垂直／斜向滚动和输入控件、心声／旁白与历史自动跟随；截图已人工查看 |
| 真实 AI/TTS | 两条成功回复均含 8 cue、四组；豆日向晃动回应返回 4.32 秒真实 PCM。此项检查实际网络语音数据，不冒充人工听感验收 |
| 真机 | Release 编译和严格签名检查通过，已安装并从 iPhone 读回星夜 0.57.0 / 83；自动启动被 iOS `Locked` 拒绝，未进行本轮真机手势或 FPS 测量 |

真实付费验证暴露 `speech.emotion=bright_smile`：模型把表情语义填入语音枚举，原有一次结构重试仍失败。新增明确同义转换，未知值仍拒收，并用该实际结构写回归测试；晃动场景的多余话题 beat 只保留首条 AI 话语，不生成本地替代台词。修复后新请求成功。该轮两个隔离测试身份共发生 **4 次 Plan、3 次 Narration、1 次 TTS**，包括结构纠错，未设计新音色。普通自动化测试禁止付费调用。

源目录中耳朵收起／展开、蓬尾等不能无条件随机填充：调整为上下文策略或匹配情绪。系统仍使用模型原有姿势和片段，没有借本轮编排添加程序身体晃动。AI 自由台词的语义质量与资源实际执行分别检查，不把生成了 ID 当作完整动画或质量保证。

SDK 旧测试曾硬断言只有四组、禁止所有 toggle、允许静态头发旁白。这些断言按新产品要求更新，继续验证真实绑定、冲突和非随机姿势；没有删除失败检查。构建生成的无关场景对象编号、材质序列化和背景缩略图波动已恢复，保留相关源码／版本／标准改动。

## 复跑与证据位置

```bash
.local/character-ai-venv/bin/python -m pytest services/character_ai/tests -q
.local/character-sdk-venv/bin/python -m unittest discover -s character-sdk/tools -p 'test_*.py'
.local/character-sdk-venv/bin/python scripts/validate_characters.py
unity run "$PWD/unity/CharacterRuntime" --timeout 300 -- -executeMethod ExpressiveConversationReview.Run -logFile "$PWD/.local/logs/expressive-ai/unity-review.log"
zsh scripts/test_companion.sh EFA3B59D-3939-4659-B60B-123516393F43 'ExpressiveConversationTests/testRichTimelineAndNativeShakeRouting(),ConversationPresentationTests/testNewMessagesAndLateNarrationReturnFromHistory(),ConversationGestureTests/testVerticalAndDiagonalMessagesScrollAndControlsStillWork()' expressive-ai/native-new
```

模拟器测试之前需正常导出并准备原模型资源；Unity CLI 使用约定技能，不能绕过构建检查。新机器资源恢复见 [Git 与资源恢复](../git-workflow.md)。`.local/checks/expressive-ai/` 保存 xcresult、截图、Unity 数值结果、真实服务回复／PCM、费用摘要和设备回读；原始证据、密钥和模型资源不公开提交。语义目录随服务部署，密钥和音色绑定仍在本机私有运行目录。

制作方见 [原作表现标准](../character-standard/06-performance-standard.md)与 [AI 表演适配标准 v2](../character-standard/08-ai-performance-standard.md)。新增能力必须有实际执行器；数值采样、模拟器、真机性能不可混为同一结论。
