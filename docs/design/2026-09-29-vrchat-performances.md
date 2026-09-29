# VRChat 原作动作与形态接入方案

日期：2026-09-29。目标是在星夜中展示两份已导入角色真正拥有的动作、表情、手势、耳尾和穿搭，而不是只提供上一版统一的九个会话动作。原作的菜单、静态姿态、连续动画、平台控制器和原始形变分别处理，避免把 99 / 64 个 `.anim` 文件误写成等量完整身体动画。

## 当前实际产物

两角色包均升级 `packageVersion:1.1.0`，新增可选能力 `core.performance@1`。截至本文件核对时，实际 manifest 中共有 **130 个可显示选项**：

| 角色 | 表情 | 姿态／动作 | 手势 | 耳朵 | 尾巴 | 穿搭 | 合计 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 琪宝 | 42 | 10 | 8 | 8 | 7 | 7 | 82 |
| 豆日向 | 25 | 4 | 8 | 4 | 4 | 3 | 48 |

原源目录为 82 / 49；豆日向 SunVisor 使用额外 Prefab/FBX，未在主 FBX 中找到对应可见 Renderer，因此转换器过滤了这一个无效选项并记录原因。不能把来源目录数当成实际按钮数。

实际 GLB 中琪宝共有 47 个 clip、177 个保留形变通道，豆日向 29 个 clip、84 个保留形变通道；这包含原有九个会话动作和原作烘焙动作。动态 morph 采用 manifest 时序数据，不能由 GLB clip 数推算表演选项数。琪宝有 104 条动态 morph track，豆日向 2 条。

界面从会话内的角色资料进入表现子页，沿用同一个面板导航，不增加多层弹窗。六组按实际包内容生成；配件显示开关，预设／动作显示选择，提供恢复原作默认。面板使用实际回执与选中状态，角色相机不因打开面板而变化。具体 UI 与运行验证结果由本轮主验收记录确认。

## 来源审计和保留范围

审计工具 `scripts/audit_vrchat_performances.py` 以 SHA-256 锁定数据为输入，解析原菜单、参数、控制器状态和转移条件，以及每个动画的可见绑定；不执行源脚本。结果为 [source-capabilities.json](../verification/vrchat-performance/source-capabilities.json) 与 [可读清单](../verification/vrchat-performance/source-capabilities.md)。路径经过 `vrchat_source_paths` 解析，根目录迁移不改写历史证据。

源清单中琪宝 99 个动画文件，68 个时长为零；豆日向 64 个，55 个时长为零。全部被计入保留、开关配对或明确省略记录。手势与坐／蹲／俯卧等静态姿态可保持，但不能称为原作者制作的进出过渡动画。

两份 Motion 菜单中的 **Wave、Clap、Point、Cheer、Dance、Backflip、SadKick、Die** 都是 `VRCEmote` 外部 SDK 项，本轮没有把 SDK 默认动作复制进 App，也不把已有独立来源的会话 Hello 冒充原包 Wave。PetMode 的开心／不满表情可展示；原 VRChat 网络 Contacts、自触碰设置和外部控制器语义没有等价迁移。

基础上装与短裤保持穿着，不开放其 OFF 选项；可切换其他已验证配件。原模型的全部形变清单保存在报告中，包含口型、技术分隔符及局部造型，不因此提供数百个未经设计的捏脸滑条。FishToy、NameTag 等额外资源也不会仅因出现在压缩包中就被宣称支持。

## 转换流程

1. `prepare_vrchat_stage.py` 把哈希核验的 FBX、贴图、动画与必要 Unity 数据放入隔离工程，只复制仓库维护的 Inspector / Sampler C#。来源 SDK、脚本与 shader 不进入 stage。
2. `VrcSourceInspector.Export` 读取主 Prefab 默认状态。`VrcPerformanceSampler.Export` 在原作者有效 Humanoid Avatar 上采样；不加载源 AnimatorController、不执行来源 MonoBehaviour、SDK 或动画事件。
3. Sampler 以 **60 Hz** 提取骨骼局部旋转／位移，同时记录原 rest、world rest 和 parent world rest。Morph 用 `AnimationUtility.GetEditorCurve().Evaluate()` 采样，保留原切线产生的时间变化，避免仅拿首帧或末帧。
4. `vrchat_performance_catalog.py` 生成中文目录草稿，保留 sourceClip、开关配对、原权重和审计键帧。YAML 需同时识别带 serializedVersion 的列表、直接 `- curve:` 的旧格式，以及双引号 Unicode 转义的日文属性。
5. `vrchat_performance_export.py` 把采样数据转换为本模型 GLB 曲线及 manifest `performance`。出版数据移除 source 字段，所有节点、Renderer、形变与 clip 重新绑定，缺失可见绑定的选项过滤并记录。
6. `prepare_vrchat_characters.py` 生成、seal 两角色包；既有会话动作、独立语音／背景／音乐、人物身份和作者资料继续保留。

## 关键决策与已遇问题

### 坐标和姿势不是直接拷贝

本项目已安装的 glTFast 使用 **镜像 X** 的手性转换。Unity 四元数进入 glTF 时对应 `[x,-y,-z,w]`，位移对应 `[-x,y,z]`；将镜像 Z 套进本链路会错误旋转骨骼。另需利用父级 world rest 与目标 bind basis 消除 FBX armature 的 -90° wrapper，不能对导出结果再随意整体旋转补偿。

每个关节转换都检查 rest 回代吻合度；位置差结合相同基转换，并遵守这两模型已经核验的 2 倍米制转换。运行时根 scale 仍为 1。该数值不是对任何未来模型通用的假设。

### 静态姿态、呼吸和连续睡眠分开

零秒原片段烘焙为两帧相同的 hold clip，由表现层权重平滑进入。它保留原姿势，但不生成来源并不存在的行走／落座过渡。

呼吸动画原曲线还包含固定的完整身体姿势。导出器仅保留随时间变化的通道，设为 additive，并以首帧为参考，避免呼吸把主 Idle 拉回 T-pose 或另一套姿态。

琪宝入睡动作完成后，通过 `next` 直接交给睡眠循环，不经过一帧站立 Idle；醒来动作完成后再平滑释放。低层会话 clip 补充耳、尾、指骨和配件骨的静态基准曲线，保证停止上层后能恢复。

### 完整表情时序和原默认形态

动态哭泣、眼睛效果等若只复制最后权重，会丢掉整段演出。运行时读取 `morphTracks`，使用有界二分定位并线性插值 60 Hz 采样结果。权重统一 0–1，源超范围值被限制并记录；此处是明确近似，不能称任意超驱动形变无损。

琪宝默认隐藏的猫耳和眼镜现在保留网格，通过 `defaults` 关闭；选择耳朵动作时才显式显示猫耳。需要动态切换的原默认非零服装形变也保留，不能既把它烘焙进中立几何、又在运行时重复施加；未保留的静态默认形变才烘焙。

表现层每帧先撤销上一帧覆盖，再让语音／对话表情等下层产生基线，最后施加当前选择。reset／解绑恢复真正的非零基准，而不是统一清零。`vrc.v.*` 口型不由手动表现选项抢占，继续归属说话驱动。

### 显隐和物理的边界

服装可见性作用于 Renderer，不关闭骨架节点。当前显隐在平滑权重阈值切换，不能把这一机制描述为所有衣物都透明渐隐。耳尾动画与原有受限动态需要实际逐项观看，不等价于 VRChat PhysBones、抓取或网络交互；原 Shader 近似边界也沿用上一轮记录。

### Editor 截图缓存与实际坐姿复核

初次批量截图中，已选择的笑脸仍看似中性，sit 仍看似站立。原曲线、Unity Avatar 采样、最终 GLB 的 FK 都存在真实脸部／屈髋变化。后续 VisualProbe 对比实时权重、CPU BakeMesh 顶点、普通渲染和临时网格渲染，确认是 **Editor 同一帧连续采样／渲染时 GPU 蒙皮缓存未刷新**。先 BakeMesh 后的普通渲染和临时网格渲染均正确显示笑脸及坐姿。

修复仅作用于截图工具：`CharacterPerformanceReview.Capture()` 先计算当前真实动画层与 morph 的 CPU 网格差值，再由 `CharacterPerformanceVisualProbe.RenderFrozenPose()` 临时 BakeMesh 渲染，完成即还原并销毁临时对象。没有修改产品动画来迁就错误截图，也没有伪造姿态。批量报告保留每个 Renderer 的变化顶点数、最大／平均位移作为独立几何证据。

sit 是真实原作静态坐姿，不是仅上身动画；仍没有世界椅子锚点／完整落座过渡。根因与来源数据见 [坐姿复核](../verification/vrchat-performance/sitting-source-review.md)，诊断截图和权重证据位于 `docs/verification/vrchat-performance/visual-probe/`。这一 Editor 工具修复不代表手机 GPU 路径或全部 App UI 已验收。

### 旧包、停用角色和集合版本

Unity `JsonUtility` 可能将缺失的可选 class 字段反序列化成空对象，因此 `performance != null` 不足以判定旧角色支持表现。新增 `CharacterPerformanceContract.IsSupported()` 以非空 options 为依据；旧角色仍走原会话路径，不展示空表现页。

库中的未选中角色根节点通常 inactive。`RestBounds()` 若用 `activeInHierarchy` 过滤，会把整个模型判为空并阻断校验／预加载；现在只沿 renderer 到角色根之间检查作者隐藏的子节点 activeSelf，并保留 renderer.enabled 判断。根节点的暂时停用不会抹掉作者默认几何。

两个模型包升级为 1.1.0 后，同步更新了 `CharacterCollections.json` 内对包版本的引用，并通过集合检查确认模型定义与集合一致；这不是修改角色身份、账号或聊天数据的理由。

## 协议与复用

发布规范在 [core.performance@1](../character-standard/06-performance-standard.md)。表现通过现有 `character.signal` 内的 `performance.select` / `performance.reset` 选择；每角色独立 profile、选项与状态，界面不硬编码两位角色的动作名称。

复用 skill：[vrchat-character-import](../../.agents/skills/vrchat-character-import/SKILL.md)。具体采样、转换命令见其 [表现迁移参考](../../.agents/skills/vrchat-character-import/references/performances.md)。新模型先做骨骼／路径／默认状态检查，不能机械复用这两个模型的 recipe。

## 验证状态

本文件已核对源目录与实际 manifest 数量、能力声明、生成 clip／morph 数及脚本实现。YAML 格式回归测试 2 项已通过；Editor 源数据／生成资源／CPU 网格及诊断渲染已用于定位并确认上述缓存问题。最终批量重渲染与导出正在执行，不能以诊断通过代替最终验收。

**最终分层结果见 [验收记录](../verification/vrchat-performance/README.md)。** 不以文件生成、动画采样频率或 clip 数量代替实际运行证据；60 Hz 采样更不代表持续 60 / 120 FPS。旧授权边界仍然适用，本轮未改变模型作者许可。
