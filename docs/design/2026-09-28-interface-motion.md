# v0.7.2：界面与 3D 构图的连续过渡

## 根因与约束

动作镜头已经有弹簧，但原生编辑弹窗会在布局回调中直接写 Camera.rect，立刻改变像素区域及投影比例。镜头位置的平滑无法弥补投影瞬变。原生遮罩使用 draw 重绘及 isHidden 切换，同样不会自动跟随 UIKit 动画。另一个独立问题是 sceneDidBecomeActive 调用完整 reveal 流程，以 immediate=true 覆盖镜头和未保存预览。

产品约束：模型和房间始终铺满画面；聊天、键盘与面板在上层；编辑面板需要可见的角色预览。模型比例及用户的取景偏好不被面板布局永久修改。

## 决策

1. Unity 相机始终使用全屏 rect、原 FOV。原生发来的区域改为“构图目标区”，不再是渲染裁切区。对八个包围盒角点求解偏心透视约束，得到最终焦点和距离，再交给保留速度的解析弹簧。算法包含深度，支持横屏和窄预览区；每帧求解不创建数组。
2. 界面让位／恢复 response=0.76 秒，沿用阻尼0.80的轻微弹性；大范围近景／全身切换同样使用这一时序。response 是固有周期，不是完成时长。手势和小幅参数仍使用原有较快响应。
3. 编辑面板开始展示时就提交目标；真正布局到达后可继续修正目标。展开到大面板时保留上次有效预览区，避免“空间不够就突然放回全屏”。下拉收起提前启动恢复，交互取消时重新趋近预览位置。
4. 将即时绘制遮罩改为两层 CAGradientLayer，渐变位置、尺寸和颜色从 presentation layer 的当前显示值过渡，支持中途打断；聊天层用 alpha 淡入淡出并单独控制点击及辅助功能。键盘采用系统 duration/curve，布局按真实键盘位置判断，避免焦点刚改变时先跳一次。
5. 前台恢复只恢复已有窗口与引擎，不重选模型、不重新应用持久配置、不强制 Snap。只有新打开角色时在加载遮盖下初始化镜头。首页、加载和角色页交接采用淡入淡出；聊天提示、快捷话题、空间工具和外观页签使用局部动画，不对逐字回复反复启动整页动画。
6. 原生编辑器明确禁用聊天输入焦点，完成关闭后恢复可编辑状态。只将 SwiftUI FocusState 设为 false 不足以阻止 UIKit 在弹窗关闭后恢复旧 responder，第一轮录像据此补充了输入禁用和关闭完成时的同步。

## 验证与范围

Unity 导出前新增108组构图数学检查（4种宽高比×3种尺度×3种角度×3种区域），约束每个角点都在预览范围内，改目标不瞬移，最终收稳。保留动作曲线30／60／120Hz验证。

新增 InterfaceMotionTests 覆盖键盘→面板、全身预览、后台恢复未保存草稿、恢复推荐／取消、外观页签、下拉关闭、展开大面板、音乐和空间弹窗；iPad另外覆盖横屏键盘及面板恢复。显式 QA 参数开启有限的真实镜头采样，正式启动没有逐帧桥接及文件写入。verify_interface_motion.py 检查渲染区域和FOV始终一致、无额外Snap、有限速度、确实经历动画；截图、录像用于检查渐变及原生边界。数值检查不代替真机帧率验收。

采用项目现有官方 [Unity CLI skill](../../.agents/skills/unity-cli/SKILL.md)，继续驱动同一个 Editor，无新增动画依赖。接口依据：[Apple 键盘动画曲线](https://developer.apple.com/documentation/uikit/uiresponder/keyboardanimationcurveuserinfokey)、[Unity 相机 FOV](https://docs.unity.com/en-us/engine/6000.3/script-reference/unityengine/camera/fieldofview)。

具体通过项目及证据见 [验收记录](../verification/interface-motion/README.md)。
