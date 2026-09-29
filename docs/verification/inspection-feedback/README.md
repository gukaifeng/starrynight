# 长按旋转反馈与双轴倾转 · 0.41.0 / 62

## 本版交互

- 按住角色 1 秒，Unity 对当前可见模型网格确认命中后，原生侧才触发一次轻震并淡入方向图标。背景、短拖、已松手后到达的旧回执不触发反馈。
- 左右旋转范围 ±180°；上下倾转范围 ±20°；斜向同时改变两轴。输入是本次手势的绝对位移，不累计圈数。上下轴按屏幕水平轴计算，转到背面后也不会反转拖动逻辑。
- 松手、取消、切页、弹窗、后台和换角色均有清理路径。模型双轴平滑回正；相机、原位置、尺度、作者骨骼和保存偏好不变。
- 方向图标使用 44pt 月白双轴轨迹、四向小箭头与两颗缓慢移动的微光，无底框和文字，位于安全区下方右侧。它不参与布局、不拦截触摸，只有长按生效时显示；结束移除循环动画。开启减少动态效果时保持静态图形。
- 两个 VRChat 角色继续只保留原作骨骼表现，本版没有重新加程序摇头、待机或目光。

## 实现与依据

使用 Apple 原生 [UIImpactFeedbackGenerator](https://developer.apple.com/documentation/uikit/uiimpactfeedbackgenerator) 的 light impact，强度 0.70；触摸开始只调用 [prepare()](https://developer.apple.com/documentation/uikit/uifeedbackgenerator/prepare())，直到 Unity 确认真正进入旋转才调用 impact。一次手势不因每帧变化或归零而重复震动。真实硬件是否输出震动由设备与系统触觉设置决定，模拟器没有实体马达。

方向图标为仓库原生 CAShapeLayer 矢量，不引入图片或第三方动画库。通过 [isReduceMotionEnabled](https://developer.apple.com/documentation/uikit/uiaccessibility/isreducemotionenabled) 关闭轨迹运动；原 UI 与作者资产保持独立。

Unity 导出与宿主构建检查要求 `inspectionGestureRevision >= 2`，继续兼容旧 `nativeGestureRevision=2`；新 `deltaY` 与 pitch 状态均为 JSON 附加字段。缺少上下旋转能力的旧 Unity 导出会在构建前被拒绝，避免原生手势被静默忽略。

## 验证

**已完成，最终 0.41.0 / 62 无线安装到 iPhone 17 并成功启动，手机端读回版本一致。** 最后的原生转场状态修正已包含在安装包内，未卸载主 App 或清空聊天数据。[设备回执摘要](device-installation.json)包含签名、安装、启动与构建日志来源。

- [Unity 审查](runtime-review.json)：30548 个断言通过，包含三个实际模型、八个方向、30/60/120Hz 时间步、双轴边界、异常输入、安全复位和骨骼/镜头保持。时间步覆盖不是设备 FPS 测量；上一版 hold-rotation 证据没有覆盖。
- **真实 UIKit 触控回归通过，134.667 秒**：初音、琪宝、豆日向各执行向右、向左、向上和右下斜向四种操作，共12组截图与运行数据；每次仅一次触觉调用与图标显示，松手两轴均回0、图标关闭。短拖和背景不触发反馈，原作角色没有新增摇头。结果见[完整 UI 记录](app-review.json)。
- 原有短按头部和固定镜头回归通过，38.423 秒。最终普通启动已退出测试参数，检查的 Metal RenderPass/NextSubPass/EndRenderPass、NullReferenceException、ArgumentException 均0，[画面](simulator/normal-launch.png)留存。
- 图标实际出现的[第1帧](simulator/active-rotation-1.png)与[第2帧](simulator/active-rotation-2.png)来自第二轮真实XCTest录屏的23秒、24秒，不是设计稿或伪造激活。图标位置、线条和微光变化已人工查看；该轮前8次操作通过后，后续一次识别超时另行记录，不能把录屏当成完整回归通过。

未做 iPad 测试；模拟器验证的是触觉API调用次数和生命周期，不表示代理实际感受了实体马达或测量了触觉强度。

## 错误与处理

首轮执行显示期待旧版本号1，尽管当前源码与已构建二进制包含新版断言。调查没有发现错误源路径；具体缓存层未能确定。仅卸载专用 QA Runner 并以新测试方法名重装隔离复验，未清主 App 数据。

第二轮8次完整手势通过后，豆日向一次长按未发出新inspection事件；该轮桌面/AX操作普遍明显变慢，不能单凭同时出现的高CPU把原因归于图标动画。检查发现回首页的getState早于转场结束，会采到暂时禁用的原生输入层。现将新进入及返回的采样都放在恢复交互之后，测试等待CharacterTouchSurface确实接管输入。自动化按压延至1.5秒，为1秒识别计时器留调度余量，产品识别阈值不变；角度、命中、反馈次数和回正断言没有放宽。第三轮12组全部通过，前两轮失败事实保留在app-review中。

本机完整结果：`.local/checks/Inspection-Feedback-v041-Phone-{1,2,3}.xcresult`；最终设备回执 `.local/checks/device-{install,launch,app}-v041-final.json`。
