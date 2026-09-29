# 角色集合标准 XCC 1.0

适用宿主：星夜；XCC 1.0 自 0.19 引入，2026-09-29 补充固定作者定义、封面和专属音乐边界。与现有 XCP Character API v1、Environment API v1 配合。此前分开的动作、空间、音频由集合清单确定可见范围。本规范为宿主角色集合层，不能替代模型骨骼、材质、姿势、眼神、表情、动画规范。

## 给制作者的交付物

1. 按 [角色标准](README.md) 完成模型包、动作、表情、姿势与行为路由、参数、肖像配置及授权文件。
2. 按 [空间标准](../environment-standard/README.md) 提供该角色可用空间。空间灯光、阴影和调色参数仍由空间协议定义。
3. 提供一项角色集合声明；参考 App 内实际使用的 [CharacterCollections.json](../../ios/CharacterHost/Resources/CharacterCollections.json)。全部 ID 稳定，显示名称可本地化。
4. 声音引擎/模型与音乐文件必须离线可解析，提供版本和授权；不能凭一个陌生路径让宿主下载或执行文件。此版引擎允许表仅包含 `melo-zh-v1`。增加引擎需实现宿主适配器及验证。
5. 提供固定角色封面的图像、来源/许可和构图信息，按下方封面目录关联基础 `runtimeID`；音乐必须是真正不同的该角色专属曲目，不能只改两首共享录音的显示名称。
6. 运行 `python3 scripts/check_character_collections.py` 和 `python3 scripts/validate_character_covers.py`，集合、模型和空间应一起交付，不把私聊、用户记忆或账号数据放入角色包。

机器字段基础规范见 [collection.schema.json](../../character-sdk/schemas/collection.schema.json)；schema 1 允许新增可选字段，下述音乐资源/作用域字段及跨模型、空间、真实文件引用由 `check_character_collections.py` 进一步校验。当前十个内置集合随同 App 打包，不提供运行时联网下载。

## 1.0 字段

| 字段 | 含义与校验 |
| --- | --- |
| schemaVersion | 当前 1；不支持的主版本拒绝导入/编译 |
| id / version | 集合稳定 ID / 语义版本 |
| modelID | CharacterCatalog 内的基础运行时角色 ID |
| scopeID | 可选；缺省为 modelID。自建实例填 characterInstanceID，用于隔离声音/音乐选项 ID；不改变 Unity 的基础模型身份 |
| modelPackageID / modelPackageVersion | 模型包及其确切构建版本；内置包编译时校验一致 |
| actions | 此角色按钮动作 ID 白名单；必须属于模型动作。自动对话行为仍在模型行为规则中，按当前 actorId 路由 |
| environments | 此角色可选空间 ID 白名单，不自动获得全局空间列表 |
| voices | 每项 id、title、detail、engine、speed；当前是同一个中文离线音色的不同节奏配置 |
| music | 每项 id、asset、title、detail、symbol，加可选 assetExtension、sourceModelID、sha256、duration；当前新资源按下方专属音乐规则校验 |
| defaultEnvironment / defaultVoice / defaultMusic | 必须属于各自允许列表 |

基础角色声音/音乐选项以 `modelID/option` 命名；自建实例使用 `scopeID/option`。不同逻辑集合不能重复选项 ID。空间 ID 引用受版本控制的空间目录，动作引用模型自己的 ID。同底座自建实例可以继承相同只读音源；不同内置角色必须拥有不同录音。这个角色没有声明的项目不得出现在界面，也不能通过保存或预览接口绕过允许范围。

## 固定作者定义与使用者偏好

集合说明“这个角色具备什么”，不代表聊天使用者可以改写全部角色内容。当前会话先由 `ModelDescriptor.conversationProfile(preserving:)` 恢复作者定义，再保留有限的听众偏好；只在 UI 隐藏按钮不足以满足这个约束，读取、保存和运行时提交同样要使用该边界。

| 数据 | 归属与当前行为 |
| --- | --- |
| 名称、人设、性格、语气、角色背景、外观、声音设定、环境/灯光、默认取景与姿势 | 作者定义；内置角色来自基础定义，自建角色来自创建时保存的 authoredProfileSnapshot。订阅者的旧本地 profile 不能覆盖它们 |
| 可用动作、姿势、空间、声音与音乐目录 | 模型包/集合声明；创建时保存快照，受到集合白名单与模型能力约束 |
| 自动朗读/静音 `autoSpeak` | 当前账号 × 当前角色实例的听众偏好；新使用者默认开启 |
| 音乐启停、已声明曲目选择、音量 `audio` | 当前账号 × 当前角色实例的听众偏好；新使用者默认关闭音乐、使用集合默认曲目和 28% 音量 |
| 私聊、记忆、进度及消息语音缓存 | 使用者的数据；不得写入作者定义、封面、角色包或另一个账号的记录 |

作者在创建流程中决定角色定义；发布/取消发布控制可见性，不从当前使用者会话反向抓取设定覆盖已保存的作者快照。需要新增“编辑并发布新版本”的能力时，应提供显式的作者更新与版本迁移流程。引擎仍能播放动作、表情和语音，临时表现不等于修改公开角色定义。

## 身份与存储作用域

- `runtimeID`：模型引擎资源实例的基础 ID，用于 Unity 选模、行为和肖像生成。
- `characterInstanceID`：用户创作的角色 ID；从同一底座创建两个角色，也必须生成两个不同 ID。
- `accountID + characterInstanceID`：朗读静音、音乐启停/曲目/音量、私聊及记忆的保存作用域。存档中仍有旧版可编辑 profile 字段不代表它们能覆盖固定作者定义。
- `CharacterCollection`：声明的选项集，用户新建时作为快照保存在 `OwnedCharacter.collection`。同底座实例可共用资源文件，但不共用用户偏好；本次旧音乐升级为下述明确的兼容迁移。
- 全局音频会话只负责硬件所有权和语音压低背景音乐；每次换角色，先停止上一角色播放器，再加载新角色偏好。它不再拥有全局曲目/音量偏好。

发布内容为设定与集合快照。另一个账号打开公开角色会创建自己的本地记录，首次默认开启朗读、关闭音乐并采用集合默认曲目和28%音乐音量，不继承作者个人的静音/音乐开关。创作者修改用户偏好不会反向覆盖使用者；更新公开设定需显式操作。用户记录不会反向写入角色包。

## 固定封面目录

[CharacterCoverCatalog.json](../../ios/CharacterHost/Resources/CharacterCoverCatalog.json) 是与 XCP 肖像配置分开的宿主封面目录。当前 `schemaVersion=1`，每项包含唯一 `runtimeID`、Asset Catalog 图像键 `asset`、封面选用的 `environmentID`、归一化裁切焦点 `focusX/focusY`。`frameBottom/cameraYaw` 供离线渲染器复现构图，当前 UI 只读取焦点进行卡片/横幅裁切。

封面按 `model.runtimeID` 查找，不按用户昵称、当前房间或聊天偏好重新生成。作者封面应能识别角色，同时体现配套背景；需登记真实资源、生成证据和许可。缺失时宿主回退该角色缩略图，不能显示其他角色封面。

**当前本地创建角色继承基础模型的封面。** 新实例有自己的名字、定义和逻辑 ID，但尚无按实例上传/生成独立封面的流程；不能宣称已经有这项能力。未来增加实例封面应增量扩展关联与来源校验，不复用另一基础模型的 `runtimeID`。封面和头肩圆形头像是不同资源，也不把听众的音乐/静音/记忆编码进任何图像键。

## 专属音乐与实例迁移

当前每个内置角色至少提供两首独立录音。`asset` 使用安全的资源文件名键；新内置音频为 `CAF / Apple Lossless`，`assetExtension="caf"`，`sourceModelID` 指向物理音源所属的**基础模型**，`sha256` 为实际文件 SHA-256，`duration` 单位秒。文件名以 `Music_<modelID 中连字符转下划线>_` 开头，角色间文件名和文件内容哈希均不重复。完整音色、循环、无损回译和来源记录见[专属音乐设计与验证](../verification/character-music/README.md)。

`CharacterCollection.scoped(to: characterInstanceID)` 保留快照动作、环境和声音配置，从同一 `modelID` 的当前内置目录获取该角色专属音乐，再将声音/音乐/default IDs 映射到实例前缀。示例：基础 `anime-uka/moon` 变为 `character-<uuid>/moon`，其 `sourceModelID` 仍为 `anime-uka`，物理文件只读共享。第二个优可底座实例必须使用另一个前缀，不共用选择状态。

旧快照可以缺少上述可选字段，原来引用 `IslandAfternoon` / `MoonlitTide` 的快照在 scoped 迁移时会获得基础角色的新专属曲目。已有基础前缀选项按稳定 suffix 对应到实例新 ID，保留音乐启停和音量；其他角色、同底座兄弟实例的选项 ID 不被接受，回到当前实例默认。此迁移仅升级音乐来源，不解冻原有环境或动作目录。

构建前必须校验来源角色、选项前缀、文件真实哈希、作者审计中的乐谱/PCM唯一性以及循环接缝；不能仅检查文件存在。新专属曲目不能退回用旧两首 WAV 充数。旧 WAV 仍可被旧 schema 快照解析，但当前会话进入 scoped 集合后使用升级曲目。音频会话保持同角色换曲淡入淡出、语音压低音乐、录音/离开/锁屏暂停；跨角色先停止旧播放器。

## UI / Runtime 边界

作者制作/创建 UI 通过 `model.collection.availableEnvironments`、`voices`、`music` 取选项；听众会话当前只开放专属音乐选择、静音及个人数据等入口，不因目录含多个空间/声音就自动开放角色编辑。按钮动作在集合白名单和当前姿势支持动作的交集中显示。`collection.normalize(profile/studio)` 校验合法范围，`conversationProfile(preserving:)` 另负责恢复固定作者定义；两者不能互相替代。Unity 原有空间/角色数据格式不变，允许范围在宿主提交前验证。

后续远端服务、插件或其他宿主入口若能直接提交 Runtime 命令，必须同样执行集合授权校验，不能将 Unity 内部全局资源目录当作用户可选列表。

## 迁移与扩展

- 0.18 存档新增字段全部可选。未提供声音、音乐时取当前集合默认；不把旧全局音乐偏好批量复制到角色。
- 旧自建角色没有集合快照时，按其基础模型的当前内置集合解析；新创建的角色保存快照。非法空间调色记录会从该角色存档清理，聊天和记忆不受影响。
- 同一主版本允许添加可选字段，旧宿主忽略未知可选字段；删除、改变字段语义、替换骨骼/空间约束等破坏性变化必须提升主版本并提供迁移器。
- 资源 ID 不复用给不同语义；增加选项不自动改变旧实例快照。上述“共享两首占位曲升级为同基础角色专属音乐”是本版明确迁移，其他目录变更仍需显式定义迁移。
- 当前本地适配不是服务器安全边界。联网后服务端仍需校验所有权、可见性、发布状态、集合版本和资源授权。

本标准提供版本协商和迁移路径，不承诺所有未来变化都能做到零兼容成本。
