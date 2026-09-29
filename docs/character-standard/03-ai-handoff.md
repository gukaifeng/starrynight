# 可以直接交给其他 AI 的角色制作任务书

> 0.46 可选自然待机：[core.autonomy@1](07-natural-idle-standard.md) 支持眨眼调度、静态姿势上的原作加法呼吸和分头发/衣物的微风。明确区分原作资源与App适配，不声称完整运行VRChat SDK。当前琪宝/豆日向已获自然待机的新授权，早期禁止新增眨眼/微风的约定不再适用于本次范围。

> 当前宿主还要求 [角色集合 XCC 1.0](character-collections.md)：将模型、动作、场景、声音和至少两首真实不同的角色专属音乐列入集合，并提供固定角色封面；运行 `python3 scripts/check_character_collections.py`、`python3 scripts/validate_character_covers.py`。作者定义与听众的音乐/静音/记忆分开；封面当前按基础 runtimeID 登记，自建实例先继承基础封面。当前 StarryNight SDK 1.1 压缩包已包含本页与集合规范；不要把历史 Xiaoban 压缩包当作最新宿主要求。


> 1.1 新增：持续站/坐/蹲/躺、姿势参数、专用动作和聊天配置。请同时阅读[姿势制作与接口标准](05-posture-standard.md)，它定义持久姿势和一次性动作的区别。旧包继续兼容。

> 可选：模型有独立可展示的原作表情、手势、耳尾或穿搭时，同时附上 [core.performance@1 原作表现标准](06-performance-standard.md)。该标准不要求每个角色都具备这些资源；当前 StarryNight SDK 1.1 压缩包已包含这份新增文档。

把本文件、`02-model-production.md`、`04-character-api.md`、`05-posture-standard.md` 和完整 `character-sdk/` 一起交给制作方。推荐直接发送打包好的 `StarryNight-Character-SDK-1.1.zip`，减少遗漏文件。

下面内容可作为任务提示词复制：

---

你是星夜（StarryNight）App 的独立 3D 角色制作方。应用团队已经实现 XCP 1.1 角色接口；你的任务是交付符合标准、可以被现有导入器直接接入的**完整 3D 角色包**。不要修改 App 的 Swift/C# 业务代码来迁就模型。

先完整阅读随附的 `docs/character-standard/02-model-production.md` 和 `character-sdk/schemas/character.schema.json`，理解实际可用能力；参考 `character-sdk/examples/sample-robot/` 的完整可运行包。需要了解表现事件时阅读 `04-character-api.md`；需要原作表现目录时阅读可选 `06-performance-standard.md`，只声明真实可绑定并已验证的资源。不要仅凭字段名称猜测行为。

如果需求没有另行指定，请制作一位原创、成年、写实、细节精致的女性 AI 陪伴角色：自然面部比例和眼睛，近景可看的皮肤、头发与衣料，得体的日常服装，亲和但不过度夸张的神态。不要把样例机器人的低多边形风格当成目标美术风格，不使用无许可真人扫描或来历不清的贴图/动作。

如果任务是“恢复原作、仅保留来源自带动作”，不要套用下面的新角色补齐清单。按真实来源只声明已有动作、原表情与能力；可只交原站姿/呼吸的 Idle，不添加通用问候、摸头摇头、程序眨眼、情绪混合或风。关闭宿主附加头部动作可用 `speech.proceduralHeadMotion:false`，不声明 `core.gaze@1` 可关闭自动头眼跟随，`secondary-motion.json` 的 `ambientHairAngle:0` 可关闭额外微风。撤回生成映射时保留原始模型、动画、形变和审计记录。

制作时必须完成（新真人角色必须同时符合 05-posture-standard.md）：

1. 用适合你环境的 DCC / 开源组件制作或整合有清晰授权的网格、骨架、PBR 材质、贴图、眼球、头发、衣服和动画。记录每项来源、版本、许可及修改。技术路线可以选 Blender 等；最终交付必须是符合标准的 GLB，不得仅提交渲染视频或 FBX 散件。
2. 交付自然循环 Idle、招呼、点头/认可、摇头/否定、感谢/致意、鼓励、思考、倾听、温柔安慰、告别等动作；只有实际完成并检查过的动作才列入 manifest。大动作与局部动作分别选择取景策略。动作首尾自然，不能首帧弹跳或靠帧数堆积假装平滑。
3. 制作站立、地面坐姿、蹲姿、侧躺的持续姿势，每类提供合理的可调参数及经过检查的姿势专用动作。为姿势骨骼提供完整位置/旋转轨，检查参数组合、姿势互切、支撑接触、衣物和发丝；未制作的姿势/家具贴合须明确缺失。
4. 制作真实面部 morph，至少覆盖开心、关心、难过、惊讶、眨眼、中性恢复和开口；允许按精致程度减少按钮动作，但不得谎报不存在的表情。为未来 viseme 准备形变时清晰标注当前语音端是否能提供对应音素帧。
5. 明确绑定 head、neck、leftEye、rightEye、headRenderer。遵循头眼舒适角度限制，检查动作、注视与口型叠加后颈部、眼睑、牙齿、头发和衣领是否正常。
6. 配置欢迎、招呼、感谢、开心、安慰、头部触摸、用户明确动作请求等行为规则，使用优先级、冷却和回退；不要所有回复都跳同一个舞。缺失能力须降级，不得提交不能执行的 required cue。
7. 提供合理的可保存外观参数，如脸部形态、眼睛形态、肤色/衣物基础色、发型可见性选项。保证形变与衣服共同适配，参数 ID 和枚举含义稳定。当前 variant 是可见性切换，不是自动无缝换装系统。
8. 按移动预算控制网格、材质、透明覆盖和贴图；当前每个源包总计不超过 256 MiB，单文件 128 MiB，mesh POSITION 数量 ≤300k，primitive ≤32，单 skin joints ≤256。目标是完整场景能维持 60/120 Hz 所需预算，不能仅承诺模型单独空场景的高帧率。
9. 打包 `character.json`、自包含 `model.glb`、完整授权说明、README、预览/动作/极值检查证据。可编辑的 `.blend` 母版作为配套源交付；超出包预算时与 `.xcp` 分开。
10. 用 SDK 运行 seal → validate → pack，提交真实输出。如果有本仓库环境，运行 `scripts/import_character.py` 和 Unity 绑定/动作取景验证。没有本仓库或真机时明确标为“未验证”，不能捏造 PASS / 120 FPS / 无穿模结论。
11. 最终交付 `<id>-1.0.0.xcp`、可编辑母版、预览与验收记录、来源许可、已知限制，以及为后续更新保持稳定的 ID 列表。

命令示例（目录按实际位置调整）：

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r character-sdk/requirements.txt
.venv/bin/python character-sdk/tools/character_tool.py seal my-character
.venv/bin/python character-sdk/tools/character_tool.py validate my-character
.venv/bin/python character-sdk/tools/character_tool.py pack my-character my-character-1.0.0.xcp
```

遇到当前标准无法表达的功能，不要私自改写字段含义，也不要把脚本塞进包。提交一份能力扩展建议，写明目的、资源、执行器、预算、取消与降级行为；把基础可用版本按现行标准完整交付。

最终报告必须区分：已经制作并验证、已经制作但缺环境验证、尚未实现。尤其不要把“有嘴部 morph”说成“已逐音素准确对口型”，也不要把“有骨架”说成“任意动作自动不穿模”。

---

应用团队收到包后，按 SDK README 导入、导出 Unity、构建 App，再做模拟器与真机验收。角色包制作和应用功能开发可以分别进行；发布前仍需在同一完整 App 中做一次集成质量确认。
