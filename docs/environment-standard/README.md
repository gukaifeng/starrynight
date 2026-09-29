# 小伴场景平台 · XEP 1.0

2026-09-28，随 App 0.10.0 / build 19 交付。角色包 XCP 与场景包 XEP 分别制作、分别升级，再由应用组合显示。

- [场景制作规范及其他 AI 任务书](01-production.md)
- [架构、交互、存档与扩展](02-architecture.md)
- [制作 SDK 使用说明](../../environment-sdk/README.md)
- [完整场景制作 SDK](deliverables/Xiaoban-Environment-SDK-1.0.1.zip)
- [可导入的清风小院](deliverables/courtyard-1.0.1.xep)
- [验证记录](../verification/environment-platform/README.md)

当前用户可选晴日客厅、柔光影棚、静夜小屋、林间花园、海边露台，以及独立 GLB 示例清风小院。支持空间配色、装饰开关、环境方向、光源方位/高度/亮度和影子强度。保存以角色 ID + 场景 ID 区分；取消还原整个草稿，切换空间不丢旧布置。

当前为静态环境及受限参数定制，不是家具自由拖放编辑器；没有天气模拟、可行走开放世界、实时水体或手机内直接上传场景。源包导入后需要重新构建 App。

App 0.11.0 补丁：SDK 1.0.1 / 小院 1.0.1 延长地面以覆盖侧躺低机位，XEP 协议仍为 1.0；角色/姿势/场景保存键保持不变。补丁验证见[姿势版本记录](../verification/posture/README.md)。
