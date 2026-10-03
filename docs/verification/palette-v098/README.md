# 0.98.0 / 129：开发者颜色定制与云端设定检查

本次只增加开发者材质实验，兼容当前 16 个角色及现有 OSS release 4。没有改用户的原始模型、重新生成图像或调用付费对话/语音/图片接口。

## 已验证的材质覆盖

`CharacterPaletteReview.Run` 在实际 prefab 的可丢弃副本上通过 **55,358 项断言**。全部 **383 个材质槽**（含 92 个当前隐藏的槽）与 **22,350 个 Color 通道**都有目录，12 个现用 lilToon 家族均有宿主调色器。

| 角色 | 材质槽 | 隐藏槽 | Color 通道 |
| --- | ---: | ---: | ---: |
| Chiffon | 15 | 1 | 889 |
| Fiona | 28 | 8 | 1,547 |
| Hikarun | 27 | 10 | 1,543 |
| Ichigo | 33 | 3 | 1,893 |
| Koharu | 28 | 6 | 1,598 |
| Lime | 14 | 1 | 828 |
| Mafuyu | 25 | 4 | 1,478 |
| Mao | 22 | 0 | 1,302 |
| Meiyun | 26 | 12 | 1,540 |
| Milfy | 31 | 4 | 1,854 |
| Mizuki | 18 | 10 | 1,069 |
| Perula | 25 | 4 | 1,479 |
| Plum | 18 | 2 | 1,010 |
| Ramune | 31 | 9 | 1,839 |
| Shinano | 17 | 3 | 1,004 |
| Sio | 25 | 15 | 1,477 |

审核覆盖全槽与全部通道的独立复制、范围/非有限数验证、alpha 不变、原始颜色不变、恢复原始材质引用、无复制材质泄漏、其他 MPB 属性保留、120 次重复更新无累积染色，以及动画换材质后以最新作者材质为恢复目标。这里的 120 次是迭代审核，不是真机 120 FPS 测量。

## 实际 Metal 画面

`CharacterPaletteVisualReview.Capture` 对 Chiffon、Hikarun、Mizuki、Ramune 的固定姿势做真实 URP/Metal 渲染：原作 → 中性调色 → 换色 → 原作恢复。背景和光照不随调色变化；实图确认仍有贴图细节、透明头发与阴影，非粉色错误材质。

平均 RGB 绝对差归一化到 0…1：中性与原作差为 0…0.00000692，恢复与原作差为 0…0.00000685；换色差为 0.00317…0.00764。完整像素结果与 PNG 在本机 `.local/checks/palette-v098/metal/`，不公开提交角色图片。

第一次像素检查 Ramune 恢复差 0.002056，超过初始 0.002 阈值。相机开启 dithering，整幅背景也出现随机 RGB 舍入噪声；关闭该测试相机的 dithering 后重跑，恢复差降到 0.00000684，通过检查。App 的原有相机设置不因此改变。

## 问题处理与导出边界

- 第一次编译发现名册条目本来就是 ID 字符串，修正 builder 对条目类型的假定；首次运行发现 MPB 不能在 MonoBehaviour 字段初始化阶段创建，移到 Awake。
- 复制材质时显式保留 renderQueue/keywords，避免换 shader 引发透明顺序改变。恢复只处理自己写入的颜色，不清空其他组件的参数块。
- 将 shader 副本注册用 dummy pass 的 v2f 输出 POSITION 修正为 Metal 所需 SV_POSITION；不改原作依赖或真正的输入/几何 pass。原依赖的注册 pass 仍可能打印旧警告，实际渲染与导出分别验证。
- 渲染审核通过后，在同一 Editor 进程做导出遇到 `DOTSInstancingMetadata::Reset / SRPBatcherInfoSetup` 的 SIGABRT。没有把这次失败当作导出成功；沿用项目已有策略，在新 Editor 中 `-nographics` 做 prepared export，保留独立 Metal 渲染证据。
- 普通未调色的进入会话仅对已存在的实验组件复位，不因此载入调色 shader 库。过期组件/通道偏好在重放前跳过，防止包升级导致加载失败。页面关闭刷新最后一笔操作，包括回到中性值。

## 云端设定检查

用户确认手机账号 `xy100000001`。API 配置、API 实际进程与 worker 均已授权，遗漏发生在 Caddy 的 testing 通配拦截。已部署精确的 POST inspector 转发；仍由可撤销登录会话、固定账号 allowlist、角色访问检查与 worker owner/HMAC 双重校验。没有打开其他测试路由或全局 inspector。

公网匿名 inspector POST 返回 401；GET 和其他 testing 仍为 404。该账号在 worker 只读检查的 16 个角色均 HTTP 200，各 48 个不同分区。Go API/config 测试和 2 个部署规则测试通过。完整配置、用户报告和认证信息不进入公共仓库。修复只 reload 公网入口，未重置用户数据或调用 AI。

服务端源码已同步 `starrynight-server` 提交 `495efd3`；部署脚本、回滚备份与服务端记录见独立仓库的 `docs/developer-inspector-2026-10-03.md`。这是云端分层验证，不代替手机上当前会话的实测。

## 原生操作与安装

iPhone 17 / iOS 26.4 模拟器：13 个内置角色逐一进入会话、读取目录、滑动调色、接收引擎回执、恢复默认及角色隔离通过，XCTest `testBuiltInPaletteCatalogEditingResetAndIsolation` 用时 479.755s。测试截图与结果在 `.local/checks/Palette-v098-Player.xcresult`，截图不公开。

真实云端/OSS 验证：Fiona、Mizuki、Ramune 从现行 release 4 下载进入会话，逐个调色/恢复并验证原作表现，继续清除资源、重新下载，XCTest `testDeleteActiveDownloadedRoleAndDownloadAgain` 最终通过 178.734s。没有重新发包。`testPalettePersistenceAndSourceSelection` 验证原作通道/整体切换、本机重启后自动重放与恢复，57.894s 通过；组合结果 `.local/checks/Palette-v098-Verified.xcresult` 共 2 个测试、0 失败。

期间发现颜色页的容器 accessibilityIdentifier 传播至返回按钮，首次旧包测试不能找到关闭入口。修正容器语义，用独立且可见的颜色目录状态文本作为动态状态元素，避免状态标识覆盖控制；又修正测试在渐变子页挂载前读取快照的等待。失败记录保留于 `Palette-v098-Player` 和 `Palette-v098-Final`，最终操作/关闭/保存均复核通过。默认选择优先可见的头发材质，避免首次调色误选仅用于表情覆盖的 Face_effect。最新选择逻辑、原作通道切回整体和重启保留再次通过 59.563s，结果 `.local/checks/Palette-v098-Persistence.xcresult`。

模拟器和设备 Unity 导出分别成功，设备 Release 0.98.0 / 129 的 Apple 签名编译成功。最初的 30s 连接尝试超时，当时 iPhone disconnected、iPad unavailable。用户于 2026-10-03 通知手机回到同一网络后，重新建立无线 tunnel；45s 安装尝试仍超时，但随后设备变为 available，实际读取旧版本为 0.96.0 / 127。沿用已签名设备包，不重复编译，改用足够的传输时限后，于约 14:10 无线安装成功。

安装 JSON 的 outcome 为 success；随后独立查询手机 App 清单，确认 `com.gukaifeng.xiaoban.dev` 为 **0.98.0 / 129**。远程启动被 iOS 明确以 `Locked` 拒绝，原因是手机锁屏，安装本身已经完成；没有把安装成功描述为真机画面或性能验证通过。用户解锁后可直接打开 App。本机证据为 `.local/checks/device-install-v098-wireless.json`、`device-app-v098-installed.json`、`device-launch-v098-wireless.json`，保留在忽略目录。

设备包留在 `.local/build/DeviceDerivedData/Build/Products/Release-iphoneos/CharacterHost.app`。以上实际画面、调色操作与持久化验证均来自 Editor/模拟器；本期没有真机帧率测量。
