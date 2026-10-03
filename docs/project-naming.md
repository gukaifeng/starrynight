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
| Xcode target / scheme / Swift 模块 | `StarryNight` |
| 编译产物 / 可执行文件 | `StarryNight.app` / `StarryNight` |
| 原生源码 / UI 测试源码 | `ios/StarryNight` / `ios/StarryNightUITests` |
| 真机 / 模拟器工程 | `ios/StarryNight.xcodeproj` / `ios/StarryNight-Simulator.xcodeproj` |
| Unity 项目 | `unity/CharacterRuntime` |

选择理由：保留「星夜」的直接意象，英文由常见词组成；连写后便于域名词干、仓库与文件夹统一，不引入另一个需要解释的中文品牌。对外介绍首次可写「星夜 · StarryNight」。

2026-09-29 检索确认 [starrynight.com 已用于 Starry Night 天文软件](https://www.starrynight.com/en/contact_us.html)。本次确定的是英文译名和工程命名，没有注册域名、创建远程 GitHub 仓库或确认商标可注册性；当时本地 Git 未配置远程；现在已使用 `git@github.com:gukaifeng/starrynight.git`。之后注册域名时围绕同一词干选择可用后缀或前缀，不把检索未发现结果当作可注册证明。

## 迁移边界与维护

- 根目录由 `ios-app` 改为 `starrynight`，原地移动完整项目，包括 Git、依赖、模型与构建缓存。
- `CharacterPrototype.xcworkspace` 改为 `StarryNight.xcworkspace`；工程生成、编译、测试脚本和当前使用说明同步更新。
- 品牌配置 `assets/brand/brand.json` 和 App 内英文签名使用 `StarryNight`。中文名和现有矢量 Logo 保持「星夜」。
- 2026-09-29 的初次迁移保留内部 targets 和 scheme；2026-10-03 用户要求在首次发布前统一工程命名，现已统一为 `StarryNight`。角色包标识、数据库键和 Bundle Identifier 继续沿用既有值，使已安装 App 的数据保持关联。
- 历史日志、原始交接文件和已校验封存的角色包保留原文；里面的旧路径描述的是生成时的位置，不作为当前开发入口。
- 运行 `bash scripts/build_host.sh` 构建模拟器，`bash scripts/build_device.sh` 构建已配置签名的真机版本；脚本均由自身位置寻找根目录。
- 真机与模拟器各自生成同目录下的独立宿主工程和 workspace，共用 `ios/StarryNight/` 源码。模拟器测试不会覆盖真机入口的 `SUPPORTED_PLATFORMS` 或 scheme。
- VRChat 工具通过项目内来源审计的受限路径重定位读取搬迁前的文件记录，继续校验来源哈希，无需修改封存角色包。

首次根目录迁移版本：0.38.1 / build 58。迁移后的实际检查结果见同目录 `verification/project-rename.json`。

## 首次发布前的工程统一（2026-10-03）

版本 0.103.0 / build 134。当前工程、运行方案、Swift 模块、可执行文件、`.app`、原生源码目录和 UI 测试目录统一使用 `StarryNight`；UI 测试 target/module 为 `StarryNightUITests`。桥接头文件为 `ios/StarryNight/Bridge/StarryNight-Bridging-Header.h`。

所有当前构建、安装、资源生成、Unity Editor 资源输出和源码验证脚本都指向新目录；根说明、Git 恢复说明和当前操作命令已同步。历史日志与封存验证中的 `CharacterHost.app` 或旧 source 路径描述生成时状态，保留原文，不作为当前执行入口。

工作区入口继续为 `StarryNight.xcworkspace` / `StarryNight-Simulator.xcworkspace`，scheme 统一选择 `StarryNight`。中文桌面名称仍为「星夜」。旧应用标识、角色 ID、账号/对话存储键和钥匙串关联没有重建。

源码目录按原地移动完成；迁移前后 614 个文件的 inode 和大小一致，角色头像、封面、音乐、开场 PCM 和忽略资源都保留。新 `.gitignore` 沿用同等资源保护，不把迁移后的受限资源加入公开 Git。验证与安装证据记录于本节。

### 完成验证

- iPhone 17 / iOS 26.4 模拟器以 `StarryNight` scheme 执行 3 项 UI 测试，全部通过：灵动岛生命周期、等待回复时切到桌面后返回同一会话、称呼页面的角色头像与全局/专属称呼保存。证据：`.local/checks/StarryNight-Rename134.xcresult`。
- 真机 Release 构建通过，`codesign --verify --deep --strict` 通过。主应用与 `ConversationIsland` 扩展同为 0.103.0 / 134；产物可执行文件为 `StarryNight`，场景入口为 `StarryNight.SceneDelegate`。
- 与迁移前产物逐项比较，设备 Bundle Identifier 和中文桌面名称保持一致；本次采用覆盖更新，沿用应用沙盒及既有账号/会话关联，不执行数据迁移或清空。
- 实际真机产物核对了 16 个角色的目录、集合、开场元数据；按下载策略包含 66 段开场 PCM 与 13 首本地音乐，3 个仅下载角色继续通过原下载机制取得资源。迁移未改变角色交付策略。
- 30 个修改过的 Python 脚本语法检查、11 个 Shell 脚本 `bash -n`、Git 差异空白检查通过；设备和模拟器共享 scheme 均不存在旧 target/product 引用。原始模型和生成图像未重新下载或生成，模拟器回归采用本地测试数据，不额外调用付费 AI 接口。

- 2026-10-03 21:05 通过已配对的同网络 iPhone 无线安装成功，并成功远程启动。设备实际回读 `name=StarryNight`、`version=0.103.0`、`bundleVersion=134`，安装容器内产物为 `StarryNight.app`。本地证据：`.local/checks/name-migration-134/device-install.json`、`device-launch.json`、`device-apps.json`。
- CoreDevice 命令起始仍会打印一次 `Code=1002 / No provider was found`，但随后建立 tunnel、取得 usage assertion，并返回成功安装与启动结果；实际退出码为 0。判断连接状态以随后设备命令结果和版本回读为准，不能把这一条初始警告误判为安装失败。

本次真机验证覆盖签名、安装、启动及版本回读；模拟器回归和上述检查不等同于真机帧率、温升或网络对话性能测试。
