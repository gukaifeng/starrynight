# 两位 VRChat 角色：恢复原作动作的来源审计

日期：2026-09-29。范围仅为来源文件、转换逻辑及生成角色包的数据核对；本文件不代表 Unity、模拟器或真机运行验收。机器可读证据见 [source-audit.json](source-audit.json)。

## 结论与恢复范围

琪宝与豆日向此前的点击摇头是星夜添加的：`CharacterGaze.TouchReaction()` 根据 1.8 秒正弦曲线生成头颈动作，原来的头部触碰规则还叠加了项目自行配比的开心表情。没有来源证据表明这一摇头属于两位作者角色。

两原包确实都有 `Contact_Pet` 以及 `Pet_Happy / Pet_Unhappy` 表情。它们是脸部表现，不能据此把项目的头部正弦摇动称为原作动作。本次保留这些原作表现选项，撤回自动摇头及自行配置的触碰规则；没有另造手机点击映射。

旧基础九动作 `Idle / Hello / Yes / No / Listen / Think / Talk / Relax / Thanks` 来自 Overte/Hanami VRMA，而不是这两份 VRChat 源包。旧 `prepare_portrait_vrm.prepare_animations()` 又对待机加入 relaxed 混合、角色速度调整、正弦呼吸与固定眨眼时间表。这条生成路径现不再用于两角色；未删除第三方原素材及历史记录。

同时撤回两角色的项目语义表情配比、星星/爱心特效、自动朝镜头转头转眼、说话/倾听/思考时的程序点头和环境头发微风。其他角色没有使用这次恢复配置。

## 原作待机的依据与转换

| 角色 | 原站姿 | 原呼吸 | 控制器中的明确关联 |
|---|---|---|---|
| 琪宝 | `Assets/MOCHIYAMA/Kipfel/Animation/Locomotion/kipfel_stand_still.anim` | `Assets/MOCHIYAMA/Kipfel/Animation/Locomotion/kipfel_breath.anim` | `Kipfel_ActionLayer.controller` 的 `WaitForActionOrAFK` → stand；`Kipfel_AdditiveLayer.controller` 的 `Breath` → breath |
| 豆日向 | `Assets/MOCHIYAMA/Mamehinata/Anim_gesture/Mamehinata_stand.anim` | `Assets/MOCHIYAMA/Mamehinata/Anim_gesture/Mamehinata_breath.anim` | `Mamehinata_ActionLayer.controller` 的 `WaitForActionOrAFK` → stand；`Mamehinata_AdditiveLayer.controller` 的 `Upright Idle` → breath |

完整 controller 路径、状态和源 clip 引用来自此前的 [原作控制器审计](../vrchat-performance/source-capabilities.json)，本次相关条目也收录在 `source-audit.json`。这是原站姿和呼吸来源的依据；没有宣称在 App 重现了完整 VRChat Animator、追踪或网络状态机。

新的基础 `Idle` 由原站姿叠加原呼吸首帧的相对变化构成：

```text
rotation(t) = stand × inverse(breath(0)) × breath(t)
position(t) = stand + breath(t) − breath(0)
```

两份呼吸均使用原 2.5 秒时间轴。源采样是每通道 151 个点，动态通道为 Hips 旋转/位移、Chest 旋转及 Head 旋转。没有改变速度、幅度、增加滤波或新时序；生成时的逆向重构最大误差不超过 `5.56e-16`。此数值是转换数据的数学核对，不是设备运行误差或帧率。

原站姿及原呼吸独立 clip 仍留在 GLB 中。面板的“轻轻呼吸”使用与 Idle 相同的组合片段，以非 additive 全身层播放，避免原呼吸再次叠加而变成两倍。原坐、蹲、躺等姿态保持原 clip。

## 主 Prefab 的直接证据

| 角色 / 主 Prefab | 眼睛跟随 | 口型 | 来源行号 |
|---|---|---|---|
| `Assets/MOCHIYAMA/Kipfel/Prefab/Kipfel.prefab` | `enableEyeLook: 0` | `lipSync: 3`，原 `vrc.v.*` viseme | eye：2921；speech：2849 |
| `Assets/MOCHIYAMA/Mamehinata/Mamehinata_PC.prefab` | `enableEyeLook: 0` | `lipSync: 3`，原 `vrc.v.*` viseme | eye：2375；speech：2317 |

行号对应 `.local/vrchat-stage/` 中这次已审阅的原数据 Prefab，其 SHA-256 已写入 JSON。原闭眼及其余此前已导入的面部 morph 仍保存，只撤回项目自编的自动调度与组合权重。讲话口型继续使用原生 viseme 绑定，`speech.proceduralHeadMotion=false`。

原 PhysBone 链及碰撞器来自 [源物理审计](../vrchat-import/source-physics.json)。本次保留迁移后的惯性，但把 `secondary-motion.json` 的 `ambientHairAngle` 设为 0。现有独立求解器使用统一阻尼弹簧和保守角度限制，并不等同作者的 VRChat PhysBone 求解器；不能将它称为完全原生物理。

## 源文件保留与输出

本次重新读取原 ZIP 计算 SHA-256，两者均与此前导入审计一致：

| 源文件 | SHA-256 |
|---|---|
| `/Users/gukaifeng/Documents/vrchar/Kipfel_1.0.3.zip` | `b1b800389aa6b174b1565527a351c7ba41653f4debeb627180c5b34e45aec053` |
| `/Users/gukaifeng/Documents/vrchar/Mamehinata1.53.zip` | `ba8e9fd15f99db4b01cb304723965995a6a69b787310fe04d4bde48903845eb3` |

原 ZIP、FBX、`.anim` 与隔离采样没有修改。恢复动作后移除公开 Hello/Yes/No 等能力，因此两个角色包诚实升为 **2.0.0**；XCP schema/API 主版本未改变。生成产物不再包含第三方九动作，原始资源与历史署名仍保留在项目原有位置。

| 包 | 原作可选表现 | GLB clips | 保留 morph | GLB 大小 |
|---|---:|---:|---:|---:|
| `anime-kipfel` 2.0.0 | 82 | 38 原片段 + 1 原作组合 Idle | 177 | 62,580,356 B |
| `anime-mamehinata` 2.0.0 | 48 | 20 原片段 + 1 原作组合 Idle | 84 | 23,762,708 B |

130 项包含静态预设、动态片段和开关；不是 130 段连续身体动画。生成包中的项目 `expressions / effects / interactions / behaviors` 均为空，公开 actions 只声明 Idle；原作面部与形态控制仍在 `performance` 中。

转换实现是 [prepare_vrchat_characters.py](../../../scripts/prepare_vrchat_characters.py) 与 [vrchat_performance_export.py](../../../scripts/vrchat_performance_export.py)。每包的 `conversion-report.json`、`source-meta.json` 均记录原站姿、呼吸路径、组合方法和数值检查。两包 seal 及全 12 包数据校验已通过，日志分别为 `.local/logs/vrchat-source-only-conversion.log`、`.local/logs/vrchat-source-only-package-validation.log`；运行画面及设备结果应另看主交付验收记录。
