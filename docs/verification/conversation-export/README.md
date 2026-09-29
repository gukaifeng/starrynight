# 对话长图验收 · v0.30.0 / build 47

## 实际效果

- [月夜：1080 × 3336 PNG 原图](images/moon-long-image.png)
- [暖笺：1080 × 3336 PNG 原图，打开日期时间](images/paper-long-image.png)
- [编辑页](screenshots/01-export-editor.png)、[精确范围](screenshots/02-selected-range.png)
- [月夜预览](screenshots/03-moon-preview.png)、[暖笺预览](screenshots/05-paper-preview.png)
- [iOS 系统分享面板](screenshots/04-system-share.png)
- [真实角色会话内入口，保留当前镜头](screenshots/06-live-character-export.png)

样图使用专门的测试对话，与普通用户档案分开；长图里的小光是已集成角色的实际头像。截图和导出 PNG 均来自 App 本身的运行结果。

## 已通过

设备为 iPhone 17 模拟器，iOS 26.4。无新增 iPad 测试。

| 验证 | 实际结果 |
|---|---|
| iOS 运行时核心断言 | **563 条通过，5.254 秒**。含包含端点的范围、越界和反向选择、空／system消息过滤、范围外消息排除、完整 Unicode 和换行、连续页边界、正文与页尾无重叠、PNG 类型与尺寸、取消清理 |
| 超长实物导出 | **4 张**，1080px 宽，高分别1506、11952、11952、11064px；没有跳字或重复，见 [机器结果](core-result.json) |
| 资料卡／聊天资料入口与镜头 | **44.258 秒通过**。资料卡连续进入两次、聊天资料入口打开关闭；distance、framingSize、framingAngle、pitch、yaw、cameraFov保持一致，framingMotionActive为false |
| 范围、搜索、双样式、预览与系统分享 | **17.554 秒通过**。搜索选起点与终点得到6条；月夜预览；系统分享显示图片标题；关闭后改暖笺和日期再生成；返回保留选择 |
| 构建 | Simulator Debug、Device Release成功，设备包 `codesign --verify --deep --strict` 通过，版本均0.30.0 / 47 |
| 手机交付 | 一次无线安装成功，设备应用列表回读「星夜」0.30.0 / 47。一次自动启动被系统以Locked拒绝，未等待解锁或重试；解锁后可直接点图标打开 |

第一轮系统分享自动化定位失败：iOS26把分享标题暴露为NavigationBar及LP.CaptionBar，而非StaticText。UI层级证实面板已出现；修正定位和使用系统关闭按钮后专项通过。保留原失败结果，未把定位问题写成分享功能失败或抹掉失败证据。

## 证据位置与复现

- `.local/checks/Conversation-Export-v0300.xcresult`：核心与真实会话入口通过，首轮分享定位失败。
- `.local/checks/Conversation-Export-Share-v0300.xcresult`：修正后的范围／风格／分享完整通过。
- `.local/logs/host-device-20260929-050207.log`：Device Release成功。
- `scripts/tests/ConversationExportTests.swift`：仅编入模拟器；SceneDelegate必须DEBUG＋显式`--export-core-check`或`--export-ui-check`才能运行隔离诊断，不改普通用户存档。
- `zsh scripts/test_companion.sh EFA3B59D-3939-4659-B60B-123516393F43 ConversationExportUITests <新的结果名>` 可复现三个用例。

这次验证了系统分享 UI 与图像文件，没有在测试中向外部联系人发送，也没有验证微信等第三方 App 的最终接收、压缩策略。系统分享面板只显示当前设备安装并声明能接收此格式的 App。预览载入小图，实际分享的是1080px无损PNG。

最终模拟器已恢复正常 App（[截图](screenshots/07-normal-app.png)），没有停留在隔离测试页；Xcode工作区为device / Release。手机安装、回读、启动原始记录分别在`.local/checks/starry-v0300-device-{install,apps,launch}.json`。
