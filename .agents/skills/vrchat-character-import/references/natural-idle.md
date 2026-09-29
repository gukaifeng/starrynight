# 自然待机与环境风（0.46）

用户2026-09-30明确授权新增自动眨眼、呼吸待机和环境风，覆盖早期“只保留原作、不加眨眼/微风”的限制。保留原始ZIP/Prefab/源动画，生成包可以增加明确标注的App适配，不应把旧限制作为要求用户再次批准的理由。

入口为 `scripts/vrchat_autonomy.py`，由 `prepare_vrchat_characters.py` 重导调用。琪宝/豆日向包2.1.0，使用可选 [core.autonomy@1](../../../../docs/character-standard/07-natural-idle-standard.md)，保持API1.1、角色ID和用户数据。导入后必须真正Setup，再导出两平台；不靠修改stamp冒充更新。

- 豆日向主FX的Auto_Blink包含原闭眼/开眼0.08/0.06秒与间隔lottery，`Auto_Blink` morph必须在转换白名单保留。检查实际FX绑定、状态/参数驱动、形变，`enableEyeLook:0`不能证明没有自动眨眼。初始延时和五次平滑属于App适配，非完整SDK图仿真。
- 琪宝使用原eye_close与App调度，未确认原自动时序，不冒称原作节奏。
- 默认Idle仍是原stand+breath；原静态姿势会覆盖Idle，使用源breath加法层补入，跟随姿势权重。静态呼吸选项本身复用Idle，动态睡眠已有自己的运动，都不叠加两遍。
- 自动眨眼必须让位于原作表情及睡眠；先恢复上帧闭眼偏移，再恢复表现层基线。跨角色Bind清理旧眼睑状态。嘴型通道不被眨眼改写。
- `secondary-motion.json`显式标记hair/cloth/none及response。微风是环境适配，原骨链、碰撞、幅度预算继续约束。强度先小，不能摇整个人或放大呼吸来伪装头发物理。

验证 `NaturalIdleReview.BuildAndReview` 和 `NaturalIdleTests`。旧 `VrchatOriginalMotionReview` 的无微风断言属于历史要求；源Idle曲线比对仍有价值，但当前待机以新版审查为准。状态isPlaying不等于画面在动：检查最终骨骼、真实形变网格与无触摸的衣发位移。60/120 Hz数值步进不是FPS实测。

批处理Editor连续修改blendShape后直接Camera.Render可能复用旧GPU蒙皮。审查截图须先BakeMesh呈现当前采样结果，并在实际模拟器核对；不要把这种截图缓存误诊为生产端眨眼失效。故障与最终证据记录于[自然待机验收](../../../../docs/verification/natural-idle/README.md)。
