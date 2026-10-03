# 原作片段库与通用动作实验标准

落地版本：StarryNight 0.94.0；本轮 16 个 XCP 包为 3.4.0。原作库使用新增必需能力 `core.source-motions@1`；新增组合属于宿主开发实验，不写成作者原装动作。

## 原作资源的范围

来源审计扫描隔离工程内的 `.anim` 以及 FBX、`.asset`、`.controller` 内嵌片段，使用 `GUID` 或 `GUID:fileID` 区分子资产。保留整个来源审计，再把实际 GLB 节点能承载的通道投影到独立片段库。原菜单与其 Mecanim 控制器继续存在；新增库用于检查原菜单没有直接入口的片段，不替换作者状态机。

支持的投影是骨骼局部位置/旋转/缩放、真实 SkinnedMeshRenderer 的 blendShape、现有 Renderer 开关和现有子节点激活开关。Humanoid muscle 在该角色自己的有效 Avatar 上先烘焙成 Transform，运行时不再次求值 muscle。普通形变曲线保留作者时间、切线、权重和阶跃，不能只取最后一帧。

不存在的节点/形变、平台参数、场景 helper、需要额外世界对象的功能和物体引用不能变成“空的成功动画”。材质/物体引用仍由已适配原控制器处理，独立库不执行这些引用。关闭整个必要头部的片段、超过 120 秒的独立预览不放进可执行库，审计中给出原因。部分通道可投影时标为 `projectionComplete:false`，界面提示其范围；原库与原文件均不被删除。

`duration <= 0.05` 视作静态姿态，平滑进入后保持作者末帧目标；一两帧的滑杆/开关片段不能一直采样未改变的首帧。作者 `loop:true` 循环；其他片段一次播放后自然释放。静态姿态、穿搭开关和连续肢体动画分别计数。原作库中的同一片段可能已被原菜单使用，因此“独立片段数 + 菜单数”不是不重复的动画总数。

## XCP 源包数据

```text
avatar-motions.json.gz      # 原控制图需要的既有采样数据，gzip JSON
source-motions.json.gz      # 全来源的可执行独立投影，gzip JSON
source-motion-audit.json    # 每个来源片段及每个舍弃通道的具体原因
avatar-controls.json        # 原菜单 + 宿主独立预览按钮
character.json             # core.performance@3 / avatar-controls@2 / source-motions@1
```

机器规范见 [source-motions.schema.json](../../character-sdk/schemas/source-motions.schema.json)。解压后的单文件最大 128 MiB，源包仍受既有 256 MiB 总预算限制。压缩是无损的，不降采样率、不降纹理质量。只有完全恒定的 Transform 轨道把重复样本收敛到首尾两点；时间与取值不变。

清单扩展为：

```json
{"app.starry.source-motions":{"version":1,"file":"source-motions.json.gz","encoding":"gzip-json","origin":"author-curves-host-preview"}}
```

`Starry_SourceMotion` 是宿主保留的 int 参数，初值 0、不可持久化。每个独立片段按钮 `source-motion-{guid}` 的值对应库内 1 起始序号；0 代表停止。SDK 检查密封文件、序号、真实节点/shape、曲线组件与属性搭配、有限值、时间序列和预算。未知 required 能力必须拒绝，不能让旧宿主把 gzip 当旧 JSON 或静默忽略必需行为。

Unity 构建生成数据型 AnimationClip 子资产，不随下载包分发作者脚本、动画事件、对象回调或可执行 SDK 行为。独立预览按实际 Avatar 根求值。所有写入属性在下一次 Animator 求值前还原，然后对当前原作姿态重新叠加；停止会归还当前控制器基线，不把全部形变清零，不永久改变默认衣装。进入使用 0.42 秒五次 smoothstep，释放使用 0.48 秒同类曲线；快速连续选择只保留最后一个待播片段，避免积压。

原作 Animator、作者 AI 白名单和独立预览库是不同层。未核对语义和动作范围的库片段不会自动加入 AI：躺姿、全身动作、衣装开关不能仅凭文件名随聊天触发。后续可审核后增量声明 `ai.automatic`，不需要改角色 ID 或聊天协议。

## 10 个通用身体与表情组合

| ID | 开发者名称 | 主要配合 |
| --- | --- | --- |
| agree | 轻轻点头 | 两阶段点头、轻微胸部跟随 |
| happy | 开心回应 | 小幅身体舒展、头部跟随、双臂向外 |
| curious | 侧头思考 | 颈部和头部不同幅度侧倾，稍后收回 |
| shy | 害羞低头 | 低头、轻转视线与身体收敛 |
| pout | 小小不满 | 小幅侧转、轻微后仰与前臂回应 |
| sad | 低落倾听 | 缓慢低头、轻微前倾、长收尾 |
| surprised | 惊讶回应 | 轻抬头、胸部退让、双臂轻抬 |
| welcome | 挥手问好 | 右侧前臂与手腕错开时序，左臂克制 |
| encourage | 温柔鼓励 | 点头与单侧前臂鼓励动作 |
| disagree | 轻轻摇头 | 头/颈分担左右摇头，身体小幅跟随 |

最低骨架要求：经过真实 `human` 映射的 Spine、Chest、Neck、Head、左右 Shoulder、UpperArm、LowerArm、Hand。未来同骨架模型由能力判断接入，不用角色白名单，不通过名字猜骨骼。上身运动轴由中性世界基坐标换算到每个关节局部坐标；肘轴由前臂到手腕方向和角色正前方建立；左右外展方向取实际关节相对胸部的位置，防止镜像模型向身体内折。

曲线采用 `S(t)=6t⁵−15t⁴+10t³`，起止一阶、二阶导数为零。短预备→躯干先动→头部跟随→手臂跟随→较长收尾；节点错开峰值，双侧不完全对称，不用逐帧随机扰动。播放过程中取消，也在 0.48 秒释放，不直接跳回默认。只叠加校准的上身关节和已有真实脸部形变，不写相机、角色根、腿脚和手指，不改变用户的取景状态。

脸部优先匹配经过识别的原作表情，排除朗读 viseme 通道。缺乏可靠对应时明示原作表达或中性回退，不能声称原包一定含害羞/惊讶等所有情绪。脸部随身体分阶段进入、释放，每帧恢复下层值，保留原口型和默认非零形变。

## 实验与撤销边界

入口仅在 `STARRY_TEST_TOOLS` 开发版的浮动开发者按钮→**动作实验**。新增组合需要 `preview:true`；自动 AI cue 返回 `HOST_MOTION_DEVELOPER_ONLY`。原作表现仍在开发者页的**角色表现**，新增库分类带“原作”前缀，两种来源不会混在一起。

关闭“身体与表情组合”只撤销这个附加层，原作表情、手势、待机、口型、风和衣发跟随继续运行。面板离开、解绑、换角色会停止预览。原作身体姿态、独立片段预览和手动位置操作优先；不在受控制姿态上叠加会改变动作意义的组合。

保留功能的升级点是 `HostEmotionMotion` / `HostEmotionRig` / `HostEmotionMotionBuilder` 和独立 `HostEmotionMotionPanel`。完整移除实验可删这些模块、DeveloperPages 的 motion 分支与相应桥接路由，不碰源包和原控制器。原作库另由 `SourceMotionPreview` / `SourceMotionLibraryBuilder` / SDK capability 控制，可独立保留或升级。私有原包回滚位置写入本轮验证记录，不公开模型数据。

## 验证要求

1. SDK 对全部发布名册 seal/validate，集合引用必须与模型版本一致；未知能力、空片段、缺形变、错序号和非有限关键帧有负向回归。
2. 全库逐片段检查实际绑定、求值、根不变以及 Transform、morph、显隐可恢复；原作片段即使与初始姿态相同也不能被误说成动态身体动画。
3. 全部有资格角色 × 10 组合 × 60/120 Hz 检查原作每帧基线、不额外移动脚、有限四元数、首尾连续、取消和开关隔离；60/120 Hz 是动画求值测试，不是设备 FPS。
4. CPU BakeMesh 截图检查方向与明显穿插；真实模拟器测试 Swift→桥接→Unity→回执以及原作控制与开关。默认衣装结果不代表任意换装都无穿模，后续正式开放前仍需用户观感验收。
5. 下载角色分别重建 iOS 与 iOS Simulator Bundle，并发布新的不可变 OSS release；只升级内置 App 无法更新旧下载包里的骨骼校准和 clip 资产。

采用 Unity 官方的 [Humanoid 重定向](https://docs.unity.com/en-us/engine/6000.3/manual/animation-section/animation-mecanim/avatar-creationand-setup/retargeting)概念，但新增组合是星夜的局部校准叠加，不冒充作者动捕。离线源采样和运行时预览使用 [AnimationClip](https://docs.unity3d.com/ScriptReference/AnimationClip.html) 数据接口；最终品质由实际角色画面验收决定。
