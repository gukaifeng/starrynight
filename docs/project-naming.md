# 星夜 / StarryNight：正式命名与目录

确定日期：2026-09-29。

## 统一约定

| 场景 | 名称 |
| --- | --- |
| 中文产品名、手机桌面名称 | 星夜 |
| 英文正式名称 | StarryNight |
| 英文语义 | Starry Night，繁星下的夜晚 |
| GitHub 仓库名、本地根目录、URL 路径片段 | `starrynight` |
| 新增代码中需要的品牌名 | `StarryNight` |
| 域名词干 | `starrynight`，实际域名另行查询、注册 |
| 当前本机根目录 | `/Users/gukaifeng/Documents/starrynight` |
| Xcode 真机 App 入口 | `ios/StarryNight.xcworkspace` |
| Xcode 模拟器 App 入口 | `ios/StarryNight-Simulator.xcworkspace` |
| Xcode scheme / 宿主实现目录 | `CharacterHost` / `ios/CharacterHost` |
| Unity 项目 | `unity/CharacterRuntime` |

选择理由：保留「星夜」的直接意象，英文由常见词组成；连写后便于域名词干、仓库与文件夹统一，不引入另一个需要解释的中文品牌。对外介绍首次可写「星夜 · StarryNight」。

2026-09-29 检索确认 [starrynight.com 已用于 Starry Night 天文软件](https://www.starrynight.com/en/contact_us.html)。本次确定的是英文译名和工程命名，没有注册域名、创建远程 GitHub 仓库或确认商标可注册性；当前本地 Git 未配置远程。之后注册域名时围绕同一词干选择可用后缀或前缀，不把检索未发现结果当作可注册证明。

## 迁移边界与维护

- 根目录由 `ios-app` 改为 `starrynight`，原地移动完整项目，包括 Git、依赖、模型与构建缓存。
- `CharacterPrototype.xcworkspace` 改为 `StarryNight.xcworkspace`；工程生成、编译、测试脚本和当前使用说明同步更新。
- 品牌配置 `assets/brand/brand.json` 和 App 内英文签名使用 `StarryNight`。中文名和现有矢量 Logo 保持「星夜」。
- 保留内部 targets、scheme、角色包标识、数据库键和 Bundle Identifier，避免把改品牌误变成另一个 App 或丢失已有聊天资料。
- 历史日志、原始交接文件和已校验封存的角色包保留原文；里面的旧路径描述的是生成时的位置，不作为当前开发入口。
- 运行 `bash scripts/build_host.sh` 构建模拟器，`bash scripts/build_device.sh` 构建已配置签名的真机版本；脚本均由自身位置寻找根目录。
- 真机与模拟器各自生成同目录下的独立宿主工程和 workspace，共用 `ios/CharacterHost/` 源码。模拟器测试不会覆盖真机入口的 `SUPPORTED_PLATFORMS` 或 scheme。
- VRChat 工具通过项目内来源审计的受限路径重定位读取搬迁前的文件记录，继续校验来源哈希，无需修改封存角色包。

本次版本：0.38.1 / build 58。迁移后的实际检查结果见同目录 `verification/project-rename.json`。
