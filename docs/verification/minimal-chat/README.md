# 星夜 0.22.0 / build35 · 极简 Logo 与聊天页

[设计与边界](../../design/2026-09-28-minimal-starry.md)。本轮为 iPhone 原生改动，复用已验证的 Unity 导出。

| 项目 | 实现 |
| --- | --- |
| 极简 Logo | 单色弯月与四芒星，两条贝塞尔路径；交付深/浅色透明SVG和深底图标SVG |
| App 品牌资源 | App 内改用PDF矢量，桌面为同源1024px无透明PNG；旧图归档 |
| 底栏图标均衡 | 共用26pt对齐框、相同笔画权重，23pt宽对话图形/21pt圆形图形作视觉补偿 |
| 回到底部 | 无圆底无边框的双下箭头，无竖线；浮层下移14pt，44pt触控，持续轻动；减弱动态时静止 |
| 不挤动其他区域 | 界面测试比较箭头出现前后的输入框Y坐标及聊天区高度，差值不超过1pt |
| 清除提示 | 无语音就绪行、陪伴状态块、游客剩余轮数和固定登录栏 |
| 贴近语音挂件 | 紧贴气泡边缘，播放时局部微光呼吸，没有音柱 |
| 定制入口 | 角色名字与副标题区域可点击；右上独立图标和标题旁静音已删除 |
| 静音设置 | 定制弹窗顶部，按角色保存；重启仍保留，单条手动播放不更改静音偏好 |

手机于9月28日23:59无线更新，9月29日00:00回读确认 **星夜0.22.0 / 35** 并成功启动。同一应用标识保留资料，未传入测试参数。见[安装记录](device-installation.json)。

## 验证

- 初轮 iPhone 17 / iOS 26.4：3条完整流程通过，0失败，总计101.197秒。
  - `MinimalChatTests.testGuestCanvasNameOpensCustomizationAndMutePersists`：游客无固定提示、点击名字进入、静音保存与重启恢复、底栏导航和矢量Logo显示。
  - `QuietChatTests.testLocalSearchFocusAndStatisticNavigation`：发送/搜索/定位、箭头几何位置及不挤动布局、点击回到底部、统计入口与主题设置。
  - `StarryImmersionTests.testBubbleVoicePlaybackDurationAndNoMessageMenu`：真实音频计量、测得时长、停止与重播、定制页静音、重启缓存。
- 底栏末次光学校准后补验入口、静音保存、品牌与底栏，24.850秒通过；最终截图已更新。
- Simulator Debug、Device Release构建及严格签名验证通过。
- 普通语音计量测试数据迁到Debug模式语音挂件的辅助功能值，不为测试保留用户要求删除的状态行。
- SVG仅含路径和可选背景矩形；没有嵌入位图。AppIcon实测1024×1024，`hasAlpha: no`；App内PDF约2.3KB并开启矢量保留。
- 原始结果：`.local/checks/Starry-Minimal-Chat.xcresult`。最后的底栏尺寸补偿后另有 `Starry-Minimal-Final.xcresult`。

## 可查看的结果

- [Logo SVG](../../../assets/brand/starry-mark.svg) · [浅色 SVG](../../../assets/brand/starry-mark-light.svg) · [深底图标 SVG](../../../assets/brand/starry-app-icon.svg) · [PNG预览](../../../assets/brand/starry-minimal-preview.png)
- [聊天页与贴近挂件](minimal-chat-pendant.png) · [无边框双下箭头](minimal-double-chevron.png)
- [游客首页](minimal-guest-home.png) · [定制页静音](minimal-customization-mute.png) · [新Logo及底栏](minimal-brand-and-dock.png)

仍使用本机模拟对话和已有离线语音引擎；移除“离线”文案不等于接入在线服务。游客五轮限制未改，只是不再常驻提示。未新增iPad测试或持续真机帧率测量。
