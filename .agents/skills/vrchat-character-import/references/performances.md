# 原作动作、表情和形态迁移

## 当前增量：0.94 完整原作片段库与开发者动作实验

见 [新标准](../../../../docs/character-standard/10-source-motion-library.md)。不再只检查作者菜单：隔离 stage 的完整 `avatar-motions.json` 包含 `.anim` 与 FBX/.asset/.controller 子资产，身份是 GUID 或 GUID:fileID。`scripts/prepare_source_motion_library.py` 把可绑定曲线投影为 `source-motions.json.gz`，逐通道记录不支持原因，加入原作肢体/表情/部件分组。复用原采样，不重新下载，不调 AI，不改用户源档案。先准备候选并预检，再 `--apply` 激活，激活副本保存在 `.local/vrchat-batch/source-motion-library/activation/`。

新包为 3.4.0，required 包含 `core.source-motions@1`、`core.avatar-controls@2`、`core.performance@3`。`avatar-motions.json` 也采用无损 `.gz`，必须使用 SDK 的 bounded reader 或 Editor `CharacterMotionData.Read`，不能继续直接 File.ReadAllText。128 MiB 解压预算、旧 256 MiB 包预算仍生效，不能为了数量绕过预算。SDK validate 与 `check_character_collections.py` 核对全部当前角色。

`SourceMotionLibraryReview.BuildAndReview` 执行 Setup/Validate、全库求值恢复和 16×10×60/120 Hz 宿主组合审查。报告和 CPU 蒙皮图留 `.local/checks/source-motion-library` / `host-emotion-motion`，不提交受限曲线、材质、图像。恢复 Update 组件必须有独立 `.cs/.meta`，与 LateUpdate 预览组件分开，以便 Unity 正确序列化 Prefab；恢复序号为 Host20→Source25→Autonomy30→Performance35，避免叠加基线污染。

新增 10 组合只在浮动开发者按钮→动作实验，自动 AI 入口拒绝 `preview:false`；脸部使用该角色可靠原作形变，口型排除。没有完整 human 映射时不猜骨名。它不是原作动画，关闭开关不影响原作能力。检验脚部时对照同一帧作者 Animator 基线，不把作者的待机位移归责于新增层。

更新下载角色时必须分别编译两平台 `CharacterBundleBuilder.BuildDevice/BuildSimulator`，运行 `package_character_delivery.py --version N` 并发布新不可变 OSS 版本，不能只更新本机资源或原生 catalog。源库数包含静态姿势与显隐片段，不能宣传成等量连续身体动画；部分投影与完全不可用必须列清。

当用户希望展示 VRChat 原包的更多动作／形态时阅读本文件。基础审计与默认外观仍按 `SKILL.md`；当前发布接口见 [core.performance@1](../../../../docs/character-standard/06-performance-standard.md)。原作菜单、静态姿态、连续动画、平台功能分别处理，不能把 `.anim` 数当完整身体动画数。

## 历史：两角色的原作恢复规则（0.39.1）

**0.46当前要求优先**：用户已授权自然眨眼/呼吸与微风，读[natural-idle.md](natural-idle.md)。以下“禁止眨眼/微风”仅是旧版背景，不再作为当前限制。

琪宝/豆日向不再使用早期九段第三方会话动画。`append_source_idle` 用原 stand 恒值与原 breath 首帧相对变化合成 Idle，保持原2.5秒周期、时间点与幅度；原 clip 仍留在GLB及源采样中。所有受原表现控制的Transform都有返回基线，复位不回T-pose。面板呼吸复用同一非叠加Idle，避免原呼吸被播放两遍。

两主Prefab `enableEyeLook:0`，故不声明 `core.gaze@1`；原 `lipSync:3` 和viseme保留，但 `speech.proceduralHeadMotion:false`。`behaviors/expressions/effects/interactions` 清空的是项目后加映射，原130项表现和已导入的原morph保留。原Pet只有表情，不得用它声称原有16度摇头或自行追加触屏映射。`ambientHairAngle:0` 关闭自编风；骨链惯性仍为独立适配，不是原PhysBones求解器。源闭眼shape保留，但不能重加人工眨眼时间表。

这种恢复删除了此前错误添加的公开动作语义，故模型包升2.0.0，XCP schema/API不变。更新集合引用，保留角色ID和用户聊天数据。验证使用 `VrchatOriginalMotionReview.BuildAndReview`（Setup/Validate、逐骨源Idle比对、关闭附加动作、旧角色回归及原performance审查），随后导出并运行 `VrchatCharacterTests/testSourceOnlyCharactersSpeakWithoutAddedMotionAndKeepCamera()`；来源和最终结果见[恢复记录](../../../../docs/verification/vrchat-original-motion/README.md)。

## 已有两角色的实际入口

从项目根运行；先确认没有另一个 Editor 写同一个 stage。所有来源通过 `vrchat_source_paths.resolve_source_path` 与原 SHA-256 核验，不修改历史审计中的旧根路径。

```bash
python3 scripts/prepare_vrchat_stage.py
.local/character-sdk-venv/bin/python scripts/audit_vrchat_performances.py
python3 scripts/vrchat_performance_catalog.py
unity run "$PWD/.local/vrchat-stage" --timeout 600 -- \
  -nographics -executeMethod VrcPerformanceSampler.Export \
  -logFile "$PWD/.local/logs/vrchat-performances-sample.log"
.local/character-venv/bin/python scripts/prepare_vrchat_characters.py
.local/character-sdk-venv/bin/python scripts/validate_characters.py
```

`prepare_vrchat_stage.py` 会复制受信任的 `scripts/vrchat/VrcPerformanceSampler.cs`，但默认只运行 Inspector，Sampler 需显式执行。动作采样输出到 `.local/vrchat-stage/Inspection/Performances/{role}.json`，当前必须包含 `rest`、`motions`、`morphMotions`；旧的仅骨骼报告不足以生成完整动态表情。

目录草稿为 `docs/verification/vrchat-performance/catalog.json`，全部源选项和控制器证据为同目录 `source-capabilities.json/.md`。最终支持情况看 seal 后的 `character.json.performance` 与转换报告，不看草稿计数。当前草稿 82 / 49，实际 82 / 48；豆日向独立 SunVisor 没有主 FBX Renderer，已过滤。

转换辅助模块是 `scripts/vrchat_performance_export.py`。新角色需要经过核验的分类、中文标签、开关配对和骨骼映射；现有 source role recipe 不是通用任意压缩包转换器。

## 不可跳过的语义核对

- **原 Animator 语义**：采样自己的有效 Humanoid Avatar，把 muscle 转为真实 Transform。运行时不加载原 FX/SDK 控制器；不自动复制 SDK 内置动作。两来源菜单的 8 个 VRCEmote（Wave、Clap、Point、Cheer、Dance、Backflip、SadKick、Die）均未作为原作本地 motion 导入。
- **手性和基坐标**：当前 glTFast 镜像 X，四元数 `[x,-y,-z,w]`、位移 `[-x,y,z]`。用父 world rest 和目标 bind basis 转换，并验证 rest 回代；别机械镜像 Z 或多转 180°。2 倍米制仅属于本轮已核验来源。
- **采样**：骨骼和 morph 由 Unity 60 Hz 采样；morph 用原曲线 Evaluate 保留切线效果。不能用 YAML 最后一帧替代连续表情。该采样率不是设备 FPS 承诺。
- **零秒片段**：用常值 hold clip 平滑进入，保持“原作静态姿态”说明。入睡可显式 `next` 接睡眠循环；不能中途落回站立一帧。
- **Additive 呼吸**：剔除固定完整身体姿态，只保留变化通道并用首帧参考，避免把呼吸误当绝对姿态。
- **默认隐藏和默认非零**：要展示的隐藏配件保留网格，用 defaults 关闭；需要切换的非零 morph 保留权重，不能烘焙之后再次施加。只烘焙不会被动态保留的静态默认形变。
- **返回基线**：底层 Idle 补上耳尾、指骨、配件骨基准；当前两角色用源stand+breath恢复，不能重引入第三方会话clip。morph表现层每帧先还原，再读取下层基准。复位不等于清零全部形变。
- **路径与 UI**：只发布真实存在的 Renderer、shape 和 clip；找不到可见绑定的选项过滤并写 limitation。SDK helper 对象不是衣物 Renderer。SunVisor、NameTag 等独立 Prefab 不等于主 FBX 已包含。
- **衣着和口型**：本批目录保留上装与短裤，不开放其脱除；`vrc.v.*` 继续由 speech 驱动。该选择是本批内容配置，不推广为所有来源任意删除数据的规则。

## 已遇解析问题

Unity YAML 同时出现 `- serializedVersion: 2` 和直接 `- curve:`。日文 `attribute` 常是带 `\u` 转义的双引号文本；未解码会让整套脸部表情静默丢失。空 `path:` 不能让正则跨行吞掉下一项 classID。回归命令：

```bash
python3 -m unittest discover -s scripts/tests -p 'test_vrchat_performance_catalog.py' -v
```

发布前移除 `sourceClip`、`sourceOffClip`、`sourceMorphCurves` 等审计字段；权重由 Unity 0–100 变为协议 0–1。完整原始曲线保留在审计报告，生产只保留有效绑定和实际需要的 shape。

## Editor 审核时的已确认陷阱

- 同一 Editor 帧反复 `Animation.Sample()` 后 `Camera.Render()`，可能复用旧 GPU 蒙皮结果，造成真实坐姿／笑脸被截图成站姿／中性。先对照曲线、实际权重与 CPU `BakeMesh` 顶点差值；本轮 VisualProbe 已确认该根因。使用现有 `CharacterPerformanceReview.Capture()` 的临时 BakeMesh 渲染，不为修截图而改产品动作。临时网格完成即销毁并还原 renderer，不能把冻结角色带入生产场景。
- 原 sit 两片段都有完整下肢曲线和屈髋姿态，不要仅看 `UpperBodyTracked` 状态名就说它只含上身；不过世界椅子锚点／落座定位仍需独立适配。
- `JsonUtility` 可能把旧包缺失的可选 profile 变为空对象。统一用 `CharacterPerformanceContract.IsSupported()` 判断非空选项，不用 `profile != null`。
- 校验／预加载中的角色根节点可能 inactive。静态 `RestBounds` 只排除作者隐藏的后代和关闭的 renderer，不因根节点暂时停用丢掉全部包围盒。
- 升级角色包版本时同步集合中的 package 引用；本轮两包为 1.1.0，运行 `python3 scripts/check_character_collections.py` 核对，不能只改 manifest 留下旧引用。

## iPhone 模拟器渲染兼容

本机 Metal iOS Simulator 的内部能力为 `Has Float MSAA: 0`，但 `SystemInfo.GetRenderTextureSupportedMSAASampleCount` 对 HDR B10G11R11 descriptor 返回 4；实际附件仍为 1 sample，造成 `RenderPass: Attachment 0 was created with 1 samples but 4 samples were requested`。仅依赖该 API 的第一版兼容处理没有生效，不能把 UI 测试通过当作渲染日志无错。

运行时 `RenderCapabilityPolicy` 先查询能力，再对已识别的 iPhonePlayer + Metal + `iOS simulator` GPU + HDR 条件应用单采样/FXAA，保留 HDR、分辨率、光和影；真机仍使用真实支持的采样数。只克隆运行时管线，不改作者资产，也不隐藏 Development Console。重新导出、编译后，普通启动采集 stdout，核对 `MODELSPACE_RENDER_CAPABILITIES` / `MODELSPACE_RENDER_CAMERA` 及实际 RenderPass 错误数，同时查看截图。若未来平台修复能力报告，应在目标版本实测后缩小或移除该兼容条件。

## 验收边界

已生成角色包后，使用表现专用的 Unity 审查入口，不能只运行基础九动作的旧审查来证明全部原作选项：

```bash
unity run "$PWD/unity/CharacterRuntime" --timeout 900 -- \
  -executeMethod CharacterPerformanceReview.BuildAndReview \
  -logFile "$PWD/.local/logs/vrchat-performance-review.log"
```

该入口会 Setup、Validate、运行表现契约与数据回归并输出实际求值截图；截图需要图形模式，勿加 `-nographics`。运行报告在 `docs/verification/vrchat-performances/runtime-review.json`（复数目录），图片和渲染清单在 `docs/verification/vrchat-performance/render/`（单数目录）。这些是审查镜头；App 会话仍固定取景，坐／趴／躺可部分出框，不能把审查截图当成会话中自动缩放后的效果。最新交付范围见 [表现验收](../../../../docs/verification/vrchat-performance/README.md)。

先跑包校验与导入，再看表情／动态脸、静态手势、耳尾、穿搭 on/off、入睡／醒来、reset、说话口型以及跨角色隔离。核对非零默认、头发/衣服与大姿态碰撞，面板开关不能悄悄改相机。实际选中状态取 `characterReceipt` 与 `performanceSelections`，不是按钮本地自报成功。

本参考说明已实现转换路径，不声明所有 130 项均已逐项真机验收。最终结果和未测部分由当轮验证报告明确给出。旧包未声明 performance 时仍显示原有会话功能；扩展新分组或控制语义需升级协议和验证器，不能往 version 1 塞未知必需字段。

## 0.42.0 原作能力与控制入口

两角色原站姿呼吸仅为小幅度变化，实际原曲线最大骨旋转约0.846°/1.594°，不要凭远景看似静止就放大或重编Idle。判断冻结须同时核对原clip曲线和实际运行的`idlePlaying / idleTime / idleWeight`。两包均有口型，当前幅度驱动只是使用原viseme，不代表有原作身体讲话片段。

角色表现外置到输入框右上侧，小按钮进入同一半屏面板。非循环动作结束淡出到作者Idle；入睡`next`仍接作者循环；姿势/循环由“恢复原作默认”退出。位置编辑是 App 对角色根的显示变换，不要写回角色源包或误记成作者动作。0.44 使用右上角图标进入，小玻璃提示条除恢复按钮外可穿透；每次松手记住该账号/角色的最后状态，已经移除长按蓄力与方案列表。旧0.43选中方案只迁移一次。旋转轴采用身体中轴，单指不能连带自动平移或缩放；0.45 已取消横纵角度及圈数限制，允许上下翻转；缩放和平移仅按原始构图及设备安全区约束，不能因旋转重新构图。存储时仅做整圈等价折算。见 [位置控制设计](../../../../docs/design/2026-09-29-position-controls.md) 与 [验收](../../../../docs/verification/position-controls/README.md)。

实际发布仅名册中的两角色。源码留存的旧模型不是当前验收对象；两角色全能力检查仍运行，不使用旧默认角色断言来替代源数据校验。

0.43 根变换可保留后，命中必须使用实际显示的根变换。导入的 SkinnedMeshRenderer.localBounds/world bounds 可能与当前 CPU 烘焙不一致，需要精确网格命中时用 BakeMesh(false) 的当前局部包围盒与三角形；不要先拿旧 Renderer.bounds 排除。头部坐标再经 TransformPoint，不能额外 BakeMesh(true) 重复应用缩放。0.44的位置按钮不需要网格命中；保留的精确互动仅在用户触碰时烘焙，不逐帧扫描。

0.45 会话控制：位置图标对齐身份胶囊，提示条在聊天区域先静态布局再向上淡入。声音仅三通道音量（0 为静音）及角色专属配乐，旧布尔开关迁移为 0 音量；不能保留不可见的静音门槛。主动问候按启动/实际角色切换触发，同角色页签返回不重复，仍尊重朗读音量。见 [0.45设计](../../../../docs/design/2026-09-29-conversation-refinement.md)。

## 自动眨眼审计补充（0.45）

不能从Avatar Descriptor的`enableEyeLook: 0`推断原作没有自动眨眼。豆日向主Prefab实际FX GUID `83bcd88bbcab770428ac7be793a3613c`对应`Mamehinata_FXLayer_v1.50.controller`，其中有Auto_Blink/Blink_Control、EyeOpen/EyeClose和间隔相关参数，当前转换尚未迁移这套自动调度。后续优先按源状态机恢复，不另造时序冒充原作。琪宝尚未确认同等自动逻辑。检查FX参数驱动、BlendTree和定时转换后再给结论。详见[待机能力复核](../../../../docs/verification/idle-capabilities/README.md)。
