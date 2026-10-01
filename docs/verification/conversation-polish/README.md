# 0.77.0 会话细节验收

2026-10-01，版本 0.77.0（104）。设计和兼容策略见 [会话过渡与操作反馈](../../design/2026-10-01-conversation-polish.md)。原始截图、视频、构建日志、JSON 和 xcresult 保留在忽略目录 `.local/checks/`，不公开提交角色素材。

## 结果

| 验证 | 实际结果 |
| --- | --- |
| iOS 模拟器 Debug 构建 | 通过，沿用 Unity v14 导出 |
| iPhone Release / 严格签名校验 | 通过，日志 `.local/logs/host-device-20261001-164352.log` |
| 氛围数值检查 | `scripts/test_atmosphere_blend.sh` 9,424 项断言通过；新映射、25 对档位、快速反向连续性、零档与粒子淡入淡出 |
| 加载胶囊与资料隔离 | H 轮 27.628 秒通过。强制延长加载时点击不打开资料、没有资料按钮；加载与会话胶囊 x/y/宽/高一致；完成后可打开资料 |
| 快捷回复与连续氛围滑块 | H 轮 52.735 秒通过。横竖屏与输入容器右侧对齐、点击空白关闭、面板打开时模型仍可拖动；五档切换及关闭重开后的保存值正确 |
| 消息删除保留展开 | G 轮 29.228 秒通过；I 轮最终复测 28.848 秒通过。左右滑动、红色操作区像素、确认弹窗下仍保留红色操作区、取消回位、不显示/撤销/重新进入会话 |
| 聊天滚动与控件 | H 轮 28.370 秒通过。文字上的纵向/斜向拖动仍滚动聊天、回到底部可用、气泡语音可点、键盘草稿保留 |
| 设置触摸隔离与横竖屏 | A 轮 57.068 秒通过。位置/声音/氛围面板都在可用区域，滑杆不改变角色位置，关闭后可输入 |

共 5 条不同的相关 UI 用例通过，没有运行全部历史用例。已查看实际加载、横竖屏快捷回复、氛围和左右侧滑删除确认截图。快速回复边框有亚像素扩展，测试允许 308 点内容加不足 1 点描边，而不是误把描边视为布局越界。

## 关键问题与处理

- 加载页仅禁止命中仍会暴露无障碍按钮。改为共用视觉内容，但静态分支不实例化 Button，保持无障碍与实际行为一致。
- 原生侧滑动作自动收回，改为独立展开状态。首轮自定义实现还发现拖动释放被 Button 视为点击、动作被前景命中层遮挡；增加短暂释放点击抑制，操作区置顶并按展开宽度裁剪。消息使用原生滚动容器与 LazyVStack，方向判断只处理水平拖动。
- 由可选删除目标推导的弹窗 Binding 在重绘时不稳定，改为独立 Bool 呈现状态；删除目标、弹窗生命周期与回位任务分开。完全关闭后移除操作按钮，避免透明按钮继续出现在无障碍树中。取消先退出弹窗，再收回行。
- H 轮的最后一例尚在启动阶段时，Mac 于 **16:30:41 合盖休眠**，到 **16:40:18 唤醒**，系统 `pmset` 记录 577 秒，造成 XCTest 启动等待超时；该轮没有标成全绿。机器恢复后不改代码，I 轮独立补跑通过，最终结果为 `TEST EXECUTE SUCCEEDED`。

主要结果包：`ConversationPolish-A.xcresult`、`ConversationPolish-G.xcresult`、`ConversationPolish-H.xcresult`、`ConversationPolish-I.xcresult`。中间诊断轮次也留本机；临时诊断文字已从产品代码移除。

## iPhone 安装与边界

**iPhone 17 安装成功：0.77.0（104）**，沿用 `com.gukaifeng.xiaoban.dev`，没有卸载或清理真实聊天。CoreDevice 安装回执为 `.local/checks/conversation-polish-device-install.json`。

安装后尝试自动启动时，系统明确返回 `Locked`，因为手机当时处于锁屏状态；不能将此次安装描述为已在真机启动或完成触摸验收。用户解锁后可以直接打开新版本。启动错误与版本查询保留在 `conversation-polish-device-launch.json`、`conversation-polish-device-apps.json`。

本轮没有 iPad 实机测试或持续帧率测量。120 Hz 只是数学曲线采样频率，不是 App 帧率结果。UI 测试使用隔离数据和包内问候，不执行付费 AI、ASR 或 TTS 生成请求。

复跑本次新增用例：

```sh
bash scripts/test_atmosphere_blend.sh
xcodebuild -workspace ios/StarryNight-Simulator.xcworkspace -scheme CharacterHost \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath .local/build/DerivedData -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO -only-testing:CharacterHostUITests/ConversationPolishTests test
```
