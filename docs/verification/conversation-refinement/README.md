# 0.45.0 会话与控制验收

**星夜 0.45.0 / build 66 已通过 Wi-Fi 安装并启动于 iPhone 17，设备读回版本吻合。** 本轮在 iPhone 17 / iOS 26.4 模拟器完成 8 项实际 UI 流程；Unity 对琪宝、豆日向共五种手机尺寸完成 87,225 项断言。不是实机帧率测量，未新增 iPad 测试。

- [设计与行为约定](../../design/2026-09-29-conversation-refinement.md)
- [UI 验证结果](app-review.json)、[Unity 结果](runtime-review.json)、[真机安装和启动](device-installation.json)

## 已完成

| 需求 | 验证 |
| --- | --- |
| 位置按钮对齐角色胶囊 | 实际控件中心误差 ≤1pt，横竖屏可点击 |
| 位置窗从聊天区向上淡入 | UIView presentation layer 连续采样 x 固定 67pt，y 从约477pt降至461pt，透明度从约0.08升至1；无左上飞入 |
| 任意方向、多圈旋转 | 真手势达到横向约248°、纵向约-176°，scale/x/y 不变；Unity 额外覆盖 ±1080°/±720°及连续900°/630°手势 |
| 保存、关闭、重启、恢复默认 | 朝向按整圈等价保存，重启不截断为旧20°；恢复原始位置和角度 |
| 启动和切换主动说话 | firstLaunch → firstMeeting → characterSwitch → appLaunch，已实测语音播放态；同角色页签/前后台切换不追加；访客轮次不增加 |
| 音量独立，0静音 | 无任何 Switch；从滑块拖至端点，朗读/音乐精确0；音乐暂停，调高恢复；朗读0重启仍静音且不影响音乐；旧布尔偏好迁移通过 |
| 紧凑表现窗 | 实际选择原作耳朵循环、恢复默认、一次起身动作结束恢复；镜头不因窗口改变 |
| 手机安装 | 签名构建成功，CoreDevice无线安装成功，读回0.45.0/66，启动成功 |

## 页面截图

[位置调整](simulator/position-pass-through.png) · [紧凑声音设置](simulator/compact-sound-settings.png) · [音量归零](simulator/compact-sound-zero-volumes.png) · [紧凑角色表现](simulator/source-ear-loop.png) · [切换角色主动说话](simulator/switch-known-character-speaking.png)

自由旋转允许立绘轮廓超出原始构图，不再以强制缩小、移动或限角纠正。平移和缩放仍以原始构图安全区约束；这是本轮明确采用的交互规则。

## 关键问题与处理

1. 弹窗零尺寸初始布局被加入动画，导致从原点飞入。现在先透明挂载并无动画完成布局，只动画18pt竖直位移与透明度；保留减少动态效果支持。
2. 一次性关系问候误用于全部入口，拦住启动/切换重逢。改用场景策略与entry UUID确认去重，不依靠生命周期每次重建。
3. 旧界面静音布尔值若仅隐藏，会留下“拉高仍无声”的隐形开关。迁移到可见0音量后，音量成为唯一控制来源。
4. 第一组测试中旧包围框断言仍要求所有旋转后的外轮廓在屏内，与新需求冲突。已更新为缩放平移边界，Unity仍独立核对原始构图全部八角。
5. iOS26 XCTest normalized slider/从轨道空白处开始的拖动会停留约6%音量。最终用实际滑块位置作为起点、拖过左端，确认精确0及音频暂停/恢复。产品没有增加粗糙的6%静音阈值来迁就测试。

通过结果分别保存于 `.local/checks/Conversation-Refinement-v045.xcresult`（7项通过、包含上述旧断言失败）和 `.local/checks/Conversation-Refinement-v045-audio-thumb.xcresult`（修正操作后的音量及双指流程通过）。中间诊断 xcresult 保留，可追溯；未把混合结果说成整包全绿。
