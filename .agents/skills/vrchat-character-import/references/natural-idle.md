# 自然待机与环境风（0.47）

## 宿主四肢待机与衣物避让（0.100）

手臂有骨骼不等于有原作 PhysBone。按 Human 映射校准 AvatarNaturalMotion 的躯干、肩肘腕、手指和下肢，脚底跟随作者本帧落点；不要用通用欧拉轴、强制内收上臂或整个人形刚体代替自然姿态。自然待机独立于开发者情绪实验，并让位于作者姿势/源片段。原始资产保持不变。

新增肢体活动后有宽袖穿模，先检查动作是否吃掉原作袖子间距，以及碰撞只覆盖骨链端点还是整段。AvatarClothingClearance 一次读取实际蒙皮/全部服装包络，建立 Human 骨骼上的少量胶囊缓存，在自然待机/情绪/惯性之后限制新增手臂挤压；衣物及无环境风配饰链使用整段接触，不只按 wind=cloth 过滤。衣袖忽略自己的附着手臂，其他身体部位仍参与；骨根附近接触也需检查。原有接缝和作者重叠作为基线，不能用巨大推力撑开服装。

恢复顺序：避让 10 → 惯性 15 → 情绪 20 → 自然待机 22 → 连续性 40；执行顺序：自然待机 85 → 情绪 90 → 惯性 95 → 避让 100 → 次级物理 110。长度与作者角度锥仍有效，不可解时退向本帧作者姿态并阻尼接触法向速度。不得每帧 BakeMesh；不能向身体/脸/衣服合并网格盲目添加 Unity Cloth，它需要布料锚点与顶点运动约束。此实现是骨链/包络近似避让，不能冒称全网格自碰撞或完整 VRChat PhysBone。

用 AvatarNaturalMotionReview.Final 检查当前名册的 60/120 Hz 数值稳定性、作者优先、无累积、腿部接地和四组情绪动作的接触/退开；Run/Stress 可额外输出蒙皮冻结渲染。再运行实际 iPhone 模拟器 NaturalBodyMotionTests，下载角色要验证真实安装的 package.json release 版本与运行态 naturalMotion.clothing，不以目录更新代替加载证明。数值时间步不等于设备 FPS。问题、设计、回退边界见 [0.100 实施记录](../../../../docs/natural-body-and-visible-asides-2026-10-03.md)。

碰撞引用和胶囊缓存在运行时建立、非序列化，不改持久化类型树；仅修改这层时既有 Bundle 可复用。改变 Human 校准、源控制器/材质或 Prefab 字段则仍需重建两个平台 Bundle 并发布不可变版本。本次新增完整手指/下肢校准已随下载包版本 5 发布，不覆盖旧包。

## FX 肌肉投影、配饰遮罩与会话连续性（0.97）

先比较导入 Idle 与实际 Animator 站姿，不能把固定张开的手臂归因于模型坏了。`AvatarIdleArmReview` 按当前名册记录肩到手的朝下方向、局部偏转及覆盖层；同时确认映射的 UpperArm/LowerArm/Hand 是否真的在原 PhysBone 链中。头发有物理不代表手臂也配置了物理。

- VRChat 第一 FX 层无自定义遮罩时，默认禁止 Humanoid muscles。Humanoid 采样成 Generic 后应投影掉这些人形骨骼通道，保留原非人形 Transform、形变和对象曲线。若第一 FX 层显式提供自定义遮罩，按实际允许的人形骨路径保留，不能一概禁止；不要改动原作绝对片段库。当前 Lime 有仅手指的人形遮罩，但没有 Humanoid FX 源片段；其余 15 个角色使用默认 FX 遮罩。
- Humanoid body mask 作用于真实映射的人形骨本身，不应套到所有后代。耳朵、尾巴、袖子等有自己的 Transform mask；作者显式 Transform 遮罩仍按路径继承。过度屏蔽后代会使配饰动画丢失。
- 会话参数驱动的选择、替换、恢复，用 `AvatarPoseContinuity` 在 Animator 之上、嘴型/眨眼/注视/物理之下进行 0.32 秒五次平滑。检测原生状态行为直接改参数，以及 write-default 通道在退出尾帧才突变的情况。目标被打断时限制每骨 360 度/秒与每形变 6 个标准单位/秒，继续收敛，不能在时间结束时硬贴终态。原作手动片段预览有独立通路，不抹掉它的节奏。
- 上帧宿主叠加必须在下帧 Animator 求值前正确恢复。手臂惯性恢复顺序 15、已有表现恢复 20/25/30/35、连续性恢复 40；不要把上帧惯性当成下一帧动画基线。无过渡时只采样基线，不反复重写所有 Transform/形变。
- `AvatarArmFollow` 是明确的 App 适配，不是原作 PhysBone：保留原手臂姿态，只在整体转动时加入有限旋转惯性，上臂/前臂/手腕上限 3/4/1.8 度，无平移、无累积。需要撤销这一适配时仅禁用该组件；遮罩与连续性修复应独立保留。不要声称整套身体物理或 VRChat IK 已等价实现。

重建控制器必须保存所有 Package/Resources/Downloadable 引用。运行 `AvatarConversationPoseReview` 与 `AvatarContinuityReview.Run`，对全部自动原生控件选择和恢复进行 60/120 Hz 数值检查，并检查惯性消退、无关节平移和恢复原始局部姿态。源片段内部带多关键帧的闪烁/漫画特效单独统计，不把它误当静态表情切换失败而删掉；切换首帧仍检查全部形变。之后验证实际 Unity 模拟器，两平台 Bundle 发布新不可变版本。仅检查 Editor 或只改 App 都不算完成下载角色更新。

发布下载角色后，检查实际安装的 `content/package.json` 的角色、平台及 release 版本。商店目录更新和模型能出现，不足以证明新 Bundle 已加载；缓存目录可能先允许旧包打开。隔离账户的资源测试可通过 App 删除旧包后重新下载，再核对版本；不要删除原始角色文件或用户聊天和记忆。

参见 [VRChat Playable Layers](https://creators.vrchat.com/avatars/playable-layers/) 与 [0.97 验收](../../../../docs/verification/continuity-timing-v097/README.md)。

## 原作加法层转换与空状态（0.96）

如果 Humanoid 片段先采样为绝对 Generic Transform 曲线，再放进 Animator 的 Additive 层，不能假定 Unity 会自动扣除原骨架参考姿态。Hikarun 原 Breathing 层在呼吸与空状态间反复切换时，旧转换会重复叠加 bind rotation，使髋部转约 88 度、躯干折叠。修复位于 `PortableAvatarControllerBuilder`，适用于所有角色的原作加法图；Override 图与原作手动片段不变。

- 单独生成加法用途的 clip/blend tree：旋转为 `inverse(firstRotation) * sampleRotation`，位置为 `samplePosition - firstPosition`，缩放为 `sampleScale / firstScale`。不修改原始绝对片段，也不把整套动画图统一改为加法。
- 对图中加法状态持有的骨路径取并集。每个加法片段（包括空状态、部分曲线状态和缺失 SDK 中性代理）明确写入 identity quaternion、零位移、单位缩放，再叠加自己的相对曲线；只修呼吸片段而不修空状态仍会横倒。曲线首帧参考语义须按作者图核对，后续遇到作者另设加法参考的图不能盲用首帧。
- 重建控制器后重新保存引用它的 Package / Resources / Downloadable prefab，实际验证必须 `Rebind` 且 `layerCount > 0`。删除 controller 后仍使用旧 GUID 的 prefab 会产生“没有坏姿态”的假通过。
- 用 `AvatarConversationPoseReview.Run` 检查当前发布名册：每个角色待机 10 秒，Hikarun 30 秒覆盖多次呼吸/空状态切换，并执行全部 `ai.automatic` 控件。设置 `STARRY_POSE_ASSERT=1`，输出放私有 `STARRY_POSE_REPORT`；它是 Editor 骨骼数值检查，不是设备 FPS 或所有原作特殊姿势的验收。
- 继续做真实 Unity 模拟器的表现页面与选择/恢复验证。部分角色的首组只有 slider，不能因没有按钮就判定页面不可用。OSS 下载角色必须重建两个平台的 Bundle，发布新不可变 release；仅更新 App 不会修改已下载 Bundle。

结果与原理见 [0.96 姿态与资源管理验收](../../../../docs/verification/conversation-pose-resources-v096/README.md)。

## 既有待机适配

用户2026-09-30明确授权新增自动眨眼、呼吸待机和环境风，覆盖早期“只保留原作、不加眨眼/微风”的限制。保留原始ZIP/Prefab/源动画，生成包可以增加明确标注的App适配，不应把旧限制作为要求用户再次批准的理由。

入口为 `scripts/vrchat_autonomy.py`，由 `prepare_vrchat_characters.py` 重导调用。琪宝/豆日向包2.2.0，使用可选 [core.autonomy@1](../../../../docs/character-standard/07-natural-idle-standard.md)，保持API1.1、角色ID和用户数据。导入后必须真正Setup，再导出两平台；不靠修改stamp冒充更新。

用户追加要求「幅度明显、单次眨眼慢一些」后，0.47优先于下方0.46背景：Chest/Head相对首帧的旋转分别4倍/3倍，髋与腿不变；保留Source_Idle与全部VRC源片段，生成Idle和App_VisibleBreath。眨眼闭/停/开为0.16/0.035/0.26秒，间隔数组不变。头发/衣物风预算7.5/3.2度、响应0.9/0.85；导入器与运行时共用8/4度最大值，逐链原限制和碰撞仍有效。不要从已放大的片段再次放大。详见[可见待机方案](../../../../docs/design/2026-09-30-visible-idle-and-defaults.md)。

- 豆日向主FX的Auto_Blink包含原闭眼/开眼0.08/0.06秒与间隔lottery，`Auto_Blink` morph必须在转换白名单保留。检查实际FX绑定、状态/参数驱动、形变，`enableEyeLook:0`不能证明没有自动眨眼。初始延时和五次平滑属于App适配，非完整SDK图仿真。
- 琪宝使用原eye_close与App调度，未确认原自动时序，不冒称原作节奏。
- 默认Idle由原stand+breath及上述明确的上半身幅度适配生成；原静态姿势会覆盖Idle，使用同幅度App_VisibleBreath加法层补入，跟随姿势权重。静态呼吸选项本身复用Idle，动态睡眠已有自己的运动，都不叠加两遍。
- 自动眨眼必须让位于原作表情及睡眠；先恢复上帧闭眼偏移，再恢复表现层基线。跨角色Bind清理旧眼睑状态。嘴型通道不被眨眼改写。
- `secondary-motion.json`显式标记hair/cloth/none及response。环境风与上半身呼吸分别控制并分别验证，原骨链、碰撞和逐链限制继续约束；不能摇整个人根节点来伪装头发物理。

验证 `NaturalIdleReview.BuildAndReview` 和 `NaturalIdleTests`，当前输出在 `docs/verification/idle-refinement/`。旧 `VrchatOriginalMotionReview` 的无微风断言属于历史要求；应把旧Idle与Source_Idle比对，不能再要求新的适配Idle幅度与源片段一致。状态isPlaying不等于画面在动：检查最终骨骼、真实形变网格与无触摸的衣发位移。60/120 Hz数值步进不是FPS实测。

表现面板每组提供默认入口，发 `performance.reset` 且 target 为该组；空target才是全部默认。默认选中态必须考虑 `defaultOn` 配件，不能把没有选择等同于原作默认。检查表情复位保留姿势/穿搭、渐出后眨眼恢复、当前分类切换回顶部。

批处理Editor连续修改blendShape后直接Camera.Render可能复用旧GPU蒙皮。审查截图须先BakeMesh呈现当前采样结果，并在实际模拟器核对；不要把这种截图缓存误诊为生产端眨眼失效。故障与最终证据记录于[自然待机验收](../../../../docs/verification/natural-idle/README.md)。
