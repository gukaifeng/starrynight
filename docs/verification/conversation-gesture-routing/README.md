# 聊天区域手势分流 · 2026-09-30

交付版本：**星夜 0.54.1 / build 77**。交互设计见[聊天区域手势分流](../../design/2026-09-30-conversation-gesture-routing.md)。

## 已完成的验证

| 检查 | 实际结果 |
|---|---|
| Unity 模拟器与手机导出 | 两个独立导出均成功；交互版本为 11，导出内容与两套角色集合的完整性守卫通过 |
| iPhone 17 / iOS 26.4 模拟器 | 最终 `chat-gestures-final.xcresult` 中 5 个相关 UI 用例全部通过，`xcodebuild test` 退出 0 |
| 手机 Release 编译 | `build_device.sh --device …` 成功；100 个原生源文件，真实 UnityFramework 链接及 Apple 签名完成 |
| 签名完整性 | `codesign --verify --deep --strict` 成功 |
| iPhone 安装 | CoreDevice 确认安装成功，随后查询到「星夜」版本 `0.54.1`、构建 `77` |
| iPhone 启动 | CoreDevice 启动成功，未使用测试参数；随后进程查询确认该次启动的进程仍在运行 |

最终 5 个 UI 用例通过真实 UIKit 触摸命中与识别器进入 Unity 场景，并读取运行时状态；不直接调用手势桥接来代替触摸：

1. **空白与横向消息拖动**：聊天左右留白、短气泡旁的空白可转动；空白纵向拖动也可转动；AI 与用户气泡横滑均可转动；从空白越过气泡仍可转动。每次检查聊天实际位置未变、角色回弹计数增加、保存姿态未变、没有打开位置编辑。
2. **纵向与斜向消息拖动**：上下和偏纵向斜滑会进入历史记录；模型旋转计数不变；“回到最近”可回到底部；语音按钮和输入框仍接受操作，输入草稿保持。
3. **起手方向锁定**：先横后竖仍转模型，聊天内容不动；先竖后横仍滚聊天，并检查实际内容发生位移，不能只依赖“历史消息”的状态标签。
4. **直接触摸模型与复位**：默认与用户调整过的姿态上，都保持小角度限制，松手回到原保存状态；不写入临时旋转角度。
5. **双指取消**：双指起手不启动临时旋转；旋转中加入第二指会结束并回弹；剩余单指不能重新启动，也不产生缩放或平移。

本轮首轮构建另外执行了既有 ±80° 位置编辑与重新加载、消息及后补旁白自动回到底部两个用例，均通过。最终回归集中在此次修改的触摸路径，没有重复运行未变动的全部 AI/后端测试。

## 问题与证据

首轮失败没有略过：提示条遮挡测试落点、父视图识别器失败后重新接收第二指的问题，处理依据见[设计记录](../../design/2026-09-30-conversation-gesture-routing.md#测试中的问题与处理)。修复后的完整定向回归重新执行并通过。

本机原始证据：

- `.local/checks/chat-gestures-final.xcresult`、`.local/logs/chat-gestures-final.log`
- `.local/logs/chat-gestures-unity-simulator.log`、`.local/logs/chat-gestures-unity-device.log`
- `.local/logs/host-device-20260930-110212.log`
- `.local/checks/chat-gestures-install.json`、`chat-gestures-launch.json`、`chat-gestures-apps.json`
- 早期失败与临时触摸轨迹：`.local/checks/chat-gestures-ui*.xcresult`、`.local/logs/chat-gestures-two-finger-trace.log`

原始引擎授权日志、模型画面和设备数据留在本机，不随公开仓库提交。临时触摸轨迹代码已移除。长聊天样本仅由 DEBUG 模拟器的显式测试参数生成；手机包不包含该样本代码。

## 复跑入口与边界

模拟器导出就绪后：

```sh
python3 scripts/check_export_content.py --platform simulator
python3 scripts/generate_host.py --platform simulator
xcodebuild test \
  -workspace ios/StarryNight-Simulator.xcworkspace -scheme CharacterHost \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=Starry Night QA - iPhone17' \
  -derivedDataPath .local/build/DerivedData -parallel-testing-enabled NO \
  -only-testing:CharacterHostUITests/ConversationGestureTests \
  -only-testing:CharacterHostUITests/CharacterViewEditorTests/testNormalDragReturnsToSavedPoseWithoutOpeningEditor \
  -only-testing:CharacterHostUITests/CharacterViewEditorTests/testNormalTwoFingerGestureIsRejectedAndCancelsAnActiveDrag \
  CODE_SIGNING_ALLOWED=NO
```

自动化手势验证禁用付费 AI，使用仅用于测试的本地聊天记录。手机完成安装与启动检查；本记录不声称完成真机手势自动化或帧率测试，也不将模拟器触摸结果等同于真机触感测评。
