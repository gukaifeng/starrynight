# 真机安装准备与个人测试

本阶段目标：在用户连接手机前完成 iOS Device SDK 导出、Release 编译和可重复安装入口；连接后使用用户自己的 Apple Account / Personal Team 进行签名和安装。无需先购买 Apple Developer Program。免费描述文件有效期为 7 天，过期后需重新签名、安装。

## 本机结果（2026-09-26）

Unity Device SDK 导出 PASS / 0 errors，Xcode ARM64 Release 完整编译成功。宿主与 UnityFramework 的 Mach-O 均确认为 IOS 平台、最低 iOS 17、SDK 26.4；App 约 123.6 MB（未签名目录大小，不是压缩下载体积），Unity Data 已内嵌，iPhone / iPad 设备族及 ProMotion plist 配置均正确。模拟器产物仍保留。

用户随后连接了 iPhone 17 / iOS 27.0（24A437）；USB 识别与配对成功。最新检查显示 Developer Mode 尚未开启、Xcode Apple Account 数量为 0、有效开发签名证书为 0；用户确认提示为“需要软件更新才能连接到 iPhone”，正在安装连接支持更新。开发者服务尚未完成连接，不能仅因手机系统比 SDK 新就断言必须升级整个 Xcode / macOS；更新、开发者模式和账号登录后重新检测。

当前状态为 **已编译、待签名和安装**。设备序列号、UDID、账户信息只用于本地操作，不写入公开报告。编译日志与哈希见下方验证 JSON。

## 已准备的工程入口

- Unity 导出：`build/unity-device/Unity-iPhone.xcodeproj`，与 `build/unity-simulator/` 分开。
- 完整 App：`ios/CharacterPrototype.xcworkspace`，选择 **CharacterHost** scheme；当前引用真机导出，Run 使用 Release。
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

先列出设备，确认用户刚连接的手机，取该设备 UDID：

```bash
xcrun devicectl list devices
bash scripts/run_device.sh DEVICE_UDID
```

安装脚本会先进行 Release 自动签名构建，再检查代码签名与 embedded.mobileprovision，安装到显式指定设备并启动。脚本不自动挑选第一台设备，不安装未签名预编译产物。Xcode 登录状态、设备注册与证书创建由 Apple 官方工具处理；若出现账号或钥匙串交互，按系统提示完成。

也可在已打开的 workspace 中选择 CharacterHost 和实际手机，在 Signing & Capabilities 选择同一 Team，点击 Run。脚本方式会将本地 Team 同时应用于宿主及 Unity 依赖目标。Xcode 界面方式若提示某个依赖目标缺少 Team，应为其选择相同团队。

安装后可拔线，从桌面“模型空间”直接运行。若系统明确提示未受信任的开发者，按提示到“设置 → 通用 → VPN 与设备管理”信任对应开发者。

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

## 验收边界

未连接手机的阶段只能证明真机代码编译和包结构准备完成，不能声称已安装、已在真机运行或已达到 120 FPS。App 默认请求 120，实际高刷新率表现仍需连接真机后查看并持续测量。Release 安装后从桌面启动，可避免调试器介入本轮实际使用体验。

Apple 官方依据（2026-09-26 核对）：[免费 Personal Team 与 7 天有效期](https://developer.apple.com/support/compare-memberships/)、[开发者模式](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)、[自动签名与 Team](https://help.apple.com/xcode/mac/current/en.lproj/dev23aab79b4.html)。本地构建结果见 `docs/verification/device/preparation.json`。
