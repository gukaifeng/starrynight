# VRChat 原作表现验收 · StarryNight 0.39.0 / 59

本轮把琪宝、豆日向原资源内可独立迁移的表现接入 App。入口为：发现 → 角色 → 进入会话 → 左上角角色胶囊 → 角色表现。沿用同一弹窗内渐变子页，打开面板不修改镜头。

## 实际交付

| 表现类别 | 琪宝 | 豆日向 |
|---|---:|---:|
| 表情 | 42 | 25 |
| 姿态与动作 | 10 | 4 |
| 手势 | 8 | 8 |
| 耳朵 | 8 | 4 |
| 尾巴 | 7 | 4 |
| 穿搭与配件 | 7 | 3 |
| 合计 | **82** | **48** |

130 项是可选表现，包含静态预设、循环/一次性动作和开关，不能称为 130 个连续身体动作。两个角色包升级至 1.1.0；可选能力为 `core.performance@1`，旧角色不需要补这项数据。角色默认配件、非零形变、动态曲线、原作入睡接循环均保留。跨分组可叠加，同组预设互斥，恢复默认按该角色执行，切换角色清除旧选择；同一个首页会话切换底部菜单时保留选择。

## 分层验证

- 来源：163 个原始 `.anim` 全部进入审计，包含菜单、控制器状态和外部引用；[源能力清单](source-capabilities.md) / [完整 JSON](source-capabilities.json)。
- 数据：全部 12 角色包校验通过；12 个独立集合、24 首独立乐曲的绑定/哈希检查通过。SDK 新增 10 个拒收回归，全套 44 项通过；两新包也通过更严格的最终校验。
- Unity：`BuildIos.Setup`、`BuildIos.Validate` 及 Simulator 导出通过。130 项的选中、开关、复位、动态曲线、骨骼采样和角色隔离由 [runtime-review.json](../vrchat-performances/runtime-review-v0.39.0.json) 记录（13,744 个断言）。
- 画面：生成 19 张实际求值截图，覆盖笑脸、动态脸部、坐/蹲/趴/睡、手势、耳尾与配件。见 [渲染清单](render/review.json)。这些是固定全身审查镜头，不能当成 App 会话镜头截图；运行中的头发物理另由模拟器观察。
- 原生与模拟器：最终结果见 [app-review.json](app-review.json)。失败轮次保留，最终通过的方法独立列出，不将整轮失败改记为成功。
- 图形兼容：重新导出/编译后普通启动确认 HDR + FXAA 已生效，原有三类 RenderPass 采样数错误均为 0；[能力与日志摘要](graphics-review.json) / [普通启动截图](simulator-graphics-final/normal-launch.png)。本机模拟器不等同真机画质/性能验收。
- 手机：本轮 CoreDevice 查询显示设备断开，继续使用 iPhone 17 / iOS 26.4 模拟器；没有把旧手机安装包当成本版已安装。iPad 和真机持续帧率未测试。

## 关键问题和修复

1. **Humanoid 与 glTF 坐标**：在隔离工程用原 FBX 的有效 Avatar 采样，并按实际 glTFast 的 X 镜像和父级基准变换烘焙；不能直接把 muscle 值当成本项目骨骼旋转。
2. **完整时间语义**：原 `.anim` 的 0 秒姿态转为常值 hold；动态 morph 保留 Unity 曲线 60 Hz 采样。呼吸只导出变化轨道，作为 additive 动作，防止整身偏移。源单个 eye_down 超范围权重按标准 0–1 限制并留证。
3. **旧包兼容**：Unity JsonUtility 会为缺失的可选字段生成空对象，故按非空 options 判定能力；不能只判断 `performance != null`。未激活的角色根节点仍需要有效 bounds，只有角色内部隐藏节点/Renderer 才排除。
4. **截图误判**：同一 Editor 帧连续 `Camera.Render` 命中旧蒙皮缓存，曾得到“表情不变/坐姿直腿”的假象。独立 [Visual Probe](visual-probe/report.json) 证实真实 CPU 网格已变化；审查截图改用临时 BakeMesh 的真实当前姿态，渲染后立即恢复和销毁，不修改产品动画。坐姿原始曲线证据见 [专项审计](sitting-source-review.md)。
5. **原生自动化**：移除根容器传播的 accessibilityIdentifier，保留真实返回/复位控件 ID。测试用固定选项 ID 等待选中回执；横向分类先完整滑入可见区域再做点击检查，保留原断言。
6. **集合版本**：模型包升级 1.1.0 后同步集合的 modelPackageVersion；converter 会更新引用并保留已有专属声音/音乐，防止宿主与引擎目录不一致。
7. **模拟器 HDR/MSAA**：普通启动发现 Metal 模拟器实际 HDR 附件为 1 sample，但公共能力查询返回 4，首版仅查能力未解决。最终针对已识别的 iOS Simulator GPU 使用单采样 HDR + FXAA，启动时克隆运行时管线并同步 camera/global AA；真机保持能力协商，不改原 4× HDR 作者资产。没有关闭报错日志。功能测试通过和图形日志通过分别记录，早期截图保留在 simulator / simulator-graphics-attempt-1，最终图形截图见 simulator-graphics-final。

## 未迁移边界

- 原 Motion 菜单的 Wave / Clap / Point / Cheer / Dance / Backflip / SadKick / Die 是外部 VRChat SDK 引用，源包不包含这些作者身体片段；本版没有把它们算作已导入。
- 原 SDK 网络参数同步、Contacts、tracking/pose space、完整 PhysBones 不在 App 直接执行。原作可见数据由本地能力适配，SDK 状态机不等于随包运行。
- 豆日向 SunVisor/NameTag 等独立 Prefab、FishToy 等额外资源未作为主 FBX 的可用选项；基础上装和短裤脱除未开放。
- 坐姿保留真实静态屈髋/腿部姿势，尚无椅子锚点、座位定位或完整落座交互。坐、趴、躺等姿态可能离开固定会话近景；没有为展示它们而偷偷改变会话相机。不能把原作姿态叠加等同通用防穿模或家具自动适配。
- 60 Hz 是离线采样频率，运行时可插值，并不证明手机稳定 60/120 FPS。材质和次级动态沿用上一版的适配边界。模型原有授权范围不变。

## 可复用交付

- [实现设计](../../design/2026-09-29-vrchat-performances.md)
- [表现制作标准](../../character-standard/06-performance-standard.md)
- [VRChat 导入 skill](../../../.agents/skills/vrchat-character-import/SKILL.md)
- [完整 StarryNight Character SDK 1.1](../../character-standard/deliverables/StarryNight-Character-SDK-1.1.zip)

本轮没有将两套受限来源角色资源放进通用 SDK 压缩包。
