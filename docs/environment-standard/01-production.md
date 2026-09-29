# 标准 3D 场景制作规范 · XEP 1.0

## 可直接交给其他 AI 的任务

你是“小伴”3D AI 陪伴 App 的独立环境制作方。制作一个适合与成年角色近距离聊天的精致室内或室外空间，交付完整 XEP 1.0 包。先读本文、随附 JSON Schema 和清风小院真实 GLB 样例。模型角色由应用提供，**不要把人物烘焙在环境里**，不要修改 Swift/C# 代码来迁就场景。

交付目录：

```text
my-environment/
  environment.json
  environment.glb
  LICENSE.txt
  README.md
  evidence/             # 预览、材质/光影/取景极值与预算证据
```

必须完成：清晰完整的几何、PBR 材质与内嵌贴图、接收阴影的地面、足够的角色活动区、可定制绑定、明确来源许可。提供可编辑 Blender 等母版作为配套交付。场景应精致但节制，不要用大量透明叶片、实时灯或几何堆积冒充品质。没有引擎或真机时，明确列出未验证项，不声称稳定 120 FPS 或完全无穿插。

## 资源与坐标

- GLB 2.0 自包含二进制；图片与 buffer 内嵌，不得含网络或外部 URI。当前为静态场景，不接受骨架、动画、morph 或可执行脚本。资源仅接受 GLB、PNG/JPG/JPEG/WebP、TXT/Markdown/JSON/CSV；Unity meta/prefab/asset 等引擎文件不得装入源包。
- GLB 使用标准 glTF 坐标，交给 glTFast 转为 Unity。最终运行时 Y 向上，角色脚底位于 `(0,0,0)`，应用一般从 Z 正侧看向中心；后景应位于 Z 负侧。实际导入可能改变路径与朝向，最终以绑定检查与渲染图为准，可通过 `source.yaw` 校正。
- 以米制作，`source.scale` 为单位转换。`stage.referenceHeight` 为该空间设计的角色身高，推荐 1.7 m。运行时等比匹配不同角色，不改变角色镜头取景。
- 原点周围 `stage.clearRadius` 至少 1.2 m，建议 1.4–1.6 m，地面以上到 2.4 m 保持通畅。座椅、树木、栏杆、台阶等放在活动区外。此检查是包围盒保守检查，不等价于任意动作自动无碰撞。
- 地面表面接近 Y=0，且至少覆盖净空区。建议地面独立于装饰组；关闭装饰绝不能让角色悬空。双脚阴影必须落在实体地面上。
- 取景包含对话近景、全身、动作退后、左右偏移、面板打开以及 iPad 横屏，不能只制作单一固定视角可看的背景板。
- 当前预算：250k mesh POSITION 顶点、48 个 primitive、256 个 Renderer、512 个节点，单文件不超过 128 MiB，总资源 256 MiB。预算只是上限，不是性能保证；建议远低于上限，控制 draw call、过绘和纹理内存。
- 常用 PBR 基础色、法线、粗糙度、金属度、遮蔽。基础色不是写死在灯光里的颜色；环境不能自带运行脚本或替换 App Shader。灯光与相机由应用管理，GLB 内的灯和相机会被移除。

## 清单字段

机器规范在 `environment-sdk/schemas/environment.schema.json`。

| 字段 | 语义 |
|---|---|
| schemaVersion | 当前结构主版本 1 |
| id / packageId / packageVersion | 稳定用户存档 ID / 制作方身份 / 三段内容版本 |
| display | 常用中文名、描述、indoor/outdoor 分类、顺序、唯一缩略图资源名 |
| compatibility | API 主版本、最低次版本、必需及可选能力 |
| source | 外部包只接受 kind=glb；模型路径、scale 和 yaw |
| stage | 参考身高和角色净空半径 |
| lighting | 天空背景、环境光、主光/补光颜色与主光/补光/轮廓光基准强度 |
| palettes | 1–5 组带稳定 ID 的配色，每组 surface 与 accent 颜色 |
| bindings | surface/accent/decor 各自绑定到哪些节点路径 |
| license / files | 授权、资源大小及 SHA-256 |
| extensions | 后续命名空间扩展，不能重新解释已有字段 |

绑定路径相对于 GLB 实例的根，不包含应用创建的 `Environment_<id>/Geometry` 包装节点。surface/accent 对绑定节点下所有 Renderer 的全部基础色材质槽作用，适合纯色墙面、地面或装饰；有写实贴图的材质会乘以基础色，不能把整个精细贴图场景随意归入同一颜色组。两个颜色组不能控制同一 Renderer。

`decor` 指定可隐藏的完整装饰层次，不允许包含地面。暂不支持单件家具位置/缩放、不同材质槽分别配色、材质替换或自动家具摆放。需要这些能力时提交新能力提案，不私自扩展现有绑定字段。

配色 ID 用于存档，发布后不能删除或复用为不同含义；新增可选配色可以升级。除配色，App 统一提供装饰开关、场景方向 ±25°、主光左右 ±90°、高度 20–75°、亮度 0.6–1.5 倍、阴影强度 0.15–1。角度与灯光均平滑响应。

## 交付命令与验收

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r character-sdk/requirements.txt
.venv/bin/python environment-sdk/tools/environment_tool.py seal my-environment
.venv/bin/python environment-sdk/tools/environment_tool.py validate my-environment
.venv/bin/python environment-sdk/tools/environment_tool.py pack my-environment my-environment-1.0.0.xep
```

`.xep` 为根目录含 environment.json 的受限 ZIP。无需安装 Unity 也能预检；应用团队使用 `scripts/import_environment.py` 做 Unity GLB 导入、绑定、净空和渲染检查。发布前验收全部角色、全部动作、室内/室外光源、各参数极值、横竖屏及温升后的帧率。

交付：`.xep`、可编辑母版、许可与来源、静态预检输出、实际渲染预览、预算、已验证/未验证清单。示例清风小院是最小接入样例，其简单几何不是精致美术质量目标。

## 星夜内置空间的宿主增强层（2026-09-29）

内置空间现在提供固定帘顶的微风、根部约束的叶片摆动和海面纹理流动。该能力由受控的宿主组件 `EnvironmentAmbientMotion` 实现，不改变 XEP 1.0 对外部 GLB 的静态资源限制。外部包不能附带脚本、未知 Shader 或绕过预检的骨骼动画。旧包继续静态展示，后续可通过新的可选能力为声明式环境动态定义独立标准。

宿主增强的清单使用 `extensions.app.starry.presentation` 标识呈现版本；不得把这些信息解释为资源已经包含所有宿主生成的网格。原始清风小院 GLB 仍是接入示例，当前 App 在它的建筑之外生成精细装饰，并生成对应的 runtime 绑定。源包、许可和散列保留原样。

环境必须归属角色集合的 `environments` 允许列表，并提供角色自己的 `defaultEnvironment`。资源可以通过稳定 ID 在应用包内去重复用，但选择、配色、摆设和方向必须跟随角色独立存档。角色切换不得把上一角色的背景设置带给下一角色。

动态不改变角色相机或主光；停用背景和 App 暂停时不累计运动。新版内置空间限制 24 个局部动态节点，仍遵循 256 Renderer 的上限；帘布顶部固定，下摆约厘米级，植物角度约一度。详细实现、原始远景素材、验证入口及运行时诊断见 [精致动态空间设计](../design/2026-09-29-refined-environments.md)。

场景制作时，地面等需要平铺材质的网格必须提供有效纹理坐标；仅绑定贴图材质不能补救缺失UV。远景与真实地面的交界须在实际角色取景中检查，以几何、材质过渡和合理遮挡消除硬接缝，不能只依赖编辑器缩略图。远景保持宽高比，导入器不得隐式把非二次幂图像拉伸。
