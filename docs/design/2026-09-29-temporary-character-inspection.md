# 长按角色临时转动（0.40 历史方案）

> 0.41 已在此基础上增加 ±20° 上下倾转、斜向组合、原生轻震和双轴方向图标，导出能力升为 inspectionGestureRevision 2。当前行为与验证见[长按反馈与双轴倾转](../verification/inspection-feedback/README.md)。以下保留 0.40 当时的设计与故障处理，不能据此关闭新版俯仰操作。

用户允许在固定的作者构图上增加临时观察操作：按住模型一秒，再左右拖动；松手恢复。它是应用的观看交互，不是新增角色动作。因此琪宝、豆日向仍保留原作姿态与呼吸，不恢复之前已撤回的摇头、自动跟随、程序点头或微风。

## 手势与边界

- iPhone 真机与模拟器共用 `CharacterTouchSurface`：UIKit 的 `UILongPressGestureRecognizer.minimumPressDuration = 1`，单指，识别前移动容差 12 pt。短触仍走现有头部命中路径，普通拖动与双指缩放保持锁定。
- 长按只能从覆盖层实际收到的空白舞台触点发起。聊天、输入框、顶栏、底栏和弹窗各自处理触摸，不把其操作转发到角色。
- UIKit 长按成功仍不等于点中角色。Unity 对活动角色当前可见的 Mesh/SkinnedMesh 做射线三角形命中；背景和隐藏配件不会启动旋转。蒙皮快照只在长按开始时生成一次，不在拖动每帧烘焙。
- 角色绕世界竖直轴旋转，偏移限制为 **-180° 至 +180°**，覆盖完整 360° 观察范围。目标由本次按住起点的横向总位移计算，重复位移不会累加成多圈。没有俯仰、移动或缩放操作。
- 松手、取消触摸、打开资料页或离开会话均结束本次旋转。平滑阻尼回到零；切换角色和暂停时恢复原始根变换，避免暂时朝向保留到下一次进入。

## 保持原作和固定镜头

`CharacterInspectionRotation` 只叠加角色根节点的旋转。每帧先撤回上一帧的临时旋转，再在作者动画更新之后叠加本帧偏移。它不写骨骼、角色位置、比例、镜头位置、视角或持久化的取景设置。回正恢复的是作者当帧的根旋转，而非假定模型原点永远为 identity。

取景仍是会话近景，旋转时不会自动变为全身，也不会为了背面或展开的头发改变距离。原模型物理适配可自然响应整体转动，但没有添加新动画。

## 桥接与旧导出保护

复用 `nativeGesture` 命令，新增 `action: "inspect"`。`began` 带归一化触点；`changed` 的 `deltaX` 是相对本次开始点的总横向位移；`ended` / `cancelled` 结束观察。原有 `tap` / `pan` / `pinch` 语义不变，故保留 `nativeGestureRevision: 2`。

新能力单独声明 `inspectionGestureRevision: 1`，同时存在于 Unity 事件与 `BuildIos` 生成的 `modelspace-export.json`。`check_export_content.py` 在两平台构建前要求这个标记。仅检查角色目录 hash 或桥接 ABI 无法发现旧 Unity 静默忽略 `inspect`，所以不得通过手改 stamp 跳过重新导出。

诊断状态包含活动状态、当前/目标 yaw、峰值、结束时 yaw、成功/拒绝/回正次数。生产仅发送开始、结束和回正事件，不产生逐帧桥接流量。

## 验证入口

- `CharacterInspectionReview.Run`：实际模型三角命中与背景拒绝、正负 180° 夹紧、总位移不累积、非有限值拒绝、30/60/120 Hz 时间步下平滑回正、取消恢复、作者骨骼/位置/比例与镜头保持不变。
- `CharacterInspectionReview.ReviewAndExportSimulator`：先验证，再运行以上审查，最后导出模拟器。当前审查结果为 [runtime-review.json](../verification/hold-rotation/runtime-review.json)，5495 个断言通过；时间步覆盖不等于真机帧率承诺。
- `HoldRotationTests/testHoldRotatesOnlyTheCharacterAndReleaseRestoresAllThreeRigs()`：真实 UIKit 按住和拖动，覆盖初音、琪宝、豆日向的双向旋转、松手回正、短按拖动锁定、背景拒绝、固定相机与原作角色不新增摇头。
- 旧角色短触回归继续使用 `AuthoredCharacterTests/testHeadReactsButDragAndPinchCannotChangeTheAuthoredCamera()`；历史 `DirectGestureTests` 描述已经移除的精细取景开关，不作为当前产品入口验收。

模拟器和真机安装、实际 UI 测试通过情况以本轮最终验收记录为准，不把 Editor 审查当作设备输入验证。

## 首轮 UI 回归发现的问题

首次真触摸回归在等待“已回正”时超时。`ViewerCoordinator` 的运行状态事件白名单遗漏了新增的四个 `inspection*` 事件，因此辅助功能探针一直保留按住前的快照。没有据此放宽旋转或回正断言。

模拟器系统日志确认引擎已收到长按并正确完成：从 0° 转到 -161.638°，松手约 1.87 秒后回到精确 0°，`inspectionReturnCount` 变为 1；[原始事件摘录](../verification/hold-rotation/first-ui-run-engine-events.json)保留实际时间和数值。修复是将开始、结束、回正和拒绝事件接入原有状态更新路径，并让 UI 测试超时时附带截图与当前状态 JSON。后续必须重跑真实触摸测试，不能用这段日志代替全角色验收。

修复后的第二轮真实 UI 测试已通过（93.066 秒）：初音、琪宝和豆日向分别完成向左/向右按住拖动并回正，短拖动不旋转，空白区域拒绝，原作角色未新增头摇。结果在 `.local/checks/Hold-Rotation-v040-Phone-2.xcresult`，日志在 `.local/logs/Hold-Rotation-v040-Phone-2.log`。六组回正截图均带相应运行状态 JSON 附件。原有角色短触回归也在本轮首轮套件中通过。
