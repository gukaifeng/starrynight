# 两位 VRChat 角色恢复原作动作 · 0.39.1 / 60

用户要求：琪宝、豆日向只保留 VRChat 来源模型本来具有的动作，恢复原始表现，不继续添加 App 自制动作；原始资源不得删除。

## 来源结论与恢复结果

| 项目 | 实际来源 | 本版处理 |
|---|---|---|
| 点击摇头 | `CharacterGaze.TouchReaction` 的 1.8 秒程序头颈反应 | 取消这两角色的通用触碰规则；原作没有该摇头 |
| 原先待机 | Overte/Hanami 第三方 Idle，另加放松混合、程序呼吸与眨眼时序 | 从两角色的生成/声明/运行路径退出 |
| 站姿与呼吸 | 原包 stand 和 additive breath；原控制器有真实引用 | 恢复为默认 Idle，原 2.5 秒周期/幅度/时间点不变 |
| 招呼、点头、否定、倾听、思考等 | 先前补入的九个通用基础动画 | 不再用于这两角色，不影响其他角色 |
| 朝屏幕转头、眼睛跟随 | App 程序层；两源 Prefab 都 `enableEyeLook:0` | 关闭 |
| 聆听/思考/说话点头 | App 程序层 | 关闭；原 `lipSync:3` 和 viseme 口型仍保留 |
| 自动情绪、爱心/闪光 | App 后加规则/权重 | 清空后加映射，保留原表情资源 |
| 待机微风 | App `ambientHairAngle` | 两角色设为 0 |
| 原表情、耳尾、姿势、配件、Pet 面部表现 | 来源真实 clips/morphs/Renderer | 琪宝 82 项、豆日向 48 项继续保留 |

原包的 Pet_Happy/Pet_Unhappy 是面部表现，不是这次取消的摇头。它们在「角色表现」中保留；本版没有另行添加手机触碰映射或声称已移植 VRChat Contacts。

详细源 Prefab/动画/控制器路径、行号、SHA-256 见 [来源审计](source-audit.md) / [结构化清单](source-audit.json)。原 ZIP 重新计算哈希与旧记录一致；源 FBX、`.anim`、采样、第三方原素材与历史记录未删改。撤回的是两个当前生成包里错误补入的动作与自动映射。

## 转换和兼容决策

Idle 由原站姿和原呼吸首帧相对变化组合：旋转为 `stand × inverse(breath₀) × breath(t)`，平移为 `stand + breath(t) − breath₀`。没有另加 sin、眨眼时间表、速度调整、幅度调整或平滑滤波。面板呼吸选择复用同一个非叠加 Idle，避免默认呼吸与显式选择重复叠加。原呼吸独立 clip 仍保留以便核对。

琪宝生成包现有 39 clips（38 原片段 + Idle）及 177 morph；豆日向 21 clips（20 原片段 + Idle）及 84 morph。两包全部 130 项原作选项继续有效。

移除此前公开的通用动作语义属于包能力变化，因此两模型包升 **2.0.0**；XCP schema 仍 1、API 仍 1.1。角色 ID、集合 ID、聊天/订阅/记忆数据不变。两集合只同步包引用与动作目录。SDK 放行合法的仅 Idle、无 gaze、无自动行为的原作包；缺省语音头部动作和微风配置保留旧包行为。

发/耳/尾的骨链有原包 PhysBones 依据，继续保留现有迁移惯性与约束适配；它仍是本项目独立近似求解器，并非 VRChat 原物理引擎。未引入源 SDK 或脚本，也不把当前画面称为原 VRChat 客户端逐像素/逐物理帧复刻。

## 验证

- 两包 seal、全 12 包 validate 通过；集合 12 角色、24 首音乐绑定检查通过。
- SDK **47 项测试通过**，含新增原作最小包、禁用 gaze 的必要 cue 拒收、语音头部动作布尔检查，见 [测试输出](sdk-tests.txt)。
- Unity Setup / Validate 通过；实际导入 clips 的 **151 个时点逐骨核对**通过，见 [runtime-review.json](runtime-review.json)。旋转误差量测为 0°、位置最大误差约 `5.96e-8` 米（浮点差）；作者真实呼吸保留，未冻结为静态或恢复成 T-pose。
- 同一审查覆盖所有 App 语音状态、触碰不加动作、语义缺失不凭空回退、跨角色重绑、旧 Luma 仍有原通用互动；原 130 选项回归通过，见 [performance-review.json](performance-review.json)。数值断言数量不等于用户界面场景数量。
- iPhone 17 / iOS 26.4 模拟器两条实际 UI 流程首轮通过：两新角色语音/真实触碰无额外动作/页面往返固定镜头 80.000 秒，旧角色摸头/拖捏锁定 28.756 秒。共 2 个不同方法、108.756 秒，0 失败。结果见 [app-review.json](app-review.json)，[琪宝恢复站姿](simulator/anime-kipfel-source-rest-pose.png)、[豆日向恢复站姿](simulator/anime-mamehinata-source-rest-pose.png)。
- 模拟器安装包已核对为 0.39.1 / 60，并恢复无测试参数普通启动；原有 Metal/HDR 兼容处理继续生效，检查的 RenderPass 错误和运行异常为 0。本次未安装到手机，不做 iPad 或真机持续帧率结论。

## 重用入口

- [VRChat 导入 Skill](../../../.agents/skills/vrchat-character-import/SKILL.md)
- [原作表现与恢复参考](../../../.agents/skills/vrchat-character-import/references/performances.md)
- [角色制作标准](../../character-standard/02-model-production.md)
- [最新 StarryNight SDK](../../character-standard/deliverables/StarryNight-Character-SDK-1.1.zip)

重导后不要用仅改 catalog stamp 的方式代替真实 Unity Setup/导出。UI 回归方法为 `VrchatCharacterTests/testSourceOnlyCharactersSpeakWithoutAddedMotionAndKeepCamera()`；旧名字中带 `GreetSpeakReact` 的方法已按新的产品要求替换。
