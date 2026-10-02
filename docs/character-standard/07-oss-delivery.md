# 星夜角色商店与运行包交付标准 v1

作者制作的 XCP 数据包仍是模型转换和审查的输入。手机交付的是经过同一运行时编译的角色运行包，两者用途不同：手机不运行 VRChat SDK、作者 C# 或 Editor 构建脚本。

## OSS 与服务器的职责

| 数据 | 存储位置 | 用户在下载模型前能否查看 |
|---|---|---|
| 角色名称、简介、公开设定、作者、版本、平台、大小、兼容性 | 服务器 PostgreSQL | 可以 |
| 封面、头像、带性格语气的声音试听 | 私有 OSS 独立预览对象 | 可以，使用临时 GET 链接 |
| 模型、材质贴图、骨骼、控制图、原作表情与动作、物理、场景背景 | 角色运行包内的 Unity AssetBundle | 下载并校验后 |
| 音乐、三组首次问候脚本及音频、公开配置、许可署名 | 同一角色运行包 | 下载并校验后 |
| 完整 AI 指令、供应商密钥、用户聊天、记忆、关系、账号与偏好 | 服务器及 AI 服务的已有业务存储 | 不放入通用角色包 |

一个角色的一个版本，在一个平台下对应一个 ZIP 文件。预览独立，避免为听声音先下载上百 MB 模型。`ios` 与 `ios-simulator` 使用独立运行包；即使都是 arm64，也不能把真机包当作模拟器包。

## 对象布局

```text
characters/{characterID}/
  previews/{contentSHA256}/cover.png
  previews/{contentSHA256}/avatar.png
  previews/{contentSHA256}/audition.m4a
  releases/{version}/ios/{archiveSHA256}/character.zip
  releases/{version}/ios-simulator/{archiveSHA256}/character.zip
```

图片可以是 JPEG；路径由发布计划记录，客户端不猜文件后缀。键名带内容哈希，任何字节变动都发布新对象。Bucket 保持私有。存储服务密钥只在服务器的私有配置中，不在客户端、Git、ZIP 或永久公开图片地址中。

## ZIP 内容与校验

```text
package.json
runtime/character.bundle
media/Music_<role>_*.caf
media/Opening_<role>_*.pcm
media/cover.png
media/avatar.png
metadata/character.json
licenses/LICENSE.txt
licenses/NOTICE.md
```

`package.json` 至少声明 `schemaVersion=1`、`runtimeVersion=starry-runtime/1`、角色 ID、正整数版本、平台、Unity 构建版本、AssetBundle 路径、Unity CRC 与 `files`。每个成员包含路径、字节数、SHA-256。外层服务器清单也包含 ZIP 的大小与 SHA-256，故客户端先验证传输对象，再验证每个展开成员。旧传输清单 schema 1 保持兼容，新的包格式通过 runtimeVersion 区分。

运行包使用 Unity LZ4 分块压缩的 AssetBundle；外层 ZIP 不重复压缩大型 bundle，便于低内存顺序下载与展开。每个角色自包含，构建器拒绝跨角色 bundle 依赖。编译器保留作者默认外观、原作控制器、曲线、物理、取景标定和既有后台 AI 表现映射。

客户端使用 ZIPFoundation 0.9.20，不自己实现 ZIP 编解码。拒绝绝对路径、`..`、反斜杠、空组件、重复成员、符号链接、未在清单中的成员、跨平台包及错误大小/哈希。最多 128 个归档成员，单成员 2 GiB、展开内容 4 GiB，读取前检查可用空间，避免无边界解压。生成器不写目录条目。

## 下载与激活

1. 发现页从 `GET /v1/store/characters` 获取商店资料、预览链接与对应平台大小，先展示介绍和试听。
2. 用户确认流量、空间及 Wi-Fi 提示后，以账户会话调用 `POST /v1/characters/{id}/download`。
3. API 检查角色访问权限，返回 15 分钟有效的 OSS GET 预签名链接，不转发大文件，不返回密钥。
4. URLSession 下载到临时文件，限制实际字节数，进度最多每秒更新十次，支持取消。
5. 校验和展开在下载 actor 内完成；只有完整通过后，原子写入当前版本指针。
6. 将验证后的路径与 CRC 注册给 Unity，异步加载 prefab 和背景，再进入原有渲染就绪过渡。问候语音与音乐从该角色已验证的 `media/` 读取。

缓存以账号、角色和平台隔离；重启后恢复安装索引，不重复下载。每次重试重新申请票据，不保存已过期的签名 URL。旧版本目录不被未完成下载覆盖。新版包拥有独立版本目录；运行时可在新版本通过后替换同角色 bundle，当前最多保留两个已实例化角色并释放其他 bundle 的资源。

本版支持 App 内跨页面继续下载、取消与完整重试；尚未实现杀掉 App 后继续下载或断点续传，下载确认明确建议保持 App 打开。以后可通过独立传输适配器改用后台 URLSession，而不改变 ZIP、对象布局、账号数据或 Unity 的验证后加载接口。

## 构建与发布

`assets/characters/delivery-policy.json` 控制本版哪些角色不进入内置 Resources。默认角色仍内置，以保证初次启动速度。全部角色仍可用于 Editor 的原作能力审查。

依次运行以下 Unity 方法，禁止并发写同一工程：`CharacterBundleBuilder.PrepareExisting`（已有审查场景）、`BuildDevice`、`BuildSimulator`。然后运行 `python3 scripts/package_character_delivery.py --version N`。新源码/模型有变动时，应先走正常 XCP 转换与 `BuildIos.PrepareExport`，不能把 `PrepareExisting` 当作重建模型的捷径。

产物在私有 `.local/character-delivery/N/`。服务器仓库 `cmd/asset-upload` 用官方 OSS SDK 上传与验证，`-publish` 原子登记目录和平台发布。配置、计划、签名 URL、模型与音频全部留在私有目录；只提交代码、标准与脱敏结果。下载包上传且验证成功后，才从 App 打包名单移除原来的运行副本。本机原始来源与恢复副本仍保留。

上传使用有写权限的发布凭证。服务运行阶段只有 `oss:GetObject` 即可分发预览和模型；只读权限不妨碍生成下载签名。后续新增角色无需在 App 中加入对应 mesh、图片或音频；公开描述和集合来自商店，运行资源走同一个下载/加载协议。新增需要执行代码的运行能力仍应升级 App 的运行时版本，不能把未知作者代码作为资源下载执行。

依据：[Unity AssetBundle 分块压缩](https://docs.unity.com/en-us/engine/6000.0/script-reference/unityeditor/buildassetbundleoptions/chunkbasedcompression)、[ZIPFoundation](https://github.com/weichsel/ZIPFoundation)、[OSS 官方预签名与权限说明](https://www.alibabacloud.com/help/en/oss/developer-reference/v2-presign-download)。
