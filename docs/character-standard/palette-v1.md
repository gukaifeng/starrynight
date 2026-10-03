# Character Palette v1：开发者颜色定制

## 边界与目标

这是开发构建的材质实验能力，入口为角色会话的浮动开发者图标 → 定制颜色。每个角色的开发者页均有入口；未载入的角色先进入会话，再读取实时组件。正式分发项目使用 `generate_host.py --distribution`，不会包含此页面。

颜色偏好按本机账号与角色保存，不改写原始 VRChat 文件、转换贴图、角色设定、封面、头像或 OSS 发布包。本期不向服务器同步颜色试验数据。关闭面板保留试验颜色，恢复默认撤销对应组件或整个角色的覆盖。

覆盖范围是 `GetComponentsInChildren<Renderer>(true)` 中的每个材质槽，包括隐藏衣服、配件、原作特效网格；枚举其 shader 的**全部 Color 属性**，不使用只列头发、皮肤和衣服的固定白名单。同一材质引用出现在不同网格/槽中，仍可独立调整。当前 16 个角色都用已适配的 lilToon 材质。

**共享贴图图集的限制：**若皮肤、嘴、眼睛等被作者画在同一个网格材质的同一贴图中，整个色系会一起变化。原作的独立颜色通道可以单独调节；没有独立通道或遮罩的像素区域不能凭空拆成解剖部位。本版本没有 UV 涂抹或自动分割。通道是否出现可见变化也取决于原作是否启用了对应的发光、MatCap、第二层阴影等效果。

## 色系与精度

每个材质槽都有整体、暗部、亮部三个调色层，另可选任意原作颜色通道。每层包含：

| 字段 | 范围 | 含义 |
| --- | --- | --- |
| `hue` | -180…180 度 | 相对色相偏移；按钮步进 0.1 度 |
| `saturation` | 0…2 | 原作鲜度的倍数；按钮步进 0.01 |
| `exposure` | -2…2 EV | 亮度乘 `2^EV`；按钮步进 0.01 EV |
| `tint` | 0…1 | 为低饱和度/白灰区域加入颜色；按钮步进 0.01 |

中性值为 `(0,1,0,0)`。原作贴图、法线、透明度、阴影几何、轮廓、裁剪、渲染顺序和各层开关不变；调色保留其空间纹理关系。整体/暗部/亮部在 lilToon 完成光照后、输出前做柔和亮度分区的相对 HSV/曝光调整，并保留 HDR；不是宣称物理材质的测量级校色。原作通道保留原 alpha。

## 运行时协议

桥接信封沿用 `schemaVersion:1`、`presentationId` 与 `modelId`，新增以下命令，兼容已有角色包：

- `getPalette`：读取当前角色组件目录；事件 `palette`，`palette.revision:1`。
- `setPalette`：`payload.palette={component,channel,tone}`；`channel` 是 `$main/$shadow/$highlight` 或目录给出的原作 Color 属性名。
- `resetPalette`：省略 component/空串恢复全部，给出 component 仅恢复一个槽；用户预览复位柔和过渡，账号/角色重新载入时 `immediate:true` 立即建立正确基线。
- `paletteApplied`：轻量回执，仅报告版本、角色与 `editedSlots`，不反复传输完整目录。

组件 ID 是相对角色根节点的名称/同级序号路径、Renderer 序号与材质槽索引。后续导入保持网格层级顺序，可延续已保存颜色；升级包删除/重命名的旧 ID 或通道在本机重放前跳过，不把失效偏好变成全局加载错误。新增通道自动出现在目录。

运行时验证当前角色，拒绝不存在的组件/通道及 NaN/Infinity，限制范围。App 50ms 合并滑条事件，shader 参数以约 100ms 的指数响应平滑追随；离开页面刷新最后一笔，包括中性值。目录只在明确调色请求时生成；没有颜色覆盖的普通启动不会额外创建材质实例或载入调色库。

## 材质与动画兼容

`scripts/prepare_palette_shaders.py` 从已固定版本的 lilToon 2.3.4 生成宿主拥有的 shader 副本，改名至 `StarryNight/Palette/`，替换副本内部 UsePass/Fallback 引用；保留原光照/混合/透明/轮廓等实现。在官方输出扩展点及 FakeShadow/Universal2D 对应输出处接入宿主 HLSL。副本含上游许可证，位于忽略目录；不修改依赖包或用户源资源。

`CharacterPaletteBuilder` 只在资源库引用当前使用的 shader 家族与可读材质名，**不引用角色材质或贴图**，不会因此把下载角色的美术资产偷偷打进 App。导出脚本先准备 shader 副本；新恢复工作区需要先按现有流程恢复 lilToon 依赖。

`CharacterPaletteRuntime` 在用户编辑时按槽复制材质，保留 renderQueue 与 keywords；原材质保持不变。原作动画换材质时，采用新材质继续调色，恢复以最新作者材质为准。每槽 MaterialPropertyBlock 合并原有值，恢复只处理自己的颜色属性，不清空其他组件的发光、淡入或参数属性。原作新写入的颜色作为新基线，避免对上一次调色结果反复染色。

此组件由宿主动态加入，不要求改 prefab。因此 Fiona、Mizuki、Ramune 的现有 OSS release 4 能继续使用，不需要本期重发下载包。实际下载验证与数值审核分别记录在验证文档，不能用 Editor 数值通过代替真机帧率。

## 维护与撤销

实现集中于 `CharacterPaletteRuntime/PaletteShaderLibrary`、`CharacterPaletteBuilder/Review/VisualReview`、宿主 `CharacterPalette.hlsl`、生成脚本、原生 `CharacterPalettePanel` 及少量桥接入口。恢复默认无需改包或重导入。撤销整个实验时移除这些入口/桥接分支、生成步骤与忽略的调色 shader/资源库；现有模型、原作表现、OSS 包与服务端均不依赖该实验。`StarryNight.developerPalette.v1.<account>.<role>` 是唯一新本机偏好命名空间。
