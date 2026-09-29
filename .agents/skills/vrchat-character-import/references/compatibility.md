# VRChat → Unity URP / XCP 兼容与转换依据

本参考用于当前仓库的数据转换，不是通用 VRChat 上传教程。版本、能力和工具状态记录于 2026-09-29；复用时检查本机文件与 `--help`，不要把本文日期冻结成未来依赖版本。

## 当前实现状态与前置

| 项目 | 已有证据 / 能力 | 仍需注意 |
|---|---|---|
| `scripts/audit_vrchat_archives.py` | ZIP / unitypackage 有界提取、输入哈希、FBX / YAML 清单、动画分类、Prefab 覆盖、物理原值、外部 GUID | 不导入 Unity；不能独立解析所有 Unity hashed fileID，也不证明动作可播 |
| `scripts/vrchat_materials.py` | 按 GUID 解析 `.mat`、贴图、FBX 材质 remap，输出原始设置与显式近似提示 | 不改图、不转换 Shader，不决定网格可见性 |
| 受信任 `VrcSourceInspector.Export()` | `scripts/vrchat/VrcSourceInspector.cs` 已由 stage 准备器复制并运行，产出 `Inspection/*-fbx.json`、`*-prefab.json` | 从 `InspectionConfig.json` 读取角色 specs；支持数据检查，不是任意 Avatar 的通用转换器 |
| stage 创建/填充 | 已有本地隔离工程和实际检查产物 | `scripts/prepare_vrchat_stage.py` 带白名单复制与哈希检查；新机器仍须准备许可/Editor/依赖 |
| `scripts/prepare_vrchat_characters.py` | 两个角色数据转换、会话九动作 + 原作 performance、有效动态 morph 保留、米制统一、XCP seal | `--only`、`--output-root`；新角色需新增经验证的 recipe |
| 生产运行时 | Unity 6000.3.25f1、URP 17.3.0、glTFast 6.16.1、Unity Toon Shader 0.15.1-preview | 未引入 VRC SDK / lilToon / UniVRM 运行时 |

前置检查应确认：源 ZIP 可读且哈希已锁定；输出磁盘空间足够；仓库 Python 工具可执行；Unity 版本与模块按实际目标已具备；当前没有其他任务写同一个 stage / 生产工程。脚本的 `--help` 不能代替检查它调用的 Blender、Unity 或 Python 依赖，等转换实现稳定后依其实际导入和子进程清单核实。

本地两款试样是 `Kipfel_1.0.3.zip` 与 `Mamehinata1.53.zip`。源 ZIP 哈希、原作者链接、详细来源统计和公开许可版本见[可行性研究](../../../../docs/design/2026-09-29-vrchat-feasibility-research.md)。本技能不自动下载模型，也不假设提供一个新 ZIP 就已支持它的全部骨架、材质或动作。

## 许可与无 SDK 路线

模型数据、模型附带第三方动作、Shader、SDK 是四种不同来源。代码开源不等于模型开放；模型许可也不会扩大 SDK 的使用范围。

当前两款作者公开 v1.60 许可允许个人使用、格式转换和修改；对外嵌入软件分发以及法人使用需要对应授权。该现行条款与旧购买时是否另有协议分开记录；不要自行断言追溯效力。本人电脑和自己的手机进行本地试样，与 App Store、对他人的 TestFlight / 安装包、公开模型下载是不同工作范围。继续完成已经授权的本地工作，不建立重复购买证明或人为审批环节。[作者日文许可](https://docs.google.com/document/d/1mXlf8pAX7fZ0Y4VjRhX4i_tYtQq2O8WrBSRu1J8Gf_M/edit)

VRChat 材料许可限制 SDK 材料的平台外用途。不要复制 SDK DLL、示例素材或默认 motion 到 App，也不要反编译 PhysBones 来复刻实现。独立使用作者 FBX/PNG/原创 `.anim` 数据，以现有引擎和项目运行时实现角色行为。[VRChat SDK 许可](https://hello.vrchat.com/legal/sdk)

未来要向他人分发时，核对那一阶段的许可范围；转换过程中可把试样标为本地专用。不存在“换格式/改名/加密/免费/只能观看就自动解除许可”的规则。也不要从条款未出现 AI 一词，推导出训练、公共 AI 角色服务等所有用途都获准。

## 原装 Prefab 是默认外观依据

按如下优先级重建：主 Prefab 的有效实例状态 → 嵌套 Prefab override → FBX importer 材质映射 → FBX 自带默认状态。最终应保存明确的 renderer / material / morph 对应表。

需要读取：

- `activeInHierarchy` 与 `SkinnedMeshRenderer.enabled`，以及是否只是菜单里备选的配件。
- 材质槽顺序与重覆 slot；同 mesh 额外 slot 可能是第二次绘制的假阴影，不是多余错误。
- 默认 blendshape 权重。它可能让衣服贴合原穿搭；丢失后即使脸部表情正常也会穿模。
- 实例 Transform 位置、旋转、缩放与来源 GUID/fileID。`.meta` 中没有 `internalIDToNameTable` 时，不靠名字猜 hashed fileID。

本地 Inspector 的具体发现：

| 角色 | 裸 FBX 与主 Prefab 的差异 |
|---|---|
| Kipfel | 主 Prefab 默认隐藏 `Cat_Ear`、`Item_Glasses`；眼镜和上衣有默认形变；`Hair_Front` 加了 `Hair_fakeshadow` 材质槽 |
| Mamehinata PC | 主 Prefab 的骨架与可见 Renderer 已实际导出；配件有约束关联，不能把裸 FBX 当完整状态机 |

这只是默认状态快照，不证明 FX 初始状态、所有服装切换或原平台动态已经运行。Inspector 观察到 Prefab 有 Missing Script 是无 SDK 检查的预期结果：Kipfel 47 个、Mamehinata 24 个；这不是安装 SDK 的理由，也不是可忽略一切组件语义的理由。记录原始数据，逐项决定转换用途。

`Body`、`Body_Base`、`Under*` 等名字不代表重复垃圾；一些身体或内衬确实属于默认外观。一律删除或全部保留都会错，应结合可见性、默认 morph 和实际画面做决定。

## 坐标、骨轴与动画

导入后检查米制比例、正面方向、根节点居中接地、bind pose、蒙皮权重、关节层级和左右映射。FBX 的前向/上向标记、DCC 导出转换、Unity 实例旋转和 glTF 手性会共同影响最终结果；不要对每个模型机械套用一次 180° 旋转。

头、颈、眼的骨轴应通过小幅受控旋转和真实渲染核对。模型声明的 head Renderer 必须对应头面范围；绑定整个身体会造成摸身体也判定摸头。瞳孔、头发和帽子不能误当面部主体；需要时拆分合法网格，而不是扩大命中范围掩盖错误。

| 输入数据 | 应有处理 |
|---|---|
| Humanoid muscle clip | 验证 Avatar，再由普通 Unity Animator 采样为自身骨骼 Transform；不是改扩展名或复制 muscle 名称 |
| Transform clip | 保留并核对路径、局部坐标与目标骨架，处理根运动和尺度 |
| 0 秒 pose | 当静态姿势；要制作过渡或持续姿势，不能直接计为自然身体动作 |
| Additive 呼吸 | 基于正确参考姿势合成/烘焙；避免把加法偏移当绝对骨旋转 |
| FX blendshape | 会话语义使用 `expressions`，显式原作目录使用 `performance.morphs/morphTracks`；口型独立 |
| 服装显隐 / 材质切换 | 作者默认外观或显式 variant；不作为身体动画播放 |
| 外部 motion GUID | 记录未解析；确认原作者/其他可用来源，不自动补 VRChat SDK 默认动作 |

当前生产 `CharacterPackageBuilder` 删除外来 Animator，并注册 GLB 的 Legacy clips；运行时没有通用 Humanoid 重定向。最终输出必须内含真实曲线，并保证 manifest 每个动作 ID 都能找到对应 clip。

Kipfel 有真实呼吸、耳尾及入睡/睡眠/起身序列；Mamehinata 有呼吸和耳尾。它们分别还有大量零时长手势、表情和服装动画，所以 99 / 64 个文件不是 99 / 64 套表演。缺少的问候、倾听或回应需单独制作或采用许可清楚的素材。

## 物理、约束和触碰

读取原始 root、chain、collision / ignore 引用、标量与曲线，但不要把数值直接复制成“等价 PhysBone”。原骨架长度、坐标和执行顺序也影响结果。

| 来源 | 当前可用适配 | 需要记录的差异 |
|---|---|---|
| 发、耳、尾、裙骨 PhysBones | `core.secondary-motion@1` 与 `secondary-motion.json` | 是受限轻量动态；不是相同的积分器、力曲线、抓取、Pose 或网络交互 |
| 球形碰撞 | 重新计算局部偏移与半径 | glTF 手性和骨架缩放必须进入换算 |
| capsule / plane / 特殊限制 | 当前球近似，或暂不声明支持 | 应用效果验收后才能认定可接受，不编造一比一能力 |
| 固定配件约束 | 烘焙父子关系 / offset | 不能错误丢失位置或套两遍变换 |
| 依赖运动目标的约束 | 烘焙到具体动作；确有必要再扩展版本化能力 | 世界冻结或外部目标不自动受支持 |
| ContactReceiver `Pet` | 现有头部热点 → 互动行为和表情/动作 | VRC Contact 不是手机触摸事件源 |

当前次级运动数据最多 128 段和 64 个球，tip 必须是 bone 的直接子级，摆角 1–20°，链半径 0–0.05 米，球半径 0–0.5 米。需要检查相邻链连续性、头肩/衣发碰撞和 Idle/说话/姿势叠加；不要给身体部位增加无依据的弹跳。

同一骨骼不能同时被烘焙耳尾动画、通用 Idle 和物理各自强行覆盖。明确每个通道的控制范围，再观察切动作后的稳定恢复。缺失组件原值是转换线索，不是允许复制其受限运行库的依据。

## 材质还原与移动端取舍

`source-materials.json` 的 `source` 是原始设置，`conversionHints` 是带限制的推测，不能当成完成的 PBR 还原。Prefab 材质槽优先于 FBX importer remap。

已知会明显改变外观的陷阱：

- **Smoothness=1 不必然意味着镜面。** lilToon 中反射可能关闭；直接写 roughness=0 会把布料和皮肤变成塑料。
- **Kipfel 眼部发光有独立 mask。** 丢掉 mask 会把整个眼部贴图一起发亮，降低眼睛细节。
- **Mamehinata Outfit 启用了两层 MatCap。** MatCap 随视角变化；它不是普通底色，也不能声称一张 PNG 已无损保存该效果。
- **`Hair_fakeshadow` 是特殊 blend。** `SrcBlend=0, DstBlend=3` 是乘色类绘制，不应凭名称或带 alpha 就自动变成普通半透明材质。
- **主色、HSVG、分层贴图、UV 变换和颜色空间需一起还原。** 不仅仅是 `_MainTex` 文件。

当前可走 `materials.json` + Unity Toon Shader，按已有字段映射底色、阴影、法线、MatCap、发光和描边。特殊效果先固定为合理的作者状态并记录损失；不把自定义 Shader 塞入 XCP。若必须增加材质能力，先形成独立宿主适配变更，再验证所有原角色。

lilToon 有 Unity 6 / URP 的官方修复记录，不能笼统认定不兼容；但这不证明当前版本组合与 Metal 已测。保留 lilToon 应是锁版本的独立对照实验，不是忽略材质转换的捷径。[lilToon 官方更新](https://github.com/lilxyzw/lilToon/blob/master/Assets/lilToon/CHANGELOG.md)

最终移动端按实际画面选 ASTC、mipmap、脸/发分辨率和透明策略。保留无损源，在编译产物中控制重复贴图、无用 morph 和未穿戴衣物；先减少不可见成本，再考虑削减影响面部和头发轮廓的细节。

## XCP 交付和可观察验证

包至少包括 `character.json`、自包含 `model.glb`、`LICENSE.txt`、README，必要时加入材质与次级运动 JSON。遵守当前 Schema 和数据文件白名单，seal 真实字节数与哈希；不要自行杜撰外部包 ID、能力版本或导入器选项。

当前预算见[角色规范](../../../../docs/character-standard/02-model-production.md)：单资源 128 MiB、包 256 MiB，GLB POSITION accessor 合计 300,000、primitive 32、单 skin 256 joints。原 FBX 面数不能代替这些检查；形变、UV/法线分裂和材质 slot 会影响导出结果。

验证顺序应让失败可定位：

1. **静态**：路径/GUID 来源可追踪，默认可见性和 morph 已还原，必需资源齐全，没有未知必要 glTF 扩展或可执行内容。
2. **骨架/动画**：头眼方向、脚底接地、Idle 循环、表情与口型独立、动作后回中立；Root 不出现意外平移或缩放。
3. **画面/触碰**：手机比例实际截图，脸、发、眼、衣服近景可比；实际点击头部触发动作，身体区域不误触；耳尾不抖散、头发不穿脸。
4. **宿主集合**：封面/头像来自对应模型，背景/动作/声源/音乐隔离，切角色不覆盖其他角色配置，首次出现直接采用最终取景。
5. **设备性能**：完整会话场景的 CPU/GPU 帧时间、长帧、内存和持续温度条件；模拟器只作功能/画面验证。60 FPS 是 16.67 ms、120 FPS 是 8.33 ms 的预算，不由 VRChat 评级或 `targetFrameRate` 自动保证。

报告区分“静态解析成功”“Unity 导入成功”“视觉达标”“真机性能达标”。当前正在建立的转换链路尚不能替任意 VRChat 角色作出最后两项承诺。


## 本轮实现的具体边界

两包使用主 PC FBX（未使用 Quest 低模），骨架保留 181 / 99 个 bones。1.1.0 表现扩展保留 Kipfel 默认隐藏的 Cat_Ear / Glasses，并由 Renderer defaults 关闭；保留可切换的原默认非零形变，仅将其余静态默认形变烘焙。原有 8 个会话动作加 Idle 来自已锁定的 Overte/Hanami 源，新增作者原作 Transform 与动态 morph 数据独立采样，形成实际 82 / 48 个 performance 选项。当前 GLB 保留 177 / 84 个 morph 通道，不能沿用初版仅 15 个形变的描述。具体流程、坐标转换与省略项见 [表现迁移参考](performances.md)；不声称支持完整 VRChat FX 状态机或 SDK 默认动作。

Blender glTF export 的实际参数是 `export_use_gltfpack`，不是 `export_gltfpack_enable`。稀疏 morph accessor 会展开成连续数据；numpy 读取 bytearray 后需 `.copy()` 再扩容，否则 BufferError。2 倍单位转换同时应用顶点、morph delta、节点平移和 inverse-bind 平移，运行时 root scale 保持 1。

材质扩展仅在 `sourceProfile=vrchat-liltoon-v1` 下生效，旧 VRM 的色阶与渲染不改。主贴图/色彩保留，发光在线性空间合成 mask 与 mainStrength，首层 MatCap 保留 mask；第二层 MatCap、Kipfel stencil fake shadow 未渲染，连续透明近似为 cutout 并逐项报告。不要将近似版描述为 lilToon 无损转换。

物理 sidecar 有 103 / 41 段受限动态；capsule 近似为重叠球，plane 未映射，原始力曲线保存在 source audit。导入 review 第一张截图曾遇到 shader 尚未就绪的黑色轮廓，回归改为同姿态先 warm render 再 capture；实际 App 的角色进入还须验证准备门控，不能靠静态截图证明。
