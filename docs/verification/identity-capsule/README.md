# 星夜 0.32.1 / build50：角色胶囊与资料入口

新版已签名安装到手机，回读星夜0.32.1 / 50。自动启动因手机锁屏被系统拒绝，未重试；用户解锁后直接打开已安装App即可。iPhone 17模拟器完成专项验证，并恢复无测试参数的正常运行；Xcode工作区保持device / Release。

## 交付

- 会话头像与名字置于按内容收拢的半透明胶囊，轻细渐淡边线、月白深色表面；没有额外图标或全宽底色。
- 头像保留圆形、当前定制对应的肖像和语音扩散波纹。装饰不拦截触摸、不裁切波纹，系统减少透明度与实色主题有对应显示。
- 定制移到资料简介头像旁：30pt高的轻量胶囊，仍保留至少44pt的点击高度。
- 从会话打开的根资料页删除底部「进入会话」，可点外部空白或左上角返回继续原会话。定制返回资料，原草稿验证／保存与退出过渡保持。
- 发现和作者作品的资料仍有「进入会话／订阅并聊天」，包括从作者作品切换到另一角色。

## 验证

两个不同XCTest方法均有通过结果，合计53.235秒用例时间，不含构建及Runner启动。导航用例验证会话资料没有聊天按钮、定制往返、实际空白处点击退出、发现仍可进入Luma并定制。打开／返回的六项相机值完全一致，详见[result.json](result.json)。

原语音用例首轮失败：它固定观察第一条气泡，而主动问候已成为第一条，实际正在播放的是后面的回复。修正测试为绑定播放中消息ID，单独复跑通过；头像状态在播放时为true，停止后为false，语音逻辑未修改。初轮失败与复跑结果均保留于.local/checks，不将失败轮次标为全通过。

Simulator Debug和Device Release编译通过，Device严格签名验证通过。真机安装与版本回读成功，未把安装成功当作真机界面或帧率验收；未增加iPad测试，也未重新导出Unity。

## 截图

- [会话顶部胶囊](identity-capsule-header.png)
- [会话内资料与小定制按钮](identity-conversation-profile.png)
- [资料内打开定制](identity-customization.png)
- [点空白处返回会话](identity-capsule-after-dismiss.png)
- [发现资料保留聊天入口](identity-discovery-profile.png)
- [播放时波纹](identity-avatar-speaking.png)／[停止后静态](identity-avatar-stopped.png)
- [最终正常启动的模拟器](normal-simulator.png)

设计决定记录在[角色资料方案的v0.32.1增补](../../design/2026-09-29-character-identity.md)和[开发记录E80](../../development-notes.md)。
