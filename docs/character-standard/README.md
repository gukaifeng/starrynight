# 星夜角色平台交付文档

> 2026-09-29 补充：[固定作者定义、听众偏好、封面与专属音乐](character-collections.md)。会话中角色定义由作者快照决定，使用者独立保存朗读静音、角色专属音乐选择和私聊/记忆。固定封面按基础 `runtimeID` 关联；当前自建实例继承基础封面。制作方交付模型时须同时阅读这项补充，当前 StarryNight SDK 压缩包已包含这些补充；旧 Xiaoban 压缩包保留作历史记录。

> 星夜 v0.31 新增：[角色订阅与作者体系](../design/2026-09-29-authors-and-subscriptions.md)。角色设定的公开作者由宿主账号绑定的 `authorID` 标识；XCP 的 `license.authors` 等原始素材署名继续独立保留，不能替换成发布者昵称。模型制作方无需在包内写入用户登录ID、手机号或邮箱，也无需因此改变 `runtimeID` 或重新导出模型。接口边界见[作者与订阅契约](../api/authors-subscriptions-v1.md)。

> 0.19 新增：[角色集合 XCC 1.0](character-collections.md)。交付模型时必须同时声明允许的动作、背景、声音和音乐；自建角色保存集合快照，账号与角色实例独立保存选择。

> 1.1 新增：持续站/坐/蹲/躺、姿势参数、专用动作和聊天配置。请同时阅读[姿势制作与接口标准](05-posture-standard.md)，它定义持久姿势和一次性动作的区别。旧包继续兼容。

本次将应用、对话与 3D 角色制作解耦，落实了 XCP 1.1 源包、Character API 1.1、同源角色目录、GLB 导入和语义表现调度。

按用途阅读：

1. [整体架构、功能覆盖与升级策略](01-architecture.md)：应用团队的完整设计，包含当前已实现与未来预留边界。
2. [标准 3D 模型制作规范](02-model-production.md)：独立角色制作方必须遵循的交付标准。
3. [可直接给其他 AI 的任务书](03-ai-handoff.md)：和 SDK 一起发送，即可独立开展角色制作。
4. [Character API 接口规范](04-character-api.md)：信号、通道、轮次、取消、回执和能力登记规则。
5. [SDK 使用方法](../../character-sdk/README.md)：预检、打包、兼容审查和导入命令。
6. [持续姿势、聊天配置与制作要求](05-posture-standard.md)：站/坐/蹲/躺、参数样本、专用动作及接触边界。
7. [可选原作表现标准 core.performance@1](06-performance-standard.md)：表情、姿态、手势、耳尾、穿搭及原作动态曲线；旧包不声明则维持既有会话能力。
8. [角色平台基础验证记录](../verification/character-platform/README.md)：构建、运行与实际发现/修复的问题。
9. [自然待机与衣发微风](07-natural-idle-standard.md)：可选 core.autonomy@1、原作眨眼/呼吸、表情优先级及环境风数据。

本次新增姿势的验收见[0.11 验证记录](../verification/posture/README.md)。

可以直接转交的文件：

- [完整制作 SDK 压缩包](deliverables/StarryNight-Character-SDK-1.1.zip)
- [可导入的示例角色包](deliverables/sample-robot-1.1.0.xcp)
- [SDK 文件完整性记录](deliverables/sdk-integrity.json)

机器规范与样本：

- [角色清单 JSON Schema](../../character-sdk/schemas/character.schema.json)
- [信号 JSON Schema](../../character-sdk/schemas/signal.schema.json)
- [独立可运行示例](../../character-sdk/examples/sample-robot/character.json)
- [校验/打包工具](../../character-sdk/tools/character_tool.py)
- [项目导入工具](../../scripts/import_character.py)

当前新角色需要导入后重新构建 App；手机内即时下载/导入尚未实现。新能力允许增量扩展和降级，但不承诺任意未来重大变化都没有迁移成本。

背景也已独立为 [XEP 1.0 场景平台](../environment-standard/README.md)，可单独制作室内/室外环境，与角色包组合使用。


### 星夜 v0.18：一个模型可以生成多个角色实例

模型制作仍使用当前 XCP 1.1，不需要为每位用户导出一套相同的模型。宿主的 `ModelDescriptor.id` 可为账号创建的实例 ID，`runtimeID` 始终是包内角色 ID。Unity 协议收到的 `modelId` / `actorId` 仍为原包角色 ID；作者不要把用户昵称当作运行时查找键。宿主分别保存实例的作者定义与听众偏好/记忆/历史；当前会话不能用旧的个人外观或取景值覆盖作者定义。公开作品是角色设定快照，现阶段仅在本机身份 A/B 间模拟发现，不是模型文件上传或网络市场。详见[星夜方案](../design/2026-09-28-starry-shell.md)及[当前集合边界](character-collections.md)。

- [AI 表演适配标准 v1](08-ai-performance-standard.md)：真实对话、原作能力匹配、专属音色、可观察旁白与取消恢复。
