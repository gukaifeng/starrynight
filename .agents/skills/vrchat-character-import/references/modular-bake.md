# Modular Avatar / NDMF 来源构建

这是隔离的来源构建步骤，不是生产工程插件，也不是角色激活命令。用于作者通过 MA Merge Animator、Menu Installer、衣物骨架合并等组件在构建时才形成完整角色的情况。先完成 batch-import.md 的来源审计和 data-only stage。

## 固定依赖与边界

`scripts/prepare_vrchat_modular_bake.py` 固定 MA 1.18.7、NDMF 1.14.8、VRC Base/Avatars 3.10.5 和 lilToon 2.3.4 的官方档案 SHA-256，只安装到 `.local/dependencies/*-bake-verified`。作者脚本、DLL 和任意 shader 仍不进入 stage；仓库的四个 Inspector 仅在 `Assets/Editor/` 作为受信代码。不要为消除 Missing Script 把作者整个项目直接打开。

官方来源依据：[MA 手动构建](https://modular-avatar.nadena.dev/docs/manual-processing)、[Merge Animator](https://modular-avatar.nadena.dev/docs/reference/merge-animator)、[官方 VPM](https://vpm.nadena.dev/vpm.json)。构建使用 `AvatarProcessor.ManualProcessAvatar`，保持作者的控制器合并次序、路径重映射及参数重命名，不在 Python 中猜合并规则。

默认来源 Editor 是 VRChat 官方要求的 2022.3.22f1，App 生产工程仍为 Unity 6000.3.25f1。2026-10-01 本机前者已安装，但尚报无有效 Editor 许可；不要循环激活或反复询问已授权动作。当前已验证 Unity 6 的隔离构建兼容流程，可以显式选该版本：

```bash
.local/character-venv/bin/python scripts/prepare_vrchat_modular_bake.py \
  --role ramune --editor 6000.3.25f1
```

输出在 `.local/vrchat-batch/bakes/ramune-6000.3.25f1/`。`--prepare-only` 仅准备，不证明构建成功。源码审计哈希改变时拒绝复用已有 stage，保留旧结果，另建经过审阅的来源阶段；不手工伪造 receipt。

## 必需的保存和读取检查

Unity 6 中发现 NDMF 的 batch serialization scope 可能在生成容器被 AssetDatabase 识别前完成。只保存 Prefab 会丢掉尚未落盘的网格、菜单和 StateMachineBehaviour；“没有 Missing Script”不足以证明成功。

仓库 `VrcModularBake` 在官方构建结束后使用 NDMF 自己的 `VisitAssets.ReferencedAssets` 和 `SingleAssetSaver` 保存仍为 transient 的引用对象。保留实际生成结果，不换回合并前的 FBX。保存后的 Prefab 再检查网格、组件和 NDMF error report，再重新实例化执行几何/动画 Inspector。手动构建产生的预览位置偏移复原为作者根变换。

保持官方二进制容器与 GUID/fileID 原位。试验中官方 Extract 在此组合下出现 `Desired root ... is not a root asset`，不能继续使用部分拆包结果或假装成功。当前用 MIT 的 [UnityPy](https://github.com/K0lb3/UnityPy) 1.25.3 只读 type tree；不执行包内程序集，不手工替换缺失 motion。

二进制引用解码必须与 Unity `AssetDatabase.TryGetGUIDAndLocalFileIdentifier` 的证据双向一致：`Inspection/Baked/<role>-references.json` 对应 `reference-validation.json`。native 有而解析器没有、解析器多出悬空引用、对象身份缺失均失败。Unity GUID 的字节表示不是 UUID 字节序；已有测试，勿凭猜测转换。

同一个 `.asset` 可以含多个 AnimatorController、菜单、mask 和状态机；不同 `.asset` 之间的状态、过渡和行为引用以 GUID + fileID 解析。不能选第一个 controller，也不能遍历一个容器中的全部菜单充当指定菜单。生成容器 GUID 每次构建会变化，因此 MA 控件 ID 由角色、菜单路径和实际参数等语义生成；同一来源重复构建要检查 ID 稳定。作者改名/改参数等版本变更仍可能需要显式迁移。

原作明确交给平台且没有 MA 合并的默认 T-Pose/IK Pose，仅用于 VR 比例和关节校准。构建后即使 SDK 物化了这些图，会话端仍保留原本的默认委托语义。不能把这个规则推广到 Action、用户菜单中的 emote、作者自定义校准动作或任意缺失引用。依据 [VRChat Additional Poses](https://creators.vrchat.com/avatars/playable-layers/#additional-poses)。

## 后续转换与禁止越级

索引成功会更新**隔离 bake stage** 的 `source-audit.json`，追加生成数据来源，不改最初的 source stage 或原包，也不把 SDK proxy 动作加入作者素材索引。之后可生成候选：

```bash
.local/character-venv/bin/python scripts/vrchat_portable_convert.py \
  --stage .local/vrchat-batch/bakes/ramune-6000.3.25f1 \
  --role ramune --output .local/vrchat-batch/converted-modular/ramune
```

该命令输出 GLB/控制图不等于通过激活；必须继续检查 materialLimitations、粒子、约束、物理组件曲线、包预算、画面和所有控件。通用 `package_vrchat_library.py` 的原 source stamp 不能手填成 bake stamp 来绕过校验；正式接入候选发布前仍需为 bake provenance 增加明确的输入路径与缓存契约。

Ramune 当前恢复 71 项控制、6 个会话控制器/109 层；1638 个控制对象的 3492 条引用匹配，两个独立构建的控件 ID 一致。仍缺眼镜框法线贴图、8 个原作粒子及抓取/头部/物理约束适配，未激活，也未为它付费生成产品媒体。详细状态见 `docs/verification/vrchat-batch-import/modular-bake.md`。
