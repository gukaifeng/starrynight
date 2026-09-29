# 星夜 0.24.0 / build37 · 启动与最终取景验证

[设计、原因与处理](../../design/2026-09-29-startup-composition.md)。本轮优先iPhone，原生代码与资源更新，Unity继续使用已校验的immersionRevision 2导出；未新增iPad测试。

| 要求 | 最终行为 |
| --- | --- |
| Luma等角色进来后又缩放 | 删除宿主入场后自动触发的招手事件；取景配置与渲染确认后直接显示最终构图 |
| App启动有连续、明确的等待反馈 | 独立全屏品牌开场；与初始化并行；1.2秒后若未就绪，继续3.6秒一轮的呼吸/流光；就绪后0.55秒淡出 |
| 启动和角色切换区分 | 启动为字标与星月，角色切换保留细星轨、角色名及底栏；不会叠放两套动画 |
| AI气泡顶部太空 | 正文顶部21pt→12pt，与底部12pt一致；播放/时长位置保持，触碰高度仍44pt |

## 画面与数据

- [App启动等待](app-startup-waiting.png) · [随后呼吸亮度](app-startup-breath.png)
- [角色切换入场](starry-arrival.png) · [Luma首次显示的最终构图](first-framing-studio-robot.png)
- [紧凑气泡留白](minimal-chat-pendant.png) · [播放中](starry-bubble-playing.png) · [实际语音时长](starry-bubble-duration.png)
- [初始角色连续相机样本](cold-start-motion.jsonl) · [样本分析](startup-analysis.json)

## 实际执行

专用iPhone17模拟器、iOS26.4，Debug宿主、现有Unity模拟器框架。

1. `Starry-Startup-Composition.xcresult`：3条完整流程、0失败，84.279秒。四个角色切换完成时均无动作构图、无相机过渡、自动身体动作计数为0；每个角色首次出现与3秒后的距离相同（误差阈值0.0001）。随后分别点击头部，确认事件和实际动作均触发。另验证冷启动待机动画与角色切换动画分离，正常后台恢复不重复启动开场。
2. 初始角色的232个连续样本跨7.15秒，相机位置、距离、FOV与snap计数不变；没有动作构图、进行中的取景动画或自动入场身体动作。角色眼睛/头部自然注视不属于相机变化。
3. `Starry-Startup-Bubbles.xcresult`：3条完整流程、0失败，96.546秒。覆盖实际语音播放/停止、音频段计量、实际时长与重启保存；播放按钮仍至少44pt高，位于正文上方；搜索跳转/小箭头布局与消失均通过。慢启动途中退后台再返回可完成加载，聊天输入可点击，启动遮罩已移除。
4. 发现构建生成器会重写Info.plist，因此把LaunchNight声明同时写回`generate_host.py`，重新编译模拟器并回读成品Info.plist确认；避免只改生成文件而在下一次构建丢失。最终启动录屏使用此成品。

两张启动等待截图相隔约0.55秒，变化仅出现在标志/光晕区域，证实等待期间并非静止图。最终模拟器录屏`.local/checks/starry-v024-startup.mp4`共解码5,197帧，其中955帧识别为品牌等待画面；标志区域包含948个不同画面，亮度持续变化，见 [录像帧分析](startup-video-analysis.json)。UIKit/Unity交接时模拟器录屏时间戳可能不连续，不用该录像推断真机FPS或宣称冷启动总耗时下降。动画改善的是等待反馈、前后过渡与主线程忙碌时的呈现；Unity仍有同步初始化工作。

## 手机交付

Device Release构建与严格签名校验通过；9月29日00:54通过同一网络更新，00:55从手机回读确认为 **星夜0.24.0 / 37**，00:55:02启动成功，稍后再次确认同一App进程仍在运行。沿用原Bundle ID，没有卸载、清空数据或QA启动参数。Xcode工作区保持device / Release。见 [脱敏安装记录](device-installation.json)。
