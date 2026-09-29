# VRChat FBX / prefab → XCP 1.1 接入方案

审查日期：2026-09-29。本文基于仓库源码只读检查；没有运行 Unity、Xcode，也没有把待实现的转换器冒充现有命令。本文的“已存在”表示入口和约束已在源码确认；新模型仍须完成实际导入和视觉验收。

## 结论与最短路径

优先采用 **原始 FBX + prefab 元数据 → 现有 bpy 4.5.3 转 GLB → 规范化动作和 sidecar → XCP → 已有 Unity 编译器**。无需为了只提取网格、骨架和声明数据，把 VRChat SDK 装进正式 App 的 Unity 工程。Unitypackage 和 prefab 不是 XCP 运行时格式，不能原样塞进 App。

这个路径有两个前提：选定 prefab 的最终外观可以从 FBX 和序列化覆盖值确定；原材质效果能被当前运行时表达，或完成明确的适配。若 Modular Avatar、VRCFury、约束、生成式网格或自定义构建步骤决定最终外观，静态 YAML 不能证明等价。这类资源才进入独立 staging 工程，以匹配源项目的环境解析最终结果；不迁移正式工程、不把第三方编辑器脚本带进 XCP。

glTFast 6.16.1 的现有导入链已经承担蒙皮、morph、Legacy 动画导入。它的导出代码中能确认蒙皮路径，但本次没有确认完整的 morph / 动画导出能力，故不把它作为替代 Blender 的首选。Blender 的 glTF 插件由 Khronos 项目维护，实际安装版本及导出参数仍应由本机 RNA/API 探查和首个样例验证后锁定。[glTF-Blender-IO 官方仓库](https://github.com/KhronosGroup/glTF-Blender-IO)

## 可直接复用的入口

| 阶段 | 真实文件 / API | 复用范围与边界 |
|---|---|---|
| 数据容器、数学、动作输入 | `scripts/prepare_anime_characters.py`：`GLB`、`paths`、`motion_tracks`、`resample`、`multiply`、`slerp` | 读取已锁定 Overte VRMA、还原其标准 Humanoid 旋转；`GLB.array` 当前拒绝 sparse / interleaved accessor，Blender 输出须检查；不是通用 FBX 导入器 |
| 非 identity 骨轴重定向 | `scripts/prepare_portrait_vrm.py`：`world_rest_rotations`、`retarget_rotation`、`smooth_rotations` | 复用数学函数；不要整套调用 `package`，其中 VRM 元数据、角色许可、面部命名和补偿角是专用逻辑 |
| 角色声明与资源密封 | `character-sdk/tools/character_tool.py`：`inspect / seal / validate / pack / compare` | XCP 1.1；所有运行资源入 `files`；包不能携带脚本、外部 URI、越界路径或运行时下载依赖 |
| 源包登记 | `scripts/import_character.py` | 目录或 `.xcp`；`--source-only` 只登记；编辑器阶段失败会回滚源目录，但已有 Unity 中间资产须重新 Setup 清理 |
| Unity 编译 | `unity/CharacterRuntime/Assets/Editor/CharacterPackageBuilder.cs`：`Preflight / CreateImported / ValidateBindings / CatalogForHost` | 必须 GLB；导入为 Legacy；移除源 Animator，按清单动作名注册；采样 Idle 后烘焙取景、足底和 Prefab |
| 材质与弹簧绑定 | `Assets/Editor/AnimeCharacterAdapter.cs`：`Prepare / PrepareMaterials` | 由 `core.secondary-motion@1` 开启；侧文件不是任意 Shader 执行接口 |
| 发丝、衣物运行 | `Assets/Scripts/Runtime/AvatarSecondaryMotion.cs`：`Step` | 固定求解器、球碰撞、有界骨骼偏转；不是 VRChat PhysBone 的完整运行时 |
| 场景集成 | `Assets/Editor/BuildIos.cs`：`Setup / Validate / Thumbnail` | Setup 同时生成现有内置角色、导入角色、环境和原生角色目录，需完整执行以建立一致场景 |
| 背景 | `Assets/Editor/EnvironmentPackageBuilder.cs`、`RefinedEnvironmentBuilder.cs` | 已有 XEP / 默认场景、缩略图和环境目录；选择角色包允许的 defaultEnvironment，避免另写无关联背景 |
| 头像 / 固定封面 | `Assets/Editor/CharacterPortraitBuilder.cs::Export`、`CharacterCoverBuilder.cs::Export` | 真实模型渲染；固定封面必须有 `CharacterCoverCatalog.json` 显式绑定；1024×768，与角色默认背景一致 |
| 音乐 | `scripts/generate_soundscapes.py`：`synthesize / synchronize_collection_music` | 原创、每角色独立 CAF/ALAC；音频审计包含实际 PCM、乐谱、接缝和源角色证据；本轮已将 20 首常量改为动态集合并实测 `--only` 增量生成 |
| 原生集合 | `ios/CharacterHost/Resources/CharacterCollections.json` | 每角色独立动作、背景、声音、音乐；模型 ID、包版本、option namespace 一致 |
| 平台导出 | `scripts/export_unity_ios.py`、`BuildIos.ExportSimulator / ExportDevice` | 编辑器任务 accepted ID 只提交一次，随后读状态；不可因状态查询短暂失败重复提交导出 |
| 最终目录校验 | `scripts/check_export_content.py`、`check_character_collections.py`、`validate_character_covers.py` | 各自检查的范围不同，不能只看到一个 PASS 就认定所有视觉内容已进入导出 |

以上 `Assets/...` 均相对 `unity/CharacterRuntime/`。源包详细接口以 [XCP 制作规范](../character-standard/02-model-production.md)、[角色集合规范](../character-standard/character-collections.md)、SDK Schema 为准。

## 从 prefab / staging 必须保存什么

建议新增一个**中间数据契约** `staging-avatar.json`；此名和字段仍是设计提议，不是目前 SDK 已支持的格式。必须能够追溯源数据与实际选定外观，而不是只保存一个 FBX 文件名。

| 数据组 | 必须提取的信息 | 用途 |
|---|---|---|
| 来源与选择 | unitypackage / FBX / prefab SHA、作者、原始名称、许可原文与 URL、选定 prefab GUID / fileID、源依赖版本 | 防止不同版本/服装混用；记录许可适用范围，不把此前 Nitral 资源的私人预览限制套到全部 VRChat 资源 |
| 节点与覆盖 | 稳定节点路径和 GUID/fileID 映射；最终 activeSelf / renderer.enabled；prefab variant 和 nested prefab 的覆盖顺序 | Blender 导入 FBX 常会显示全部可选网格，必须按 prefab 默认外观过滤；禁止把内衣/替换脸等隐藏部件意外一起导出 |
| 几何与蒙皮 | Mesh 对应、material slot、skin joints、bind poses、4 权重化前后误差、顶点/UV/法线/切线、默认 blendshape 权重 | 证明导出没有丢蒙皮或默认造型；UV 接缝导致顶点复制属于预期，应比较几何和形变而非只比较顶点数 |
| Humanoid | `HumanBodyBones` 或 importer humanDescription 的映射、骨父子关系、完整 local/world rest TRS、单位/朝向、标准 T-reference 姿态 | 非同名骨架重定向；名称推测只能生成待确认映射，不能自动当作权威 |
| 面部 | Renderer 的实际 blendshape 名称/索引/frame 权重；AvatarDescriptor 的 lipSync、viseme 名单、jaw、eyeLook、blink 绑定；表情动画曲线 | 生成明示 aliases；处理多 Renderer 表情，保留独立眼睛 |
| 材质 | Shader 名称和版本、keywords、renderQueue、Cull/ZWrite/alpha、所有颜色和贴图、贴图 ST/UV 通道、色彩空间、normal 强度、matcap/emission/mask | 建立逐特性映射与缺失列表；拒绝“材质变白但导入成功”的假完成 |
| PhysBone | 启用状态、组件根、ignoreTransforms、endpointPosition、multi-child 模式、局部限制轴、radius/angle 及曲线、pull/spring/stiffness/gravity、collider 引用/形状/位置/旋转/insideBounds | 判断哪些能近似，哪些不支持；不得静默丢弃链端、分支或碰撞组 |
| 构建后差异 | 若用 staging：最终渲染树与源 prefab 的差异、生成网格、约束烘焙结果、未解析脚本/引用清单 | 只有这里确实改变外观时才引入源 SDK / 插件；原生包不携带这些组件 |

静态解析也必须解引用 prefab 的对象 ID，不能靠 YAML 中碰巧出现的第一个 Renderer/材质判断。不存在完整性证据时，将该特性标记为“待解析”；不要默认为关闭或随意取默认。

## Humanoid 重定向：骨轴和姿态分开处理

现有归一化函数先将源 VRMA 局部旋转变成标准 Humanoid 参考，目标恢复公式为：

```text
q_target_local = inverse(W_target_parent_reference)
                 × q_normalized
                 × W_target_bone_reference
```

其中 W 是**同一个标准参考姿态**下的世界旋转。`world_rest_rotations` 当前读的是 GLB 的原始 rest。它能纠正 FBX 风格的任意骨局部轴；当 FBX 绑定姿态是 A，而源动画参考是 T 时，仅使用原始 rest 仍会保留两者的肩臂偏差。normalized identity 恢复原始 local rest 就是可独立验证的例子。

最短实施顺序：

1. bpy 导入保持源骨轴和 bind 数据，明确检查 automatic bone orientation、单位、root transform；导出到标准 glTF 后只让 glTFast 处理一次坐标手性。不要照搬 VRM0 的 Y 半转或给 Blender 导出再手工翻 X。
2. 比较目标肩—肘—腕、髋—膝—踝的世界方向，核验是 T、A 还是已有会话姿态。T-reference 已一致时可直接复用当前函数。
3. A-pose 等差异必须新增显式参考姿态校准，保留原 inverseBindMatrices。校准的是骨旋转参考，不是把原绑定矩阵伪装成 T。原始 rest 和校准参考都进入审计。
4. 有合格 Unity Humanoid Avatar 且比例复杂时，备选是在 staging 用 Unity 的 Humanoid 重定向 / HumanPose 采样，再烘焙回目标局部曲线。Unity 官方明确要求配置有效 Avatar 才能做 Humanoid 重定向；这不是正式 App 增加 Animator 的理由。[Unity Humanoid 重定向](https://docs.unity.com/en-us/engine/6000.0/manual/animation-section/animation-mecanim/avatar-creationand-setup/retargeting)
5. helper/twist/sleeve 骨不能只按主骨名字复制局部 quaternion；保留其静态关系，或明确复制世界姿态/分配 twist，再逆父世界矩阵回局部。会随动画变化的非 Humanoid 中间父节点需要全层级烘焙，不能使用假定父节点静止的公式。
6. 第一版只烘焙站姿会话的九个既有逻辑动作：Idle / Hello / Yes / No / Listen / Think / Talk / Relax / Thanks。腿部和 hips 支撑保持稳定；不自动声称已经支持坐/蹲/躺、导航根运动或双人 IK。
7. 复用统一上肢 160ms 平滑、符号连续和首尾基线；不可照搬旧角色的固定上臂 ±5° 外展补偿。手指、独立眼睛、脚底另行检查。动画采样 30Hz 不等于屏幕只能 30FPS，帧间插值由播放器负责。

数学验收应独立重建 GLB FK，验证脚底世界位置、关键骨端点、首尾姿态和四元数角速度。只比较“生成函数重新算出的同一个结果”没有独立性。现有 `scripts/tests/test_illustrated_characters.py` 的 `sampled_world`、`angular_speed` 和 220°/s 会话上肢舒适预算可复用；新骨名应来自显式 map，而非扩展硬编码字符串猜测。

## Blendshape aliases 与 authored defaults

不要改作者 morph 名。新增导入中间 aliases，将逻辑 `joy/care/sad/anger/blink`、口型 `aa/ih/ou/ee/oh/sil` 指向确实存在的 `renderer + shape + weight`，落入标准 `expressions` / `speech`。依据顺序是 AvatarDescriptor 明示绑定、源表情 clip 的实际曲线、最后才是人工确认的名称候选。

默认形变可能决定脸型、遮体或服装适配，必须保留 FBX shape keys 和 prefab 默认值。若导入 GLB 默认 weights 不能被现有 mixer 保留，应在 staging 将**不再需要动态控制**的 authored default 烘入 basis，并保留动态 morph 的正确相对差分；不得把永久默认脸型误当每次 neutral 要清零的表情。先用一项非零默认 morph 实测运行时重置路径，再选实现。

口型与情绪、作者外观变形分开；当前 TTS 主路径仍是 amplitude 驱动开口，viseme 字段只代表模型已提供绑定，不能声称已实现逐音素口型。左右眼骨存在时独立留给 gaze，不向眼骨烘焙头部动作。面部整体挂在 Body Renderer 的资产需拆分可命中的 face mesh 或明确适配头部命中范围，不能把整身当 headRenderer。

## 裙发 spring 的兼容边界

VRChat PhysBone 包含端点、多分支、约束模式、碰撞范围和交互参数；sphere、capsule、plane、insideBounds 各有不同语义，不能只改字段名字。[VRChat PhysBones 官方说明](https://creators.vrchat.com/common-components/physbones/)

当前 `secondary-motion.json` 只支持 root→tip **直接父子**边，最多 128 个 strand / 64 个 sphere；角度 1–20°、strand 半径 0–0.05m、sphere 半径 0–0.5m。运行时共享 Spring=140 / Damping=19、120Hz 子步，碰撞集合没有每条链的独立分组。头发有缓慢风动，名称识别到裙/袖/cloth/ribbon 的链只参与惯性，不加抬升风力。

转换须保存全部源参数并列出近似损失。优先保留主要发链、裙摆和袖口；terminal bone 有 endpoint 时新增真正的子 tip，不能指定不存在的路径。分支逐边展开并排序，ignoreTransforms 按源语义排除。capsule 可近似为少量 sphere，但必须对比接触误差；plane / insideBounds / grab / stretch / squish / contacts 不能假装支持。不能为过预算直接截前 128 条而不记录被删链。

骨骼级 spring 不能修复权重错误或静态衣服与身体的穿插，也不是 cloth 自碰撞。裙摆受腿部摆动时应单独检查动态碰撞；第一版站立小动作仍需逐动作全时域观察。若共享碰撞组使头发被无关腿部 sphere 推走，应调整表示或扩展能力，不能靠加大碰撞体遮掩。

## 材质与近景画质

可以复用 `materials.json` 的 albedo / normal / matcap / emission 和 `kind`，但当前 UTS 适配并不等价于 lilToon：

- 读入的 `shadeColor` / `rimColor` 尚未用于还原源阴影配色；阴影阶和 rim 主要由 C# 固定规则控制。`shadeTexture` 也不是当前 C# MaterialData 字段。
- 非 glass 的非 OPAQUE 材质统一作为 cutout；多层透明、叠加、stencil、2nd/3rd main texture、anisotropy、特殊高光和 rim mask 等不能自动复刻。
- 现有纹理预处理只匹配 `Imported/anime-*/textures/`，normal 文件必须 `normal_` 前缀。新包可以明确使用 anime ID 复用它；后续通用化应改成能力/目录契约，不能宣称所有导入包都已获得 ASTC4×4 / mipmap 策略。
- 颜色字段为 linear RGBA，适配器调用 `.gamma`；源 Unity YAML Color 的序列化语义与贴图 sRGB 标志必须核对。UV scale/offset、emission alpha、透明眼镜、睫毛与眼球是优先对照点。

首轮用源作者允许的参考图或 staging 同光照渲染，对比正面、侧面和头肩近景。如果关键风格依赖不支持的 Shader 特性，先明确适配成本；需要正式依赖时选择官方版本并确认 URP/iOS 支持，不能以“模型能显示”作为画质验收完成。

## 背景、封面、音乐与导出一致性

新增角色需同时建立 XCP manifest、XCC collection、author 关联、默认背景、两个角色专属音乐选项，以及 cover/portrait。背景本身仍用现有 XEP 与 refinement：不要为了一个角色复制全套公共环境，也不要让某角色的 allowed IDs 意外暴露给另一角色。

当前 `check_character_collections.py` 校验集合和模型目录一一对应、包版本、action/room 默认与范围、语音 namespace，以及 CAF 的 sourceModelID / 文件 SHA / 实际 PCM 和 score 唯一性。`generate_soundscapes.py` 扩展角色时要以选择参数仅生成新角色，验证旧音频 SHA 未改变；不要重新生成旧角色造成无关资产波动。

封面生成器用角色默认场景隔离渲染；`validate_character_covers.py` 检查 runtimeID 集合、场景、1024×768 图像、渲染报告关联。它**尚不校验封面像素 SHA 与模型 SHA 的关系**。角色换外观后即使文件名不变，也应重新渲染并保留源内容指纹。

平台导出 stamp 当前包含 CharacterCatalog 和 EnvironmentCatalog 的 SHA、模型集合以及 framing / immersion / nativeGesture 等协议版本。`check_export_content.py` **没有覆盖模型 GLB、材质、sidecar、Unity C# 或贴图内容 SHA**。清单不变而模型内容变化，旧导出仍可能通过目录校验；本轮必须重建场景并重新导出对应平台，不把这个 PASS 当缓存新鲜度证明。

建议随后新增组合内容指纹：排序后的已密封角色资源 SHA、环境资源 SHA、适配器和场景构建源码、集合、渲染设置一起形成输入摘要，写入 Setup、封面报告、Unity export stamp。正式构建比较摘要，能让“改了 GLB、没重新导出”确定失败。此机制在本次审查时尚未实现。

## QA 与失败记录

验收按阶段放行，不因后续目标帧率而跳过资产完整性：

| 关口 | 必留证据 | 失败时的处理 |
|---|---|---|
| 来源 / staging | 资源锁、许可、prefab 选择与覆盖清单、缺失引用清单 | 源不完整则补数据；不得用其他脸/服装凑数 |
| GLB 静态 | 300k POSITION / 32 primitive / 256 joints 上限；归一权重、有限 TRS、morph 名单、全部纹理及默认姿态截图 | 区分单位、骨轴、rest pose、bind matrix；只改一个原因再复验 |
| 动画 / 表情 | 独立 FK 足底、上肢角速度、首尾 morph、每动作 / 表情接触画面 | 记录首个异常时间、骨路径和前后值；不拿滤波掩盖绑定错误 |
| 物理 / 材质 | 发裙动态、碰撞错位、重新激活复位；发色 emission、眼镜、alpha、法线近景 | 明列不支持的源特性；有视觉差异则未完成 |
| Unity | SDK seal/validate、绑定校验、取景 envelope、safe-area、真实 portrait / cover | Shader 编译、骨路径和采样问题分别留完整日志 |
| App | 默认进入即终态、头像、头触、AI 语音口型、两首实际播放、角色隔离和返回恢复 | 使用现有真实 UI 流程；新测试不得只读“文件存在”冒充播放 |
| 性能 | iPhone 实际 60/120Hz 帧时间、热状态、CPU/GPU、内存；近景发片透明覆盖 | 模拟器只验功能和截图，不能证明 120FPS；记录条件和降级 |
| 导出 | 本次源 hash、Setup/平台导出标记、目录与封面音频审计、安装版本 | 旧 hash / 平台混用则重导；不重复提交已接受的长任务 |

失败记录建议一条一个问题：`sourceHash / stage / expected / observed / exact evidence / cause / minimal fix / recheck / residual limitation`。保留有价值的前后证据，例如 A-pose 肩膀偏角、漏 prefab 隐藏网格、emission 丢失、两种透明模式差异、未更新 export stamp；不记录无信息的每条终端操作。

优先复用 `test_illustrated_characters.py` 的独立几何工具、`test_character_music.py` 的实际资源边界、`AuthoredCharacterTests.testCAFPlaybackAndMusicPreferencesStayInsideEachCharacter` 的播放验证，以及 `SafeAreaFramingReview.Validate` / 原生安全取景用例。模型规模变化会要求测试枚举读取新 manifest，不能修改阈值让错误样本通过。

## 项目 skill 草案

已阅读 `skill-creator`。建议名称 `vrchat-character-import`，放 `.agents/skills/vrchat-character-import/`，只在“把 FBX/prefab/unitypackage 角色接入本项目 XCP、补齐材质动作物理和完整配套资产”时触发，不承担通用 Unity 操作。真正调用 Editor 时继续使用现有 `unity-cli` skill。

```text
vrchat-character-import/
  SKILL.md                         # 触发范围、阶段关口、输入/交付、禁止的假成功
  references/
    pipeline-map.md                # 本文中的实际仓库 API、版本与能力边界
    staging-metadata.md            # 实际验证后固化的中间数据契约
    retarget-and-springs.md        # 参考姿态、别名、物理近似与失败例
    acceptance-and-evidence.md     # 证据格式、最小回归选择、性能范围
  agents/openai.yaml               # 需要时按 skill-creator 的规范生成
```

SKILL 主文只保留决策路径和必须遵守的项目约束，细节按需读 references，不重复 SDK 全文。转换器归项目 `scripts/` 管理，skill 引用经验证入口即可，避免复制一套逐渐偏离的脚本。

在首款 FBX/prefab 完整通过前，不写可执行的 Blender/Unity 命令，不预设导出器存在的参数，也不创建“成功即可下一步”的伪验证。流程完成后再把实际命令、输入 hash、最小复现与失败处理收敛为 skill，并以新模型或独立样例验证它能重复执行；skill 的格式校验不等于模型流水线验证。
