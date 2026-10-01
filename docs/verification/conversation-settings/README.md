# 0.76.0 会话设置验收

2026-10-01，iPhone 17 模拟器 / iOS 26.4。生产代码、测试与设计见 [设计说明](../../design/2026-10-01-unified-conversation-settings.md)。截图、录像、原始 JSON 和 xcresult 留在忽略目录 `.local/checks/`，不向公开 Git 分发角色图像。

## 已执行结果

| 检查 | 结果与范围 |
| --- | --- |
| iOS 模拟器 Debug 构建 | 通过；本轮不修改或重新导出 Unity |
| iPhone Release 构建与严格签名校验 | 通过，最终日志 `host-device-20261001-152835.log` |
| 氛围数学连续性 | `bash scripts/test_atmosphere_blend.sh` 9,421 项通过：25 组档位组合、120 Hz 数值采样、零档完全关闭、连续反向切换保留值和速度、粒子透明度边界连续 |
| 位置穿透与持久化 | C 轮 `testButtonPassThroughAutoRememberAndReset` 45.603 秒通过。玻璃说明区单指旋转、保存、重启恢复，切声音→氛围→位置后恢复默认真实生效 |
| 双指及声音设置 | A 轮 `testTwoFingerAndCompactSoundSettings` 46.309 秒通过。双指缩放移动、声音滑杆、滑至零停止音乐、重新升高音量开始音乐 |
| 横竖屏触摸隔离 | B 轮 `ConversationSettingsTests` 57.282 秒通过。三个页签均在窗口内；声音和氛围滑杆不改变取景；关闭后恢复聊天输入 |
| 横竖屏位置面板 | C 轮 `testCompactPhoneEditorInBothOrientations` 19.236 秒通过，复位与收起控件都可点击 |
| 紧凑界面和订阅确认 | B 轮 `ImmersiveRefinementTests/testDiscoveryDeveloperPagesAndConversationControls` 77.507 秒通过。胶囊尺寸/44 点点击高度、快捷回复宽度、氛围保存、取消/确认两条订阅路径、重新订阅、开发者和发现页仍可达 |
| 音量持久化与隔离 | B 轮 `ProfileSoundTests/testTwoRealSoundChannelsMutePersistAndStayIsolated` 47.675 秒通过，重启保留音量，不同角色互不影响 |
| 语音按住与编辑 | A 轮 `testHoldSurvivesEarlyRecognitionAndReleasesIntoEditor` 13.339 秒通过 |
| 语音取消与原草稿 | A 轮 `testHeldCancelDiscardsEarlyRecognitionAndPreservesTypedDraft` 9.791 秒通过 |

以上是 8 条不同的相关 UI 回归用例，未声称运行全部历史测试。源码中旧声音入口相关用例同步改为新面板入口；音频证据移到既有调试状态，不保留虚假的隐藏声音按钮。

原始结果：`UnifiedSettings-A.xcresult`、`UnifiedSettings-B.xcresult`、`UnifiedSettings-C.xcresult`；最后一轮为 **TEST SUCCEEDED**。A、B 中的失败按下节处理后复测，没有将整轮失败包装为成功。

## 实际发现与修复

1. 最初将原 UIKit 复位按钮继续添加到 SwiftUI hosting view 里，切页后可能被新视图层遮挡。改为位置页自己的 SwiftUI 按钮，UIKit 只路由触摸，不再混入按钮子层。
2. 迁移后说明列原本按内容宽度排版，复位按钮实际位置与 UIKit 保留的触摸区域不一致。把列铺满面板可用宽度，使可见按钮与触摸矩形一致；C 轮特意从已保存的非默认取景跨三个页签后执行复位，验证真实动作而不只检查按钮存在。
3. iOS 26 的系统警告弹窗给添加标识的动作按钮暴露了父子两层同名元素。移除多余标识，并让测试在系统 alert 内确定唯一动作入口。保留订阅不修改状态，确认取消后聊天仍在，胶囊可重新订阅。

已人工查看导出的实际截图：竖屏快捷回复、声音和氛围页、横屏声音页，以及最终竖屏位置页。未发现文字/按钮重叠、贴边或窗口越界。

## 真机与边界

**iPhone 17 已成功安装并启动 0.76.0（103）**，设备查询读回同一版本。安装、启动、版本读回记录分别位于 `.local/checks/unified-settings-device-{install,launch,app}.json`。本次更新沿用同一个 bundle ID，不卸载 App、不清理真实账号或会话。

本轮重点是界面与交互；未做长时间真机 GPU 帧率、发热或耗电测量，也未重新测试 iPad。120 Hz 是曲线数值测试的采样频率，不能解释成 App 120 FPS 实测。模拟器验证使用隔离测试数据和已有包内问候，没有执行付费 AI/ASR/TTS 生成请求。

复跑示例：

```sh
bash scripts/test_atmosphere_blend.sh
xcodebuild -workspace ios/StarryNight-Simulator.xcworkspace -scheme CharacterHost \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath .local/build/DerivedData -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:CharacterHostUITests/ConversationSettingsTests \
  -only-testing:CharacterHostUITests/ImmersiveRefinementTests/testDiscoveryDeveloperPagesAndConversationControls \
  -only-testing:CharacterHostUITests/CharacterViewEditorTests/testButtonPassThroughAutoRememberAndReset test
```
