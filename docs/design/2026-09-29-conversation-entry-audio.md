# 会话再进入与默认音乐

本次按新的产品要求替代早期「每次进入都问候」策略。角色的首句介绍属于当前账号和角色之间的第一次相遇，不能绑定到每次页面呈现。

## 问候规则

- 当前账号的当前角色既没有 `CharacterRecord.greeting`，也没有历史消息：会话稳定显示之后，按首次启动或首次认识角色的场景发送一条问候，并沿用角色的声音自动播放。用户已静音时仍尊重静音。
- 已有问候，或旧版留下任意聊天历史：切换底部菜单、从消息进入、换角色后再回来、前后台切换及重新启动 App 均不再追加或重播问候。
- 新账号和新的角色实例各自保留首次机会；游客资料迁入新账号时连同已认识的关系一起迁移。
- 清空显示的聊天消息不会抹掉独立保存的问候记录，所以不会因为清空聊天而重新问候。
- 用户主动输入、录音或已有回复优先于尚未交付的问候。关闭资料页后会再次检查历史，避免等待期间已经聊天却仍插入自我介绍。
- 不改消息内容、语音音色、角色动作、取景或模型包。原有其他返回场景的文案接口保留供以后显式功能使用，本轮不会自动调用。

实现复用现有账号／角色命名空间；`ConversationGreetingPolicy` 只读取当前记录，没有全局一次性开关，也不依赖页面 UUID 作为是否认识的依据。`CompanionSession` 在接受进入和真正交付两个时点检查策略，成功持久保存首条消息之后才播音。

## 音乐规则与旧配置

新会话默认启用角色自己的默认曲目，音量保留原有 28% 起点。曲库和选择仍以角色实例隔离，明确暂停、选择曲目和音量的操作按账号和角色保存。

继续使用已有播放器生命周期：说话时压低伴奏，录音、离开会话和后台暂停；同一会话回到首页时恢复原播放位置。用户显式暂停后，不会因返回、重启或其他角色开始播放而被重新开启。角色语音静音与背景音乐暂停是两个独立选项。

旧版 `enabled=false` 同时代表默认关闭和手动关闭，无法可靠还原当时的操作意图。本次增加可选的 `autoplayVersion`：旧配置缺少该字段时按新的默认播放规则归一化，保留原曲目和音量；新版创建或保存的设置带版本 1，此后保存的 `false` 始终代表用户暂停。没有改写旧配置文件结构版本，也不重置聊天或其他偏好。

## 验证入口

- `AuthorSubscriptionUITests/testCoreMigrationAndSocialContracts()`：通过现有的 `--social-core-check` iOS DEBUG 模拟器入口运行生产数据模型和 `CharacterLibraryTests` 断言，覆盖音乐默认、旧配置迁移、暂停持久化以及账号／角色隔离。未新增运行时依赖或测试入口。
- `ProactiveGreetingTests/testGuestEntriesSpeakWithoutSpendingTurnsOrChangingFraming()`：首次真实问候与语音；返回、换角色返回和前后台不重复。
- `ProactiveGreetingTests/testSignedInLaunchAndMutedGreetingPersistAcrossRestart()`：登录状态、静音和已问候关系跨重启保留。
- `ProactiveGreetingTests/testMusicAutoplaysAndExplicitPauseSurvivesReturnsAndRestart()`：实际播放器自动播放；手动暂停后跨菜单、角色及重启仍暂停，另一角色仍使用自己的默认音乐。
- `AuthoredCharacterTests/testCAFPlaybackAndMusicPreferencesStayInsideEachCharacter()`：实际 CAF 资源、私有曲库、音量及所选曲目的角色隔离。

上面列出的是验证入口；真实设备与模拟器的执行结果由本轮验收记录另行注明，不把新增测试代码本身当作通过证据。

独立 `bash scripts/test_character_library.sh --greetings` 首次尝试发现原作表现的数据类型与 SwiftUI 页面混在一起，纯 Swift 输入清单缺失。已将 `CharacterPerformanceProfile` 原样拆成只依赖 Foundation 的文件，并补齐测试所需曲库资源。修复后 `CharacterLibraryTests` 编译成功，但本机执行再次遭 SIGKILL（exit 137），与项目历史已记录现象一致；没有得到断言通过结果，也没有修改系统安全设置或签名策略。原始结果在 `docs/verification/conversation-entry/native-core-tests.txt`。本轮以既有 iOS DEBUG 核心检查和实际 UI 回归作为执行证据。
