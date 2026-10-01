# Git 同步与本地资源恢复

## 远程和持续跟踪

- 仓库：[gukaifeng/starrynight](https://github.com/gukaifeng/starrynight)
- SSH 远程：`git@github.com:gukaifeng/starrynight.git`
- 远程名 / 主分支：`origin` / `main`
- 用户于 2026-09-30 授权首次推送与后续开发阶段的持续提交、推送。长期约定见根目录 `AGENTS.md`。
- 本机原有 SSH key 已成功通过认证，GitHub 返回身份 `gukaifeng`。私钥没有复制到项目。

首次连接遇到未知 GitHub 主机公钥，按 [GitHub 官方 SSH 指纹文档](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)核对 Ed25519 指纹后补入本机 `known_hosts`，保持严格主机校验。没有关闭主机校验，也没有更换用户密钥。

开发阶段完成后检查 `git status`、暂存差异与适用验证，写明实际完成内容，再执行 `git commit` 和 `git push`。首次使用 `git push -u origin main` 建立上游；后续在该分支直接 `git push`。推送后核对本地 HEAD 与远程分支一致。失败保留本地提交，报告阻塞原因；不强制覆盖远端。

## 公开仓库的内容边界

该仓库在建立远程时为 **Public**。Git 保存 iOS/Unity 源码、SDK 和契约、生成与转换工具、固定依赖锁、设计与文字验收记录、可分发的项目自有资源。首次基线对应 v0.46.0 / build 67，保留此前已有的 Git 历史。

以下资源保持本地原位，不删除、不改变现有本机运行环境：

| 本地内容 | 原因与恢复入口 |
| --- | --- |
| `.local/`、`build/`、Unity Library/Temp、Xcode DerivedData | 下载缓存、语音权重与运行库、引擎导出、编译产物；用固定锁文件与构建脚本恢复 |
| `character-packages/imported/`、Unity CharacterPackages、角色生成 Prefab、Resources/Characters、ViewerScene.unity | 可能含禁止公开分发的模型、贴图、原作动画与 Prefab 覆盖；通过合法取得的源包和 BuildIos.Setup 本地重建。场景留本机，不再公开跟踪 |
| 历史 Miku/RealCharacter 制作资产与 MakeHuman 中间件资产 | 当前名册不再打包；历史制作脚本、来源与署名保留，生成资产不随源码上传 |
| iOS `CharacterCatalog.json`、导入角色头像、封面与初始角色背景快照 | 由角色源数据生成，目录中也包含原作表现数据；Unity 构建工具重建 |
| `docs/verification/` 新增原始截图、录像、日志、JSON 采样及源审计 | 大体积证据或包含角色源数据；保留 Markdown 决策、结果和复跑说明。早期已跟踪的普通基线证据仍保留 |
| SDK deliverables 归档 | 可由 `scripts/package_character_sdk.py`、`scripts/package_environment_sdk.py` 从源码重新生成 |
| `ios/Config/Local.xcconfig`、证书、描述文件、私钥与 `.env` | 本机账户及签名配置；每台开发机单独配置 |

**公开 Git 仓库不是整台开发机或受限美术资源的完整备份。** 现有验收文档内的截图、录像与原始报告链接，有一部分仅在原开发机有效。克隆后不要把这些链接缺失误判为原验证从未执行，也不能把历史验证当作新机器已经构建成功。

当前琪宝、豆日向的资源声明为 `private-local-preview-only`；完整模型及采样曲线不能通过 Git 或 Git LFS 上传到公开仓库。来源版本和哈希保留在 `assets/characters/vrchat-sources.lock.json`，许可分析见 `THIRD_PARTY_NOTICES.md` 与 VRChat 导入文档。公开源码不授予第三方角色的再分发权。

## 新机器恢复顺序

当前发布名册内的第三方角色需要用户自行提供合法取得的原始资源，因此 **仅克隆仓库不能直接构建出含这些角色的完整 App**。已有开发机资源都保留。新批次来源锁为 `assets/characters/vrchat-library.lock.json`；旧两角色保留原专用转换管线。

1. 安装与项目锁一致的 Unity 6000.3.25f1、iOS Build Support、Unity CLI、Xcode 和 Python 3.11，按个人资格完成 Unity 许可；参照 `docs/environment.md` 与项目 Unity CLI 技能。
2. `python3 scripts/prepare_packages.py` 恢复固定 UPM 归档。Python 虚拟环境依赖分别在 `character-sdk/requirements.txt`、`scripts/vrchat/requirements.txt` 和 `services/character_ai/requirements.lock`；虚拟环境建在 `.local/`。
   0.60 起另执行 `python3 scripts/prepare_liltoon.py` 与 `python3 scripts/prepare_vrc_reference_data.py`，恢复固定官方渲染包与私有 mask 数据。批量审计依赖另见 `scripts/vrchat/audit-requirements.txt`。
3. v0.48起不再下载或打包离线语音模型。按[真实AI实施文档](design/2026-09-30-real-character-ai.md)准备私有Key、本机网关与客户端连接。音色绑定、SQLite和音频私有状态需要从原机器安全恢复；不能因为克隆仓库而重复付费设计音色。
4. 提供与 VRChat 来源锁匹配的原 ZIP，严格按 [VRChat 导入技能](../.agents/skills/vrchat-character-import/SKILL.md)及其 `references/performances.md`、`references/natural-idle.md` 依次审计、隔离导入、采样原作表现、生成目录与物理数据、转换 XCP 并校验。审计报告和源采样也必须重建；不能只运行最后一步 converter。不要从公开仓库寻找付费源包。
5. 恢复对应集合/背景/音乐数据后，由 `BuildIos.Setup` / 正常 Unity 导出流程生成当前角色 Prefab、场景、iOS 角色目录与头像/封面。当前名册以 `assets/characters/active-roster.json` 为准；首次恢复不能使用跳过 Setup 的故障恢复捷径。详细顺序及命令以导入技能和 `scripts/export_unity_ios.py` 为准。
6. `python3 scripts/export_unity_ios.py --platform simulator` 后执行 `bash scripts/build_host.sh`。真机使用独立 device 导出与 `scripts/build_device.sh`，个人签名设置写入忽略的 `ios/Config/Local.xcconfig`。
   0.67 起先按[角色媒体制作与恢复](character-media-authoring.md)恢复 AI 封面、头像、背景及每角色唯一音乐，并运行媒体/音乐一致性检查。生成结果与回执不随公开仓库上传；优先从原机器恢复，不重复收费制作。
   0.73 起还需恢复包内初见 PCM 及私有指纹回执；0.83 包含 33 条当前 v2 音频及 33 条旧版回放音频。运行 `python3 scripts/prepare_character_openings.py --check` 验证全部 66 项，不能把旧 ID 指向新台词音频。只有明确需要付费生成时使用 `--synthesize --limit N`，优先恢复已有文件，详见 [预制初见与删除](design/2026-10-01-first-meetings-and-reset.md)及 [v2 心声与语句边界](design/2026-10-01-clause-safe-replies-and-message-scroll.md)。后续不得因恢复或构建自动调用图片生成模型。
7. Xcode 模拟器入口为 `ios/StarryNight-Simulator.xcworkspace`，真机入口为 `ios/StarryNight.xcworkspace`；scheme 均为 `CharacterHost`。先做实际构建与运行，再记录该机器的验证结果。

源码层面的 SDK 契约测试可独立运行（安装 `character-sdk/requirements.txt` 后）：

```bash
.local/character-sdk-venv/bin/python -m unittest discover -s character-sdk/tools -p 'test_*.py'
```

这些测试使用随库示例或测试构造数据，不代表已恢复受限角色、Unity/iOS 编译或真机渲染。
