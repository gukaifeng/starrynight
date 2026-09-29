# 星夜 0.21.0 / build34 · 结果与验证

本轮仅修改 iPhone 原生界面、消息定位与搜索，复用已有 Unity 导出（immersionRevision 1）。[设计与边界](../../design/2026-09-28-quiet-chat.md)。

| 用户要求 | 结果 |
| --- | --- |
| 小巧的气泡外语音挂件 | 位于 AI 气泡外部左上方，23pt 可见高度；仅播放/停止与简写时长，没有音柱 |
| 简写时间 | `8″`、`1′08″`；未合成显示“约”，完整播放后保存实测音频时长 |
| 首页不要返回／动作按钮 | 聊天模式隐藏返回和动作菜单，定制、对话和底栏保持可用 |
| 静音到角色名右侧 | 28pt 视觉尺寸、44pt 点击区，背景14%不透明，按角色保存状态 |
| 中间加号无文字 | 删除“创建”可见标签，保留辅助功能名称 |
| 月白默认并首位 | 新偏好默认月白、列表首位；保留用户明确选择的旧主题 |
| 我的页去标题／重复入口 | 删除左上标题及独立菜单行，关注／角色／聊过三处数字直接打开列表 |
| 搜索本地聊天记录 | 搜索当前账号实际消息正文；匹配片段、日期、关键词高亮；点击定位原消息 |

手机已于 **23:43** 无线更新，**23:45** 回读确认版本 **星夜 0.21.0 / 34** 并成功自动启动。沿用稳定 Bundle ID，保留用户资料，没有向真机传入测试参数。见[脱敏安装记录](device-installation.json)。

## 实际执行

- Simulator Debug 构建通过；Device Release 构建通过；`codesign --verify --deep --strict` 通过。
- `bash scripts/test_character_library.sh`：**53项通过**。新增覆盖双方消息检索、按日期排序、不可访问角色过滤、账号隔离、不能只命中角色名字、多词/重音/全半角、空白查询、Unicode片段、超出最近60条的历史定位及有界窗口。
- iPhone 17 / iOS 26.4 模拟器：**3条 UI 流程全通过，0失败，用例总计104.313秒**。
  - `QuietChatTests.testLocalSearchFocusAndStatisticNavigation`：真实发送、关键词搜索、定位、回到最近；挂件几何位置、顶部静音、统计入口、月白默认与顺序、无首页返回及动作菜单。
  - `StarryImmersionTests.testBubbleVoicePlaybackDurationAndNoMessageMenu`：实际声音计量、时长、停止／重播、静音下手动播放、重启恢复时长、无长按菜单。
  - `StarryImmersionTests.testRetainedHomeCompactMessagesAndProfileRoutes`：切菜单后原 presentationId / cameraSnapCount 不变，草稿保留，账户和各列表可打开。
- 原始结果：`.local/checks/Starry-Quiet-Chat.xcresult`；构建与运行日志位于 `.local/logs/`。未运行历史全部 UI 测试，也没有新增 iPad 或持续真机帧率测量。

## 截图

- [气泡外语音挂件／首页顶部](quiet-chat-pendant.png)
- [播放中的挂件](starry-bubble-playing.png) · [完整播放后的实测时长](starry-bubble-duration.png)
- [本地聊天搜索](local-search-results.png) · [定位原消息](search-focused-message.png)
- [个人页数字入口](quiet-profile-statistics.png) · [聊过的角色](chatted-character-list.png)
- [月白首位且默认选中](moonwhite-first-default.png)

搜索不会访问其他账号，也不会恢复已删除或超出原有1000条保留上限的消息。登录与对话服务仍按既有本机模拟运行，未新增服务端。
