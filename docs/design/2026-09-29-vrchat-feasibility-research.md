# VRChat 角色转入星夜：Kipfel / Mamehinata 可行性研究

研究日期：2026-09-29。目标环境：原生 iOS 宿主 + Unity 6000.3.25f1、URP 17.3.0、glTFast 6.16.1、XCP 1.1。

本次只读检查用户提供的两个 ZIP、包内文本与二进制结构，并查阅作者及平台原始资料；没有导入 Unity、执行来源脚本、改生产代码、下载其他模型或发布资源。本文是下一步转换的实施依据，不是已完成转换或真机性能验收的报告。

## 1. 结论

**两款都具备转换基础，建议转成我们自己的 XCP 角色包；不能把 VRChat Prefab / SDK / Animator Controller 原样放入 App。** 它们已包含真实蒙皮模型、丰富表情、贴图、Humanoid 映射与部分呼吸、耳尾、休息动作。工作量主要在动画烘焙、材质还原、次级运动重建，以及让头部互动、视线、表情和语音口型遵守我们的接口。

三项边界直接影响实施：

1. **个人本地测试与向他人分发应分开。** 作者公开现行许可允许个人使用、格式转换和修改，但在 2026-09-07 的 v1.60 中，把嵌入软件后分发改为需单独联系授权。不能由“可个人使用”推出“可作为公共 AI App 的内置角色”。具体依据见第 3 节。
2. **VRChat SDK 不作为我们的运行时依赖。** 官方 SDK 材料许可第 4.3(h) 限制将其用于 VRChat 平台外的软件。转换仅处理模型作者独立提供的资源；VRChat 默认动作、SDK 示例资源和动态组件不随之获得外部使用权。[VRChat SDK 材料许可](https://hello.vrchat.com/legal/sdk)
3. **可接入不等于原样还原，更不等于已经达到 120 FPS。** 近景画质、动作自然度、裙发碰撞和完整会话场景性能，都需要转换后实际验证。

推荐先用 Mamehinata 的 Quest 模型验证几何、表情与动画链路，再用其 PC 模型做画质对照；Kipfel 随后接入，优先保留其原创呼吸、耳尾和休息动作。Quest 版本是管线验证和性能基线，不自动成为最终高画质成品。

## 2. 本地包实际内容

检查对象位于 `/Users/gukaifeng/Documents/vrchar/`。ZIP 内的 `.unitypackage` 只在内存中读取 tar 的 `pathname` / `asset` / `asset.meta`；没有解包执行脚本。FBX 数据为直接读取二进制节点所得。

| 项目 | Kipfel_1.0.3.zip | Mamehinata1.53.zip |
|---|---:|---:|
| ZIP 字节数 | 249,230,754 | 150,941,220 |
| 主 FBX | `FBX/Kipfel.fbx` | `PC/FBX/Mamehinata.fbx` |
| 另附低模 | 未见独立 Quest / Mobile 角色 FBX | `Quest/FBX/Mamehinata_Quest.fbx` |
| 编辑母版 | `.blend`、PSD、PNG、UV | PC / Quest `.blend`、PSD、PNG、UV |
| Unity 动画文件数 | 99 | 64 |
| 其中时长为 0 的文件 | 68 | 55 |
| 其中时长大于 0 的文件 | 31 | 9 |
| Animator Controller 数 | 8 | 9 |
| 包内 `.cs` / `.dll` / `.asmdef` | 未见 | 未见 |

ZIP SHA-256：

```text
Kipfel_1.0.3.zip
b1b800389aa6b174b1565527a351c7ba41653f4debeb627180c5b34e45aec053

Mamehinata1.53.zip
ba8e9fd15f99db4b01cb304723965995a6a69b787310fe04d4bde48903845eb3
```

主 FBX 统计如下。三角形数是多边形索引扇形三角化后的结果；不是 Unity 导入后的顶点数、draw call 数或所有穿搭配件之和。

| 主 FBX | 三角形 | Mesh 节点 | Material 节点 | LimbNode 骨骼 | Shape 几何节点 | AnimationStack |
|---|---:|---:|---:|---:|---:|---:|
| Kipfel | 69,640 | 23 | 8 | 181 | 456 | 0 |
| Mamehinata PC | 55,855 | 13 | 6 | 99 | 253 | 0 |
| Mamehinata Quest | 14,984 | 2 | 1 | 99 | 221 | 0 |

Shape 节点包含不同网格的形变目标，不能当作独立表情数量；LimbNode 数也不能直接等同于最终每个 skin 的 joint 数。三个主 FBX 本身均没有 AnimationStack，实际动作在 Unity `.anim` 中。Importer 的 `animationType:3` 为 Humanoid，分别已有 51 / 53 / 51 个 `humanName` 映射；这提供了重定向基础，仍需验证实际骨骼方向和 T Pose。

贴图并不轻：Kipfel 独立源 PNG 中有 9 张 4K 方图，Mamehinata 有 12 张，此外还有 2K、Matcap 和预览等。此处排除了 UV 辅助图，但没有把源文件数量当成运行时必需贴图数量。应按最终穿搭和材质引用筛选，不能把所有源图一并常驻。

### 2.1 已确认的实际动画与姿势

| 类型 | Kipfel 例子 | Mamehinata 例子 | 接入含义 |
|---|---|---|---|
| 呼吸 | `kipfel_breath`，2.5 秒 | `Mamehinata_breath`，2.5 秒 | 可作自然 Idle 的输入，但要正确处理 additive 基准姿势 |
| 耳部运动 | `kipfel_CatEar_pyoko_loop`，约 8.43 秒 | `DogEar_Pyoko`，约 7.88 秒 | 可保留角色特色，不能与物理或其他动画重复驱动同一骨骼 |
| 尾部运动 | downwag 7 秒，upwag 约 1.67 秒 | DownWag 约 2.33 秒，UpWag 0.6 秒 | 限幅并检查与腿、衣物、坐姿穿插 |
| 连贯休息动作 | stand-to-sleep 约 7.83 秒、sleep-loop 6 秒、sleep-to-stand 约 11.17 秒 | 本次未确认对应的完整休息序列 | Kipfel 可作为坐卧/休息制作参考；接入仍需拆分一次性动作与持续姿势 |
| 零时长 pose / 设置 | 蹲、趴、手势、服装开关、表情等 | 手势、服装、表情等 | 是姿态/属性快照，不是自然挥手、走路或舞蹈 |

所以“有 99 个 `.anim`”不能写成“支持 99 个动作”。例如手势文件可能只改手指 muscle，FX clip 可能只改 blendshape 或 `m_IsActive`。部分控制器的 motion 指向包内不存在的外部 GUID；其具体来源需逐条解析，不能假定所有默认走跑、坐姿和 action 都随作者包获得了可用于 App 的授权。

## 3. 作者、原始出处与许可边界

两款原作者均来自 **もち山金魚 / かめ山（kameyama）**；推荐署名为 `©MOCHIYAMA KINGYO`。

- [Kipfel 官方 BOOTH](https://booth.pm/ja/items/5813187)：当前页面已列出 1.2.0，不能把新版 Mobile 支持当成本地 1.0.3 已有。页面另列 AFK 动作作者 STUDIO MOCA，转换后的来源说明应保留此贡献。
- [Mamehinata 官方 BOOTH](https://booth.pm/ja/items/4340548)：包含 PC / Mobile 规格。页面汇总面数与本次主 FBX 统计口径不同，不能混写。
- 两者官网都说明 VRM / PMX 等转换不提供支持。这是售后支持范围，不应改写成禁止转换。

### 3.1 现行许可原文

作者官网短链 [日文许可](https://mochiyama.com/license_jp)、[英文许可](https://mochiyama.com/license_en) 均指向作者公开 Google Docs。**日文优先**；实际核对的是 v1.60，更新日为 2026-09-07。

原文入口：[日文正文](https://docs.google.com/document/d/1mXlf8pAX7fZ0Y4VjRhX4i_tYtQq2O8WrBSRu1J8Gf_M/edit)、[英文参考](https://docs.google.com/document/d/1sX0eSvGMz-eQfAD435a8c2Um54qBgNfF7xlSDR2ePQc/edit)。官网动态短链的公开目标被解析后，通过 Google Docs 的公开文本导出读取；没有登录、绕过权限或取得非公开资料。

| 条款 | 当前公开文本的含义 |
|---|---|
| A / B | 个人使用允许；法人使用需联系作者 |
| I / J | 格式转换、调整及修改允许 |
| M / N | 原资源及修改资源直接再分发禁止 |
| R / 第 18 项 | 嵌入软件或游戏、以不易取出的形式分发，也需单独联系作者 |
| v1.60 更新记录 | R 从允许改为需联系作者 |
| 模型条款与角色创作指南 | 仍需遵守角色使用限制；二创指南不能代替模型许可 |

这是本次查到的**现行公开条款**。本次没有确定用户获取旧版资产时具体适用的历史授权或另行协议，也不对新版条款是否追溯旧交易作结论。

### 3.2 对本项目的实施解释

以下为基于上述文本对工作流程的判断：

- 用户自己的 Mac 上转换、预览，并签名安装到自己的手机测试，属于个人修改和自用的场景；不能仅凭“禁止公众再分发”就宣称这种测试被禁止。
- App Store 上架、给其他测试者发送包含模型的 App、公开 XCP 下载，以及将模型作为平台公共角色提供给其他用户使用，涉及软件分发或他人使用，应在进入这一阶段前明确对应授权。
- 换成 GLB、加密资源、免费提供或仅让用户看渲染结果，都不会自动解除分发条款。法人项目还要单独处理 B 条款。
- 本轮研究不请求购买证明，不联系作者，不上传资产；若后续做个人原型，应把转换结果标记为本地专用，避免进入公开角色源和可分享模型包。

### 3.3 AI 相关范围

对当前日/英文模型许可及[作者英文创作指南](https://docs.google.com/document/d/1Ke9g1CncdF1pbmCph-J-YyXKbNLem6rFuMtF17T7gzA/edit)全文检索，未发现 `AI`、人工知能、生成 AI、machine learning 等明确专项条款。**这仅说明检索到的文本没有该项表述，不表示取得了“任何 AI 用途”的授权。** 把本地对话文本驱动角色，和拿网格/贴图训练或公开生成模型，是不同用途；后者不在本研究范围内。角色内容限制和软件分发要求仍然存在。

本次公开文本导出 SHA-256，供以后辨认调研时的版本：

```text
license_jp: 2fb7c41e1cd12b73b25a990cfbd4e1754a7e5d378368784b1856bc795773c52a
license_en: 5c1e286905880aa1f4134156725eba0be21648e2df7a0f595516ff057977a44e
guideline_en: a1a1d0518df84158a35a1837e7c82bec2a5eeb0410a340365131c10f8879289e
```

## 4. Unity / VRChat 版本与工程边界

VRChat 当前指定 Unity **2022.3.22f1**；两款作者手册也按此版本的 Avatar 工程说明。我们使用 **6000.3.25f1 / URP 17.3**，不能以安装一个 VRChat SDK 的方式抹平差异。[VRChat 当前 Unity 版本](https://creators.vrchat.com/sdk/upgrade/current-unity-version/)、[Kipfel 作者手册](https://docs.google.com/document/d/1Phdnksr3hGku7j5BvaL_-sQjNgXwZRlU3AC_92eA7-c/edit)、[Mamehinata 作者手册](https://docs.google.com/document/d/1wHMXDhK7eoMECxEar0reAl-lYGzbATUkkdrd8KY0Cbw/edit)

可选的 VRChat 2022 工程只用于在其正常使用范围内查看原角色效果，不承担给 App 烘焙 SDK 默认内容的任务。真正的 App 转换工作区使用作者独立 FBX / 贴图 / 原创动画数据与普通 Unity / DCC 工具，不引入 VRC 运行时。最终生产工程维持 Unity 6；研究阶段无须另装 2022。

作者手册中的 Built-in / lilToon 材质参数需要另行转移；既不能假设 Built-in 材质会自动变成 URP，也不能笼统说 lilToon 不支持 URP。这个区别见第 7 节。

## 5. 骨骼、动作与状态机的转换

VRChat 的 Base、Additive、Gesture、Action、FX 是多层 Animator 系统的一部分，还依赖平台参数、追踪状态和 SDK 行为。FX 常用于表情、材质与物件开关；Gesture 也不等于完整身体动作。[官方 Playable Layers](https://creators.vrchat.com/avatars/playable-layers/)

我们的 [XCP 制作规范](../character-standard/02-model-production.md) 要求实际动作嵌入 GLB。`CharacterPackageBuilder.cs` 采用 glTFast Legacy 动画导入，删除原 Animator 并按 manifest 注册 clip；**运行时不会替外来 Humanoid 控制器做重定向**。

建议转换步骤：

1. 从主 FBX 建立 Humanoid Avatar，核对 required bones、左右手、颈头、脚尖、T Pose 和单位；已有映射可复用但不跳过检查。[Unity Humanoid 配置说明](https://docs.unity3d.com/6000.0/Documentation/Manual/ConfiguringtheAvatar.html)
2. 给作者原生 `.anim` 分类：身体 muscle、局部 Transform、morph、材质、物件显隐。只处理有明确来源的自带数据；控制器的外部 GUID 不自动补 SDK 动作。
3. Humanoid muscle 曲线必须经正确 Avatar 采样为角色自身骨骼 Transform 曲线；不能把 `Left Arm Down-Up` 当作 glTF 普通节点通道。Additive 呼吸先按基准姿态组合，再烘成自然循环。
4. 耳尾曲线可保留实际路径；根运动归零，动作不能改整个模型的全局缩放。脸部 shape 另列为 `expressions` / `speech`，服装显隐另处理成作者固定外观或经验证的 variant。
5. 最低交付 Idle、问候、头部回应，再按真实素材增加倾听、思考、开心、告别。不能用静态手势快照冒充挥手；缺少动作时使用另有清楚许可的动捕/手工动作并重新烘焙。
6. 待机、视线、口型、耳尾各有明确骨骼/形变所有权；避免烘焙耳尾动作又同时强制物理覆盖同一链。坐卧与 AFK 要按 XCP 姿势标准拆开，检查接地和回待机连续性。

## 6. PhysBones、Constraints、Contacts：逐项替代

| VRChat 功能 | 原功能 | 我们的处理路线 | 不能承诺的部分 |
|---|---|---|---|
| PhysBones | 发、耳、尾、衣物的链式动态及碰撞，还可支持平台交互 | 提取骨骼链和碰撞范围，重建 `secondary-motion.json`；先做发尾与小幅衣物摆动 | 不是物理参数一比一复制，不自动保留抓取、Pose、网络行为 |
| VRC / Unity Constraints | 父子、位置、旋转、朝向及平台扩展约束 | 固定配件烘焙 offset / 重设父级；动画依赖约束时烘焙结果 | Freeze To World、外部目标等动态语义没有现成等价支持 |
| Contacts | Sender / Receiver 匹配，向 Animator 写参数 | 头部触碰映射到现有热点与 `head-touch` 行为；确认面部 Renderer 和骨骼范围 | 不把 ContactReceiver 当作 iOS 触摸事件，也不保留 VRChat 社交接触网络 |
| Expression Menu / Parameters | 服装开关、表情状态、用户控制参数 | 归入角色作者配置、表情映射或固定穿搭 | 不复制整个 VRChat 菜单，也不恢复已被产品移除的任意模型操控入口 |

依据：[PhysBones 官方文档](https://creators.vrchat.com/common-components/physbones/)、[Constraints 官方文档](https://creators.vrchat.com/common-components/constraints/)、[Contacts 官方文档](https://creators.vrchat.com/common-components/contacts/)。这些组件的执行和平台行为有依赖关系；“把 DLL 丢进 Unity”既不能保证行为正确，也不符合本项目的依赖和许可边界。

本地 Prefab 确实包含动态骨根和 `Pet` Contact 参数；Mamehinata 配件还出现 Unity `ParentConstraint`。不能因为当前 VRChat 已有 VRC Constraints，就断言这些旧版本资源已经全部采用它。

当前 `AnimeCharacterAdapter.cs` 已支持可选 `core.secondary-motion@1`：最多 128 段、64 个球形碰撞体，要求 tip 为 bone 的直接子级，并限制半径与摆角。它是轻量次级运动，不是完整 PhysBone 或布料系统。必须按转换后的坐标、骨架比例重新调参；超出能力的 capsule / plane / 曲线行为要简化并记录，不能虚报已支持。

## 7. lilToon 到移动端材质

[lilToon 原作者项目](https://github.com/lilxyzw/lilToon)采用 [MIT 许可](https://github.com/lilxyzw/lilToon/blob/master/LICENSE)。近期[原作者更新记录](https://github.com/lilxyzw/lilToon/blob/master/Assets/lilToon/CHANGELOG.md)包含 Unity 6 / URP 修复，说明直接使用经过验证的 lilToon 版本并非原则上不可行。但材质系统兼容不表示模型资产许可随之开放，也不保证指定 Unity / URP / Metal 组合已经验证。

本项目优先采用现有 Unity Toon Shader 适配器，不给每个 XCP 包引入 Shader 源码：

| 原材质内容 | 建议输出 |
|---|---|
| 主色与多层颜色、固定装饰 | 正确处理混合与颜色空间后烘成底色；保留细节，不只取第一张主贴图 |
| 阴影色 / 阴影分界 | 映射现有 Toon 阴影参数，结合角色脸部与光照逐项比对 |
| 法线、Matcap、高光、发光 | 复用当前 `materials.json` 已支持字段；保留眼睛和发饰识别细节 |
| 毛发、睫毛、薄片 | 优先合理 alpha clip，控制透明层；检查边缘锯齿和背面，不全体改透明 |
| 描边 | 根据角色屏幕占比设置，防止近景变成粗黑线 |
| 动态材质、复杂特殊效果 | 首轮固定为合理状态；只有确有需要时设计新的版本化材质能力 |

直接保留 lilToon 可作为独立画质对照实验，但需要锁版本、压缩变体并测 Metal。它涉及宿主材质能力变更，不能作为当前“仅转换数据包”的默认捷径。

移动构建建议主贴图 2K，近景脸、眼睛、头发按实际差异保留 4K，并分别选择 ASTC 精度。[Unity 平台贴图格式建议](https://docs.unity3d.com/cn/6000.0/Manual/texture-choose-format-by-platform.html)给出了 iOS 的压缩选择。作为量级估算，4096² RGBA32 含 mip 约 85.3 MiB，ASTC 6×6 含 mip 约 9.5 MiB；这是格式计算，不是本项目现测显存，实际还取决于导入格式、读写副本、运行时拷贝与同时加载资源。

## 8. VRM 是否更适合作为中间格式

VRM 规范集中表达 humanoid、表情、视线、MToon 和 Spring Bone，[UniVRM](https://github.com/vrm-c/UniVRM)是可用的 MIT 开源实现。它对长期接入更多角色有价值。[VRM 功能说明](https://vrm.dev/en/vrm/vrm_features/)、[VRM 1.0 Spring Bone](https://vrm.dev/en/api/springbone/vrm1/)

但是 VRChat → VRM 不会自动无损保留 FX 状态机、任意约束、Contacts 和 PhysBones。我们的 glTFast / XCP 也不直接执行 VRM 扩展；转换成 `.vrm` 后改后缀为 `.glb` 不能完成接入。

**当前推荐 FBX / 原创动画 → 自身骨架烘焙 → GLB + XCP。** 若另做 VRM 母版，可作为交换格式和未来标准角色入口；要另写表达式、视线、Spring Bone 到 XCP 的适配，不把它列为本轮必要下载。这样不会为两个模型给运行时增加第二套头像系统。

## 9. iOS 画质与性能验收

VRChat iOS 使用其移动平台约束，[官方 iOS 平台说明](https://creators.vrchat.com/platforms/iOS/)与[移动资源限制](https://creators.vrchat.com/platforms/android/quest-content-limitations/)可以帮助理解作者 Mobile 版本。它们是 VRChat 客户端的规则，不是我们独立 Unity App 的硬限制。[VRChat 性能评级](https://creators.vrchat.com/avatars/avatar-performance-ranking-system/)也不是 FPS 实测结论。

本项目已有硬预算：GLB POSITION accessor 总计不超过 300,000、primitive 不超过 32、单 skin 不超过 256 joints、单资源 128 MiB、包 256 MiB。上述 FBX 面数看起来在可优化范围内，但导出后的 shape、材质拆分、顶点分裂和贴图总量才是实际验收对象。

建议第一版分别设高画质与省电档，保留角色脸部和头发质量，优先减少不可见服装、无用 morph、重复材质、透明覆盖及物理链。不能为了数字达标只把 PC 模型粗暴减面，再声称是高画质立绘。

完整会话场景测量应包含：

- 同一镜头、光照、背景下的正面、侧面、脸部近景和头发边缘对照。
- 30 秒待机循环、说话口型、实际头部触碰、问候、蹲坐/躺姿和回待机；检查手臂/衣物、耳尾/身体、眼睑/眼球穿插。
- 背景动态、阴影、聊天渐变、TTS / STT 和资源切换同时开启后的 CPU / GPU 帧耗时、内存峰值与持续发热表现。
- 60 FPS 对应 16.67 ms，120 FPS 对应 8.33 ms 的单帧预算；记录 p95 / p99 和长帧，不能只看瞬时 FPS 标签。模拟器只用于功能与画面检查，最终性能需要目标 iPhone 实测。

在这些数据产生前，只能说“结构具备移动优化基础”，不能承诺严格全程超过 60 帧或稳定 120 帧。

## 10. 可执行接入路线与产物

1. **锁定输入**：沿用本文两个 SHA-256，建立本地转换工作区和来源清单；不把 ZIP / `.unitypackage` 添加到公开仓库或 XCP 分发目录。
2. **Mamehinata Quest 管线试样**：先验证单位、骨架、表情、口型、真实触头和基础 Idle，输出可校验 GLB。它有 1 个原材质、约 15k 面，便于把管线问题与高成本画质问题分开。
3. **Mamehinata PC 画质样板**：保留眼睛、脸部、头发与穿搭细节，做手机近景对照，重新优化材质和纹理。避免任意改成人体比例；保持原角色风格。
4. **Kipfel 动态样板**：移植作者原创呼吸、耳尾及适合当前交互范围的休息动作；补齐问候、头部回应。检查其更多网格、shape 与配件是否确有保留必要。
5. **输出 XCP 1.1**：`character.json`、嵌入骨骼/morph/clip 的 `model.glb`、适配后的 `materials.json` / `secondary-motion.json`、来源与许可说明、预览和转换 README；按 SDK seal 生成文件哈希。
6. **接入现有角色集合**：动作、背景、声源、音乐均保持角色独立；默认创作设定不读取其他角色或旧个人 profile。先作为本地试样，不自动变成对外公共发现资源。
7. **完成真实验收后再决定**：如果轻量球碰撞不能稳定避免特定穿插，先调整动作和衣物骨权重，必要时再扩展版本化次级运动能力；不要跳过验收把所有 PhysBones 标签转换成一个“已支持”。

当前阻碍已经明确：公共软件分发授权未由本次研究解决；VRChat SDK 内容不能直接随 App 带出；原创动作仍需烘焙并补齐；材质和物理需要视觉调校。除此之外，未在静态检查中发现会阻止个人本地转换试样的文件格式或骨骼结构问题。Unity 实导、近景成图、互动回归和真机帧率均留待实施验证。
