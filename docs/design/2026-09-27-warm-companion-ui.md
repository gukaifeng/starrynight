# v0.5 · 一起待一会儿

对象是想塑造私人 3D AI 伙伴的人。界面的首要任务：让进入角色空间后的第一句话自然发生，同时保持 AI 身份和本地情景对话能力边界清楚。

## 视觉与结构

- 晨雾青 #EAF2ED、贝壳白 #F7F5F0、深苔绿 #274A43、安静灰绿 #5B7168、浅桃 #E7BCAD、玉青 #B8D5C5。
- 中文标题采用系统圆润字重，正文采用系统标准字体，辅助信息使用较小但可读的动态字体。不引入远程字体。
- 首页：简短的时段问候，两个紧凑的角色邀请卡（宽屏并列），主要入口为聊天，次级入口为角色设定与互动舞台。取消大段功能介绍。
- 角色空间：上方真实 3D，下方柔和渐变衔接的聊天区；移除硬边框和重复角色标题。用角色口吻的开场邀请、可横向浏览的轻量话题、实际生成/录音/朗读状态提供在场感，不伪造真人在线、情绪或记忆。
- 标志性元素是“留一盏小灯”：微光色的状态点和安静的音乐入口。全局颜色、空间和声音保持一致；不使用常驻粒子或连续高成本模糊。
- 所有 ScrollView / Form / List 隐藏滚动条；保留手势浏览和无障碍滚动。短内容完整可见，历史支持浏览，不通过裁剪隐藏内容。
- iPhone/iPad、键盘、动态字体和减弱动态效果沿用原生能力；保留 v0.4 有界取景。

设计复核：只改变色调仍然像功能展示，因此同步调整首屏信息层级、角色开场、工具入口和回复状态。避免装饰文案占据聊天空间。

## 背景音乐

- 内置两段原创程序合成的器乐循环，无人声、无网络下载、无第三方采样；生成脚本和音符参数留存，可替换成正式录音。
- 默认关闭；提供开关、选曲、音量；偏好落盘，测试偏好与普通使用隔离。
- 只在前台聊天空间播放，退出/后台暂停，恢复空间后按偏好恢复。录音暂停音乐，角色持有语音播放焦点期间压低到原音量的 18%（含分段合成间隙），结束恢复。
- 一个统一的 AVAudioSession 协调者处理音乐/语音的音频类别；避免旧语音 stop() 直接关闭整个共享 session。
- 音频中断或耳机拔出暂停，用户明确继续；不申请后台音频权限，不在锁屏后继续播放。
- 真正播放和电平采样后才记录测试证据，不以按钮文字代替音频输出证明。

## 验证与参考

实际模拟器截图检查首页、空对话、真实本地回复、键盘、音乐面板、iPad 横竖屏。音频验证包括播放、切换、音量、暂停、偏好恢复、离开/回来及与语音的压低协作。既有取景和存储做相关回归。

本轮使用本地 frontend-design / 官方 unity-cli skill。skills.sh + `npx skills find swiftui` 检索到多个社区 SwiftUI skill，当前实现优先已有设计指导及 Apple 官方 API，未安装来源不明的附加组件。

官方依据：[音频体验](https://developer.apple.com/design/human-interface-guidelines/playing-audio)、[AVAudioPlayer 音量渐变](https://developer.apple.com/documentation/avfaudio/avaudioplayer/setvolume(_:fadeduration:))、[ambient 音频类别](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/ambient)、[隐藏滚动指示器](https://developer.apple.com/documentation/swiftui/view/scrollindicators(_:axes:))。
