# 自动发言与本机音频中断恢复

2026-10-03，0.103.1 / build 135。用户在 Hikarun 会话中没有发送消息，却看到「设备处理这次回复时出错（XuyuAudio 1）。点消息旁的感叹号可重发」。修复位于所有角色共用的原生语音路径。

## 根因与边界

`CompanionSoundscape.beginVoice` 在 `active=false` 或 `interrupted=true` 时抛出同一个裸 NSError（XuyuAudio / 1）。该错误没有角色差异，也不是百炼的响应错误。仅凭用户的错误提示，无法区分当时是页面/音频会话激活竞态，还是音频中断标记未恢复。

代码存在两个明确的问题：

- 音频中断通知只处理 began，没有处理 ended；耳机断开也被写入同一个 interrupted 标记。此标记可能持续阻止后续语音。
- 播放器错误会退出 `ReplyAudioPump`，再进入整次会话的失败处理。失败提示无条件要求点击用户气泡的感叹号，即使当前轮次是摇晃、捏扯、问候或待机自动发言，根本没有用户气泡。

## 公共修复

- 音频状态分为页面未激活、系统正在中断和主动暂停输出。系统 ended 通知清除中断状态；遵从 shouldResume 建议。耳机断开或系统不建议自动继续时暂停输出，不冒充一个永久进行中的中断。
- [Apple 音频中断说明](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions)和[音频路由变化说明](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes)作为实现依据。工程最低 iOS 17，当前 SDK/设备为 iOS 26，因此使用相应 interruptionNotification 的 began/ended API；没有引用需要 iOS 27 的新 API。
- 本机暂时不能播放、音频配置被替换或 AVAudioEngine 启动失败时，只停止扬声器输出。保留当前消息、网络轮次、完整 PCM、缓存标识、语音时长和文字进度；输出恢复后可以从气泡重新播放已有语音，不重新生成回复。
- 播放期间收到中断、后台或耳机移除通知，也采用上述局部暂停，不再清空尚未接收完的 PCM。语音录制仍按原流程取消并保留可编辑的文字。
- 多个旧语音实例不会在没有活跃播放时通过通知重置当前音频焦点。重复设置同一 active 状态不重复创建硬件配置竞态。
- 普通用户发言保留有界重试、原用户气泡的失败状态和感叹号重发。自动触发耗尽重试时保留诊断，不显示不存在的重发操作，也不把旧用户消息标为失败。新轮次清除上一轮的 notice。
- 开发者语音耗时记录增加 `reply_origin`、`audio_output_deferred` 和失败时的 `reply_error`，只记录触发归属、状态或错误 domain/code，不保存对话正文。无法输出仍保留下载、解码、缓存和处理耗时。

上述改动由 CompanionSoundscape、CloudSpeech 和 CompanionSession 统一处理，没有按 Hikarun 单独判断。不改服务器、角色包、模型动作或账户/对话标识，不发起新的收费生成任务。

## 实际验证

iPhone 17 / iOS 26.4 模拟器执行三项 XCTest，3 passed / 0 failed，结果为 `.local/checks/AudioRecovery135.xcresult`：

1. 实际 AVAudioEngine / 会话回归：真实通知模拟中断开始与结束、在播放前中断、在两次网络 PCM 分片之间中断、should-not-resume、耳机移除和页面/音频 active 竞态。检查无错误传播、整段 PCM 和缓存标识不丢失，以及恢复后真实输出。进一步通过真实 CompanionSession 测试 Hikarun 的摇晃反应和 Chiffon 的扯动反应，没有用户消息，仍保留助手回复和语音；模拟自动场景的网络重试耗尽，不显示重发提示或虚构用户气泡。
2. 用户消息回归：临时失败私下重试成功；重试耗尽后原用户消息显示重发按钮；重发不新增重复用户气泡、不覆盖随后输入的草稿。
3. 后台回归：发送后切到桌面，当前回复继续完成，灵动岛返回同一会话，没有新建轮次或显示失败气泡。

测试采用合成 PCM 和隔离的本地事件夹具；禁用付费调用与预生成，没有联系百炼。音频输出发生在模拟器，不等同于真机来电/控制中心的现场复现，也不测量百炼或真机语音延迟。

真机 Release 首次构建在复制 Unity 的 resources.assets.resS 时遇到磁盘空间不足。按用户此前对可重建编译缓存的清理授权，仅删除 `.local/build/DeviceDerivedData/.../CharacterHost.app` 和 `.local/build/DerivedData/.../CharacterHost.app` 两个旧 build 133 产物；恢复约 11 GiB 可用空间后重新构建成功。实际复制文件大小与源框架一致，没有使用失败的半成品安装。

`codesign --verify --deep --strict` 通过，主应用与灵动岛扩展均为 0.103.1 / 135。已通过同网络无线覆盖安装到用户 iPhone，设备回读 `name=StarryNight`、`version=0.103.1`、`bundleVersion=135`，原 Bundle Identifier 保持一致。本地证据在 `.local/checks/audio-recovery-135/device-install.json` 与 `device-apps.json`。

安装后尝试远程启动时，手机已经锁定；CoreDevice 明确返回 Locked（10002 / FBSOpenApplicationErrorDomain 7），这是 iOS 解锁保护，没有把安装成功描述成启动成功。用户解锁后可直接从桌面打开星夜。本次真机已确认签名、安装和版本，尚未真机复现来电/耳机路由变化。
