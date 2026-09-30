# 构建时组装模型的转换进展

2026-10-01。此前已交付的 11 位角色保持不变；本阶段完成隔离来源构建和读取工具，**没有新增已发布角色**。整库仍有未完成项，见 [逐项清单](library-status.md)。

## 关键决定

Ramune 原 Prefab 依赖 Modular Avatar 在构建时合并控制器、菜单和骨架。静态读取只得到 23 项控制，不能把它当成完整角色。采用官方 MA/NDMF 构建结果，再读取数据进入现有 XCP 控制图；没有自行重写 MA 的合并算法。

来源工程与 App 工程隔离，依赖固定为 MA 1.18.7、NDMF 1.14.8、VRC SDK 3.10.5、lilToon 2.3.4。上游包的下载来源和 SHA-256 固定在准备脚本。生产工程不安装 VRC SDK；源包与生成数据保持私有。

Unity 2022.3.22f1 已安装，启动仍提示 `No valid Unity Editor license found`，一次 Personal 激活返回成功也未改变该结果。没有把这次激活记录当作许可验证通过。后续继续使用已许可 Unity 6 的独立来源 stage，2022 许可问题不影响已安装 App。

## 发现并修复的问题

- **只有内存中的结果完整。** 官方手动构建返回对象，但部分生成资源未持久化；最初保存的 Prefab 丢了 12 个网格。仅保存网格后又发现菜单、参数与行为仍会丢失。现在在构建的 AssetDatabase 编辑作用域结束后，用 NDMF 原生的遍历和保存 API 持久化所有 transient 引用；实际补齐 222 个生成对象。网格、菜单和状态行为都保留，不以作者原始 FBX 代替合并后的网格。
- **官方拆包在当前版本组合下失败。** Extract 出现 `Desired root ... is not a root asset`。最终流程保留二进制容器与身份，用 UnityPy 1.25.3 只读解析；失败实验日志仍保留。
- **同一资源不等于同一控制器。** 一个二进制 `.asset` 可以容纳多个控制器、菜单和 mask，状态机还会跨容器引用。解析器现在用 GUID + fileID 精确选取，不取文件里的第一个控制器，不把同文件所有菜单重复列出。
- **重建不应改变用户选项身份。** MA 容器 GUID 每次生成不同。MA 控件用角色、菜单路径、参数及选项语义生成稳定 ID，两个独立 stage 的 71 项控件保持一致；原作者改菜单/参数仍需要升级处理。
- **平台校准与会话动作分开。** 仅保留源 Descriptor 中明确默认、且没有 MA 合并到其中的 T/IK 校准层委托语义。普通 Action、作者动作、菜单和未知 motion 仍完整检查，不把缺动作当作空白。

## 实际验证

| 检查 | 结果 |
| --- | --- |
| 官方构建、保存后重新读取 | 成功；没有缺失网格、Missing Component 或 NDMF build error |
| 几何 | 23 个几何 renderer、535 个源节点；候选 GLB 约 21.5 MiB |
| 合并控制图 | 71 项控件、6 个会话控制器、109 个 Animator 层 |
| 解析与 Unity 原生引用交叉核对 | 1638 个对象、3492 条引用全部一致 |
| 第二个独立 stage 端到端执行 | 成功；控件 ID、名称和参数一致 |
| 已发布通用管线角色兼容 | 戚风、卡琳及新增七位的控制内容与上个提交相同；仅图内无语义的枚举顺序可能不同 |
| 导入解析单元测试 | 47 项通过，包含外部状态引用、二进制指针、带 BOM 的 YAML、同容器多菜单、ID 稳定与 native 证据不一致拒绝 |
| App/真机结果 | 此阶段没有改变生产模型、运行时或已安装 0.68.1/95；不把来源构建当成 App 交互或帧率测试 |

真实日志：`.local/logs/vrchat-modular-fresh-stage.log`、`vrchat-modular-bake-ramune-6000.3.25f1.log`；交叉证据位于 `.local/vrchat-batch/bakes/ramune-6000.3.25f1/Inspection/Baked/`。初期网格缺失、拆包失败日志位于 `.local/logs/vrchat-modular-*.log`，未删去失败证据。

隔离 Editor 日志仍有插件初始化阶段的 Harmony `mprotect returned EACCES` 及 Oculus 音频插件架构警告。它们没有作为该次 NDMF 构建错误出现，且上述数据检查通过，但不能由此认定这些插件的全部运行功能可用；它们也没有被带入生产 App。

## Ramune 尚不能激活

候选转换另外发现眼镜框材质 `Glass_frame.mat` 的 `_BumpMap` 指向 `1cb7c20344ec6b3478b08524c3ac3ba3`。在已审计的整库和固定 lilToon 依赖中没有找到它，不用其他贴图冒充。

原作还有 8 个 ParticleSystemRenderer，以及 `VRCHeadChop`、`VRCParentConstraint`、`VRCPhysBone` 类型的动态曲线，需要运行时适配和实际效果验证。用户授权的屏幕氛围粒子不能代替这些原作道具/头发粒子。正式封包还需接通 bake provenance 的发布入口、材质和资源预算检查。因此本角色未加入名册，也没有提前付费生成封面、音色等产品资源。

这阶段解决的是构建结果还原与精确读取，不能写成全部 VRChat 能力已经支持。后续 AI 可直接按 [导入技能的构建参考](../../../.agents/skills/vrchat-character-import/references/modular-bake.md) 复用流程。

官方依据：[MA 手动构建](https://modular-avatar.nadena.dev/docs/manual-processing)、[Merge Animator](https://modular-avatar.nadena.dev/docs/reference/merge-animator)、[NDMF 源码](https://github.com/bdunderscore/ndmf)、[UnityPy](https://github.com/K0lb3/UnityPy)、[VRChat 校准与动作层](https://creators.vrchat.com/avatars/playable-layers/)。
