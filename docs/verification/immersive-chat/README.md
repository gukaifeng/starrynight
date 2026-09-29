# 沉浸式聊天验证 · 小伴0.6.1 / build9

2026-09-27，Xcode iOS26.4模拟器实际运行截图。三维场景实时渲染；图中按钮、文字和透明度均来自真实App。没有用设计图替代运行效果。

| 设备 | 本轮最终流程 | 结果 |
| --- | --- | --- |
| iPhone17 | 小夏／Luma／初音头部实际触摸；完整背景；输入与回复；静夜；定制保存、取消、重启恢复 | 3条测试，0失败 |
| iPad Pro11 M4 | 完整背景；头部互动；竖屏键盘；消息；静夜；横屏与横屏大键盘下输入栏让出脸部 | 1条测试，0失败 |

原始结果：`.local/checks/Immersive-Phone-2.xcresult` 和 `.local/checks/Immersive-iPad-3.xcresult`。时长、版本与范围见 [results.json](results.json)。此前 iPad 第2轮虽然键盘不遮输入断言通过，但截图发现输入框遮住角色嘴部，因此不作为最终横屏验收图；第3轮已修正并增加位置断言。

## 重点截图

- [iPhone全屏角色＋底部渐变](iphone17/01-full-stage.png)
- [iPhone键盘避让](iphone17/02-keyboard.png)
- [iPhone静夜聊天](iphone17/04-night-conversation.png)
- [Luma](iphone17/studio-robot-full-stage.png)／[初音](iphone17/hatsune-miku-full-stage.png)
- [定制身形时的完整预览](iphone17/studio/03-body-preview.png)
- [iPad竖屏](ipad-pro-11/01-full-stage.png)／[横屏](ipad-pro-11/05-ipad-landscape.png)
- [iPad横屏输入，聊天自动移到右下](ipad-pro-11/06-ipad-landscape-keyboard.png)

## 范围

本轮重点是画面主体、透明度、互动与键盘布局。音频引擎和角色资源未在本轮重新做全套验收。保留120FPS请求设置，但本轮没有真机帧率测量。真机安装状态独立记录，不以签名构建成功表示已更新手机App。

最终普通启动截图：[iPhone17正在运行的界面](iphone17/final-running.png)。同版本真机Release构建与深度签名验证通过；本轮未推送到手机。workspace保留device配置，模拟器App已安装并运行。
