# 真机安装准备与个人测试

本阶段目标：在用户连接手机前完成 iOS Device SDK 导出、Release 编译和可重复安装入口；连接后使用用户自己的 Apple Account / Personal Team 进行签名和安装。无需先购买 Apple Developer Program。免费描述文件有效期为 7 天，过期后需重新签名、安装。

## iPad 首次安装（2026-09-30，0.66.0 / build 92）

用户将 iPad Pro 11 英寸（M4，2024）解锁、开启开发者模式并通过 USB 连接后，CoreDevice 实际读到 `paired`、`tunnelState=connected`、`transportType=wired`、`developerModeStatus=enabled`，开发服务可用。此前无线查询只有旧配对缓存与 `unavailable`，缓存中的 disabled 不是设备当前开发者模式状态，不能据此否定用户已开启的操作。

现有宿主已支持 `UIDeviceFamily=[1,2]`，无需改 App ID 或重新导出 Unity。旧描述文件只含 iPhone，本次按 iPad 的实际 UDID 使用现有 Personal Team 自动注册／签名；Release 构建、严格验签及目标设备包含检查通过。**星夜 0.66.0 / build 92 已安装并自动启动于实体 iPad，设备读回版本一致。** iPhone 上的安装保留。本轮验证安装、启动和版本，没有声称已完成 iPad 横竖屏逐项交互或持续帧率验收。

配对后可通过同一可互通局域网使用 Xcode 无线安装、更新及启动；安装时保持设备解锁，网络需要能发现并连接该设备。见 [Apple 无线运行说明](https://help.apple.com/xcode/mac/current/en.lproj/dev3e2f4ee6d.html)。用户随后拔掉数据线，实际复查得到 `transportType=localNetwork`、`tunnelState=connected`，并成功无线读取版本、使用同一 0.66.0 / 92 包再次安装及启动。**无线安装和启动已实测通过**。已安装的 App 可拔线打开；当前开发版真实 AI 使用 Mac 上的服务，聊天仍需能访问该服务。

证据仅留本机：`.local/checks/ipad-066-connected.json`、`ipad-066-lock-connected.json`、`ipad-066-install.json`、`ipad-066-launch.json`、`ipad-066-app.json`，以及 `.local/logs/ipad-066-device-build.log`。设备标识、签名描述文件和账户材料不提交公开仓库。

拔线验证另存 `.local/checks/ipad-066-wireless-{details,app,install,launch}.json`，无线测试没有变更版本或先卸载 App。

## 历史交付状态（2026-09-29，0.37.0 / build56）

角色定义固定、10个实际3D封面和紧凑发现、20首独立原创音乐、胶囊小静音按钮及三项相处设置已完成。聊天高度固定60%，默认15pt全局字体在我的→设置调整。7个不同iPhone17模拟器流程最终通过；两平台原生编译、20首音源打包和Device Release严格验签通过，无需重新导出Unity。

**一次手机安装成功，回读星夜0.37.0 / 56；一次自动启动因Locked被系统拒绝。** 未等待或重试，手机解锁后直接点开星夜即可。本轮交互由模拟器验收，未进行真机完整交互或持续FPS验证。

签名包：`.local/build/DeviceDerivedData/Build/Products/Release-iphoneos/CharacterHost.app`。工作区device / Release，iPhone17模拟器已恢复普通启动。见[本轮结果](verification/authored-characters/README.md)、[安装结果](verification/authored-characters/device-install.json)及[版本回读](verification/authored-characters/device-app.json)。下文首次配对记录作为历史保留。

## 运行目标与平台切换（2026-09-27）

**2026-09-29 更新：真机与模拟器现已使用独立入口。** 真机固定打开 `ios/StarryNight.xcworkspace`，模拟器打开 `ios/StarryNight-Simulator.xcworkspace`，两者均选择 `CharacterHost` scheme。生成模拟器工程不再改写真机工程。若 Mac 已识别、配对手机但 Xcode 显示 No Device，先确认打开的是真机入口；网络可达不能让一个仅支持 `iphonesimulator` 的工程安装到实体手机。

Xcode 的三角形只会构建、安装并启动到当前选中的运行目标。之前按要求开发模拟器版本，workspace 引用 `unity-simulator`，宿主限定 `iphonesimulator`；顶部的 **iPhone 17** 是模拟器，而连接的实体设备名称是 **iPhone**。连接数据线不会自动把工程切为真机。

当前最新产品名称为 **小伴 0.5.1（build 7）**。真机 Unity 导出已更新到 contentVersion 5，包含新版对话、取景和场景协议。当前工程已切为 device / Release；本轮已完成签名、安装和启动，结果见 `docs/verification/xiaoban/device-installation.json`。随后按用户要求改为独立应用标识，于10:58安装并启动新“小伴”，保留此前 App；Xcode 本地配置已指向新标识。

在 Xcode 打开 `ios/StarryNight.xcworkspace`，顶部选择 **CharacterHost → iPhone**。不要选择 `UnityFramework`、`Unity-iPhone`、`Any iOS Device` 或模拟器作为完整 App 的安装入口。每个平台的 workspace 固定引用对应的 Unity 导出。

更新真机工程时，先确保 Unity 真机导出是最新的，再执行：

```bash
python3 scripts/check_export_content.py --platform device
python3 scripts/generate_host.py --platform device
open ios/StarryNight.xcworkspace
```

若第一条检查失败，按提示先运行 `python3 scripts/export_unity_ios.py --platform device`。选择实际手机后再点击三角形；仅修改下拉目标不能把模拟器 Unity 库变为真机库。

## 首次真机结果（历史记录，2026-09-26）

**历史结果：Xcode 真机 Release 构建成功，用户已确认手机打开“模型空间”并能看到模型。** 09:48 完成的 GUI 构建记录为 0 errors / 15 warnings；此前 UnityFramework 头文件错误已消除。安装与模型显示以用户本人确认为证，当前受限工具会话未取得设备启动遥测。真机交互完整回归、持续帧率及 iPad 运行仍待验证。证据见 `docs/verification/device/first-device-run.json`。

以下为准备阶段结果，未签名包的体积与哈希不代表后续 GUI 签名产物。

Unity Device SDK 导出 PASS / 0 errors，Xcode ARM64 Release 完整编译成功。宿主与 UnityFramework 的 Mach-O 均确认为 IOS 平台、最低 iOS 17、SDK 26.4；App 约 123.6 MB（未签名目录大小，不是压缩下载体积），Unity Data 已内嵌，iPhone / iPad 设备族及 ProMotion plist 配置均正确。模拟器产物仍保留。

用户随后连接了 iPhone 17 / iOS 27.0（24A437）；USB 识别与配对成功。初始检查显示 Developer Mode 尚未开启、Xcode Apple Account 数量为 0、有效开发签名证书为 0；用户随后完成连接支持更新、开发者模式和账号登录。没有仅因手机系统比 SDK 新就升级整个 Xcode / macOS。

准备阶段状态为已编译、待签名和安装，已由本节顶部的真机运行结果更新。设备序列号、UDID、账户信息只用于本地操作，不写入公开报告。编译日志与哈希见下方验证 JSON。

## 账号与重启后的复查

用户确认连接支持更新、手机开发者模式及重启后确认、Xcode 登录均已完成。2026-09-26 随后读取 Xcode 本地元数据，确认已有 1 个 Apple Account 和唯一的免费 Personal Team，并将该 Team 写入 Git 忽略的 `Local.xcconfig`。不需要用户手工填写团队 ID。

该次会话权限已变为受限工作区模式。`devicectl` 访问 CoreDeviceService 的 XPC 连接被中断并超时；`xcodebuild -showdestinations` 同时出现系统服务连接失败、日志路径 Operation not permitted，并报 workspace 无法识别。实际 workspace 文件、引用项目均存在，XML 验证通过，不能据此把工程当作损坏。未绕过权限边界，也未更改系统服务或重置手机配对。

因此当时未从工具复核重启后的设备状态，改由用户在本机 Xcode 选择 CharacterHost scheme 和实际 iPhone 后 Run。后续构建成功，用户确认手机已打开 App 并显示模型。此前“账号数量为 0”的记录是初始检查状态，已被本节的账号复查更新。

## 已准备的工程入口

- Unity 导出：`build/unity-device/Unity-iPhone.xcodeproj`，与 `build/unity-simulator/` 分开。
- 完整 App：`ios/StarryNight.xcworkspace`，选择 **CharacterHost** scheme；当前引用真机导出，Run 使用 Release。
- 模拟器 App：`ios/StarryNight-Simulator.xcworkspace`，同样选择 **CharacterHost** scheme；引用模拟器导出，Run 使用 Debug。
- 真机编译缓存：`.local/build/DeviceDerivedData/`。模拟器缓存 `.local/build/DerivedData/` 保留。
- 本地签名配置：`ios/Config/Local.xcconfig`，Git 忽略；团队未配置时不进行签名构建。
- 真机 App ID 由 `MODELSPACE_DEVICE_BUNDLE_IDENTIFIER` 配置，仅对 iphoneos 生效；模拟器仍使用 `com.modelspace.viewer`，现有自动化与安装脚本不受影响。

## 用户需要完成的一次性操作

1. 在 Xcode → Settings → Apple Accounts / Accounts 登录自己的 Apple Account；免费账号会显示 Personal Team。
2. 用可传输数据的 USB-C 线连接手机并解锁，按手机和 Mac 提示允许连接、信任电脑。
3. 配对开始后，在手机“设置 → 隐私与安全性 → 开发者模式”打开开关，按提示重启并再次确认。配对前可能看不到该选项。
4. 选择自己的 Personal Team。将实际 Team ID 保存为 `Local.xcconfig` 中的 `DEVELOPMENT_TEAM = ...`，不得保留示例占位符。无需向项目提供 Apple 密码。

项目已准备 App ID 本地覆盖。如果 Apple 报标识符已被占用，在同一本地配置中更换自己的唯一值，再构建；不修改 UnityFramework 固定标识，因为原生端用它定位 Unity Data。

## 连接后安装

先列出设备，确认用户刚连接的手机；用列表中的标识符查询详情，从 `hardwareProperties.udid` 取硬件 UDID（不要把 CoreDevice UUID 当作 Xcode 目的地 ID）：

```bash
xcrun devicectl list devices
xcrun devicectl device info details --device DEVICE_IDENTIFIER
bash scripts/run_device.sh DEVICE_UDID
```

安装脚本会先进行 Release 自动签名构建，再检查代码签名与 embedded.mobileprovision，安装到显式指定设备并启动。脚本不自动挑选第一台设备，不安装未签名预编译产物。Xcode 登录状态、设备注册与证书创建由 Apple 官方工具处理；若出现账号或钥匙串交互，按系统提示完成。

也可在已打开的 workspace 中选择 CharacterHost 和实际手机，在 Signing & Capabilities 选择同一 Team，点击 Run。脚本方式会将本地 Team 同时应用于宿主及 Unity 依赖目标。Xcode 界面方式若提示某个依赖目标缺少 Team，应为其选择相同团队。

安装后可拔线，从桌面“小伴”直接运行。若系统明确提示未受信任的开发者，按提示到“设置 → 通用 → VPN 与设备管理”信任对应开发者。

## 重建与切回模拟器

仅原生代码修改：

```bash
bash scripts/run_device.sh DEVICE_UDID
```

Unity 代码、模型、材质或场景修改后，先重新导出，再执行上述安装命令：

```bash
python3 scripts/export_unity_ios.py --platform device
```

未连接手机、未配置账号时，只做编译准备：

```bash
bash scripts/build_device.sh --unsigned
```

此产物没有 Apple 开发签名，不能直接复制或 AirDrop 到手机安装。

切回模拟器：

```bash
python3 scripts/generate_host.py --platform simulator
bash scripts/run_simulator.sh
```

已有模拟器构建未包含后续源码修改时，应先 `bash scripts/build_host.sh`。不要在真机 Xcode 构建运行期间执行平台切换；同一个 workspace 同一时刻引用一个平台。

## 已修复的 GUI 构建问题

如果曾出现 `UnityFramework/UnityFramework.h file not found`，本次实际日志的原因是宿主按 Simulator 编译、UnityFramework 按 Device 编译。生成器已修正 SDKROOT / SUPPORTED_PLATFORMS，使宿主和 Unity 导出始终使用同一平台。当前 workspace 为真机模式；重新打开 workspace 后，在顶部选择 CharacterHost 和连接的实体 **iPhone**，再 Run。若 Xcode 仍显示上次的模拟器目的地，需要重新选择实体设备。

不要通过添加另一平台的 framework 搜索路径来解决此类报错。平台切换统一使用 `generate_host.py --platform device` 或 `--platform simulator`。两个分支配置与桥接文件的真机编译器检查已通过，修复后的完整 GUI 构建也已成功。

本次 Xcode Run 记录曾报告开发者证书尚未被手机信任；这是构建完成后的启动问题。随后用户明确确认手机已打开“模型空间”并能看到模型，说明用户实际运行已成功；没有推定或记录用户具体执行了哪一步信任操作，也没有将旧的 Run 错误改写为自动启动成功。

## 验收边界

当前已确认真机构建，以及用户观察到的安装、启动和模型显示；尚未确认真机全部交互、持续 120 FPS 或每帧高于 60 FPS，也未完成 iPad 运行验收。App 默认请求 120，界面中的“目标 120”是配置值，旁边 FPS 为实测 Unity 渲染循环统计，不能替代屏幕呈现与长时性能测量。Release 安装后从桌面启动，可避免调试器介入本轮实际使用体验。

Apple 官方依据（2026-09-26 核对）：[免费 Personal Team 与 7 天有效期](https://developer.apple.com/support/compare-memberships/)、[开发者模式](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)、[自动签名与 Team](https://help.apple.com/xcode/mac/current/en.lproj/dev23aab79b4.html)。本地构建结果见 `docs/verification/device/preparation.json`。

## 2026-09-28 · v0.7.0 手机离线语音

已完成 Release 0.7.0 / build11 签名、深度验证，并更新安装及启动于已配对 iPhone 17，Bundle ID 继续为 `com.gukaifeng.xiaoban.dev`。语音模型与 iOS 运行库已打包，Mac 语音服务已关闭；手机无需连接电脑或本地语音服务。聊天页显示“离线语音已就绪”，麦克风首次使用需要系统授权。实际语音速度和 3D 同时运行的帧率仍需真机实测。

安装输出 `.local/checks/device-install-20260928-003917.json`，启动输出 `.local/checks/device-launch-20260928-003917.json`。完整范围见 [离线语音验收](verification/offline-speech/README.md)。

## 2026-09-28 · v0.7.1 弹性动作取景

Release 0.7.1 / build12 已签名并更新安装到已有“小伴”。自动启动因手机锁屏被拒绝（CoreDevice Locked），安装本身成功；解锁后点图标即可打开。安装与启动结果分别保留在 `.local/checks/device-install-20260928-010329.json` 与 `.local/checks/device-launch-20260928-010329.json`。动作过渡、连切与恢复及手势回归已在 iPhone／iPad 模拟器通过，详见[动作取景验收](verification/framing-motion/README.md)。


## 2026-09-28 · 0.7.2 / build13 界面连续过渡

完成双平台Unity构图协议5导出；真机Release构建、深度验签及安装成功，设备App列表确认小伴0.7.2/build13。沿用com.gukaifeng.xiaoban.dev，保留用户资料。安装后启动因设备锁定被系统拒绝；解锁点小伴图标即可。未声称本轮已做真机动态效果或持续帧率实测。

- 构建：`.local/logs/host-device-20260928-012910.log`
- 安装：`.local/checks/device-install-20260928-012959.json`
- 锁屏启动结果：`.local/checks/device-launch-20260928-012959.json`
- 版本查询：`.local/checks/interface-motion-installed-app.json`
- 交付和验证：[界面过渡验收](verification/interface-motion/README.md)


## 2026-09-28 · 0.8.0 / build14 本地测试登录

真机Release构建、深度验签与安装成功，使用原有com.gukaifeng.xiaoban.dev和用户资料。更新后首次打开显示微信／邮箱／手机号登录页，默认测试信息已填好。手机锁屏阻止自动启动，解锁点小伴图标即可。

- 构建：`.local/logs/host-device-20260928-014752.log`
- 安装：`.local/checks/device-install-20260928-014805.json`
- 锁屏启动结果：`.local/checks/device-launch-20260928-014805.json`
- 版本查询：`.local/checks/account-installed-app.json`
- [账号验收与截图](verification/account/README.md)


## 2026-09-28：v0.8.1 / build15 半屏聊天

已签名编译、深度验签并安装到既有小伴，设备查询确认0.8.1/build15。安装记录 `.local/checks/chat-fade-device-install.json`；版本查询 `.local/checks/chat-fade-device-app.json`。自动启动被手机锁屏拒绝（`.local/checks/chat-fade-device-launch.json`），解锁后点击图标即可。普通iPhone 17模拟器也已更新；实际模拟器验证与截图见 [半屏聊天验收](verification/chat-fade/README.md)。


## 2026-09-28：v0.8.2 / build16 透明弹层

Release签名编译、深度验签及安装完成；设备查询确认小伴0.8.2/build16。记录在`.local/checks/soft-panels-device-install.json`与`soft-panels-device-app.json`；自动启动被手机锁屏拒绝（`soft-panels-device-launch.json`），解锁点击图标即可。测试账号、聊天与角色资料保留。模拟器实测及录像见[透明弹层验收](verification/soft-panels/README.md)。


## 2026-09-28 · 0.8.3 / build17 自然注视

Release签名构建、深度验签及安装成功；设备App查询确认小伴0.8.3／17。自动启动因Locked被拒绝，解锁后点小伴即可体验。新增头颈／双眼注视与背面退出，iPhone17和iPadPro11模拟器完整流程通过；不将模拟器结果视作真机持续FPS结果。证据见[自然注视验证](verification/gaze/README.md)。
