# 附加情绪动作试验 v1

用户要求：挑选骨架完整的现有角色，为对话增加自然、平滑且匹配情绪的身体动作，提供独立开关，并允许整体撤销。本次授权只用于明确标记的宿主动作层；不能把新增动作描述为 VRChat 原作动作或动捕数据。

## 范围及检查入口

试验角色为青柠（Lime）、望（Nozomi）、小梅（Plum）。从已导入的 `avatar-geometry.json` 的 Humanoid 映射确认脊柱、胸、颈、头、左右肩、上下臂和手腕；不用同名骨骼猜轴向。其余已发布角色不启用该层。

角色会话 → 角色表现 → **情绪动作 · 试用**：包含独立的“附加情绪动作”开关和七个身体动作预览。开关默认开，本机持久化，影响三个试验角色，不写入角色的原作参数或 XCP 包。关闭会用 0.48 秒平缓撤除剩余偏移。原作表情、手势、穿搭、口型、眨眼、呼吸、环境风及已有展示层转动保持原有逻辑。

| 新增身体动作 | 搭配现有原作表情的语义 | 动作要点 |
|---|---|---|
| 轻轻点头 | 手动预览 | 有轻微预备的两次点头，后一次较轻 |
| 开心回应 | soft_smile / happy / proud / playful | 舒展肩臂、轻侧倾和点头 |
| 侧头思考 | curious / confused | 胸部先倾，头颈稍后侧倾 |
| 害羞低头 | shy | 低头、轻微转脸和收肩感 |
| 小小不满 | pout / angry | 幅度克制的左右扭头和肩臂回应 |
| 低落倾听 | sad / worried | 缓慢低头、轻微上身前倾 |
| 惊讶回应 | surprised / surprise | 稍后仰头、舒展手臂再落回 |

预览只演示新增身体动作。真实对话使用 AI 已选择的**原作表情**的 `ai.intent` 来匹配身体动作；不再发起 AI 请求，不增加对话等待或费用，不自行生成表情 morph。未知语义不猜测。新增动作不加入原作表现目录，也不改变服务端的原作能力声明。

## 动画与优先级

运行顺序：原作 Animator / Animation → 现有表情与视线 → 附加上身动作 → 头发/衣物物理。每帧先恢复上一帧附加值，再叠加当前采样，防止未被原作动画逐帧覆盖的骨骼累计扭曲。

十个上身关节使用中性站姿校准轴向；肩臂外展方向取实际骨骼相对胸部的位置，不按骨名假定坐标正负。肘部旋转轴由实际前臂到手腕的方向及角色正面计算，避免直接复制另一模型的局部 X 轴。所有阶段使用五次平滑曲线（阶段边界速度与加速度归零），胸、头、手臂错开起落，动作 3.6–4.4 秒。脚、髋、角色根变换、手指、眼球、脸部形变、摄像机都不属于这一层。小梅身体动作幅度为公共值的 90%。

原作整身动作、明确姿势参数、坐卧/AFK、手动取景和临时旋转/捏扯优先；新增层淡出。原作手指动作与表情继续独立评估。连续 AI 表情只保留一个最新待播动作，不堆积队列、不突然重启动作；相同动作不反复从头播放。预览可以打断当前附加动作，但必须先平滑撤除。

这不是动捕，也不是全身接触 IK 系统。首批避免走跑、下蹲、手摸脸和手臂横穿胸前等需要足底/接触解算的动作。骨架关节限幅不能单独证明任何换装都没有穿插；实际画面和用户观感仍是验收条件。60 / 120 Hz 数值采样不等于手机实测帧率。

## 隔离与撤销

统一标记：`HOST-EMOTION-EXPERIMENT v1`；事件前缀 `host.motion.*`；状态来源 `starrynight.host-emotion.v1`。

| 层 | 新文件 / 接入点 | 移除方式 |
|---|---|---|
| Unity 模块 | `HostEmotionRig`、`HostEmotionMotion`、`HostEmotionMotionRestore` | 删除三个独立模块和各自 meta |
| 构建校准 | `HostEmotionMotionBuilder`，`CharacterPackageBuilder` 一处调用 | 删除 builder 和调用，重新 Setup / 导出恢复生成 Prefab |
| Unity 消息 | `CharacterDirector` 的 Bind/Clear/Cancel、四个事件与有限次数的状态通知；`CharacterPlatformState` 可选状态 | 移除对应接入，不改原作 performance 事件 |
| 操作让位 | `ViewerController` 一处 `SetHostMotionInteraction` | 删除一处调用 |
| iOS | `HostEmotionMotionPanel`、表现页试用分类/可选状态、Coordinator 的配置/通知/AI cue | 删除模块和对应接入，原作选择回调保留 |
| 本地偏好 | `hostEmotionMotionEnabled.v1` | 可保留无害旧值，或仅移除该键，不能清空 UserDefaults |
| 检查 | `HostEmotionMotionReview`、`HostEmotionMotionTests` | 随试验一起移除 |

快速停用只需关闭界面开关。整功能回退优先反向应用本次独立功能提交，保留之后的其他改动；重新生成 Unity 导出与 iOS App 才会去掉已经打包的组件。原始压缩包、转换 GLB、XCP 清单、原作控制器 IR、服务端人设与音色无修改。

参考：[Unity 动画分层与遮罩](https://docs.unity.com/en-us/engine/6000.7/manual/animation-section/animation-mecanim/animation-animator-controller/animation-state-machines/animation-layers)、[Unity 人形骨骼重定向](https://docs.unity.com/en-us/engine/6000.3/manual/animation-section/animation-mecanim/avatar-creationand-setup/retargeting)。本项目的导入骨架在生产中使用已烘焙 Transform 动画，因此采用独立、校准过的加法层，没有替换原作 Animator 或引入另一套下载执行脚本。

真实验证结果单独记录在 `docs/verification/host-emotion-motion/README.md`，不能将本文的设计目标当成通过结果。
