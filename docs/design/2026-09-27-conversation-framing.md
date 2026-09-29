# v0.4 对话取景

## 产品规则

角色是聊天伙伴。取消角色上的拖拽旋转、捏合缩放、滚轮和任意俯仰；触碰头部仍可摇头，拖动与多指手势不会误触。聊天与独立互动舞台使用同一套规则。

顶部「取景」打开实时预览面板：
- 对话近景（默认）：以上半身与面部为中心，下半身允许自然出画。
- 全身互动：保留完整角色与地面空间。
- 大小 90%–110%，左右朝向各 20°；固定柔和俯角，无任意平移。
- 自动居中于原生 UI 分配的角色区域，避开标题、聊天面板、键盘。键盘和屏幕变化只重算构图，不复位偏好。iPhone 和 iPad 竖屏采用上方角色、下方聊天；iPad 横屏左右并排，避免狭长角色窗导致近景过小。
- 设置按角色保存，点击「完成」提交；取消或下拉关闭回到打开面板前的设置。恢复推荐先预览，完成后保存。保存失败保持面板并提示，不假报成功。
- 大动作临时展示全身，结束后平滑回到已选取景；不改写用户设置。头部摇头保留近景。

## 实现决策

1. SwiftUI 取景面板，沿用栩屿暖白、玉青、圆角样式；不增加第三方组件。使用已有 frontend-design 与官方 Unity CLI skill；相机 API 依据 Unity 官方文档。
2. 宿主 CharacterFraming 和 Unity FramingMath 双端约束非法/越界值。资料中新增可选 framing 字段，缺失时采用推荐设置；兼容 v0.3 schemaVersion 1 的聊天、性格、记忆。
3. 镜头根据角色包围盒、当前景别、角度及实际 viewport 计算透视投影距离。导出时按 30 Hz 采样每个动作，保存独立的活动范围；运行时直接读取。实时过程仅做常量数量的向量计算，无每帧烘焙网格或跨桥消息。
4. 取景与动作、外观数据独立；Bridge 新增 configureFraming。Unity 导出标记 contentVersion 4 / framingProtocol 1，防止新宿主误接旧引擎。
5. 采用 Unity CLI 驱动 Editor 编译/导出，不手改场景 YAML。仅模拟器验证，不触碰真机。

## 验证

- 旧档读取、往返保存、两角色隔离、参数边界与非有限数处理。
- Unity 实际相机投影覆盖 iPhone/iPad 常见及键盘极端宽高比、大小与朝向极值。
- 真 Unity 模拟器 UI：预览/保存/取消/恢复、重启保持、拖拽和多指不改变相机、动作自动取景并恢复、头部点击、键盘与 iPad 横竖屏。
- 留存截图、真实引擎事件、XCTest 结果及未通过项。不能以本轮取景改动证明真机 60/120 FPS。

官方参考：[Camera.rect](https://docs.unity3d.com/6000.3/Documentation/ScriptReference/Camera-rect.html)、[Camera.WorldToViewportPoint](https://docs.unity3d.com/6000.3/Documentation/ScriptReference/Camera.WorldToViewportPoint.html)。
