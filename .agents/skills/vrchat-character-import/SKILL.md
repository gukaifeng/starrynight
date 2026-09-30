---
name: vrchat-character-import
description: Inspect and convert user-supplied VRChat avatar archives into this project's data-only XCP character packages for native iOS and Unity URP. Use for FBX/Prefab appearance, original animations, toon materials, and secondary-motion adaptation; not for uploading avatars to VRChat.
---

# VRChat 角色导入 XCP

目标是保留角色的默认外观和原创表现，把独立资产转换为星夜可验证的角色数据包。批量多作者来源或需要迁移完整原作控制图时，先读 [分批导入参考](references/batch-import.md)，使用 `core.avatar-controls@1` 与 `core.performance@2`。旧两角色的片段/曲线表现管线见 [表现迁移参考](references/performances.md)。基础动作按用户要求和来源声明，不自动补通用九动作。`.unitypackage`、VRChat SDK、源 FX Controller 文件不直接交付 App；审核后的数据图由宿主重建。

以项目根目录为工作目录。先读 [compatibility.md](references/compatibility.md) 中与当前步骤相关的部分；XCP 字段和预算以 [角色制作规范](../../../docs/character-standard/02-model-production.md) 和 `character-sdk/schemas/` 为准。操作 Unity CLI 前另读本项目 [unity-cli 技能](../unity-cli/SKILL.md)，不要凭记忆编造 CLI 参数或同时启动多个写同一工程的 Editor。

## 先确定输入和实际完成度

- 记录 ZIP 路径、版本、SHA-256、选用的主 Prefab、PC / Mobile 变体，以及本次目标是个人本地试样还是对外分发。沿用用户已经给出的用途，不重复索要购买证明。
- 核对原作者模型许可、第三方动作/贴图署名及 SDK 依赖许可。区分个人转换、自用安装与公开分发；不要因分发尚需许可而把已授权的本地检查和转换也全部停掉。也不要把“没有写 AI”当作无限 AI 使用授权。
- 默认外观以作者主 Prefab 为准，包括嵌套覆盖、激活状态、Renderer 开关、材质槽和默认 morph。裸 FBX 全部显示通常不是作者的角色成品。
- 按证据报告阶段：静态审计 → 隔离导入检查 → GLB/XCP 转换 → 实际画面/交互 → 目标设备性能。前一阶段通过不能代替后一阶段；不把非零 `.anim` 数量当作可用身体动作数量。

## 发布名册与兼容

实际打包由 `assets/characters/active-roster.json` 决定，默认琪宝；不要在技能中用固定数量代替名册。批次由 `assets/characters/import-batches.json` 记录，用户已要求一批完成即安装一批。其他角色来源、候选和历史资料仍在工作区，不代表已发布。公共运行时、标准、材质或交互升级必须兼容并回归全部已发布角色。不要为通过旧的 Luma/初音测试而重新加入已下架模型。

原作表现入口已外置到聊天输入框上方右侧；声音按钮单击分项设置，定制页不再放音乐。位置按钮操作独立根变换，自动记住该账号/角色的最后状态，移除长按蓄力与方案列表，不构成作者待机／讲话动画，也不改角色源包；参考 [取景编辑及边界](../../../docs/verification/position-controls/README.md)。

## 当前可直接运行的检查

以下接口已核对；第一个命令中的路径换成用户指定的 ZIP，可以传多个。脚本写隔离提取目录和报告，不修改原 ZIP，也不执行包内代码。

```bash
python3 scripts/audit_vrchat_archives.py \
  "/absolute/path/Avatar.zip" \
  --output-root .local/vrchat-audit \
  --report docs/verification/vrchat-import/source-audit.json

python3 scripts/vrchat_materials.py \
  --audit docs/verification/vrchat-import/source-audit.json \
  --output docs/verification/vrchat-import/source-materials.json
```

检查已有源树的新解析字段时，可使用已存在的报告：

```bash
python3 scripts/audit_vrchat_archives.py \
  --refresh-metadata \
  --report docs/verification/vrchat-import/source-audit.json
```

`--refresh-metadata` 不与新的 ZIP 参数组合；它不是重新核对原压缩包的替代品。换来源或版本时重新做输入审计。提取目录同名时会复用路径，不把两个不同来源悄悄混为同一次转换；保留旧结果时为新批次指定独立输出目录和报告。

已验证的两角色转换入口（在审计之后执行）：

```bash
python3 scripts/prepare_vrchat_stage.py
python3 scripts/vrchat_physics.py \
  --allow-unresolved-prefab Assets/MOCHIYAMA/Mamehinata/Prefab/NameTag.prefab
.local/character-venv/bin/python scripts/prepare_vrchat_characters.py
.local/character-sdk-venv/bin/python scripts/validate_characters.py
```

`prepare_vrchat_stage.py` 会调用 Unity CLI；需要已有 Unity 6000.3.25f1 许可。先 `unity status --json`，不要与占用同一工程的 Editor 并发。数据清单与 GUID 保留，C#/DLL/Shader 不从来源包进入 stage。`--prepare-only` 只准备文件；`--specs FILE` 接收 `{"specs":[{"role":"...","fbx":"Assets/...fbx","prefab":"Assets/...prefab"}]}`。Inspector 在 `scripts/vrchat/VrcSourceInspector.cs`，不会调用 VRC SDK。

`prepare_vrchat_characters.py --only kipfel|mamehinata` 可单角色重建；`--output-root .local/vrchat-replay` 用于隔离复跑。命令自动 seal。依赖分别在 `.local/character-venv`（bpy 4.5.3、numpy、Pillow）与 `.local/character-sdk-venv`（`character-sdk/requirements.txt`）。系统 Python 没有 jsonschema 时使用 SDK venv，勿安装到系统 Python。构建工具版本已锁定在 `scripts/vrchat/requirements.txt`（Python 3.11）；技能校验另需在其 venv 安装 `PyYAML==6.0.3`。

当前有一条已知 Mamehinata 独立 NameTag Prefab 引用未导入，故 physics 命令仅允许该精确路径；原值仍记录在报告，不能将它推广成忽略所有 unresolved。其他物理根/碰撞器解析失败仍停止。表现目录中豆日向 SunVisor 也因不在主 FBX 中过滤，不显示无效按钮。已转换主 FBX 的包上配饰保留，这个额外名牌和 VRC 平台功能不列为已支持。

新增其他作者模型时使用批次参考中的通用 stage/portable 转换管线；现有 `ROLES` / `EXPRESSIONS` recipe 专用于旧两角色的兼容维护。它们不是任意 ZIP 一键转换器，尤其不得照搬本例 2 倍米制转换、T-pose、局部碰撞坐标映射到未经检查的新模型。

## 转换时守住的语义

**当前琪宝/豆日向保留原作动作，并支持本次授权的自然待机。** 用户2026-09-30明确要求补自动眨眼、呼吸待机和环境风，取代早期对这些附加行为的禁止。按 [自然待机参考](references/natural-idle.md) 处理，模型包2.2.0通过可选 `core.autonomy@1` 标明来源与适配；保留原曲线、viseme与表现。不要借此恢复旧Overte/Hanami九动作、触屏摇头、自动头眼跟随或语音点头。原始来源资产不改；旧[原作恢复记录](../../../docs/verification/vrchat-original-motion/README.md)仅描述0.39.1当时范围。

1. **隔离数据导入。** 仅将已经审阅的 FBX、贴图和必要的 Unity 数据资产放入临时 stage；由仓库维护的 Inspector 读取 Prefab 实例。来源 C#、DLL、Editor 扩展、SDK 和未知 Shader 不进入生产工程，也不为消除 Missing Script 盲目安装依赖。
2. **还原作者默认状态。** 用实例检查结果解析 GUID/fileID、节点路径、默认可见性和形变。不要按名字猜测衣服、身体或阴影层该删还是该留；先记录变更，再比较近景外观。
3. **确认坐标和骨轴。** 骨骼同名不代表同轴；核对比例、正面、bind pose、头颈/眼轴、蒙皮和根变换。Humanoid muscle 动画经有效 Avatar 采样烘焙，最终 clip 必须驱动该 GLB 的真实骨骼。
4. **重建应用行为。** FX/手势里的表情、服装开关、静态姿势与真正的连续动作分开。Contacts 接现有互动热点；PhysBones 和约束按当前 XCP 能力重建或烘焙，不能把 VRChat 组件当成已支持。
5. **保留有辨识度的材质。** 解析 Prefab 材质覆盖、颜色变换、发光 mask、MatCap、透明/乘色 pass；将近似或暂不支持之处明确记录。不能只取主贴图就宣称还原 lilToon。
6. **交付数据包。** GLB 内含 mesh、skin、morph、贴图和已声明动画；JSON 映射真实路径与能力。模型、动作、背景、声音和音乐按角色隔离，来源与转换限制随包记录。不要借转换恢复与当前产品设计冲突的操作入口。

## 验证与交回

先运行现有 XCP 校验和构建检查，再做实际角色画面与交互回归。当前两角色可执行：

```bash
unity run "$PWD/unity/CharacterRuntime" --timeout 900 -- \
  -executeMethod VrchatImportReview.BuildAndReview \
  -logFile "$PWD/.local/logs/vrchat-unity-review.log"
python3 scripts/check_character_collections.py
python3 scripts/export_unity_ios.py --platform simulator
bash scripts/build_host.sh
```

生成角色目录后要同步 `CharacterCollections.json`、`CharacterCoverCatalog.json`，头像用 Unity 渲染；来源有合适封面时保留作者原图与哈希，缺封面才渲染生成；`scripts/generate_asset_credits.py` 将包署名带入 iOS。新角色音乐必须独立创作/获得授权，在 soundscape 生成器登记后用 `--only ROLE` 增量生成，别覆盖旧角色的 CAF。现有 `VrchatImportReview` 是这两角色的回归入口，新增角色时扩展测试集合。

运行完整会话 UI 验证使用 `scripts/test_companion.sh`；现行两角色会话回归为 `ConversationControlsTests`，原作动作数据用 `VrchatOriginalMotionReview` 与 `CharacterPerformanceReview`；旧版 `VrchatCharacterTests` 的入口假设需按当前默认角色核对，方法筛选需带 `()`，必须核验实际执行不为零。手机只尝试一次安装，失败继续 iPhone 模拟器；不为等待手机中断开发。导出器的 catalog stamp 不能代替 GLB/贴图/sidecar 变更后的真正 Setup 和重新导出。

基础导入结果见 [导入验收记录](../../../docs/verification/vrchat-import/README.md)；原作表现扩展的实际 82 / 48 项、运行和画面证据见 [表现验收记录](../../../docs/verification/vrchat-performance/README.md)。130 项包含静态预设、动作和开关，不是 130 个连续身体动作。

验证至少覆盖作者默认穿搭与脸部、自然 Idle、讲话口型、头部真实命中、合理视线、动作首尾和衣发碰撞。确认加载首次显示即为终态取景，角色切换不回写其他角色的设定，封面/头像来源正确。完整会话场景的设备帧耗时才能支持 60/120 FPS 结论，模拟器或静态面数不能替代。

交回实际产物位置、输入哈希、验证证据、保留/替代/暂缺的能力和许可范围；没有跑过的检查明确标为未测。若出现未知骨架或材质，先把失败缩到隔离 stage 的一个可重现角色，不反复改主场景或无边界重导出。


### 已保存场景后的 Editor 原生崩溃恢复

仅当本次日志明确有 `MODELSPACE_SETUP_PASS`、`MODELSPACE_VALIDATION_PASS`、缩略图成功、场景已保存，且旧 Editor 确实退出时，可以新进程使用已有 `BuildIos.ExportPreparedSimulator` 或 `BuildIos.ExportPreparedDevice`。例如：

```bash
unity run "$PWD/unity/CharacterRuntime" --timeout 900 -- \
  -buildTarget iOS -executeMethod BuildIos.ExportPreparedSimulator \
  -logFile "$PWD/.local/logs/vrchat-export-recovery.log"
python3 scripts/check_export_content.py --platform simulator
```

它仍运行 Validate，只跳过已成功完成的 Setup/缩略图；不是处理脚本编译错误、过期 GLB 或缺少资源的通用绕过方式。保留第一次失败日志和恢复结果。

当前位置编辑允许横向不限圈数、纵向 ±80°，身体中轴固定；非编辑模式的小幅单指旋转松手恢复，缩放平移仍受构图安全区约束。以现行代码和 [取景验证](../../../docs/verification/position-controls/README.md) 为准，导入不得恢复历史交互。声音只有各通道音量、0 静音，不恢复长按蓄力或总静音入口。

2026-09-30 用户进一步授权所有角色在会话待机及说话时做更小的随机根转动。`CharacterAmbientTurn` 是宿主展示层，不是原作骨骼动画：不写入保存位置，不计入晃动投诉，编辑/手动拖转时平滑让位。不得把这种视觉活动标成原包自带待机。新包由 `CharacterPortraitCalibrationBuilder` 从中性眼骨/头骨生成取景，保留脸部屏幕锚点、头饰空间及硬件安全区；不要复制上一角色的固定摄像机距离。详见 [0.61 验证](../../../docs/verification/ambient-portrait/README.md)。
