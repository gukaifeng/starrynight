# 小伴标准 3D 角色制作规范 · XCP 1.1

> 1.1 新增：持续站/坐/蹲/躺、姿势参数、专用动作和聊天配置。请同时阅读[姿势制作与接口标准](05-posture-standard.md)，它定义持久姿势和一次性动作的区别。旧包继续兼容。

**这是一份可以独立交给模型制作 AI / 美术团队的交付标准。** 交付内容是一个完整角色包，不是几张效果图，也不是需要应用团队重新拼装的散件。与本文一同提供 `character-sdk/`，尤其是 JSON Schema、校验器和真实样例。

当前宿主的作者/听众边界、固定封面和每角色专属音乐要求另见[角色集合标准](character-collections.md)。`parameters` 声明制作与作者配置能力，不表示订阅者可在会话中改写作者定义；音乐/静音和记忆等个人数据不放进模型包。

当前适配环境：Unity 6000.3.25f1、URP 17.3、glTFast 6.16.1，iOS / iPadOS 17+，iPhone 17 / iPad Pro 11 英寸为主要验收设备。源包本身不依赖 Xcode 工程、Unity GUID 或绝对路径。新的角色以构建时导入接入 App。

## 1. 必须交付的目录

```text
my-character/
  character.json       # 完整、机器可验证的角色声明
  model.glb            # 网格、PBR 材质、嵌入贴图、骨骼、morph 和所有声明动画
  LICENSE.txt          # 模型、贴图、动作等所有来源及使用条件
  README.md            # 制作说明、已知限制、检查方法、软件版本
  previews/            # 建议交付正面/侧面/背面/近景/动作接触检查图
  source/              # 建议交付 .blend 等可继续编辑的源文件；超过包预算时作为配套母版单独交付
```

`character.json` 位于根目录，不放进第二层同名目录。运行时必需资源全部在包内，GLB 内的 buffer 和 image 必须嵌入；不得包含外部下载 URL、绝对路径、`..`、符号链接、C#/JS/Python/动态库/可执行脚本/Shader 源文件/UnityPackage。

每个交付资源列入 `files` 的 SHA-256 与字节数；由 SDK `seal` 自动生成，制作方不要手工编造哈希。单资源不超过 128 MiB，完整源包不超过 256 MiB，最多 512 个文件。大型 DCC 母版可以另附，但模型运行所需内容必须完整留在 XCP 内。

## 2. 两个交付档位

**基础可接入档**：模型和材质正确、有头部绑定、有 Idle、至少一个自然招呼动作、头部互动回退、视线限幅、完整授权、通过校验。没有独立眼球、表情或口型时必须真实声明缺失；平台会保留模型基本展示，不能用“已接入”冒充完整对话表演。

**原作保留型导入例外**：如果用户明确要求只保留来源模型自带内容，则原作忠实度优先于补齐上述会话表演。只提供真实来源的 Idle（可由原站姿与原 additive 呼吸合成），没有原始招呼/摇头/视线时不自行补充；保留原形变资源与来源证据，撤回的是宿主后加映射。

**精致对话角色档（本项目新真人角色的制作目标）**：在基础档上，必须提供细节合格的成年人物、自然面部、独立眼球、眨眼、情绪表情、口型、待机呼吸、倾听/思考/回答的小动作、清晰的近景材质、稳定的头发和衣物、符合移动预算的 LOD 母版，以及后面列出的动作和视觉验收。LOD 目前不是运行时自动切换能力，交付的 `model.glb` 必须自身满足预算；另附 LOD 资产供后续编译器扩展。

不能用高面数代替高画质。发丝轮廓、眼睛湿润感、皮肤色彩与法线、衣物剪裁与纹理一致性，比堆积不可见顶点更重要。不要把照片贴在平面头上当写实角色，也不要用无授权人物扫描数据。

## 3. 模型、坐标、蒙皮和材质

1. GLB 2.0，采用 glTF 标准坐标与单位；推荐 DCC 中按米制作。通过 `source.scale` 归一到约 1.5–2 米的成年人体高度，角色导入后站立在地面，脚底不漂浮。
2. 必须在 Unity 导入预览中确认正面朝向平台的 +Z；`source.yaw` 是静态导入朝向修正，不能用来驱动对话动作。提交前做正面/背面核验，不靠猜 DCC 导出轴。
3. 原点、缩放和绑定姿态稳定；不使用负缩放。应用会根据中立网格把角色水平居中、脚底对地。动画不得改写整个角色根对象的全局位移/尺度；需要跳跃时用内部骨骼驱动。
4. 名称采用稳定可读标识，同级节点不得重名，名称不含 `/`。骨骼不强制固定语言命名，**manifest 提供准确相对路径**。路径相对于导入实例根，不包括文件名或 Unity 场景根。
5. 头、颈、眼应有合理的局部轴和蒙皮权重。皮肤、头发、衣物变形不能靠程序自动猜测；模型制作方对动作期间的碰撞和穿插负责。
6. 保持 mesh / morph 的顶点数量与拓扑一致，权重归一、无非法骨索引、无 NaN/Inf、无断裂法线。建议最多 4 骨影响/顶点，单 skin 不超过 256 joints。
7. 使用 glTF metallic-roughness PBR。颜色贴图按颜色空间处理，法线/粗糙度/金属度按线性数据处理。透明尽量用裁剪并减少叠层，尤其是头发；半透明发片堆叠会明显增加移动 GPU 开销。
8. 推荐主贴图 2K，近景脸/头发有依据时使用 4K；不因“极高画质”无差别铺 8K。纹理在应用编译阶段压缩，制作方保留无损源。
9. 当前预检允许的必要 glTF 扩展：`KHR_materials_unlit`、`KHR_texture_transform`、`KHR_materials_emissive_strength`。不要声明 Draco/KTX2 等尚未纳入本项目验收的必要解码依赖。
10. 不依赖自定义 Shader。特殊皮肤、毛发、多层折射等材质需要后续材质能力及适配器；不能通过塞脚本绕过。

**硬性移动源预算**：GLB 总 POSITION accessor 计数不超过 300,000，普通 profile 的 primitive 不超过 32，单 skin joint 不超过 256。已声明 `core.avatar-controls@1` 或 `core.materials.liltoon@1` 的完整可移植 profile 允许最多 64 个存储 primitive；后者必须提供 schema 2 的 `liltoon-properties-v1` 材质数据，不能只添加能力名放宽预算。存储 primitive 包含作者隐藏配件与叠加材质 pass，不等于默认穿搭的 draw 数。它们是拒收上限，不是推荐达到的目标。推荐精致角色约 50k–120k 可见三角形、尽可能少的材质和透明覆盖，具体以完整场景的 GPU/CPU 实测为准。

## 4. `character.json` 清单

完整字段约束以 `character-sdk/schemas/character.schema.json` 为准。先复制真实样例再替换，不能只交下方片段。

| 字段 | 要求 |
|---|---|
| `schemaVersion` | 当前为 1 |
| `id` | 稳定小写 slug，3–64 字符；不使用内置的 studio-robot / hatsune-miku / real-woman |
| `packageId` | 制作方反向域名标识；与角色 ID 一起长期稳定 |
| `packageVersion` | `major.minor.patch`；版本变化记录在 README |
| `display` | 名称、简介、邀请语、标签、SF Symbol、缩略图资源名、排序、风格、卡片/打开标识；标识全局唯一 |
| `compatibility` | API 主/次版本、required、optional 能力 |
| `source` | `format:"glb"`、相对文件名、scale、yaw；外部包不能使用 builtin |
| `rig` | 头/颈/左右眼/头部 Renderer 路径和 conversationStart |
| `gaze` | 产品范围内的头眼舒适角度上限 |
| `actions` | 逻辑动作 ID 到 GLB clip 的映射、语义、按钮、取景与视线策略 |
| `expressions` | 表情 ID → 一个或多个 morph 权重 |
| `speech` | none / amplitude / viseme 与独立口型 morph 映射 |
| `effects` | 星光/爱心预设参数 |
| `interactions` | 热点 ID、骨骼、可选 Renderer、半径、语义事件 |
| `behaviors` | 情境事件 → 有优先级和冷却的 cue 列表 |
| `parameters` | 可保存的外观 morph、基础色或 variant 选项 |
| `performance` | 可选原作表现目录：表情、姿态、手势、耳尾、穿搭；见 [core.performance@1](06-performance-standard.md) |
| `license` / `files` | 许可作者来源与资源完整性列表 |
| `extensions` | 反向域名隔离的未来可选数据 |

`display.thumbnail` 为应用生成的资源名，例如 `Package_lan`，只用字母、数字和下划线；不能包含路径。缩略图由实际导入模型渲染产生。`cardIdentifier` / `openIdentifier` 推荐 `card-<id>` / `open-<id>`，供 UI 可访问性和验收使用。

从宿主 0.16.0 起，首页优先使用 `<display.thumbnail>Portrait` 的 512 × 512 真实头肩近景。`rig.headRenderer` 应绑定面部主体 Renderer，不能指向整套服装或房间；宿主据其变形后的范围和角色身高取景。无需额外交付 AI 绘制的角色头像或改变 XCP 1.1。导入、重建并保存 ViewerScene 后，用图形模式 Editor 执行 `CharacterPortraitBuilder.Export()`，再编译宿主，把新角色的默认头像收入 Asset Catalog；未生成时临时回退原缩略图。

作者在制作/创建流程保存脸型、肤色、发型、服装或角色包外观参数后，运行时可用独立相机生成匹配头像并缓存；昵称、姿势、背景和聊天取景不进入头像键。修改模型资源时同步增加角色包 `version`，使旧头像缓存失效。头像失败不阻止打开角色，下次打开可重试。发现页/角色简介使用的固定封面另由 `CharacterCoverCatalog` 按 `runtimeID` 关联，不使用听众个人 profile 重生成；当前自建实例继承基础封面，详见集合标准。

必须声明 `core.animation@1`，并提供 `Idle`。`core.gaze@1`、`core.behavior@1` 与 `core.expression@1`、`core.speech.amplitude@1`、`core.speech.viseme@1`、`core.interaction@1`、`core.effects@1`、`core.parameters@1`、`core.performance@1` 按实际启用能力声明。没有声明 `core.gaze@1` 时，宿主不叠加头颈/眼睛朝相机跟随。原作保留型角色允许仅声明源站姿/源呼吸的 Idle、空的 interactions/behaviors/expressions/effects；不能为了凑基础对话体验而添加用户未要求的第三方身体动作。

**未知必要能力会拒绝导入；未知可选能力会忽略并告警。** optional 不表示可以把损坏资源放进已知字段：当前认识的表达式、动作和参数仍须全部绑定有效。

## 5. 骨骼与自然视线

```json
"rig": {
  "head":"Rig/Hips/Spine/Chest/Neck/Head",
  "neck":"Rig/Hips/Spine/Chest/Neck",
  "leftEye":"Rig/Hips/Spine/Chest/Neck/Head/EyeL",
  "rightEye":"Rig/Hips/Spine/Chest/Neck/Head/EyeR",
  "headRenderer":"Face",
  "conversationStart":0.58
},
"gaze":{"yaw":50,"up":22,"down":28,"eyeYaw":12,"eyeUp":8,"eyeDown":10}
```

`head` / `headRenderer` 必需，头部 Renderer 应尽量是独立的头部表面，不能用整个身体代替，否则“摸头”会误触全身。左右眼必须成对；没有独立眼球时两个路径填空字符串。`neck` 可为空。上限可以收紧，不能超过头部左右 50° / 抬头 22° / 低头 28°，眼部左右 12° / 上 8° / 下 10°；必须为正数。

平台会在目标超过合理侧后方或极端俯仰时逐步释放视线，不会强行扭头 180°。动作的 `gaze:"release"` 用于鞠躬等明确低头，`soft` 用于摇头，`follow` 为常规自然注视。作者仍须检查大动作与跟随叠加后的颈部、领口、头发、眼球。

## 6. 动作

动作全部导出进 GLB，曲线必须连续；Unity 编译器按 manifest 的 `clip` 找资源，并以 `id` 注册。逻辑 ID 不必等于原 clip 名。外部资源使用自己的骨骼和动画，不依赖通用 Humanoid 自动重定向。

```json
{"id":"Hello","clip":"Greeting_Take_02","semantic":"greeting","label":"挥手","symbol":"hand.wave","button":true,"framing":"full","gaze":"follow"}
```

`Idle` 是保留逻辑 ID，必须存在并自然循环；非 Idle 默认一次播放后平滑回待机。非 Idle 时长建议 0.6–8 秒，过长舞蹈先分段。动作交叉淡入约 0.24 秒，回待机约 0.18–0.28 秒；首尾应接近中立姿态，不能依靠淡入掩盖一帧巨大跳变。

- 精致角色建议语义：idle、greeting、agreement、disagreement、gratitude、encouragement、celebration、listening、thinking、speaking、head-touch、farewell、surprise。
- `framing` 仅 `full` 或 `conversation`。大动作使用 full，点头/摇头等局部动作使用 conversation。平台为每个 clip 烘焙全时域包围盒，保留已有弹性取景过渡。外部包单个动作范围超过中立模型大小 6 倍会被拒绝，防止错误单位、离场根位移或缩放让镜头拉到远处。
- 当前没有根运动导航、循环舞蹈状态机、任意部位动作混合、双人接触 IK。需要这些功能时声明新的必要能力并与应用团队协商，不能给当前包写一个虚假的 `supported:true`。
- 尽量避免把表情、说话口型和服装切换烘进大动作；不同通道要能分别控制。

## 7. 表情与说话口型

表情不是贴图替换截图，要提供真实 morph。名字任意，由清单映射，例如：

```json
"expressions":[
  {"id":"joy","bindings":[{"renderer":"Face","shape":"Smile","weight":0.75}]},
  {"id":"care","bindings":[{"renderer":"Face","shape":"BrowConcern","weight":0.3}]}
],
"speech":{
  "mode":"amplitude",
  "amplitude":[{"renderer":"Face","shape":"JawOpen","weight":0.65}],
  "visemes":[]
}
```

权重单位 0–1，由运行时按该 morph 自身的满量程换算（旧角色通常是 100，glTF 导入可以是 1）。`neutral` 是内置释放表情状态，不需要制作一个空 morph。推荐 joy/care/sad/surprise/anger/blink，但必须以自己确实做出的形变为准；不能给没有笑容能力的模型谎填 Smile。

当前 TTS 使用实际播放音量驱动开口，**不是逐音素准确对口型**。运行时已经能接收带播放时间的 viseme 权重。准备升级的制作方可交 `aa / ih / ou / ee / oh / sil` 等明确定义的口型，并在 `speech.visemes` 里映射；只有将来或外接的语音提供方真的产生这些帧时，才会按对应口型播放。

`speech.proceduralHeadMotion` 是宿主附加的倾听/思考/说话头部小动作开关；省略时为 `true`，旧包行为不变。只保留原作者动作的包应设为 `false`，口型映射仍按原配置工作。该字段不关闭作者自己制作的动画轨道；它与是否允许自动目光跟随分别配置。

口型和情绪不得共用同一个 morph；外观参数也不得占用表情/口型通道。眨眼可保留在自然 Idle 中；做强烈表情时检查眼睑是否穿透眼球。多个 viseme 指向同一 morph 时运行时累加后限制最大权重，防止后一个绑定覆盖前一个。

## 8. 情境行为规则

```json
{
  "id":"comfort",
  "eventName":"dialogue.reply",
  "emotion":"care",
  "priority":40,
  "cooldown":6,
  "probability":1,
  "minIntensity":0,
  "cues":[
    {"channel":"expression","target":"care","fallback":"neutral","delay":0,"duration":2.5,"intensity":0.8,"required":false},
    {"channel":"body","target":"Comfort","fallback":"Hello","delay":0.15,"duration":2,"intensity":1,"required":false},
    {"channel":"effect","target":"warmHeart","fallback":"","delay":0.3,"duration":2,"intensity":0.6,"required":false}
  ]
}
```

事件和 emotion 精确匹配。emotion 空字符串表示不限制；`minIntensity` 是触发阈值。所有匹配规则按声明顺序处理，后续同优先级可替换同通道，作者应避免多个无意冲突的规则。cooldown 单位秒，delay / duration 单位秒；随机概率 0–1。最长 cue delay / duration 15 秒，rule cooldown 最长 120 秒。

当前 channel：

| 通道 | target | duration 含义 |
|---|---|---|
| body | actions.id，Idle 除外 | 身体占用实际 clip 时长，cue duration 不截断动作 |
| expression | expressions.id 或 neutral | 保持表情多久，然后平滑回中立 |
| effect | effects.id | 调度占用时长；粒子寿命由受控预设决定 |
| gaze | camera / release | 跟随或暂时让权多久 |

默认事件见 [接口规范](04-character-api.md)。缺失目标尝试 fallback；均不可用且 required=true 时预检拒绝，optional cue 则允许跳过。不要把制作方任意文本作为需要执行的脚本。

## 9. 触摸与特效

```json
"interactions":[
  {"id":"head","bone":"Rig/Hips/Spine/Chest/Neck/Head","renderer":"Face","radius":0.1,"eventName":"interaction.head.tap"}
],
"effects":[
  {"id":"warmHeart","kind":"hearts","anchor":"chest","color":"#EFA9AC","count":7}
]
```

保留 `head` 区域且 renderer 等于 `rig.headRenderer` 时，用当前动画头部网格做精确射线命中；其他区域当前为骨骼球形热点，radius 按模型源坐标并乘角色源缩放，按声明先后命中首个区域。`renderer` 对普通球形热点仅用于作者标记，不改变球形检测。触摸防抖 0.35 秒，不把拖拽误判成轻点。

特效目前只有 `sparkles` 和 `hearts`，anchor 为 head/chest，count 1–24。胸前为基于头部与身高的公共近似锚点；需要精确手部、道具和任意场景节点锚点时应升级效果能力。

## 10. 可保存的外观参数

| kind | 绑定 | 保存值 |
|---|---|---|
| morph | path=SkinnedMeshRenderer，property=正向 morph，可选 negativeShape | 默认 0–1；成对负向/正向时 0.5 为中立 |
| color | path=Renderer，property 固定 `baseColor`，materialSlot 从 0 开始 | options 中十六进制颜色的整数下标 |
| variant | 每个 binding.path 指向一个可开关对象，顺序对应 options | 选中对象的整数下标 |

color / variant 的 min 必须 0，max 必须 options.length−1，至少两个选项。不能重排已经发布的 options，否则保存的“选项 1”会变成另一件衣服。允许添加新选项但仍需兼容审查。对所有外观极值组合检查脸部、身体和服装穿模；不能只检查滑块初始位置。

variant 第一版是对象可见性切换，尚无换装网格交叉淡化；如产品要求换装也连续变形，应先新增能力再使用。颜色和 morph 调整已有平滑插值。variant 应只指向衣物/饰品视觉分支，禁止关闭头、眼、骨架或被动画/表情绑定的关键节点。

## 11. 验收清单与性能

制作方需要交付以下结果，不得只回复“应该可以”：

- SDK seal / validate 完整输出 PASS，所有警告解释清楚；GLB 中所有声明 clip、morph、节点都存在。
- Unity 绑定、蒙皮、材质、有限值、动作取景验证 PASS；预览图是实际模型渲染。
- 正面/侧面/背面、近景/全身、三个背景光照、头部触摸、每个动作、所有表情、口型、外观极值的截图或录像。
- 重点检查发片透明排序、头发穿肩、手穿脸/胸/腰、裙摆/裤腿穿插、眼睑与眼球、牙齿舌头、颈部极限、脚底地面、阴影偏移。
- 聊天→听→想→说→打断→新对话→关页面→再进入；动作抢占、低优先级不抢用户操作、延迟 cue 不串到下一轮。
- iPhone 17 和 iPad Pro 11 真机在完整聊天界面与语音同时工作时记录 CPU/GPU、内存、帧时间和发热，持续运行而非只看静止截图。

目标档位：60 Hz 下每帧预算约 16.67 ms，120 Hz 下约 8.33 ms。目标帧率不是“每帧严格达标”的保证；刷新率、热状态、低电量、其他系统负载和内容复杂度都会影响结果。**模拟器不能证明真机 120 FPS。** 若不能满足预算，应降低透明覆盖、材质次数、不可见几何和纹理负担，并按平台性能策略降级，不能虚报。

## 12. 最终交付与升级

打包成 `<id>-<packageVersion>.xcp`，同时提供可继续修改的 DCC 母版、制作记录、授权清单、验收报告。README 列出“已实现 / 缺失 / 需要后续能力”的清单；写实质量、准确口型、物理防穿模都不能靠标准声明自动获得。

更新保留角色 ID、包 ID、动作/表情/外观参数语义，先跑 `compare`。新增必要能力、删除资源语义、改变参数范围或选项含义属于需要迁移或新主版本的变化。任何兼容性保证都以旧样本和保存数据回归为证据。


## 13. 可选二次运动扩展（星夜 0.28）

本轮实际样例为 `character-packages/imported/anime-vita`、`anime-shino`、`anime-fumiriya`。它们仍是完整 GLB + JSON 的 XCP 1.1 包，导入后不下载脚本。兼容能力 `core.secondary-motion@1` **只放 optional**；旧宿主保持静态头发降级，基本动画、表情、触头均继续使用原有标准。

本适配器读取包内 `secondary-motion.json`：`schemaVersion:1`，`strands:[{bone,tip,radius,angle}]`，`colliders:[{bone,offset:{x,y,z},radius}]`。路径均为导入根相对路径，tip 必须是 bone 的直接子级，最多 128 段、64 个球；发链半径 0–0.05 米、偏角 1–20 度；碰撞球半径 0–0.5 米，所有数值有限。坐标为导入后的 Unity 局部坐标，不能直接忽略 glTF 手性差异复制偏移。推荐发链 16 度以内、裙摆 8 度以内；不加入身体部位弹跳。当前球约束和摆角限制不能代替完整布料模拟或任意动作下的穿插验收。

可选 `ambientHairAngle` 范围 0–4 度，省略为历史默认 2.2。设为 `0` 禁止宿主附加微风，保留已声明骨链的受力惯性适配；该适配仍不等价于 VRChat PhysBones 原始积分器。只保留来源动作的导入不得自行添加待机风、眨眼时间表或表情混合。

同时交付 `materials.json`（schemaVersion 1，materials 数组）和 `textures/` 内嵌图像的无损导出副本，可复用本轮移动端柔和二次元材质适配器。每项包含 name、texture、color（glTF 线性 RGBA 对象）、alphaMode、cutoff；只允许包内相对图片路径。对应 Shader 由宿主提供，不从包内执行 Shader。当前三个 anime 包的纹理编译为最高 2K、ASTC 4×4、mipmap。普通角色仍可只交付标准 GLB 材质；这是可选的本地构建扩展，不意味着任意 VRM 可原样导入。扩展文件和图片全部纳入 files 哈希。

新来源的动作必须先还原源骨架的世界静置方向，再进行重定向。不能假设同名骨骼有同样的局部轴。详见 `scripts/prepare_anime_characters.py` 与 `scripts/tests/test_anime_characters.py`：后者包含腿部轴翻转、源到目标旋转、首尾归位、稳定下肢和移动端资源预算的回归约束。源动画采样 30 Hz 不限制连续插值后的显示帧率，但仍需实际设备测量。


### 导入角色的固定近景（0.38 起，可选）

`rig.portraitWidthScale`：1–1.5，省略为 1。用于头身比较大的角色扩大近景横向包围范围，避免面部被放得过大、落到聊天交互层。它由作者固定，不是用户缩放控件；不改变物理几何、动作 bounds 或全身取景。旧包默认 1，原取景不变。Mamehinata 的 iPhone 会话使用 1.4；来源、实际渲染、触碰都须验证，不能对所有模型套相同参数。

VRChat 来源转换的可复用流程见项目技能 [vrchat-character-import](../../.agents/skills/vrchat-character-import/SKILL.md)。

### 默认沉浸取景与用户缩放（0.74，运行时 v14）

角色继续交付现有中性骨架、眼/面部参考和静置网格，无新增必填包字段。宿主通过 `CharacterPortrait` 和中性网格顶点识别头部保护区，包含头顶、耳朵与帽饰；腰部、尾巴和垂下的长发不再误用为头部的深度/高度。初始镜头在首次可见帧前完成近景合成，硬件安全区由原生视口提供，不能再重复加一层顶部百分比空白。

`rig.portraitWidthScale` 仍可扩展头部采样横向范围，但不能因此退回旧的腰部包围框。v14 通过纵向和深度参考识别同一近景，保留原包宽度参数；审查使用真实作者参数，不只测默认值 1。

默认比例为 1，须给放大和缩小两侧保留操作空间；几何验收至少检查可放大到 1.20、可缩小到 0.75，同时覆盖 0.50 的更宽取景与 1.28 的上限。平移和缩放按中性头部边界适配，单指旋转不附带自动平移或缩放。眼位、头饰特别大的角色仍须逐一实际查看，不能仅凭角色总身高或渲染包围盒认定适配完成。

`CharacterViewEditorReview.Run` 在当前名册全部角色和五种手机视口中验证几何与旋转不变量；`CharacterPortraitCompletionTests` 通过实际 iPhone 模拟器路径检验发现封面、资料卡、默认取景、双指放大/缩小、复位。数值检查、实际画面验收与真机帧率应分别记录。
