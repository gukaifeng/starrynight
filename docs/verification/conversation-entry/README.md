# 会话进入与临时旋转 · 0.40.0 / 61

本轮要求先修复 Xcode 真机入口并安装当前版本，再实施临时旋转、音乐默认播放和问候去重。只验证 iPhone，不扩展 iPad 测试。

## 真机问题与修复

- 初始 `StarryNight.xcworkspace` 指向 `build/unity-simulator`，宿主 `SUPPORTED_PLATFORMS=iphonesimulator`，因此 Xcode 不提供物理手机目的地。手机实际已经配对，Developer Mode 开启，CoreDevice 经 localNetwork 成功建立隧道。
- 真机永久使用 `ios/StarryNight.xcworkspace` / `CharacterHost.xcodeproj`；模拟器改用 `ios/StarryNight-Simulator.xcworkspace` / `CharacterHost-Simulator.xcodeproj`。二者共用源码、各自引用平台导出，模拟器构建不再重写真机工程。
- 先导出、编译并签名稳定版 **0.39.1 / 60**，无线安装成功；`devicectl` 启动成功，手机应用清单读回版本 0.39.1 / 60。随后才开始新功能源码修改。更新现有 bundle，保留聊天和账户数据。
- 旧的 Xcode/`xctrace` 离线缓存不能替代实时 CoreDevice 证据。当前手机系统为 iOS 27.0，实际部署已成功，无需因版本差异盲目升级 Xcode。

## 行为约定

- 单指按住角色 1 秒后，水平拖动临时查看。绕角色默认朝向左右最多各 180°，总范围 360°；累计位移有界，不能绕多圈。松手、取消、离开或打开面板后回默认朝向。相机、大小、位置和作者骨骼动画保持不变。
- 每个角色的音乐初始开启，曲目仍按角色隔离。保留说话时压低音乐、录音/后台/离开暂停及返回恢复。旧数据未记录过新的默认播放策略时迁移一次，之后尊重用户手动暂停。
- 问候按账户和角色持久去重。有过问候或已有聊天记录的角色不再自动加开场白；切页返回、重启和切换回来同样适用。新角色首次进入仍主动问候，并遵守用户静音设置。
- 琪宝/豆日向保持 0.39.1 的来源动作恢复结果。整体临时旋转属于用户查看操作，不重新加入自制摇头、目光或待机。

## 最终验证与安装

**0.40.0 / 61 已成功无线安装到实际 iPhone 17，启动成功，手机应用清单读回同一版本。** 更新现有 `com.gukaifeng.xiaoban.dev`，未卸载 App 或清空用户数据。[手机安装证据](device-installation.json)记录签名检查、安装、启动及版本读回。Xcode 主窗口保留 `CharacterHost → iPhone`，[界面证据](xcode-device-target.png)。

| 验证 | 结果 |
|---|---|
| 真机/模拟器工程隔离 | 实际生成模拟器后，真机工程、workspace、scheme SHA-256 不变，[证据](workspace-isolation.json) |
| Unity 实际网格/临时旋转 | 5495 个断言通过，含两向 ±180°、不累计圈数、回正、30/60/120Hz 时间步、相机和骨骼不变，[审查](../hold-rotation/runtime-review.json) |
| 真实 iPhone 17 模拟器触控 | 初音、琪宝、豆日向左右长按旋转均成功，释放角度约 ±160～163°，随后回 0°；短拖不旋转、背景拒绝，93.066 秒通过 |
| 音乐与问候 | 4 条实际 UI 流程通过：取消进入不提前问候、初次语音与二次进入去重、音乐自动播放/暂停/角色切换/重启、登录与静音持久化 |
| 生产数据规则 | iOS DEBUG 入口实测 69 条作者/订阅及 227 条集合/迁移等断言通过，含新增音乐默认和旧存档迁移检查 |
| 旧短按互动 | 原有头部互动与镜头锁定回归通过，36.306 秒 |
| 普通启动 | 模拟器去掉测试参数启动，画面复核正常；检查的 Metal RenderPass/NextSubPass/EndRenderPass、NullReferenceException、ArgumentException 均 0 |

合计 **7 个不同 UI 测试方法最终通过**，详见 [app-review.json](app-review.json)。长按首轮超时没有隐藏：Unity 已收到真实手势并从 −161.64° 回到 0°，原生 QA 更新白名单漏了新事件，断言读取旧快照。补齐四种事件后只重跑受影响的方法并通过；[首轮引擎证据](../hold-rotation/first-ui-run-engine-events.json)保留。未放宽旋转断言或用模拟数据代替触控。

macOS standalone Swift 检查编译通过，但执行被 SIGKILL；[原始输出](native-core-tests.txt)保留，不计为测试通过。数据迁移实际验证改复用已有 iOS DEBUG 入口，并非绕过系统安全策略。未测试 iPad，也没有声称实机持续 60/120 FPS；时间步检查只验证旋转算法与刷新频率无关。

真机和模拟器均已真实重导，导出元数据加入 `inspectionGestureRevision:1`。构建器会拒绝缺此能力的旧导出，避免新原生手势被旧 Unity 静默忽略。

示例：[正常启动](simulator/normal-launch.png)、[首次进入音乐实际播放](simulator/music-default-autoplay-runtime.json)、[重启后仍尊重手动暂停](simulator/music-explicit-pause-restored-runtime.json)、[琪宝右转复位状态](../hold-rotation/simulator/anime-kipfel-hold-right-restored-runtime.json)。

本机原始结果位于 `.local/checks/Conversation-Entry-v040-Phone-1.xcresult`、`Hold-Rotation-v040-Phone-2.xcresult`；最终设备原始回执为 `.local/checks/device-{install,launch,app}-v040.json`，真机构建日志为 `.local/logs/host-device-20260929-194414.log`。
