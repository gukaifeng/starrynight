# 会话控制与原作角色 · 0.42.0 / 63

本轮目标：只发布琪宝与豆日向；移除键盘收起按钮，点击输入区域外收起但保留草稿；角色表现与声音入口外置；长按蓄力反馈及临时多指查看；核对原作待机、口型与动作结束恢复。

## 关键设计

- `assets/characters/active-roster.json` 作为实际打包名册，Unity 场景只实例化两位 VRChat 角色，琪宝为默认角色。其他模型退出目录和实际 3D 构建，原始资料及历史聊天保留。旧账户若原订阅全部已下架，迁移至琪宝；主动取消全部订阅的账户保持空列表。
- 输入框上方右侧两个小入口：角色表现、声音。声音单击总静音，长按进入同一声音设置页；总开关不破坏分项选项与音量。胶囊内静音及定制内音乐入口退出。
- 音频统一由 `CompanionSoundscape` 管理；音乐与朗读用 `AVAudioSession.playback`，录音仍用 `playAndRecord`。手机静音开关不抑制媒体播放，App 内总静音有最高优先级。各角色曲目仍隔离，讲话降低伴奏、录音暂停伴奏、离开会话暂停。
- 原包没有独立动作音效，音效偏好预留；不声称有可播放的源音效。两包均有 viseme，说话只驱动原口型，不添加身体说话动作。
- 手势 Revision 3：可见模型真实三角形命中后进入短蓄力；1 秒解锁。蓄力期间约 1.4% 的临时根缩放及轻弹性是操作反馈，不写入角色 Idle。Core Haptics 连续强度 0.06→0.62，解锁为独立 heavy impact 0.95。后台、失败命中、取消、角色更换均清理。
- 解锁后消息不可滚动，新增触点归查看操作。单指左右 ±180°、上下 ±20°；双指缩放 0.8–1.25，平移每轴不超过视口的 16%；单双指切换重新取基准，不跳变。最后一根手指离开后所有临时变换回到作者当前根变换，不改相机、骨骼及保存的取景。

## 源能力核对

沿用并复核两原包站姿、2.5 秒原呼吸、原 viseme；详见 [源动画审计](../vrchat-original-motion/source-audit.md)。琪宝 82、豆日向 48 项是静态姿势、表情、配件与动态原片段的总数，不是 130 个完整身体动作。

非循环动作到时淡出至底层原作 Idle；琪宝原入睡片段衔接原睡眠循环。姿势、循环与配件保留选中状态，由面板顶部“恢复原作默认”退出。没有添加眨眼、摇头、语音点头或自制自然待机。

## 已通过的验收

- Unity 重新 Setup / Validate，实际场景与 simulator、device 导出都是 **2 个角色**，`inspectionGestureRevision=3`。旧 12 个角色素材源不再被场景引用，Host 音乐仅打包四首当前角色曲目。
- 原曲线逐骨核对 **150,577** 个断言通过；原作呼吸最大骨旋转约琪宝 **0.846°**、豆日向 **1.594°**。位置误差仅约 `5.96e-8m`。见 [source-motion-review.json](source-motion-review.json)。
- 两角色130项表现数据、动画首尾、循环/reset检查 **14,089** 个断言通过，见 [source-performance-review.json](source-performance-review.json)。
- 新手势原位还原与边界检查 **20,477** 个断言通过，含真实网格命中、角度/比例/位移边界、无效浮点输入、取消蓄力、根变换与摄像机不被永久修改，见 [runtime-review.json](runtime-review.json)。这些是算法与数据断言，不等于真机FPS测量。
- iPhone17模拟器两条实际UI流程通过，分别 **64.456s / 20.479s**，见 [app-review.json](app-review.json)。第一条覆盖去掉收起按钮、点按外部关闭真实键盘且草稿保留、声音总开关、长按不误切开关、分项音量、播放音频session、活跃Idle计时、耳朵原循环/reset、原醒来片段自动回归、单指长按倾转还原，以及发现页仅两角色。
- 第二条通过Xcode事件合成注入真正两根手指：按住1秒，第二指加入、捏合与平移、第二指先离开、剩余单指继续移动、最后释放。活跃时实际根比例 **1.25**、Y偏移 **0.10953**（视口归一化）、聊天锁定为true；释放后比例精确1、位置偏移与旋转精确0、聊天解锁。截图和运行事件见 [simulator/](simulator/)。没有给产品加入测试专用手势入口。
- 两个实际App角色的 `idlePlaying=true`、`idleWeight=1`，琪宝跨不同会话操作 `idleTime` 从6.09s持续增加到51.34s，豆日向切入时也正常播放；没有发现当前原作Idle冻结。来源呼吸本身幅度较小，因此视觉较安静。
- 角色集合/四首专属曲目完整性通过；当前两角色封面匹配检查通过；导入技能格式校验通过。设备Release签名编译与严格codesign验证通过。
- 最终 Release 已无线安装到 iPhone 17，自动启动成功，设备回读确认为 **星夜 0.42.0 / 63**；保持现有 bundle 与用户数据。见 [device-installation.json](device-installation.json)。这是安装、启动及版本验收，不代替真机触觉与音频听感验收。
- 模拟器已恢复无测试参数的普通启动，保留正常用户数据；[最终普通会话截图](simulator/normal-launch.png)可见外置表现/声音入口及移除静音后的身份胶囊。启动日志未出现检查的运行异常；仍有模拟器 ASTC 解压与 Unity 阴影深度回退警告，不把这些警告描述为已消除。

## 问题处理与验证边界

- 移除键盘工具栏后发现原消息/输入区域的CGRect Preference合并会被空值覆盖，导致兜底把整个聊天区域当成输入区，不响应外部点按。保留有效几何值、缩小兜底至真实输入底部、消息区域显式撤销焦点后，真实键盘与草稿验证通过。
- Swift6.3对直接Actor方法引用作为Binding setter的IRGen崩溃，改为显式闭包解决。
- 多指测试工具首次把Xcode内部completion的BOOL当NSError导致测试runner崩溃；核对本机ABI并修复后，第二条流程完整通过。产品进程未因此崩溃。
- 早期失败与编译错误保留在 `.local/logs/Conversation-Controls-v042-[1-4].log`；最终通过为第5轮。第3轮只编译失败，不能计为已执行UI流程。
- 模拟器没有实体马达，也不能切换真机静音拨片：确认了真实手势调用、haptic状态和 `.playback` 类别；震动主观手感与真机静音下听感不冒充模拟器可测结果。本轮不做持续帧率或iPad验收。


## 官方依据

- [Apple：AVAudioSession playback](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playback)
- [Apple：Core Haptics patterns](https://developer.apple.com/documentation/corehaptics/representing-haptic-patterns-in-ahap-files)
- [VRChat：Playable Layers](https://creators.vrchat.com/avatars/playable-layers/)
- [VRChat：口型与 Animator 参数](https://creators.vrchat.com/avatars/animator-parameters/)
