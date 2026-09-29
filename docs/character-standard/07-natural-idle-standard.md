# 自然待机：core.autonomy@1

星夜 0.46 引入、0.47 更新 / Character API 1.1 的可选能力。角色制作方通过数据声明眨眼形变、节奏、表情优先级，以及静态姿势上的呼吸。不向角色包放入 C# 或平台 SDK。未声明此能力的旧包行为不变；旧宿主可忽略可选字段，继续播放基础 Idle。

## 清单

在 `compatibility.optional` 加入 `core.autonomy@1`，再提供 `autonomy`：

```json
{
  "schemaVersion": 1,
  "blink": {
    "bindings": [{"renderer":"Rig/Body","shape":"eye_close","weight":1}],
    "intervals": [3.2,4.7,5.8,3.9,4.4],
    "closeSeconds":0.16,
    "closedSeconds":0.035,
    "openSeconds":0.26,
    "firstDelay":1.8,
    "suppressGroups":["expression"],
    "suppressOptions":["sleep"]
  },
  "breathing": {
    "clip":"App_VisibleBreath",
    "bones":["Rig/Hips","Rig/Hips/Spine/Chest"],
    "poseOptions":["sit","stand"]
  }
}
```

示例路径/选项必须换成包中真实内容。`blink.bindings` 为1～4个原作闭眼形变，不能与口型共用通道；权重0～1。`intervals` 为1～16个秒数，每轮等概率选一个，重复值用于表达权重，范围0.2～30秒。闭眼0.04～0.3秒、停留0～0.1秒、睁眼0.04～0.4秒，首次等待0.2～10秒。闭合曲线使用端点速度与加速度为0的五次平滑插值。

`suppressGroups` / `suppressOptions` 引用原作表现。眨眼在被覆盖的表情/睡眠渐入与渐出期间让位；解除后等待再眨眼，不中途补发积攒的眨眼。不要对手动闭眼再叠加新的闭眼形变。口型仍由 `speech` 定义。

`breathing` 可选。呼吸 clip 必须是经该模型自身骨轴转换的加法呼吸，以第一帧为参考；bones最多16个。`poseOptions` 只列会替代基础 Idle 的原作静态姿势，不能列已经含呼吸的默认 Idle、动态入睡或睡眠循环。运行时按对应姿势权重补入，与基础 Idle 同步时间，不叠加两遍。没有原呼吸资源的新角色需要作者交付合适的 Idle，不能把任意角色的动画名称换成自己的。

0.47 当前两角色按用户要求增强可见度：保留 `Source_Idle` 和所有原作 VRC clip；另生成 `Idle` / `App_VisibleBreath`，仅将 Chest/Head 相对首帧的四元数短弧幅度放大，琪宝4倍、豆日向3倍。时间、髋部及下肢不放大，单骨偏转不超过8度；实际数据和测量在本轮报告中。转换必须从原作重新生成，禁止在已放大的片段上再乘一次。这是当前两角色的审阅配方，不应把同一倍率直接用于其他骨架。

## 环境风与衣发

`core.secondary-motion@1` 的 `secondary-motion.json` 仍使用 schemaVersion=1，新增兼容字段：

- 0.47起 `ambientHairAngle`：0～8度；`ambientClothAngle`：0～4度，缺省0。旧包省略头发值时仍采用原2.2度。使用扩大范围的新包需要0.47及以后的导入器/运行时；不承诺旧宿主呈现相同强度。
- 每条 strand 的 `wind`：`hair`、`cloth` 或 `none`；`windResponse` 为0～1。
- 老包省略 `wind` 时保留原有头发分类行为。新包应显式填写；尾巴、耳朵、身体、坚硬配饰通常为 `none`，保留其原作动画和惯性。

角度是弹簧外力的幅度预算，不是直接写入骨骼的旋转。微风以连续低频水平流动驱动原骨链，入场1.4秒渐入；沿链传递、阻尼、长度与角度限制、碰撞约束继续有效。不产生向上掀衣的阵风。暂停/长帧重置速度与风强度淡入，防止回前台爆冲。小角度旋转应采用保留叉积精度的实现，不能在高刷新率下被舍入为零。

## 来源与验证

当前两包升级至2.2.0，角色ID和会话记录不变。豆日向保留原 `Auto_Blink` 形变及间隔数组；琪宝使用原 `eye_close` 和已有App间隔数组。两者闭/开过程都按本次要求适配为0.455秒，不能再称为原FX闭/开时长。源2.5秒呼吸与原130项表现保留，App上半身幅度和更明显衣发气流单独声明，不声称与VRChat PhysBone完全等价。

必须验证实际闭眼网格、最终骨骼变化、静态姿勢/睡眠优先级、讲话口型、切角和后台恢复。基础检查：

```bash
.local/character-sdk-venv/bin/python scripts/validate_characters.py
unity run unity/CharacterRuntime --timeout 900 -- \
  -executeMethod NaturalIdleReview.BuildAndReview \
  -logFile /absolute/path/natural-idle-review.log
```

60/120 Hz逐帧步进是数值与行为检查，不是设备60/120 FPS实测。完整导出后仍需iPhone模拟器实际运行；性能结论应由真机持续帧耗时支持。

来源参考：[VRChat状态行为与参数驱动](https://creators.vrchat.com/avatars/state-behaviors/)、[Unity执行顺序](https://docs.unity3d.com/6000.3/Documentation/Manual/execution-order.html)。还原时须检查实际绑定FX，而不能由Avatar Descriptor的 `enableEyeLook` 单独判断是否存在自动眨眼。
