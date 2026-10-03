# 发现页下载状态与角色声音升级（0.95.0 / build 126）

## 结果与边界

本轮保留 16 个完整对话角色，模型包版本仍为 3.4.0；三个 OSS 下载角色的 release 仍为 2。不重新制作角色资源，不调用图片生成模型。修改涉及原生界面、个人声音设置迁移与开发验证入口，无 Unity 内容或服务端实现变更。

发现卡片均为封面 + 固定高度名字行 + 固定高度简介行。名字右侧预留 14×14 点状态位：待下载箭头、实时进度环、完成勾选、失败重试符号。内置角色也保留同样空位，因此是否需要下载、进度变化、安装完成都不会添加一行或改变卡片尺寸。VoiceOver 从整个卡片读出下载状态。

下载确认改为最大 380 点、左右至少 16 点留白的深色卡片；保留下载量、安装空间、Wi-Fi 提醒、取消和确认。独立的全窗口遮罩接收外部取消点击，淡入淡出，不调整底下角色的摄像机。简体、繁体、英文沿用应用语言设置。

位置、声音、氛围共用页签行右侧的复位图标，图案约 12 点，触控区 44×44 点，读屏标签仍为“恢复默认”。原位置说明区继续允许触控穿透，删除旧复位矩形对该区域的拦截。声音面板从 214 点缩到 166 点，氛围从 166 点缩到 134 点；声音通道改名为“角色语音”，另一个明确为“背景音乐”。

## 静音原因与迁移决策

直接读取手机 App 的本地资料确认：当前名册中有 9 个角色仍保留预览时期的 `autoSpeak=false / speechVolume=0 / volumeControlsVersion=1`，其他记录中还存在用户已手动调高语音但 `autoSpeak=false` 的旧预览状态。原始资料只作本机私有备份，未提交用户对话、记忆、身份或其他个人数据。

完整角色目录本身已不是预览，问题在于个人历史设置仍把声音保持为零；缓存/自建角色的旧 `previewOnly` 集合快照还可能退回预览行为。本轮同时修复：

1. 当本机对应包已经升级为完整角色时，旧预览集合使用当前完整集合，再进行独立角色的命名空间映射。未来仍只有预览内容的未知角色不会被强行冒充完整角色。
2. 音量设置升级到 `volumeControlsVersion=2`。新角色明确默认语音 100%、音乐 28%。已有版本 1 的零语音音量在升级时恢复一次；旧预览强制静音的音乐恢复为 28%，已有非零语音音量保留。
3. 历史版本 1 无法可靠区分用户主动零语音与预览遗留零语音，按本次“统一正常化”要求进行一次修复。该边界不伪称能识别所有旧版手动意图。版本 2 起主动将音量降到 0 会正常保留，不会在角色切换或重启时自动开声。
4. 后续真正的预览状态显式记录 `previewSilenced` 来源，转为完整角色时移除系统强制静音，不再丢失来源。旧的独立总静音开关兼容逻辑保留。
5. 创建会话时将升级后的音量及自动播放标志写回原记录；修改只针对声音偏好，不删除聊天、记忆或相处进度。新标记随既有账户设置 JSON 同步，不需要服务端更改协议。

## 验证

- 16 角色目录/音乐归属/哈希与循环检查通过。
- iOS 原生隔离验证：`CharacterModelReviewTests` 104 项检查通过（16 完整、0 预览），`CharacterAudioUpgradeTests` 193 项检查通过。覆盖每个角色的新默认值、旧预览激活、部分已调高音量、幂等、现代静音编码/重读、缓存快照和自建实例隔离。不构造实际付费请求。
- `DiscoverDownloadLayoutTests` 3 项通过：初始声音/迁移检查、下载和内置卡片尺寸一致、确认卡片的宽度及外部取消/取消按钮/确认回调。取消路径不启动下载。
- `ConversationSettingsTests` 2 项在包含实际 Unity 的 iPhone 17 模拟器通过：三页外部关闭；短拖拽不能误关闭；三个复位按钮；音量/氛围不改变角色位置；横竖屏安全区域适配。

- `ProfileSoundTests/testTwoRealSoundChannelsMutePersistAndStayIsolated` 在实际 Unity iPhone 17 模拟器通过：默认语音 100%、手动静音、App 重启保留音量、另一角色默认声音独立；复位按钮与页签同一行。
- 最终 iOS Release 签名构建与 `codesign --verify --deep --strict` 通过。

iPhone 17 已成功安装并启动 **0.95.0 / build 126**；`devicectl` 安装、启动均返回 success。保留应用数据进行升级安装。启动后从手机再次读取资料，Koharu 的旧 `autoSpeak=false / speechVolume=0 / musicVolume=0 / version=1` 已实际升级为 `true / 1 / 0.28 / version=2`；原消息与记忆 ID 均保留。其他角色在各自创建会话时进行相同幂等升级。模拟器布局与数值检查不代表真机听感或渲染帧率实测。

原始结果、截图、构建日志与手机资料备份存放于 `.local/checks/discover-sound-v095/`、`.local/checks/*v095*.xcresult`、`.local/logs/*v095*`，不进入公开 Git。

## 处理过的问题

- 下载确认协调器的 Swift 6 闭包跨隔离编译错误：明确 UIKit 协调器为主 actor，设备/模拟器重新编译。
- 确认卡片没有显式的读屏容器，容器标识覆盖了内部按钮标识，导致自动化找不到已经显示的下载/取消按钮：为卡片声明 `children: .contain`，验证按钮身份与确认行为。
- 音量测试没有固定语言，新增“角色语音”的英文翻译导致中文断言失败：测试明确简体中文，保留产品多语言能力。
- 早期 UI 构建尚未包含刚加入的隔离下载检查入口，保留失败日志并用最新工程重建，未将旧构建失败当作通过。
- macOS 独立 Swift 检查可编译，但执行以 SIGKILL/137 退出，临时重新签名仍未恢复。改在 iOS 模拟器运行同一纯 Swift 检查；不关闭系统或公司的安全软件，未声称已查明 SIGKILL 根因。

## 复跑

```sh
# 不调用付费 AI；原生隔离 UI 与真实 Unity UI 分开报告。
bash scripts/test_native_ui.sh DiscoverDownloadLayoutTests Discover-Download-Review
zsh scripts/test_companion.sh 99F5FAC6-A73A-4C59-A723-D57D648B342E 'ConversationSettingsTests,ProfileSoundTests/testTwoRealSoundChannelsMutePersistAndStayIsolated()' Sound-Settings-Review
bash scripts/build_device.sh
```

`bash scripts/test_character_library.sh --audio` 适用于能执行本机 Swift 检查程序的环境；本机已采用上面的 iOS 验证入口，未把被系统终止的 macOS 运行记为通过。
