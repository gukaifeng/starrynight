# 星夜角色制作 SDK · XCP 1.1

0.94 新增 [core.source-motions@1 原作片段库](../docs/character-standard/10-source-motion-library.md) 和 [机器 Schema](schemas/source-motions.schema.json)：独立来源片段、有界 gzip JSON、实际节点/形变绑定和可逆预览。原作菜单不被替换；宿主的 10 个附加组合仅在开发者页面预览，不写成作者原装动画。运行时下载使用 [OSS 平台资源包](../docs/character-standard/07-oss-delivery.md)，与制作方源 XCP 交付分开。

0.46 新增可选 [core.autonomy@1 自然待机](../docs/character-standard/07-natural-idle-standard.md)：眨眼调度、原作静态姿势呼吸与衣发环境风。源曲线和App适配须分别说明；不声明该能力的旧包维持原行为。

> 近伴 0.19 新增角色集合：请一起交付 `collection.json`，遵循 [XCC 1.0](../docs/character-standard/character-collections.md) 和 [集合 Schema](schemas/collection.schema.json)。集合文件作为模型包的配套声明，由应用团队合入 `CharacterCollections.json`；当前构建时装入 App。旧 XCP 模型包本身的封装不变，不把用户私聊装入公开集合。


这是角色制作方的独立交付入口。无需修改小伴的 Swift / Unity 业务代码；按规范制作 GLB 和 `character.json`，通过预检后交给应用团队导入。

先读 [完整制作规范](../docs/character-standard/02-model-production.md)，再看 [可直接发送给其他 AI 的任务书](../docs/character-standard/03-ai-handoff.md)。机器规范是 [character.schema.json](schemas/character.schema.json) 和 [signal.schema.json](schemas/signal.schema.json)。

可选扩展 [core.performance@1 原作表现标准](../docs/character-standard/06-performance-standard.md) 支持角色独立的表情、静态姿态、连续动作、手势、耳尾和穿搭目录。发布清单使用当前 Schema，引用真实 GLB clip／形变／Renderer；未声明该能力的旧包保持原有会话功能。该标准已随源码及当前 StarryNight SDK 1.1 压缩包交付；历史 Xiaoban 压缩包不代表当前标准。

最小可运行样本位于 [examples/sample-robot](examples/sample-robot/character.json)。它包含真实 GLB、7 个可用动作、4 个表情、头部触摸规则、两种特效映射、材质颜色选项和 CC0 来源说明。该样本用于验证集成，不代表写实角色的美术质量标准。

## 制作方独立使用

需要 Python 3.10+。使用虚拟环境，避免改动系统 Python：

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r character-sdk/requirements.txt
.venv/bin/python character-sdk/tools/character_tool.py seal my-character
.venv/bin/python character-sdk/tools/character_tool.py validate my-character
.venv/bin/python character-sdk/tools/character_tool.py pack my-character my-character-1.0.0.xcp
```

可以先用 `python character-sdk/tools/character_tool.py inspect model.glb` 列出源节点路径、动画、morph 和材质，辅助填写清单；最终仍以 Unity 绑定验证为准。

`seal` 重新计算资源 SHA-256 和大小；修改模型、贴图或授权说明后必须重跑。`pack` 只接受通过验证的包，输出文件必须放在源包目录之外。`.xcp` 是有严格路径、大小和内容限制的 ZIP；根目录直接放 `character.json`。校验失败应修复源资产，不能关闭校验。

```bash
.venv/bin/python character-sdk/tools/character_tool.py compare old/character.json new/character.json
.venv/bin/python character-sdk/tools/test_character_tool.py
```

`compare` 是静态兼容审查，不承诺动画视觉效果相同，也不能代替真机性能与穿模验收。

## 应用仓库接入

本机已准备 `.local/character-sdk-venv`。新环境先运行：

```bash
python3 -m venv .local/character-sdk-venv
.local/character-sdk-venv/bin/python -m pip install -r character-sdk/requirements.txt
```

打开本仓库 Unity 工程，确保 `unity status --format json` 显示 ready，然后：

```bash
.local/character-sdk-venv/bin/python scripts/import_character.py /path/to/my-character-1.0.0.xcp
python3 scripts/export_unity_ios.py --platform simulator
bash scripts/build_host.sh
bash scripts/run_simulator.sh
```

导入会验证包、复制到 `character-packages/imported/<id>`、通过 glTFast 导入模型和动画、绑定声明、烘焙动作取景范围、生成预览图和原生端 `CharacterCatalog.json`。导入失败会撤销源包注册；若 Unity 已产生中间资产，修复后重新执行 `BuildIos.Setup()` 即可重建场景。

已有同 ID 包默认禁止覆盖。兼容升级显式使用 `--replace`；静态审查发现破坏性变更时会拒绝，需要先编写迁移或分配新角色 ID。`--source-only` 只注册通过预检的源文件，随后正常导出仍会执行引擎验证。

制作方源 XCP 仍为**构建时导入**；运行包可内置或由私有 OSS 下载，当前三角色已采用远程分发。App 不向终端用户提供“选择任意 VRChat ZIP 即时加载”。源包、受支持能力和经过验证的平台 Bundle 是三个不同边界。

1.1 新增 [持续姿势标准](../docs/character-standard/05-posture-standard.md)。完整示例现有站/坐姿势、前倾参数、姿势专用动作，真实资源都在 GLB 内。运行全部 SDK 回归使用 `python -m unittest discover -s character-sdk/tools -p 'test_*.py' -v`。
