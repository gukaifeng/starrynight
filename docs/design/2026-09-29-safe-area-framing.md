# 会话角色的屏幕安全区取景

角色的头顶、头发不应进入刘海、灵动岛或旋转后的侧边遮挡区域。以前的沉浸取景先按静态模型包络求距离，再把主体向上提；这段上移没有把原生窗口的安全区域送入 Unity，因此不同屏幕的头顶可能被切掉。

## 实现决策

- `ViewerOverlayController` 把当前 `UIWindow.safeAreaLayoutGuide.layoutFrame` 转成 Unity 全屏视图的坐标。`AdaptiveViewerLayout.characterSafeFrame` 在安全区顶边留 10pt、左右留 8pt，再转成左下原点的归一化矩形。运行时没有设备名称、型号列表、屏幕像素密度判断；横屏也使用当前窗口的实际左右安全边界。
- 左上身份胶囊不扩大整屏禁入区域，避免为了一个局部控件把角色整体压低。聊天框高度、键盘、底部菜单栏与临时弹窗都不参与这个安全区计算。
- `conversationViewport` 新增可选的 `safeFrameX/Y/Width/Height`。Unity 继续全屏渲染，保留 FOV、用户的取景模式、缩放与转角；安全约束只在现有取景结果上施加最小必要的相机平移。仅当极窄的横向安全区域无法容纳包络时，才计算最低限度的后退距离，不修改保存的用户偏好。
- 使用静态角色包络，而非逐帧追踪头骨。近景包络原有的身高 3.5% 顶部余量保留，覆盖正常待机微动；头发等最高可见部分来自模型的静态边界。环境背景仍铺满屏幕，身体可自然延伸到聊天渐变背后。
- 约束包含包络八个角点各自的深度，处理旋转后突出的头发。先约束弹簧目标，再约束实际显示的瞬时相机位置，避免平滑转动的中间帧越界。重复相同布局不会积累位移。
- 原生在准备呈现阶段发送几何，随后恢复角色保存的最终取景。原有三帧稳定画面再揭示的链路保留。切菜单、弹窗、键盘和聊天高度调整不会产生新的安全区。

## 兼容与诊断

角色包和制作规范无需升级。内部导出 `framingProtocol` 升至 **8**，构建脚本拒绝旧引擎导出，以免新宿主发送了安全区但旧 Unity 忽略它。

Unity 事件新增 `safeFramingRevision=1`、`characterSafeFrame`、`framingEnvelopeViewport`、`framingTopClearance`；后者是安全区顶部与实际相机投影顶部之间的归一化距离。调试宿主同时提供 `nativeWindowGeometry`，可独立核对真实安全区是否到达渲染端，而非只检查配置值。

## 检查

已完成的静态/本机检查：

- C# 使用当前 Unity 实际引用程序集检查：运行时与 Editor 程序集均通过；未以此代替 Unity 内容验证。
- `scripts/tests/check_safe_frame_geometry.swift`：4 种窗口几何、UIKit 到 Unity 的 Y 坐标转换、12 组键盘/聊天高度变化通过。测试窗口是投影夹具，运行时不查询这组值。
- 改动 Swift 文件与新增 UI 测试语法解析通过。

已完成的引擎与实际模拟器检查：

- `SafeAreaFramingReview.Validate()` 使用场景内全部 10 个模型的真实静态边界，覆盖 4 种窗口、2 种取景、3 种缩放和 3 个角度；每模型/窗口额外检查 240 帧转角运动，使用 Unity `Camera.WorldToViewportPoint` 独立验证安全边界。检查竖屏距离不变、初帧即终态、重复布局无漂移及中间帧安全。输出 `.local/checks/safe-area-framing/projection-audit.json`。
- `SafeAreaFramingTests/testActualWindowSafeAreaProtectsDefaultAndIllustratedCharacter` 在实际 iPhone 模拟器核对默认角色和优可的窗口安全区、相机投影、头部位置，并附截图与 JSON。
- `PanelCameraStabilityTests` 检查取景在弹窗、键盘和菜单切换时保持一致。

实际结果：Unity十角色×四窗口的82,560个角点投影、9,600个连续转角采样通过，最小边界误差−4.77e−7在2e−5容差内；竖屏最大距离变化为0。iPhone 17实际窗口402×874pt／顶部62pt，17e为390×844pt／顶部47pt，Unity额外保留10pt；初音和优可均通过实际投影检查，初轮分别28.498秒及26.603秒；庭院美术收尾后复核分别37.230秒和37.380秒。17e面板、键盘与菜单相机稳定检查163.896秒通过。两种窗口都来自UIKit真实几何，未硬编码设备型号。截图和JSON见[统一验收目录](../verification/immersive-scenes/README.md)。真机安装单独记录，以上不代表真机性能验收。

依据：[Apple 关于相对安全区放置内容的说明](https://developer.apple.com/documentation/uikit/positioning-content-relative-to-the-safe-area)、[Unity 关于归一化视口投影的说明](https://docs.unity.com/en-us/engine/6000.7/script-reference/unityengine/camera/worldtoviewportpoint)。
