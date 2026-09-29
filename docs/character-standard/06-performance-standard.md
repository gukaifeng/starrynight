# 原作表现标准：core.performance@1

`performance` 是角色包中的可选能力，供模型作者声明表情、姿态、手势、耳尾和穿搭配件。它与对话用 `actions` / `expressions` 并存；只交付数据，不携带源 SDK、控制器、脚本或 Shader。当前模式适合把原作可见选项接入 App，并不模拟完整 VRChat FX 状态机。

规范以 `character-sdk/schemas/character.schema.json` 和 `CharacterPerformanceContract.Validate()` 为准。本文件记录当前实现，不保证未来宿主对尚未声明的能力自动兼容。

## 能力和包结构

在 `compatibility.optional` 声明 `core.performance@1`，并提供 `performance.schemaVersion:1`。没有该字段的旧包照常使用原会话行为。新包升级 `packageVersion`，保持既有角色 ID、选项 ID 和安装标识稳定。

```json
{
  "performance": {
    "schemaVersion": 1,
    "defaults": [{"path":"armature/Item_Glasses","visible":false}],
    "groups": [{"id":"appearance","label":"穿搭配件","symbol":"sparkles"}],
    "options": [{
      "id":"outfit-glasses", "group":"appearance", "label":"眼镜",
      "kind":"toggle", "clip":"", "duration":0, "loop":false,
      "defaultOn":false, "bones":[], "morphs":[], "offMorphs":[],
      "morphTracks":[],
      "visibility":[{"path":"armature/Item_Glasses","visible":true}],
      "offVisibility":[{"path":"armature/Item_Glasses","visible":false}]
    }]
  }
}
```

示例路径必须替换为实际 GLB 导入后的节点路径；通过最终 `CharacterContract.Resolve` 和 mesh 形变名验证。源 FBX 路径不能未经映射直接发布。

## 分组、选项及单位

六个固定分组为 `expression`、`pose`、`hands`、`ears`、`tail`、`appearance`。未提供资源的分组不显示。每个选项稳定 ID 唯一；界面标签使用面向用户的名称，不直接展示技术骨骼名。

| 字段 | 当前语义 |
|---|---|
| `kind:preset` | 选择后保持的表情／姿势，可包含动态曲线；由同组其他预设或 reset 替换 |
| `kind:motion` | 连续表演；`loop:false` 在时长结束后淡出，循环项持续到替换／reset |
| `kind:toggle` | 独立开关；多个穿搭配件可并存，非穿搭分组也应严格按作者实际语义设计 |
| `clip` / `offClip` | GLB 内真实动画名称；`offClip` 仅用于 toggle 关闭过渡 |
| `bones` | clip 实际影响的 Transform 路径，建立非递归混合掩码；不可填整个角色来掩盖错误路径 |
| `duration` | 秒，0–120；静态原片段可转换成常值 hold clip，不能冒充长动画 |
| `loop` | 是否循环；静态 hold 允许循环以保持姿态 |
| `additive` | 以第一个关键帧为参考的叠加动画；不能把完整绝对姿态直接标成 additive |
| `next` | 非循环 motion 完成后，切到同组指定选项；不能引用自身或 toggle |
| `morphs` / `offMorphs` | `{renderer,shape,weight}`，权重归一化 0–1；源 Unity 0–100 必须转换 |
| `morphTracks` | `{renderer,shape,keys:[{time,value}]}`；time 为严格递增秒，value 为 0–1；当前线性插值，源曲线应离线采样以保留切线效果 |
| `visibility` / `offVisibility` | Renderer 显隐路径；不关闭整个骨架 GameObject，不破坏动态和其他配件 |
| `defaults` | 角色作者默认 Renderer 可见性；缺省值不是把全部 mesh 打开 |
| `defaultOn` | 进入该角色时选中的默认项；同组非 toggle 默认最多一个 |

已知预算：最多 6 组、256 选项；每个 morph 数组最多 256 绑定，每个可见性数组及 defaults 最多 64；骨骼数组最多 256；全包累计动态 morph track 最多 256，每条最多 7201 个关键帧。performance 的选项 ID、分组／选项标签、clip／offClip 名、形变名和所有节点／Renderer 路径最长 **128 个 UTF-16 code unit**（与 Unity string.Length 一致；普通汉字算 1，补充平面字符如多数 emoji 算 2），且不可全为空白。路径必须相对、无反斜杠、无空段及 `.` / `..`。各 morph／morphTracks 数组按 renderer + shape 去重，各 visibility／defaults 数组按 path 去重，bones 不可重复。SDK Python 预检按同样规则拒收；其他能力的共享路径长度不会因此改变。这些是拒收上限，不是推荐资源量；包体仍遵守 XCP 文件和几何预算。

源数据中的 `sourceClip`、`sourceOffClip`、`sourceMorphCurves` 属于转换审计材料，发布前移除。原作缺少 renderer、clip 或形变时，不展示一个没有效果的按钮；记录为何过滤。单纯引用外部 GUID 不是可用动作。

## 命令与回执

使用既有 `character.signal` 外层和 `apiMajor:1` 的角色信号，正常校验 presentation、actor、sequence；无对话轮次的手动选择可用空 turnId。支持：

| 事件 | target | intensity |
|---|---|---|
| `performance.select` | `performance.options.id` | toggle：≥0.5 开、<0.5 关；非 toggle：选择／重播 |
| `performance.reset` | 空字符串或分组 ID | 不使用；恢复该组或全部作者默认 |

```json
{"schemaVersion":1,"kind":"command","name":"character.signal","presentationId":8,"requestId":"performance-12","payload":{"signal":{"apiMajor":1,"apiMinor":1,"actorId":"anime-kipfel","sequence":12,"eventId":"performance-event-12","turnId":"","eventName":"performance.select","target":"outfit-glasses","intensity":1}}}
```

成功回 `characterReceipt`，`channel:performance`；错误码有 `PERFORMANCE_UNSUPPORTED`、`PERFORMANCE_OPTION_UNKNOWN`、`PERFORMANCE_GROUP_UNKNOWN`。状态里的 `performanceSelections` 与 `performanceTransitioning` 驱动实际选中态；`performanceConfigured` 提示状态变化，UI 不提前猜测成功。绑定错误与 Schema 错误在导入时拒绝。

角色切换清除旧角色表现，下一角色按自己的默认值进入，不能把某角色的耳尾／服装选择写入另一个角色。当前手动选项是展示会话状态；不把它表述为云端保存的永久形态。

0.47起原生面板在每个分类首项提供明确的「默认」入口，发 `performance.reset` 并指定当前分组；「全部默认」才发送空target。默认选中态比较该组当前选择与作者的 `defaultOn` 集合，穿搭配件不能简单地全部关闭。恢复表情保留姿势和其他分类，并在表情渐出后恢复允许的自动眨眼；不改变相机取景或用户位置。

## 混合、恢复和姿态

非 toggle 同组互斥，不同分组可叠加。动画按组建立独立混合层。体态变化以指数缓动改变叠加权重；Renderer 显隐在过渡权重越过阈值时切换，不等价于所有材质都具备透明淡化。

`CharacterPerformanceRestore` 在执行序 35 先恢复上一帧表现层覆盖的 morph，随后外观参数（40）、语音（50）、对话表情（55）计算自己的基线，表现层（60）最后混合。恢复必须回到真实非零基准和正在运行的下层值，不能一律写 0，也不能累加上帧覆盖导致表情卡住。退出角色时恢复初始值与作者 Renderer 状态。

为让耳尾、手指及配件骨骼回到下层，导出时给原会话 Idle/动作补上缺失的静态基准轨道。正在控制身体的姿态层会降低视线与会话小动作干预；additive 呼吸不要求释放普通注视。次级动态仍由独立物理执行器处理，应逐动作确认其叠加结果，不能宣称等价 PhysBones。

本能力负责表现，不改变相机取景。坐姿、躺姿等可能离开当前近景；完整身体展示应由独立产品设计决定，不能让每次开面板隐式缩放模型。

## 制作与验证

来源动作应在自己的有效 Avatar 上离线采样；该角色生成的 Transform 曲线才能进入自己的 GLB。Morph 曲线既要保留形状变化，也要保留时间、循环和复位语义。特别核对静态手势、连续耳尾、动态脸部、上装遮挡形变及默认隐藏配件。

至少验证：选择与 reset、开关配对、非零默认形变、说话期间切表情、动作结束恢复、跨组混合、切角色隔离、面板开关不改镜头。静态校验、Unity 批量渲染、模拟器实际触控、真机帧率是不同级别证据；采样频率 60 Hz 不代表 App 达到 60 或 120 FPS。
