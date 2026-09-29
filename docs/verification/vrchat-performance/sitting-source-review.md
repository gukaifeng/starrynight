# sit 原片段复核

2026-09-29；只读检查，没有修改模型、转换器、运行时或坐姿数值。

**结论已确认：两个 sit 片段都有完整下肢坐姿，初次站立状截图来自 Editor 同帧 GPU 蒙皮缓存，不是源动作或产品播放数据丢失。** 原始 `.anim`、可信 Unity Avatar 采样、最终 GLB 首帧、CPU BakeMesh 均有明显屈髋前伸。VisualProbe 先 BakeMesh 后，普通和临时网格渲染均正确显示坐姿及笑脸。修复仅落在截图工具，没有改造产品动画或伪造姿势。

## 原始证据

两个片段均为零秒、89 条有效 muscle/root 曲线：

- 琪宝：`kipfel_sit.anim`，GUID `854cba89c21b29945b984a0d16344fed`。
- 豆日向：`Mamehinata_sit.anim`，GUID `4fbf74a10c4a7e046bae7cae847861f5`。

曲线包含 RootT/RootQ、脊柱／胸、肩臂／手指，以及双侧 Upper Leg、Lower Leg、Foot、Toes。完整数值保存在 [sitting-source-review.json](sitting-source-review.json)，不是依文件名推断。

两模型的 SittingLayer 都在 `PoseSpace`、`UpperBodyTracked` 状态引用自己的 sit；ActionLayer 的 Prepare Sitting、Sit、BlendOut Sit、Restore Tracking(sit) 也引用它。PoseSpace 的行为数据为 `enterPoseSpace:1`、`delayTime:0.51`；UpperBodyTracked 把头／手 tracking 设为 1，髋／足值为 0。状态名“UpperBodyTracked”不能推导 clip 只动画上半身。

## 生成资源的 FK 检查

下表是最终 GLB sit 第一帧关节位置，单位米，GLB 空间。大腿从髋关节几乎水平前伸，和站姿向下垂直明显不同。

| 角色 | 左髋关节 | 左膝 | 左踝 |
|---|---|---|---|
| 琪宝 | (0.089, 0.765, -0.005) | (0.055, 0.682, 0.279) | (0.100, 0.355, 0.236) |
| 豆日向 | (0.089, 0.751, -0.007) | (0.149, 0.649, 0.266) | (0.237, 0.376, 0.435) |

这证明曲线写入生成资源。初次 `render/anime-*-sit.png` 双腿下垂，后经 `visual-probe/` 的 CPU 顶点和普通／临时 BakeMesh 渲染对照，确认 Editor 同帧 GPU 蒙皮缓存。`CharacterPerformanceReview.Capture()` 现渲染真实求值后的临时网格并保存顶点差值；最终批量重渲染／导出结果由主验收记录确认，本专项不宣称最终 App UI 通过。

## SDK／座位语义的实际边界

原 sit 的 RootT.y 约 1.05，而站姿约 0.96；它没有把整个角色下移到当前 App 地面上的某张椅子。源 Sitting 控制器涉及 viewpoint calibration、pose space、tracking，不能由一条独立 clip 完整复刻。VRChat 官方将 Sitting slot 定义为动画加姿势并使用 viewpoint 校准；Pose Space 行为会调整使用者视点空间。[Playable Layers / Sitting Pose](https://creators.vrchat.com/avatars/playable-layers/)、[State Behaviors](https://creators.vrchat.com/avatars/state-behaviors/)

因此该资源可称“原作静态坐姿”或“坐姿参考”，并说明未适配椅子／接地；不能称为已实现完整落座动画或座位交互。截图工具修复保留原作数据，坐姿本身无需另造或改名掩盖问题。
