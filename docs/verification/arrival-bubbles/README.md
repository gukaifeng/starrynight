# 星夜 0.23.0 / build36 · 入场与聊天细节

[设计与原因](../../design/2026-09-29-arrival-bubbles.md)。范围：iPhone手机版，原生UI与Unity运行时共同更新。

| 用户反馈 | 结果 |
| --- | --- |
| 打开新角色白闪 | 星月呼吸与细轨道加载；外观、空间、灯光、姿势、镜头准备完成并连续渲染三帧后才淡入；去除引擎浅白过渡遮罩 |
| 语音像另一个气泡 | AI气泡左上角自身抬起，单一连续轮廓包住播放与时长；播放时微光呼吸，无第二个Capsule |
| 点头部不响应 | 修复头顶、刘海不在面部网格里的漏点；四个角色面部点击均启动动作，初音头顶正例和胸部负例通过 |
| 箭头过大、过亮 | 13pt双下箭头、28%～52%不透明度、持续缓动，保留44pt触碰区与原有位置；没有挤动其他布局 |

## 可直接查看

- [最终透明星月加载画面](starry-arrival.png) → [淡入后的角色](starry-settled-closeup.png)
- [一体语音气泡](minimal-chat-pendant.png) · [播放中](starry-bubble-playing.png) · [实际时长](starry-bubble-duration.png)
- [小尺寸淡箭头](minimal-double-chevron.png)
- [触碰前](head-before-touch.png) · [头顶触碰后的摇头](head-crown-touch.png) · [动作事件](head-crown-touch-runtime.json)
- [冷启动确认顺序](cold-arrival-events.jsonl) · [录像帧亮度分析](white-flash-analysis.json)

## 实际验证

设备环境：专用 iPhone 17 模拟器，iOS26.4。未新增iPad测试。

1. 基线先运行旧引擎：面部点击链通过；增加可见头顶区域点击后失败，证实了用户反馈。原始结果分别为 `.local/checks/Starry-Head-Baseline.xcresult` 与 `Starry-Head-Crown-Baseline.xcresult`。
2. `.local/checks/Starry-Arrival-Head.xcresult`：4条流程、0失败，101.882秒。覆盖头顶及胸部负例、四角色切换与动作、冷加载取消后继续、加载动画到真实模型。
3. `.local/checks/Starry-Arrival-Bubbles.xcresult`：3条流程、0失败，123.782秒。覆盖气泡播放/停止与真实音频段计量、时长重启保存、无长按菜单、消息搜索定位、箭头消失及几何不挤动、跨三个菜单恢复同一presentation/镜头/草稿。
4. `.local/checks/Starry-Arrival-Final.xcresult`：移除矢量标志方底后，加载到实时模型补验通过，16.441秒；最终截图已替换。

录屏 `.local/checks/starry-v023-arrival.mp4` 中逐帧解码检查3,219帧，取主体区、排除状态栏和底栏。大面积白闪定义为平均亮度超过200/255且至少75%像素达到225/255；命中0帧，最大近白像素占比3.489%。此检查覆盖录到的切换、取消与冷启动过程，不代表所有未来配置永远无闪烁，也不用于测量真机帧率。模拟器录屏在UIKit/Unity交接时存在不连续时间戳，统计仅按解码帧检查像素，不用视频标称FPS推断运行帧率。

桌面独立Swift状态检查程序成功编译并通过签名校验，但两次执行被SIGKILL终止，没有得到断言结果，因此未计入通过项。未修改系统安全配置；同一加载状态代码的实际iOS流程由上述模拟器验证覆盖。

Unity两端导出均零构建错误、`immersionRevision: 2`；导出前的编辑器Metal着色器崩溃及无图形恢复流程见设计文档。真实渲染仍通过上述模拟器检查。

## 手机安装

Device Release构建、严格签名校验通过。9月29日已通过同一网络无线更新，00:32从手机回读确认为 **星夜0.23.0 / 36**，并成功启动；保留同一Bundle ID，没有卸载、清空数据或传入测试参数。见 [安装记录](device-installation.json)。Xcode工作区保持device / Release。
