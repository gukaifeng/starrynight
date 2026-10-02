# 原始角色包基础能力逐项核查与保留决定

日期：2026-10-02。范围：[当前发布名册](../../../assets/characters/active-roster.json)中的 41 个角色；不把旧未上架模型或只有衣装的来源加入检查范围。

本记录描述重新导入前的来源筛选，表内 App 绑定与骨段数量为该次审查快照。后续保留 11 个完整对话角色、更新 30 个预览角色的导入状态见[本轮导入记录](2026-10-02-model-only-import-progress.md)。

## 用户确认的筛选标准

用户明确选择：**眨眼和衣发物理都要具备；待机可由宿主适配。**

据此检查原包是否包含可用的闭眼/眼睑资产，以及作用于衣发的原作物理配置。源资产存在而转换、封包或运行驱动尚未接入的角色保留。没有独立呼吸片段不作为删除依据。不能把缺少星夜自动眨眼绑定解释成原包没有眼睑能力；原作自动时序与宿主调度也分别标记。

## 结果与名册处理

**检查 41 个，保留 41 个，删除 0 个。** 所有角色均找到闭眼资产和衣发物理来源，没有发现符合本次“原包缺基础能力”删除条件的角色。因此发布名册、默认角色、客户端目录和已有用户角色数据均未改动，无需为本次筛选重新构建或安装 App。

这不是 41 个角色当前动效已经正常的结论：当前只有 24 个包配置宿主眨眼绑定，19 个包含物理骨段；其余仍有转换或启用工作。没有宿主眨眼绑定的完整控制包也可能由原作控制图驱动，本次不据该字段断言实际不会眨眼。

## 核查方法与来源一致性

- 重新计算 41 个原始压缩包 SHA-256，全部与各自来源记录一致；共读取 15,631,053,952 字节，约 14.56 GiB。没有修改原始压缩包。
- 39 个批次角色按计划表的 `id → role` 对照原包 SHA、选定 Prefab、隔离检查 stamp、原生包资源索引和复制到 stage 的关键 Prefab/FBX 哈希。物理来源 Prefab 同时核对文件内容哈希；不将转换后的空预览包作为原生能力的证据。
- 检查 39 个角色原网格检查数据中闭眼形变的实际顶点偏移，排除仅有名字但没有变化的占位形变；每位均找到默认可见 Renderer 上非零的闭眼相关形变。非零位移不是完整合眼或眼睑视觉质量的验收。
- 两个旧角色使用独立原包与原始 FBX 检查、原作形变/动作审计，核对物理源 Prefab 及全部来源动作文件哈希。琪宝原 `eye_close`、豆日向原 `Auto_Blink` 的来源与实际形变历史验证见[自然待机记录](../natural-idle/README.md)；不借用新版琪宝的批次目录来证明旧版来源。
- 40 个角色的解析结果包含指向实际骨骼、默认启用的原作物理链，并逐个核对衣发相关根节点。Shizuku 单独追查原包本体 Prefab，而不是将转换中间结果的 0 条视为源包缺失。
- 源身体动作的数值核查比较 Hips、Spine、Chest、Neck、Head 在原采样中相对首帧的位移和旋转；不把静态姿势偏移当作动态待机，也不把动作文件总数当作身体动作数。

私有逐角色证据与可复跑检查脚本位于项目本机 `.local/checks/basic-motion-source-audit/`，其中 `report.json` 记录来源哈希、闭眼形变位移、物理来源、原身体采样的变化和当前交付状态。源形变数据、原采样与二进制均留在私有目录，不复制到公开文档。

## 逐角色结果

“原包物理”列是原作物理链/组件数量；“App 物理骨段”是星夜转换后的逐骨段数量，两者不是同一个计数单位。宿主眨眼列只表示星夜自动调度绑定是否已配置，不能代替原作控制图或设备行为检查。

| 角色 ID | 原包闭眼资产示例 | 原包物理证据 | 当前宿主眨眼绑定 | 当前 App 物理骨段 | 处理 |
| --- | --- | --- | --- | ---: | --- |
| `anime-kipfel` | `eye_close` | 24 条启用骨链 | 有 | 103 | 保留 |
| `anime-mamehinata` | `Auto_Blink` | 15 条启用骨链 | 有 | 41 | 保留 |
| `anime-chiffon` | `vrc.blink` | 19 条启用骨链 | 有 | 93 | 保留 |
| `anime-karin` | `vrc.blink_left` | 39 条启用骨链 | 无 | 99 | 保留 |
| `anime-torao` | `blink_eye_close` | 21 条启用骨链 | 无 | 43 | 保留 |
| `anime-ichigo` | `vrc.blink (3.0)` | 63 条启用骨链 | 有 | 264 | 保留 |
| `anime-lime` | `vrc.blink` | 21 条启用骨链 | 有 | 172 | 保留 |
| `anime-mafuyu` | `vrc_blink` | 92 条启用骨链 | 有 | 176 | 保留 |
| `anime-nozomi` | `blink_eye_close` | 64 条启用骨链 | 无 | 184 | 保留 |
| `anime-siska` | `Eye_Blink_VRC` | 26 条启用骨链 | 有 | 87 | 保留 |
| `anime-plum` | `vrc.Blink` | 18 条启用骨链 | 有 | 112 | 保留 |
| `anime-airi` | `vrc.Blink` | 51 条启用骨链 | 有 | 154 | 保留 |
| `anime-marycia` | `eyeBlinkLeft` | 9 条启用骨链 | 无 | 68 | 保留 |
| `anime-meiyun` | `vrc.blink` | 41 条启用骨链 | 无 | 126 | 保留 |
| `anime-milltina` | `vrc.blink ` | 56 条启用骨链 | 有 | 206 | 保留 |
| `anime-shinano` | `vrc.Blink` | 57 条启用骨链 | 有 | 189 | 保留 |
| `anime-milfy` | `vrc.blink` | 39 条启用骨链 | 有 | 105 | 保留 |
| `anime-shizuku` | `bs.eye_close_R` / `bs.eye_close_L` | 本体 Prefab 12 条，当前未提取 | 无 | 0 | 保留 |
| `anime-eku` | `vrc.blink` | 52 条启用骨链 | 有 | 95 | 保留 |
| `anime-sio` | `Blink` | 59 条启用骨链 | 无 | 220 | 保留 |
| `anime-kipfel-v111` | `eye_close` | 24 条启用骨链 | 无 | 0 | 保留 |
| `anime-azuki` | `blink` | 17 条启用骨链 | 无 | 0 | 保留 |
| `anime-cornet` | `blink` | 4 条启用骨链 | 无 | 0 | 保留 |
| `anime-fiona` | `vrc.blink_left` | 29 条启用骨链 | 无 | 0 | 保留 |
| `anime-elusion` | `eyelid_blink` | 39 条启用骨链 | 无 | 0 | 保留 |
| `anime-hikarun` | `auto_blink` | 18 条启用骨链 | 无 | 0 | 保留 |
| `anime-kumaly` | `vrc.blink` | 37 条启用骨链 | 有 | 0 | 保留 |
| `anime-kikyo` | `vrc.Blink` | 25 条启用骨链 | 有 | 0 | 保留 |
| `anime-lasyusha` | `vrc.Blink` | 119 条启用骨链 | 有 | 0 | 保留 |
| `anime-maki` | `まばたき` | 8 条启用骨链 | 有 | 0 | 保留 |
| `anime-mao` | `vrc.Blink` | 34 条启用骨链 | 有 | 0 | 保留 |
| `anime-mashu` | `blink` | 13 条启用骨链 | 有 | 0 | 保留 |
| `anime-mizuki` | `vrc.Blink` | 55 条启用骨链 | 无 | 0 | 保留 |
| `anime-nemesis` | `eyelid_blink` | 40 条启用骨链 | 无 | 0 | 保留 |
| `anime-nochica` | `auto_blink` | 19 条启用骨链 | 有 | 0 | 保留 |
| `anime-perula` | `まばたき` | 32 条启用骨链 | 有 | 0 | 保留 |
| `anime-ramune` | `blink` | 35 条启用骨链 | 有 | 0 | 保留 |
| `anime-ririka` | `blink` | 25 条启用骨链 | 无 | 0 | 保留 |
| `anime-rurune` | `b_blink` | 20 条启用骨链 | 有 | 0 | 保留 |
| `anime-shiratsume` | `vrc.blink` | 12 条启用骨链 | 有 | 0 | 保留 |
| `anime-koharu` | `eye_blink` | 29 条启用骨链 | 无 | 0 | 保留 |

## Shizuku 的遗漏

当前所选 `Assets/kuromaru9/shizuku/Prefabs_lil/shizuku_lil.prefab` 导入结果为 0 条物理链，但同一个原压缩包的完整本体 `Assets/kuromaru9/shizuku/Prefabs/shizuku.prefab` 内有 12 个启用的 spring-chain 组件，涉及 hair、jacket、jacket_shoulderString、jacket_armString、tie 等对象。其 Prefab 原始内容哈希为：

`6dca80127d58fac24a3f403189f8f4f0fd925e563c4c7631c1fe91c3d22a328c`

脸部原网格还包含有实际顶点位移的 `bs.eye_close_R` 与 `bs.eye_close_L`。因此归类为“原包具备，当前导入未恢复”，保留。后续需修复当前版本的继承/物理提取或使用同原包中合适的完整变体；本次没有换 Prefab 或重建该角色。

## 没有独立身体待机采样的角色

11 个角色在本次检查的上述上身骨骼采样中没有测出独立的时间变化：Chiffon、Karin、Lime、Nozomi、Siska、Meiyun、Milltina、Cornet、Kikyo、Maki、Mashu。这个结果只针对已检查的源采样及骨骼范围，不声称整个档案所有动作都静止。

前 10 个来源 Descriptor 使用默认 Additive 层；Mashu 的自定义 Additive 控制图引用 `b0f4aa27579b9c442a87f46f90d20192`。在固定哈希的官方 SDK 3.10.5 索引中，该 GUID 对应 `Samples/AV3 Demo Assets/Animation/ProxyAnim/proxy_idle.anim`。本次只核对索引，没有提取、复制或交付平台动作。VRChat 的默认层与 Additive 呼吸叠加机制见[官方 Playable Layers 说明](https://creators.vrchat.com/avatars/playable-layers/)。

这些角色的眼睑与衣发物理资产均存在，按用户允许宿主待机适配的标准保留。星夜后续仍需恢复或提供自己的待机驱动，而不是只播放固定站姿。

## 后续适配与验证边界

21 个外观预览角色的物理在当前封包流程中被整体清空，应恢复已经解析且可验证的衣发能力；Shizuku 的源物理提取单独修复。自动眨眼需扩充对左右眼独立形变、非规范命名及原作控制图的适配，避免与口型、手动表情和睡眠状态冲突。

本次完成来源资产筛选和逐角色静态/数值核查。没有修改角色包、运行 Unity 重导、重新安装手机、调用语音或图片模型，也没有宣称移动端碰撞、完整眼睑效果或帧率已经通过。可见动作是否恢复需在后续实际运行验收中确认。
