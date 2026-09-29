# VRChat 源压缩包只读审计

只读取本地压缩包、FBX 二进制结构与 Unity YAML；未导入 Unity、未执行来源脚本，也未验证动画实际播放。路径、GUID 和详细计数以同目录 JSON 为准。

## Kipfel_1.0.3.zip

- 源 SHA-256：`b1b800389aa6b174b1565527a351c7ba41653f4debeb627180c5b34e45aec053`
- 安全提取目录：`/Users/gukaifeng/Documents/ios-app/.local/vrchat-audit/kipfel-1.0.3`
- 许可正文：No license body found in supplied archive; URL shortcuts are references, not an embedded license.

包内文件计数：`{".anim": 99, ".asset": 10, ".controller": 8, ".fbx": 2, ".mat": 13, ".png": 26, ".prefab": 3, ".unity": 1}`。
未解析的外部 GUID：69；源码脚本/编译程序集：0；Shader资源：0。

| FBX | 骨骼 | 表情通道 | 三角面 | 内含 AnimationStack |
|---|---:|---:|---:|---|
| Assets/MOCHIYAMA/Kipfel/FBX/Kipfel.fbx | 181 | 456 | 69640 | [] |
| Assets/MOCHIYAMA/Kipfel/FBX/FishToy.fbx | 0 | 0 | 321 | [] |

动画绑定类别（可重叠）：`{"blendshape-expression": 59, "humanoid-hand-muscles": 8, "other-or-empty": 3, "object-toggle": 29, "transform-curves": 26, "humanoid-body-muscles": 10}`。

主/附属 Prefab：

- `Assets/MOCHIYAMA/Kipfel/Prefab/Kipfel.prefab`
- `Assets/MOCHIYAMA/Kipfel/Prefab/AvatarDynamics.prefab`
- `Assets/MOCHIYAMA/Kipfel/Prefab/Kipfel_kisekae.prefab`

具有非零时长的身体肌肉曲线（仍需重定向/播放验证）：

- `Assets/MOCHIYAMA/Kipfel/Animation/AFK/kipfel_afk_sleep_to_stand.anim`：11.166667 秒；37 条身体绑定。
- `Assets/MOCHIYAMA/Kipfel/Animation/AFK/kipfel_afk_sleep_loop.anim`：6.0 秒；37 条身体绑定。
- `Assets/MOCHIYAMA/Kipfel/Animation/Locomotion/kipfel_breath.anim`：2.5 秒；1 条身体绑定。
- `Assets/MOCHIYAMA/Kipfel/Animation/AFK/kipfel_afk_stand_to_sleep.anim`：7.8333335 秒；37 条身体绑定。

身体肌肉曲线但时长为 0 的静态姿势：6 项；不能算作可直接循环的身体动作。

转换主参考：`Assets/MOCHIYAMA/Kipfel/Prefab/Kipfel.prefab`。其 PrefabInstance 共 462 条显式 override；其中可见性/材质/shape 相关 38 条。


本地说明文件：

- `Kipfel_1.0.3/ReadMe_(en).url` → https://mochiyama.com/kipfel_manual_en
- `Kipfel_1.0.3/ReadMe_(ko).url` → https://mochiyama.com/kipfel_manual_ko
- `Kipfel_1.0.3/ReadMe_(ZHcn).url` → https://mochiyama.com/kipfel_manual_zhCN
- `Kipfel_1.0.3/ReadMe_âLâvâtâFâïÉαû╛Åæ(jp).url` → https://mochiyama.com/kipfel_manual_jp
- `Kipfel_1.0.3/闲鱼逛资源小铺店内获取更多资源哦.txt` → https://m.tb.cn/h.g6lgC37?tk=Lyeb3ZhoaXd

## Mamehinata1.53.zip

- 源 SHA-256：`ba8e9fd15f99db4b01cb304723965995a6a69b787310fe04d4bde48903845eb3`
- 安全提取目录：`/Users/gukaifeng/Documents/ios-app/.local/vrchat-audit/mamehinata1.53`
- 许可正文：No license body found in supplied archive; URL shortcuts are references, not an embedded license.

包内文件计数：`{".anim": 64, ".asset": 9, ".controller": 9, ".fbx": 4, ".mat": 7, ".png": 19, ".prefab": 6}`。
未解析的外部 GUID：176；源码脚本/编译程序集：0；Shader资源：0。

| FBX | 骨骼 | 表情通道 | 三角面 | 内含 AnimationStack |
|---|---:|---:|---:|---|
| Assets/MOCHIYAMA/Mamehinata/Quest/Quest_FBX/Mamehinata_Quest.fbx | 99 | 221 | 14984 | [] |
| Assets/MOCHIYAMA/Mamehinata/FBX/NameTag.fbx | 0 | 0 | 1070 | [] |
| Assets/MOCHIYAMA/Mamehinata/FBX/Mamehinata.fbx | 99 | 253 | 55855 | [] |
| Assets/MOCHIYAMA/Mamehinata/FBX/SunVisor.fbx | 0 | 0 | 1014 | [] |

动画绑定类别（可重叠）：`{"object-toggle": 12, "blendshape-expression": 30, "other-or-empty": 4, "humanoid-hand-muscles": 8, "humanoid-body-muscles": 4, "transform-curves": 8}`。

主/附属 Prefab：

- `Assets/MOCHIYAMA/Mamehinata/Prefab/NameTag_Position.prefab`
- `Assets/MOCHIYAMA/Mamehinata/Quest/Mamehinata_Quest.prefab`
- `Assets/MOCHIYAMA/Mamehinata/Prefab/SunVisor.prefab`
- `Assets/MOCHIYAMA/Mamehinata/Prefab/NameTag.prefab`
- `Assets/MOCHIYAMA/Mamehinata/Mamehinata_PC_kisekae.prefab`
- `Assets/MOCHIYAMA/Mamehinata/Mamehinata_PC.prefab`

具有非零时长的身体肌肉曲线（仍需重定向/播放验证）：

- `Assets/MOCHIYAMA/Mamehinata/Anim_gesture/Mamehinata_breath.anim`：2.5 秒；1 条身体绑定。

身体肌肉曲线但时长为 0 的静态姿势：3 项；不能算作可直接循环的身体动作。

转换主参考：`Assets/MOCHIYAMA/Mamehinata/Mamehinata_PC.prefab`。其 PrefabInstance 共 289 条显式 override；其中可见性/材质/shape 相关 20 条。


本地说明文件：

- `ReadMe_(EN).url` → https://mochiyama.com/mamehinata_manual_en
- `ReadMe_(KO).url` → https://mochiyama.com/mamehinata_manual_ko
- `ReadMe_(zhCN).url` → https://mochiyama.com/mamehinata_manual_zhCN
- `ReadMe_傑傔傂側偨愢柧彂(JP).url` → https://mochiyama.com/mamehinata_manual_jp

## 转换交接与边界

优先以原装主 Prefab 的可见性、衣服、材质和默认 BlendShape 为准：Kipfel 使用 FBX/Kipfel.fbx + Prefab/Kipfel.prefab；Mamehinata 以 PC 的 FBX/Mamehinata.fbx + Mamehinata_PC.prefab 保留较完整细节，Quest 是另一个较低面数版本。不要因为 FBX 内同时存在多个衣服或替换部件而全部显示。

JSON 的 prefabInstances 保留每项源 GUID/fileID、属性路径、值和 objectReference；strippedSourceObjects 保留本地 fileID 到源的映射。physicsComponentsByFields 保留原始根引用、碰撞/忽略引用、标量与参数曲线。两个 FBX 的 internalIDToNameTable 为空时，离线解析不能可靠还原 Unity hashed fileID 到网格名，需由隔离的 Unity 数据导出步骤解析；本报告不虚构该映射。

Kipfel 的物理组件主要位于 AvatarDynamics.prefab，主 Prefab 的 rootTransform overrides 把它们绑定到 FBX 骨架。对应 SDK 只有组件引用，没有随包 DLL/源码，因此本地解析记录原值而不运行 SDK。

完整材质数据与贴图 GUID 解析见 [source-materials.json](source-materials.json)。Kipfel 眼睛发光带独立 mask，Mamehinata 的 Outfit 启用两层 MatCap；基础色贴图不能替代这些效果。原 toon 材质的 Smoothness=1 经常伴随 Reflection 禁用，不能直接转换为 PBR 零粗糙度。

骨骼计数为 FBX Model/LimbNode 与 Root 节点数；BlendShapeChannel 是形变通道数量，不等于已绑定的对话表情数。三角面由原始 polygon 拆分计数，不能代替 Unity 导入后的 GPU 顶点/材质预算。controller 名称不能证明有独立身体动作；需看 .anim 的变换/肌肉绑定及外部 motion GUID。外部 GUID 没有源码依赖包时仅报告未解析，不猜测版本或补装 SDK。

此审计未导入主 Unity、未安装 SDK、未执行下载包内的代码。压缩包内是说明网页 URL 快捷方式，未发现许可正文；文件持有本身不能作为许可范围的确认。来源/授权由上层集成流程另行确认。
