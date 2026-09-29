# 星夜 0.25.0 / build38 · 静态语音标签与消息转场

[设计和原因](../../design/2026-09-29-message-handoff.md)。范围：iPhone原生界面与Unity桥接；模型、动作和Unity导出沿用已验证的immersionRevision 2，未新增iPad测试。

| 反馈 | 处理 |
| --- | --- |
| 未播放的按钮/时长仍有动效 | 只有正在播放的子树包含循环动效；准备、未播放、停止、完成均为静态 |
| 不要“约”字 | 统一显示`13″`/`1′08″`；临时估值与实际时长的存储语义仍区分 |
| 消息进入角色动画末尾闪一下 | 3D窗口保持不透明，原生窗口固定在上方，仅淡出原生内容；结束时不移除/重排窗口，不恢复遮层alpha |
| 返回同一角色也要连续 | 驻留会话使用同一套原生遮层过渡，保留presentation、草稿与镜头 |

## 画面与采样

- [未合成的静态标签，已去掉“约”](minimal-chat-pendant.png)
- [播放中](starry-bubble-playing.png) · [手动停止后的静态标签](voice-stopped-static.png)
- [消息进入初音](message-handoff-0-hatsune-miku.png) · [消息进入Luma](message-handoff-1-studio-robot.png) · [消息返回同一个Luma](message-handoff-2-studio-robot.png)
- [窗口交接事件](message-handoff-events.jsonl) · [自动校验结果](window-handoff-analysis.json)

## 执行范围

1. 基线`Starry-Handoff-Baseline.xcresult`的2条路由用例通过，69.179秒，但录屏仍能看到加载末尾的亮度跳变。这说明“最终页面出现了”不足以验证转场视觉。
2. `Starry-Quiet-Voice-Handoff.xcresult`：5条流程、0失败，137.445秒，覆盖估值标签静态/无“约”、真实语音段播放、播放中动效状态、自然结束/手动停止静态、实际时长重启保存、取消加载、启动途中后台恢复与正常恢复不重播。
3. 常驻透明宿主改动后的`Starry-Message-Handoff-Final.xcresult`：消息专项通过，32.277秒。连续从消息页切换初音/Luma，返回同一角色不增加presentation；随后实际输入文字、收键盘并点击头部，确认透明原生窗口没有截住输入或Unity触摸。
4. 最后进一步去掉返回菜单时重复激活Unity窗口的调用，桥接只在scene不同才重新绑定、窗口隐藏或非key时才调用showUnityWindow。`Starry-Message-Handoff-Bridge.xcresult`末次补验通过，30.308秒；消息切换、驻留恢复、键盘输入和头部互动均正常。11次交接、277个显示回调样本通过单调性/窗口透明度/层级校验。

采样仅在DEBUG加`--window-handoff-review`时记录。校验工具要求每段具有中间透明度、透明度单调变化、Unity窗口始终alpha=1、两个窗口在过渡过程中均存在且层级不变。中间录屏曾捕获返回菜单处3个近全黑帧，进一步收紧桥接激活和scene重绑定后，末次录屏解码2,173帧，近全黑主体帧为0，见[逐帧分析](final-video-analysis.json)。录像保留在`.local/checks/starry-v025-handoff-*.mp4`。模拟器在窗口交接附近存在时间戳/录屏采样限制，不能以视频标称帧率声称真机120FPS；这轮也不以最终截图代替过渡过程检查。

## 手机安装

最终Device Release构建、严格签名校验通过，9月29日01:19通过同一网络更新手机，回读确认为 **星夜0.25.0 / 38**，01:19:21启动成功。沿用原Bundle ID并保留资料，没有卸载、数据重置或QA启动参数。Xcode保持device / Release，见[脱敏安装记录](device-installation.json)。
