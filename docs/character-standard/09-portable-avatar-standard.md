# VRChat 与自制角色的可移植控制标准

版本：`core.avatar-controls@1`，数据 profile：`mecanim-portable-v1`；首次落地于星夜 0.60.0。

本标准扩展现有 XCP、Character API、原作表现和自然待机协议。它把角色自身的模型、原作控制图和可选表现保存在角色包中，宿主提供统一执行器、会话界面与 AI 调度。制作方可以直接按标准制作自有角色，不必依赖 VRChat；VRChat 是当前的一种来源适配器。

## 分层与边界

| 层 | 责任 | 当前实现 |
| --- | --- | --- |
| 原始资产 | 作者 Prefab、FBX、材质、控制器、菜单、许可及版本 | 原文件只读，按 SHA-256 锁定 |
| 来源适配 | 解析 Prefab 有效状态、GUID、控制图和 Humanoid 曲线 | 隔离 Unity stage + `vrchat_controls.py` + `vrchat_portable_convert.py` |
| 通用角色包 | GLB、控制数据、原作曲线、材质、衣发运动、能力和来源 | XCP 清单 + 本文五类 sidecar；SDK seal/validate |
| 运行时 | 重建原生 Mecanim、材质、可控参数和恢复默认 | `PortableAvatarControllerBuilder`、`AvatarControlDriver`、既有 Character API |
| 产品 | 会话、动作菜单、音量、背景和账号隔离 | Swift 由角色目录生成选项，不按角色写分支 |
| AI | 根据该角色的已审核语义白名单选择表现 | 现有 `performance_catalog`；不直接产生骨骼路径或任意参数名 |

编译 App 时只把默认角色实例放进初始场景，其他角色通过编译后的 Resources Prefab 异步加载。最多保留两个角色实例；切换和预热用请求代次取消过期结果，淘汰后可重新加载，包括初始角色。此机制适用于整个发布名册。当前仍是随 App 安装的资源，不是已上线的远程下载市场。

## 包目录与版本

```text
character.json             # 现有 XCP 清单，稳定 id/packageId、包版本、能力与文件校验和
model.glb                  # mesh/skin/morph，固定坐标与骨架，合法基础 Idle
avatar-controls.json       # 参数、菜单控制、原作控制图、mask 与明确的适配说明
avatar-motions.json        # 原作曲线及 Humanoid 烘焙轨道
avatar-geometry.json       # Prefab 节点默认激活状态、Renderer 默认开关
materials.json             # liltoon-properties-v1，schemaVersion 2
secondary-motion.json      # schemaVersion 2，宿主衣发运动适配数据
textures/                  # 按角色封装并参与校验
LICENSE.txt / NOTICE.md    # 来源许可、署名与适配边界
source-meta.json            # 原始版本、哈希、主 Prefab 和变体来源
```

五类 sidecar 和所有依赖文件必须进入 `character.json.files` 的 seal。源数据变化后重新转换、校验和画面复核，不能只改目录版本号或 catalog stamp。第一批新角色包为 3.0.0；旧琪宝、豆日向的 2.2.0 包保持可读，不为形式统一而改写其原作曲线。

清单 `compatibility.required` 必须包含 `core.avatar-controls@1`；有菜单时同时声明 `core.performance@2`。衣发适配声明 `core.secondary-motion@2`。原作口型、眨眼依照实际数据分别声明可选 speech/autonomy 能力，不能由“有 Humanoid 骨架”推断已经有这些动作。

新宿主同时支持旧、新能力版本；旧包不进入新控制解析器。未知 optional 能力可以忽略，未知 required 能力必须拒绝加载并给出版本要求。未知 JSON 附加字段可以保留，但其执行语义必须有对应能力版本，不得靠未知字段偷偷改变旧版本含义。

## 控制与表现

机器字段见 [avatar-controls.schema.json](../../character-sdk/schemas/avatar-controls.schema.json)，跨文件语义与预算检查见 [portable_avatar.py](../../character-sdk/tools/portable_avatar.py)。JSON Schema 负责形状，SDK 继续检查真实节点、密封文件、引用、图和资源预算。

每个控制都有稳定 `id`、展示 `label/group`、`parameter`、`kind`、`initial/value/minimum/maximum` 和可选的父菜单 `gates`。支持 `toggle`、`button` 和 `slider`；VRChat 二轴/四轴菜单转换成独立参数滑杆，径向菜单转换成归一化滑杆。子菜单参数门在选择时生效，分类复位时恢复初值；这是宿主面板交互适配，不是 VRChat 菜单打开/关闭生命周期的逐帧复制。

`character.json.performance.options[].control` 必须与同 ID 的 sidecar 控制完全一致。用户界面沿用表现分组；类别不限于表情、姿势、手势、耳尾或穿搭。浮点控制显示实际确认值，选择回执和 `avatarControlValues` 来自 Unity Animator。恢复默认恢复参数初值、原作默认状态、层权重和可见性，不以“全部设为 0”代替默认。

控制图包含状态机、状态、过渡、BlendTree、mask 和原作 motion 引用。源 Unity 文件可能残留已脱离实际层根的历史对象，只导出从实际层根可达的图；可达依赖缺失必须失败。不能把任意缺失动画替换成空动作。已审核的三项 SDK 中性手/站立基线 GUID 在校验器中精确列举，使用该角色自身 Prefab 中性手指和明确标注的宿主站姿；表情、运动和平台 emote 不在此允许列表内。

来源适配器同时读取内联和独立 `.asset` BlendTree。外部树以 `guid:fileID` 标识，保留同一文件中的嵌套子资产；内部树继续沿用旧 ID。循环引用留给 SDK 检查并拒绝，不能在展开时无限递归。这是现有控制图表示的解析补齐，不新增宿主能力版本。

Prefab 候选发现沿实际 `m_SourcePrefab` 链查找 Descriptor，不要求 Descriptor 直接序列化在最外层文件。作者场景与备选变体保留为审核依据。构建时合并控制器的组件（例如 Modular Avatar Merge Animator）是另一类来源能力：在没有经过验证的合并适配器时必须阻止激活，不能误判为无动作、无菜单的简单角色。

MA 来源现可在独立工程中用固定官方 MA/NDMF 完成组装，再用只读二进制适配器读取生成数据。同容器内多个控制器/菜单/mask，以及跨容器的状态机和行为，都按 GUID + fileID 定位。生成数据引用必须与 Unity 原生检查双向一致；不能因为网格完整就接受丢失的菜单。生成容器 GUID 不作为持久控件 ID，同来源重建应保持控件语义身份。该流程只补齐来源解析，未自动实现原作粒子、世界约束、抓取或缺失贴图；现有 XCP 能力版本不变，实际进展见 [构建结果验证](../verification/vrchat-batch-import/modular-bake.md)。

参数驱动支持已审核的 Set/Add/Random/Copy 和范围映射；层权重与 playable 权重独立相乘，遵循原作混合时长；Eyes/Mouth tracking 所有权决定宿主眨眼、口型是否让位。源脚本、动画事件、任意回调与网络行为不执行。同步层、状态机级行为及未支持状态行为先隔离，不悄悄丢弃。

AI 自动调度与手动菜单独立：只有人工/画面核对过的 `ai.automatic` 语义才能给 AI 使用；模型衣服、体型等选项默认仅手动。新增角色的语义映射不能从别的角色复制动作 ID；新增分组无需修改聊天协议。遵守 [AI 表演标准](08-ai-performance-standard.md) 的轮次、取消、冷却、恢复和语音所有权规则。

从 0.61.0 起，`performance.options[].ai.kind` 可选为 `expression` 或 `action`。它描述实际表现语义，与菜单组 ID、按钮种类分离；不填时沿用旧包的类别推断。原作手势触发表情的选项应声明 `expression`，并填写该角色真实 `intent/effects/moods`，这样旧版规划器顶层 `expression_intent` 也能映射到任意作者分组。不能把一个作者的“食指”表情推断成另一个作者相同表情。3.0.1 包只补语义，不改原曲线。AI 临时表现结束时先恢复组默认，再重放用户原选中值；共用一个枚举参数的未选中菜单项不能逐个写零，否则会抵消恢复。

## 中性取景和展示层运动

所有已发布角色共用 `CharacterPortraitCalibrationBuilder`：在中性站姿提取眼骨间距、脸部锚点和中性轮廓，生成带版本和测量来源的 Prefab 取景数据。没有有效双眼绑定时回退到头骨与身高测量，并记录回退原因。角色米制高度不同、耳朵或帽子较高都不使用固定摄像机距离。当前手机构图以脸部中心位于画面自底向上约 62% 为目标，在硬件安全区内为头顶、头饰保留余量；需要时后退镜头，避免把脸压低到聊天区。取景只在中性姿态建立，不随眨眼、呼吸、根转动或弹窗追踪头部；用户保存的缩放和平移继续叠加。

`CharacterAmbientTurn` 是用户授权的宿主展示行为，独立于 XCP 原作动画：待机最多 yaw ±6.5° / pitch ±2.6°，说话最多目标 yaw ±3.2° / pitch ±1.3°，2–4 个随机方向组成一段，中间回正休息；平滑阻尼过渡。手动拖转、位置编辑和非站姿优先，临时偏移不会写入持久位置或触发 `model_shaken`。只有真实手动位移计入晃动阈值，达到阈值即在手指尚未松开时发出事件，保持 20 秒冷却及后端独立防重。这些展示层能力不证明原作自带全身待机，也不代表已测得设备帧率。

## 外观、骨骼与运动

| 来源能力 | 本版处理 | 不能据此宣称的能力 |
| --- | --- | --- |
| 作者 Prefab 默认形态 | 有效嵌套覆盖、激活状态、Renderer、原始 morph 和材质槽 | 裸 FBX 的所有网格同时显示就是作者默认 |
| 原作 FBX / Humanoid 曲线 | 原模型 Avatar 采样 60 Hz，普通曲线保留关键帧及切线；手指专用曲线不覆盖 Hips | 原作不存在的舞蹈、全身待机、讲话点头 |
| lilToon 材质 | 固定官方 2.3.4，保留审核过的颜色/数值、贴图、UV 变换和渲染状态 | 所有第三方自定义 Shader、所有平台效果完全等价 |
| 说话口型 / 自动眨眼 | 优先使用 Descriptor 绑定；无原作 Blink 控制层时，可审核已有标准眼睑 morph 后补宿主时序 | 原作没有口型/闭眼形变也自动生成一套 |
| PhysBone | 提取来源参数、骨链、碰撞体，以宿主有界弹簧与风适配 | VRChat PhysBone 数值等价、完整抓握拉伸和 multiplayer 参数联动 |
| 球 / 胶囊 / 平面碰撞 | 球体适配；胶囊采样为球；平面和 inside 模式记录未支持 | 已完成通用布料模拟或所有碰撞模式 |
| 无独立站立动画 | 经角色 Avatar 得到站立适配，明确标 `host-standing-adaptation` | 把宿主站立姿态标成作者原装待机动画 |
| Contacts / Constraints / 音源 / 粒子 / 平台功能 | 源审计保留；可影响默认外观或必需控制的未支持依赖阻止激活 | 只因 Unity 不报错就算已迁移 |

当前 mobile profile 采用四骨骼权重渲染；高于该配置的来源需要另做外观比较。衣发 profile 上限为 512 链段 / 256 球碰撞体；单角色包受 256 MiB、300k 顶点、256 个有效 skin joints 约束。可移植 profile 的总 primitive 上限为 64，旧 profile 保持 32；移除未被任何顶点权重使用的索引后再检查 joints，不能截断有权重的骨骼。帧率必须在完整会话真机实测，不能由预算、采样 60 Hz 或模拟器运行推断 60/120 FPS。

## 0.68 来源数据解析补齐

Material Variant 递归合并父材质属性，区分缺少覆盖和显式清空贴图；子材质保留自身 shader，render queue 按 Unity 的覆盖标记继承。只接受固定宿主 shader profile，未覆盖的自定义 LCD/相机 shader 不自动转成白色材质。纹理分支只有在静态禁用、且没有可达动画开启它时才可省略；检查动画影响时限定 renderer 路径，不能把另一件衣服的开关套到当前材质。

动画身份支持 `.fbx/.asset/.controller` 中的 `guid:fileID`，同文件多 clip 不相互覆盖。采样档案保留全部源证据，交付只包含活控制图和作者中性身体基线需要的 clip；不改变曲线或丢帧来压缩。角色属于本地、静止的桌面会话，来源适配可以用明确宿主参数值消除必不成立的分支；用户菜单、驱动器和曲线能写入的参数不能固化，更不能因缺资源而把分支判为不可达。

分包、共享依赖属于来源组成，纳入 inspection stamp。同作者 addon 引用本体时保留两个包的清单；跨档案共享依赖要求精确 GUID 和内容哈希一致。原包保持不变。每角色完整内容还包括独立的人设、真实音色、头像、封面、2.5D 场景、特效配色、单首音乐、公开介绍和后端稳定 ID；这些产品数据不能由模型转换成功推定为齐全。

原作与宿主能力必须分别说明。当前仍不等价于整个 VRChat 平台：多人网络、世界坐标交互、专用 shader、Modular Avatar 未烘焙组装及全部 PhysBone 动态参数，需要对应适配器。通用画面/交互检查不允许覆盖这些差异。

## 跨批次升级约定

1. 发布真源为 `assets/characters/active-roster.json`，批次状态为 `import-batches.json`；候选目录存在不等于角色已发布。
2. 通用修复落在解析器、SDK、运行时或公共 UI，不复制到每个角色。能力数据变换也用统一转换器；升级转换器后按源哈希、工具哈希和 Prefab 路径失效缓存。
3. 原始版本升级保留角色稳定 ID、账号历史、订阅和独立偏好。模型版本变动不复用旧生成包；有不兼容形变/参数时提供显式迁移或回到该角色默认，不能串用另一角色选项。
4. 影响公共执行路径的改动检查**全部当前发布角色**：静态包与集合完整性、旧新包混合切换、淘汰后加载、默认形态、动作结束/复位及角色隔离。性能敏感变更另做真机采样。
5. 每批只激活已通过画面与控制检查的候选。控制复核记录绑定 `character.json` SHA-256，并覆盖全部控制 ID；过期记录不能放行新包。
6. 后续新能力用独立 capability 和 schema revision 增加适配器、兼容样本与验证；现有文档中的预留不代表已经实现。重大升级仍可能需要迁移，不能承诺任意未来需求都零成本兼容。

元数据重建的转换缓存同时记录工具、源审计、几何 JSON/二进制、动作采样和站姿哈希；旧回执没有签名也不能直接复用。源版本、主 Prefab 或 Inspector 不符时先重新检查。预检将官方 SDK 引用与本地未解析 GUID 分开，避免把“平台运行时提供的动作”误说成“作者档案缺文件”；识别出处不代表已经实现该平台能力。

实际首批结果和未完成项见 [分批导入记录](../verification/vrchat-batch-import/README.md)。

## 官方依据

控制层、参数、菜单和行为分别依据 VRChat 官方 [Playable Layers](https://creators.vrchat.com/avatars/playable-layers/)、[Animator Parameters](https://creators.vrchat.com/avatars/animator-parameters/)、[Expression Menu](https://creators.vrchat.com/avatars/expression-menu-and-controls/) 和 [State Behaviors](https://creators.vrchat.com/avatars/state-behaviors/)。平台的 [PhysBones](https://creators.vrchat.com/common-components/physbones/)、[Constraints](https://creators.vrchat.com/common-components/constraints/) 与 [Contacts](https://creators.vrchat.com/common-components/contacts/) 是不同能力，不能相互代替。

外部混合树依据 Unity [Blend Trees](https://docs.unity3d.com/6000.0/Documentation/Manual/class-BlendTree.html)；构建时控制器组装依据 Modular Avatar [Merge Animator](https://modular-avatar.nadena.dev/docs/reference/merge-animator)。来源的构建流程与已烘焙的运行数据需要分别验证。
