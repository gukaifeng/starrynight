# 第二批候选预检与来源解析补齐

日期：2026-09-30。本阶段是候选预检，**没有新增或替换已发布角色**。手机已安装的版本仍为 [0.61.0（87）](../ambient-portrait/README.md)，保留琪宝、豆日向、戚风、卡琳。公共解析修复先复核已发布包，再用于下一批来源；原档案未改动。

## 已完成的通用修复

| 问题 | 处理与实际边界 |
| --- | --- |
| 独立 BlendTree 被当成缺少的动画 | 同时读取控制器内的树及外部 `.asset`，按 GUID + fileID 处理嵌套、去重与循环；宿主控制协议不变 |
| 完整 Prefab 没有直接序列化 Descriptor | 沿实际 `m_SourcePrefab` 发现嵌套 Descriptor，保留作者场景与全部候选变体；重新选择后强制重新检查 |
| 构建时合成的控制器被误判成不存在 | 发现源 Merge Animator 指令就记录未适配能力，不能把“零菜单”当成完整转换成功 |
| 转换器升级仍可复用旧候选 | 增加转换输入/工具签名；旧回执缺签名、源版本或主 Prefab 不符均拒绝元数据复用，要求重新生成 |
| 所有缺引用被混称为原包缺文件 | 从固定 SHA-256 的官方 SDK ZIP 只读建立 GUID/路径索引，区分官方平台引用和仍未定位的引用；没有提取平台动画或把名字当成实现 |

这些改动影响后续来源转换工具，不修改已安装 XCP 的可读性。旧四角色的运行时回归和手机交付见 0.61 记录。

## 下一批的具体发现

- **Plum / Siska**：独立树展开后仍有可达平台动作引用；它们主要来自官方 SDK，不是通过反复解压作者档案就能补上的作者动画。既有中性手适配以外的代理没有被替换成空动作。
- **Ramune**：主来源应是 `Ramune/Ramune.prefab`，Descriptor 继承自 Base。原先选中的 Gomenne 是另一个简化变体。重新完成隔离 Unity 检查，完整根包含 23 个 skin，源采样列出 245 个 motion；控制解析识别 23 个现成菜单项、19 处 Merge Animator 指令，以及未支持的状态行为。245 个采样条目不代表 245 个可用身体动作；构建合并尚未实现，不能激活此候选。
- **Torao**：发现 Black / White 成品变体，不再把 Parent 根当作默认成品；Black 变体已重新检查。候选仍有平台动作依赖，尚未做发布画面和交互验收。
- **Lime**：前次转换记录有三个材质槽引用同一未解析的 AlphaMask；不使用白贴图顶替。还需要刷新旧工具生成的 inspection。
- **龙胆**：仍只有服装，没有本体，继续按用户要求跳过。

预检在已有采样清单上重新读取源控制图。`inspectionCurrent=false` 明确表示几何/采样还需用当前工具重跑；这种记录只能定位缺口，不能作为打包放行依据。`graph-ready` 同样不代表材质、包预算、AI 数据、设备性能已经通过。

本次完整重跑覆盖 40 个来源条目，使用同一版解析器：已发布的戚风、卡琳为 `graph-ready`，38 个条目暂缓。36 个条目存在未提供给宿主的可达 motion，其中 21 个条目的这些引用全部能定位到官方 SDK，另外 15 个还含未定位引用；其余两项是青柠的旧检查/材质缺口与龙胆缺本体。只有四个条目的 inspection 为当前工具版本；没有把旧采样重新标记为已刷新。此统计包含琪宝高版本候选，不等于 40 个不同的已发布角色。

## 验证与续跑

- 控制解析、严格缺依赖、转换缓存、来源变体检查及 SDK 索引共 **10 项测试通过**；嵌套 Prefab 计划选择另有 **2 项通过**。
- 新解析结果与已发布戚风 31 项、卡琳 16 项的参数、控制、状态图、mask、中性手适配逐字段一致；证据 `.local/vrchat-batch/batch02-compatibility.json`。
- Ramune / Torao 的重新隔离导入均成功；`.local/logs/vrchat-batch02-inspection.log`。这是数据检查，未冒充 App 中实际画面验收。
- 导入技能 `quick_validate.py` 通过，Python 语法和 Git 差异检查通过。控制转换测试使用 `.local/character-venv`，计划测试使用有 `libarchive-c` 的 `.local/character-sdk-venv`，不能混用依赖环境。
- 详细图、GUID、源路径和状态留在 `.local/vrchat-batch/capability-preflight.json`；私有日志与模型不公开推送。

续做时先查该报告里的平台引用、真实未解析资源、组装指令和旧 inspection 标记，选能完整适配的小批次。补能力后重跑来源检查、转换、包校验、实际画面和控制复位，再激活、编译及安装；不要手工补签名或跳过缺口。

运行命令和已知陷阱已更新到 [导入技能](../../../.agents/skills/vrchat-character-import/SKILL.md) 的 [分批参考](../../../.agents/skills/vrchat-character-import/references/batch-import.md)。控制标准见 [可移植控制标准](../../character-standard/09-portable-avatar-standard.md)。平台动画分层依据 [VRChat Playable Layers](https://creators.vrchat.com/avatars/playable-layers/)，构建合并语义依据 [Modular Avatar Merge Animator](https://modular-avatar.nadena.dev/docs/reference/merge-animator)。
