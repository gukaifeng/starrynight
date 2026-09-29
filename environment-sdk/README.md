# XEP 1.0 场景制作 SDK

先读 [制作规范与 AI 任务书](../docs/environment-standard/01-production.md)，对照 [Schema](schemas/environment.schema.json)。完整 SDK 同时带上 character-sdk 中的通用资源检查工具及 Python 依赖；两个包的业务协议独立。

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r character-sdk/requirements.txt
.venv/bin/python environment-sdk/tools/environment_tool.py validate environment-sdk/examples/courtyard
.venv/bin/python environment-sdk/tools/environment_tool.py seal my-environment
.venv/bin/python environment-sdk/tools/environment_tool.py pack my-environment my-environment-1.0.0.xep
.venv/bin/python environment-sdk/tools/environment_tool.py compare old/environment.json new/environment.json
```

应用仓库内导入：

```bash
.local/character-sdk-venv/bin/python scripts/import_environment.py my-environment-1.0.0.xep
python3 scripts/export_unity_ios.py --platform simulator
bash scripts/build_host.sh
bash scripts/run_simulator.sh
```

要求本仓库 Unity Editor 就绪。`--replace` 只允许通过兼容检查的同 ID 升级；`--source-only` 只登记源包，后续导出仍做引擎检查。源包注册失败会回滚，若留下 Unity 中间资源，修复后重新执行 BuildIos.Setup 重建。构建阶段自动生成场景目录、绑定与预览图，并以目录哈希核对宿主和导出。

当前没有手机内上传/下载入口。制作工具的静态校验不能证明美术质量、动作无穿插或持续真机帧率。
