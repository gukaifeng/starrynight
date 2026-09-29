# 栩屿 v0.5 · 角色空间与音乐验收

本轮仅模拟器。原生版本0.5（build6），Unity contentVersion5 / atmosphereRevision1，保留 framingProtocol1。

## 交付内容

- 晨雾青、贝壳白、浅桃色系；首页角色邀请、角色口吻的开场、实时回应状态、柔和舞台边缘；设置与记忆等收进“我们的空间”。明确 AI 身份及本地对话体验。
- 全部 SwiftUI ScrollView/Form/List 隐藏指示器，UIKit 动作栏保持隐藏。内容仍可浏览，旧消息阅读不被每个生成片段拉回底部。
- 两首原创程序合成音乐，离线48秒立体声循环；开关、选曲、音量、偏好恢复。
- 原生统一音频焦点：语音播放压低音乐至18%，录音与后台暂停，退出空间暂停，系统中断／耳机拔出需明确继续。
- 保留既有角色取景、头部互动、动作、资料、记忆、聊天与开源语音。

## 已通过的前置检查

- Swift6 + iOS Simulator SDK：新 Companion 源码、Theme 与模型目录类型检查通过；其他改动源码语法检查通过。
- C# Assembly-CSharp 与 Editor 程序集源检查通过。
- Unity 已通过官方 CLI 导出 v5。首次同步探测超时后，使用跟踪任务确认新字段已生效、未编译失败，再提交一次正式导出并成功结束。
- 音轨[实际文件哈希、峰值、RMS、接缝差](music-assets.json)，32kHz/16bit/立体声，无第三方采样。接缝差为相邻样本差，不等于听感评价。

## 模拟器验证

最终应用源码已通过完整构建。iPhone 17 / iOS 26.4 Simulator 的音乐完整流程通过（317.403秒），工具导航专项通过（102.542秒），均为0失败。iPad Pro 11英寸 M4 的交互用例通过（86.299秒），覆盖竖屏、旋转、音乐播放与角色资料入口。

横屏视觉另行复核完成：首次 application 截图的取图区域出现黑边与裁切；普通启动后直接旋转 Simulator，整屏原始采集与 Simulator 窗口截图确认角色在左、聊天在右、输入区完整可见，应用本身没有该裁切。最终展示采用[实际横屏窗口截图](screenshots/13-ipad-landscape-window.png)，没有对截图进行补绘。

追加自动化截图复核的 iPad2 / iPad4 在进入房间前触发启动超时，iPad3 中途报告 Mach -308 / simulator server died；本轮未消除这些稳定性问题。原用例通过记录与追加失败记录分别保留。新增整屏截图方式与布局断言留在测试源码中，追加版本尚未完整跑绿，不把普通运行截图当成这些自动断言的通过证据。

- 音乐验证使用`AVAudioPlayer.isPlaying`、时间推进、非零电平共同取证；语音另有真实音频电平断言。
- 用户音量15%时，语音焦点期间实际音乐 player.volume 最低为0.027，即原音量18%。该焦点也覆盖分段合成间隙，`duckedSamples`不表示每一次采样都同时存在语音波形。
- 退出角色空间证据为 active=false、playing=false、outputVolume=0；enabled仍保留true，重启后恢复曲目与15%音量。
- iPhone检查还包括默认音乐关闭、两曲切换、暂停/继续、后台恢复、键盘不遮挡输入、共同记忆、取景20°保存；专项覆盖资料保存与历史入口。
- 结构化结果见[acceptance.json](acceptance.json)，原始 XCTest 摘要见[手机](phone-test-summary.json)、[工具](tools-test-summary.json)、[平板](ipad-test-summary.json)。失败的迭代 xcresult 保留于 `.local/checks`，没有覆盖成成功结果。

## 效果与使用

- [首页](screenshots/01-welcome.png)：两位角色的聊天邀请都能在默认 iPhone 17 一屏内看到。
- [Luma 角色空间](screenshots/02-luma-room.png)、[键盘展开](screenshots/04-keyboard.png)、[正常启动的初音空间](screenshots/12-miku-normal-launch.png)。
- [音乐面板](screenshots/03-music.png)：从聊天区右上音符按钮进入，第一次默认关闭；选择曲目即可播放。
- [我们的空间](screenshots/11-space-tools.png)：聊天区省略号打开角色设定、共同记忆和聊天记录。
- [iPad 竖屏](screenshots/08-ipad-portrait.png)、[iPad 实际横屏](screenshots/13-ipad-landscape-window.png)：上下布局与左右布局分别复核。

曲目为“岛上的午后”和“月光潮汐”，随 App 打包，不依赖网络或本机语音服务。它们仅在前台聊天空间播放。音量、开关、曲目为全局音乐偏好；角色资料、记忆和取景仍按角色分别保存。测试使用独立数据，不污染普通使用偏好。

## 边界

此轮不做真机60/120FPS或温升结论。麦克风真人采集、耳机物理拔出、真实电话中断需要后续真机验证；这些实际设备条件尚未验证。当前器乐为合成原型，不是录音棚演奏成品。默认字体布局已检查，超大辅助字号与 VoiceOver 尚未完整审计。文本仍使用本地情景库；高宿主负载下曾观察到单次本地 TTS 合成约40秒，后续仍需优化语音响应速度。

遇到“准备模型所需时间较长”可从错误页返回后重试；本轮多次模拟器启动出现该情况，需后续单独改善 Unity 冷启动稳定性。尚不能把本轮成功流程视为所有环境下的稳定启动保证。

交付时 iPhone17 已以普通启动打开[新版首页](screenshots/14-final-home.png)，不带测试或预览参数。最后一次预览启动同样出现了模型准备超时，随后恢复到普通首页；该失败一并计入已知启动问题。
