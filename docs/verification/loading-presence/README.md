# 0.78.0 加载与交互验收

2026-10-01，0.78.0（105）。设计见[加载画面与离散交互](../../design/2026-10-01-loading-presence.md)。截图、录屏、日志和设备回执留在本机 `.local/checks/`，不提交角色图片。

## 已完成的验证

| 项目 | 实际结果 |
| --- | --- |
| 模拟器原生 Debug 构建 | 通过，iPhone 17 / iOS 26.4，复用 Unity v14 |
| 全屏加载、提示及共享胶囊 | C 轮 28.499 秒通过：封面覆盖屏幕顶部与完整高度，点击提示位于胶囊下方且不挪动胶囊，约 4 秒消失；加载时不打开资料，完成后胶囊位置和尺寸与加载一致，资料可打开 |
| 右滑、并排操作与确认 | C 轮 23.887 秒通过：左滑不展开，右滑后操作区位于消息主体右侧且无重叠；删除红色像素在确认期间保留，取消后恢复宽度；不显示、撤销和重新进入会话通过 |
| 快捷回复与氛围档位 | A 轮 53.480 秒通过：横竖屏面板右对齐、空白关闭、拖动模型保留；五档滑动、档间点击选择最近整数档、关闭重开后保存值正确 |
| 输入模式版式 | A 轮 8.273 秒通过：键盘／按住说话模式起点、基线、宽度和切换按钮位置一致，切回不改变原布局；两张截图已审查字重和颜色 |
| 语音提前识别、松手编辑 | A 轮 13.516 秒通过：早到识别结果不结束持有，松手才进入编辑，直接松手发送仍可用 |
| 语音取消与原草稿 | A 轮 9.900 秒通过：取消不发送，键盘草稿保留 |
| iPhone Release / 严格签名 | 通过，`.local/logs/host-device-20261001-171711.log`；`codesign --verify --deep --strict` 成功 |
| iPhone 安装 / 版本回读 | 成功，0.78.0（105），bundle `com.gukaifeng.xiaoban.dev` |

共 6 条不同的相关 UI 用例通过。A 轮其中 4 项通过，加载与右滑的最终修正版在 C 轮通过；没有将 A/B 两轮的失败掩盖为一次全绿。最终 C 轮为 `TEST SUCCEEDED`。未运行全部历史测试；未重新做 iPad 或真机持续帧率测量。UI 测试使用隔离测试账号和包内／确定性语音，不调用付费 AI、ASR 或 TTS 生成。

已实际查看最终整屏加载提示、右侧并排操作、确认期间保持展开、五个刻度、两种输入模式及横屏快捷回复截图。呼吸滤镜采用渲染层 opacity 动画；没有将视觉审查解释为帧率验收。

## 发现与修复

- 加载黑边来自父容器安全区域，而非源图本身；移动背景层到整窗解决，不靠放大图片掩盖错误容器。
- 静态胶囊外再包 Button 时，原静态无障碍标识产生嵌套身份。改为胶囊自身提供独立加载提示入口，共用视觉、分离操作。第二轮提示实际已显示，但 XCTest 把合并后的静态文字查成 Other；按真实无障碍树改成 StaticText 后通过。
- 右侧操作视觉已在正确位置，但整行手势使消息按钮的无障碍范围仍覆盖操作区。手势收窄到消息主体；随后真实点击发现操作按钮命中仍受影响，补齐内容形状及操作区层级。最终同时验证几何无重叠、真实点击、确认保留、取消和不显示，不能只看截图判定成功。
- 氛围从松手吸附改成触摸期间选整数档；五个刻度直接取原生拇指中心坐标，避免宽度变化后刻度和滑块错位。粒子倍率和原有过渡曲线未修改。

## 手机结果

17:18 安装成功；安装后查询显示版本 **0.78.0 / 105**。17:19 尝试自动打开时，设备明确返回 `Locked`，不能把安装成功描述为已自动启动或完成真机触摸验证。用户解锁后可直接打开。没有卸载应用或清空真实聊天记录。

回执：`.local/checks/loading-presence-device-{install,launch,apps}.json`；模拟器结果：`LoadingPresence-A.xcresult`、`LoadingPresence-B.xcresult`、`LoadingPresence-C.xcresult`，对应附件目录 `loading-presence-{A,B,C}-attachments/`。新源码已登记在真机和模拟器工程。

复跑相关检查：

```sh
python3 scripts/generate_host.py --platform simulator
xcodebuild -workspace ios/StarryNight-Simulator.xcworkspace -scheme CharacterHost \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath .local/build/DerivedData -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:CharacterHostUITests/ConversationPolishTests \
  -only-testing:CharacterHostUITests/VoiceAtmosphereTests/testHoldSurvivesEarlyRecognitionAndReleasesIntoEditor \
  -only-testing:CharacterHostUITests/VoiceAtmosphereTests/testHeldCancelDiscardsEarlyRecognitionAndPreservesTypedDraft test
```
