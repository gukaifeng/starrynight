# 模型操控锁与自适应弹窗背景 · 小伴 0.13.1 / build 24

## 使用方式

角色页顶部、返回按钮右侧新增小锁头，与相邻顶部按钮使用相同的半透明白底、深绿图标，保留 44pt 触摸宽度。进入角色页默认锁定，点击解锁，再点重新锁定。锁住时拖动、旋转、双指缩放不改变取景；轻触头部仍触发角色互动。精细「取景」面板始终可用，关闭面板不会改变之前选择的锁状态。重启后默认重新锁定，已保存的角色大小和角度仍保留。

覆盖屏幕的大窗口使用完全不透明的暖白底；半屏取景、外观预览和横屏侧栏保留原有渐变半透明。根据窗口实际尺寸计算，不把 iPad 的局部窗口当成全屏；拖动展开与旋转时平滑调整背景。左上返回、窗外关闭、弹簧位移与模型构图缓动继续使用现有实现。

## 实现与兼容

- 原生统一发送两项输入状态：所有直接触摸是否可用，以及直接取景手势是否解锁。面板打开暂停输入，退出恢复原状态；背景恢复和角色切换不会通过单一 true 回调意外解锁。
- Unity 独立拦截旋转/缩放，保持头部点击命中检测。锁定下单指移动仍取消点击候选，多指触摸抬起后不会变成头部点击；切换锁状态会清除在途输入，已经达到的有效取景先正常提交。精细面板与动作触发不受直接取景锁影响。
- `configureGestures.payload.framingGesturesEnabled` 为可选增量字段；老宿主缺省字段保持旧行为，新宿主总是显式发送，新的运行时初始值为 false。实际状态随事件回传，测试读取 Unity 事件，不能仅凭图标判断。用户资料格式和角色包标准不变。
- UIKit 呈现层在 SwiftUI 渐变下方统一添加实体底色。可见宽度达到安全区域的 65% 后，高度占比 72%～90% 使用 smoothstep 过渡，到 90% 完全不透明；窄侧栏保留预览。展开拖动连续更新，旋转/程序布局切换使用 0.35 秒动画，降低动态效果时 0.15 秒。降低透明度时始终实底。
- 沿用 frontend-design 的现有视觉体系和项目 Unity CLI 技能，通过已打开的 Editor 导出双平台，没有新增 UI 库或图片依赖。

## 验证记录

- iPhone 17：手势专项最终通过 66.929 秒，涵盖默认锁、锁内拖动/缩放不生效、锁内头部互动、解锁后边界/反向响应、精细编辑、重锁、重启默认状态和聊天滚动。原始结果 `.local/checks/ModelLock-Phone-Gestures-Final.xcresult`。
- iPhone 弹窗专项通过 28.661 秒：半屏透明、拉满实底、大窗口实底、旋转后透明侧栏、返回和窗外退出保留锁状态。原始结果 `.local/checks/ModelLock-Phone.xcresult` 的 `PanelSurfaceTests/testAdaptiveSurfacesAndLockAcrossPanels`。该结果包另一个旧用例失败，因此不将整个包标为通过。
- 首轮旧手势测试在窗外操作已经关闭面板后，再查找返回按钮失败。按现有关闭契约改为断言窗口退出且 Unity 旋转计数不增加，最终手势用例通过。未通过取消窗外关闭来迁就测试。
- 646 条几何断言通过，覆盖手机、iPad、窄窗/半窗/宽窗、键盘、聊天高度、半屏/展开及透明度单调连续性。原始脚本 `.local/checks/model-lock-layout.swift`。
- iPad Pro 11-inch (M4)：手势 76.361 秒 / 弹窗 32.763 秒，两个用例均通过，包含横屏操控、局部预览、展开实底、旋转为侧栏。原始结果 `.local/checks/ModelLock-iPad.xcresult`。
- simulator/device 最新 Unity 导出均通过角色和场景完整性检查；关键截图已实际查看。详见 [结构化结果](results.json)。

## 真机更新

Release 编译、深度严格验签、无线安装与启动均成功。设备 App 列表独立回读为小伴 **0.13.1 / build 24**。保留现有 App 数据，未使用测试启动参数；workspace 留在 device。详见 [安装记录](device-installation.json)。

## 截图

- [默认锁定，头部互动仍可用](phone-00-default-locked-head-interaction.png)
- [半屏取景保留模型](phone-01-translucent-framing.png)
- [取景展开后不透明](phone-02-expanded-opaque-framing.png)
- [大窗口完全不透明](phone-03-tools-adaptive-surface.png)
- [横屏侧栏保留半透明](phone-05-landscape-translucent-sidebar.png)
- [iPad 大面板展开后实底](ipad-04-ipad-expanded-opaque.png)
- [iPad 横屏模型与半透明侧栏](ipad-05-landscape-translucent-sidebar.png)

本轮不作为新增真机持续帧率或整个产品的全量回归结论。
