# 主动问候验证 · v0.27.0 / build 43

iPhone 17、iOS 26.4 模拟器，3条主动问候流程与2条现有启动流程全部通过，**5条，0失败，134.806秒**。结果包 `.local/checks/Starry-Proactive-Greetings-Run.xcresult`。

| 流程 | 结果 |
| --- | --- |
| 游客首次启动，AI先发消息并实际朗读 | 通过；音频非零采样、播放中气泡和头像波纹；没有用户消息 |
| 同一首页点击、资料弹层关闭 | 通过；问候次数仍为1，没有重复消息 |
| 消息返回驻留角色、初见Luma、切回已知角色 | 通过；场景、各角色独立次数与文案相符 |
| 后台回来 | 通过；新增foregroundReturn问候，原角色会话保持 |
| 已登录账户、静音返回及重启 | 通过；问候落入记录，静音不自动播；重启为appLaunch，不重复自我介绍 |
| 取消加载再进入 | 通过；未展示的进入没有留下问候，真正进入后计数为1、firstMeeting |
| 游客额度和取景 | 通过；多次问候后用户轮数为0，actionFraming为false，没有全身招手引起的变焦 |
| 启动等待、中途后台与恢复 | 通过；语音不越过启动遮层，启动动画不在后台返回时重播，准备后的距离和取景保持 |

第一次编译发现 `CharacterIntent` 的成员初始化参数顺序错误，修正后执行上述最终测试。另有53条现有角色集合、账号隔离、游客额度、搜索与持久化检查通过。

新增的独立macOS纯逻辑测试源码 `scripts/tests/ConversationGreetingTests.swift` 已编译，但其进程连续被SIGKILL终止，未进入断言结果；严格签名检查正常，系统日志没有给出足以确定原因的终止报告。没有修改系统安全设置、伪装进程或把它报告为通过。保留 `bash scripts/test_character_library.sh --greetings` 作为显式补验入口；常规脚本仍运行原53条检查。本轮App功能结论来自上表真实iOS运行流程，不依赖这份未完成的独立测试。原始诊断仅保存在 `.local/logs/greeting-core-*.log`。

截图和对应 `*-runtime.json` 来自最终通过的测试。JSON中的 `avatarVoicePlaying=false` 只表示采样时刻尚未开始或已停止，实际语音播放由UI测试等待非零音频采样验证，不用单张截图证明完整朗读。

设计和接口见[主动问候方案](../../design/2026-09-29-proactive-greetings.md)。构建和手机一次安装结果见本目录 `result.json`；未新增iPad测试，未重导Unity。

最终Device Release编译与严格验签通过；手机一次无线安装成功，回读星夜0.27.0 / 43。自动打开因设备锁定被系统拒绝，没有重试或等待解锁。模拟器已经以正常参数启动；手机本轮验证为安装和版本确认，不将模拟器的语音检查算作真机测量。

![首次启动主动说话](greeting-first-launch-speaking.png)

[返回会话](greeting-retained-return.png) · [第一次认识Luma](greeting-first-meeting.png) · [静音重启](greeting-signed-in-relaunch.png)
