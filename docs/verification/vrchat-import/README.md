# VRChat 角色转换与接入 · 0.38.0 / 57

本轮实际验证：两套用户提供的作者模型可转换为独立 XCP 角色包，并在星夜 iPhone 会话运行。不是把 VRChat Prefab/SDK 整包塞进 App，也不是声称任意 Avatar 无损一键转换。

## 已交付

| 原始包 | 星夜入口 | 主模型三角形 | 原骨架 | 会话 morph | 动态段 / 碰撞球 |
|---|---|---:|---:|---:|---:|
| Kipfel 1.0.3 | 发现 → 琪宝 | 66,780 | 181 | 15 | 103 / 33 |
| Mamehinata PC 1.53 | 发现 → 豆日向 | 55,855 | 99 | 15 | 41 / 12 |

两者各含 Idle + Hello / Yes / No / Listen / Think / Talk / Relax / Thanks；实际身体动作来自已锁定的 Overte/Hanami Apache-2.0 数据，按目标骨轴重定向、平滑和接地。作者原始表情用于 blink / joy / care / sad / anger 与五元音口型。没有带出 VRC SDK 默认动作、DLL 或源脚本。

保留作者默认脸、头发、服装及主 FBX 配饰。Kipfel 默认隐藏的猫耳和眼镜不启用，上衣两项形变烘焙到中立几何；未开放换装/捏脸等当前产品已移除的入口。每角色固定独立背景（花园 / 晴窗）、声音配置、封面、圆形头像和两首原创新 CAF 音乐。原有 10 个集合与 20 首音乐哈希不变；现在共 12 角色、24 首独立乐曲。

## 可复用工具

- [导入 skill](../../../.agents/skills/vrchat-character-import/SKILL.md)：直接给后续 AI 的入口，附实际命令、依赖、失败处理、兼容边界。带 `agents/openai.yaml`，已通过技能校验器。
- [压缩包审计](../../../scripts/audit_vrchat_archives.py)：有界提取 ZIP/unitypackage，防路径逃逸，记录 SHA/GUID/动画分类，不执行来源代码。
- [隔离 stage 准备](../../../scripts/prepare_vrchat_stage.py) + [可信 Inspector](../../../scripts/vrchat/VrcSourceInspector.cs)：白名单复制数据，Unity 实例解析 Prefab 覆盖、骨架、材质和默认形变。
- [材质解析](../../../scripts/vrchat_materials.py)、[材质转换](../../../scripts/vrchat_render_materials.py)、[物理解析/适配](../../../scripts/vrchat_physics.py)。
- [XCP 转换器](../../../scripts/prepare_vrchat_characters.py)：bpy FBX→GLB，默认状态烘焙、米制统一、morph 削减、独立动作及绑定、seal。
- [来源锁](../../../assets/characters/vrchat-sources.lock.json)、[来源审计](source-audit.json)、[材质审计](source-materials.json)、[物理审计](source-physics.json)、[转换统计](conversion-report.json)。

当前转换器内有这两款模型的实测 recipe；新作者模型仍须根据审计新增骨架/表情/材质映射。stage 接受自定义 specs，不能把此能力误当成所有未知资产都无需适配。既有 Unity 6 / iOS / bpy 4.5.3 可直接用，本轮仅为技能校验在 SDK venv 补装 PyYAML 6.0.3，没有向系统 Python 或生产 App 加 VRC SDK。

## 验证与证据

- 全部 XCP 校验通过；12 集合 / 6 背景 catalog 一致，24 首 CAF 的所有权、唯一性、哈希和无损解码检查通过。
- Unity Setup、绑定、全部动作、取景验证通过；两角色共 18 张姿态审查图，见 [render](render/review.json)。此审查不是穿模零概率或硬件 FPS 证明。
- iPhone 17 / iOS 26.4 模拟器最终两项 XCTest 全通过，104.785 秒：新两角色发现搜索→资料→会话→主动问候/真实语音播放→实际屏幕摸头→资料往返镜头不变（75.500 秒）；原初音摸头与拖捏不能改变固定镜头（29.285 秒）。结果 `.local/checks/VRChat-Phone-Final.xcresult`。
- 两新角色 `nativeHeadHit=CharacterTouchSurface`，实际点击后 `headReactionCount` 增长，反应峰值分别超过 8°；[琪宝证据](evidence/anime-kipfel-head-reacted-runtime.json)、[豆日向证据](evidence/anime-mamehinata-head-reacted-runtime.json)。
- 角色页实际截图：[琪宝](screens/anime-kipfel-portrait-idle.png)、[豆日向](screens/anime-mamehinata-portrait-idle.png)；封面由实际 3D 渲染生成，不是示意图。
- 从公开的 stage 准备入口重新运行 Inspector，并转换到隔离 `.local/vrchat-replay`。两包的 GLB、materials、secondary-motion、manifest **8/8 SHA 完全一致**，见 [replay.json](replay.json)。这是实际复跑，不只是代码阅读。
- Simulator Debug 和 Device Release 完整构建状态、手机安装尝试见 [result.json](result.json)。未做 iPad、长时间发热或真机 60/120 FPS 验收。

## 关键问题与处理

1. **文件很多不等于动作很多。** 两原包没有 FBX 内嵌身体动画，许多 `.anim` 是 0 秒表情/换装/手势。采用许可清楚的独立会话动作库，原 FX 菜单和 SDK 动作不搬入 App。
2. **FBX 不是默认成品。** Unity 哈希 fileID 不能可靠从 Blender 名字猜。先隔离实例化 Prefab，确认 Kipfel 隐藏部件和两项上衣形变；把固定形变烘焙进所有保留的 morph 基底，防止 Idle/封面归零造成外观改变。
3. **Blender 接口与 buffer。** 4.5 实际参数是 `export_use_gltfpack`；稀疏 morph 需展开，numpy buffer 视图需复制后才能扩容。均已写入复用脚本。
4. **单位与取景。** 首次运行时 root scale=2 得到不一致的蒙皮 bounds（高度3.36m）。改为数据中统一2倍米制，顶点、morph、节点和 inverse-bind 平移一起转换，运行时 scale=1，高度约1.68m/1.73m。
5. **大头角色触碰被聊天层截获。** 首轮新角色 UI 测试中，豆日向的脸中心 y≈0.445，命中 `PlatformGroupContainer`。新增可选、作者固定的 `rig.portraitWidthScale`（默认1），豆日向为1.4；最终脸中心 y≈0.355、原生触碰通过。旧角色默认1，其镜头行为不变；没有扩大聊天层的触摸穿透区域。
6. **首张渲染黑轮廓。** 新shader第一GPU请求未完全就绪，review 改为同姿态 warm render 后 capture。最终 App 会话截图和进入流程验证正常。
7. **Unity Editor SIGABRT。** 一次在 Setup / Validate / Thumbnail 均成功后、构建回调初始化阶段原生崩溃。保留失败日志 `.local/logs/vrchat-export-simulator-final.log`，退出旧进程后在新 Editor 用既有 `BuildIos.ExportPreparedSimulator` 复用已保存场景重新导出成功；不是跳过校验或改动系统工具链。
8. **系统 Python 缺少依赖。** XCP 使用已有 SDK venv；技能校验额外安装 PyYAML 至该 venv。安装时代理短暂超时后正常下载，无需换来源或执行未知安装器。

首轮失败测试保留在 `.local/checks/VRChat-Phone.xcresult`；最终通过结果独立保存，不抹掉错误证据。

## 明确保留的差异

- 不是完整 lilToon 还原：保留主色、贴图、遮罩发光及首层带 mask 的 MatCap；Kipfel 投影式 stencil fake shadow、Mame 第二层 MatCap 尚未渲染，半透明贴片近似为 alpha cutout。主场景实时阴影保留。
- 发、耳、尾和衣物用自有受限弹簧，capsule 用多球近似，plane 未映射；原拉力/弹力曲线和每链 collider mask 没有等价执行。仍可能存在极端动作下的局部穿插，不能保证所有 VRC 物理行为无损。
- Mame 的额外独立 NameTag Prefab 未打入本版；源主 FBX 的背包和服装保留。该唯一已审阅未解析路径显式允许，其余物理引用错误仍阻止转换。
- 没有导入原平台的完整 FX 状态机、参数菜单、抓取、网络交互、所有 AFK/睡眠序列。XCP 仍可后续增量加能力。
- 保持现有 60/120 Hz 目标配置，但本轮没有硬件持续帧率结论；移动设备不能由面数、VRChat 评级或动画采样率保证 FPS。

## 使用范围

当前个人本地预览可继续；本轮没有发布模型或公开 App。作者现行 2026-09-07 v1.60 条款将软件/游戏集成后分发列为需联系作者，原件和改作资产不能直接再分发。旧获取时间可能适用的其他协议未作追溯判断。完整原始来源、原文、SDK 边界见 [可行性研究](../../design/2026-09-29-vrchat-feasibility-research.md)。
