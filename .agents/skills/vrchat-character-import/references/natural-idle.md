# 自然待机与环境风（0.47）

用户2026-09-30明确授权新增自动眨眼、呼吸待机和环境风，覆盖早期“只保留原作、不加眨眼/微风”的限制。保留原始ZIP/Prefab/源动画，生成包可以增加明确标注的App适配，不应把旧限制作为要求用户再次批准的理由。

入口为 `scripts/vrchat_autonomy.py`，由 `prepare_vrchat_characters.py` 重导调用。琪宝/豆日向包2.2.0，使用可选 [core.autonomy@1](../../../../docs/character-standard/07-natural-idle-standard.md)，保持API1.1、角色ID和用户数据。导入后必须真正Setup，再导出两平台；不靠修改stamp冒充更新。

用户追加要求「幅度明显、单次眨眼慢一些」后，0.47优先于下方0.46背景：Chest/Head相对首帧的旋转分别4倍/3倍，髋与腿不变；保留Source_Idle与全部VRC源片段，生成Idle和App_VisibleBreath。眨眼闭/停/开为0.16/0.035/0.26秒，间隔数组不变。头发/衣物风预算7.5/3.2度、响应0.9/0.85；导入器与运行时共用8/4度最大值，逐链原限制和碰撞仍有效。不要从已放大的片段再次放大。详见[可见待机方案](../../../../docs/design/2026-09-30-visible-idle-and-defaults.md)。

- 豆日向主FX的Auto_Blink包含原闭眼/开眼0.08/0.06秒与间隔lottery，`Auto_Blink` morph必须在转换白名单保留。检查实际FX绑定、状态/参数驱动、形变，`enableEyeLook:0`不能证明没有自动眨眼。初始延时和五次平滑属于App适配，非完整SDK图仿真。
- 琪宝使用原eye_close与App调度，未确认原自动时序，不冒称原作节奏。
- 默认Idle由原stand+breath及上述明确的上半身幅度适配生成；原静态姿势会覆盖Idle，使用同幅度App_VisibleBreath加法层补入，跟随姿势权重。静态呼吸选项本身复用Idle，动态睡眠已有自己的运动，都不叠加两遍。
- 自动眨眼必须让位于原作表情及睡眠；先恢复上帧闭眼偏移，再恢复表现层基线。跨角色Bind清理旧眼睑状态。嘴型通道不被眨眼改写。
- `secondary-motion.json`显式标记hair/cloth/none及response。环境风与上半身呼吸分别控制并分别验证，原骨链、碰撞和逐链限制继续约束；不能摇整个人根节点来伪装头发物理。

验证 `NaturalIdleReview.BuildAndReview` 和 `NaturalIdleTests`，当前输出在 `docs/verification/idle-refinement/`。旧 `VrchatOriginalMotionReview` 的无微风断言属于历史要求；应把旧Idle与Source_Idle比对，不能再要求新的适配Idle幅度与源片段一致。状态isPlaying不等于画面在动：检查最终骨骼、真实形变网格与无触摸的衣发位移。60/120 Hz数值步进不是FPS实测。

表现面板每组提供默认入口，发 `performance.reset` 且 target 为该组；空target才是全部默认。默认选中态必须考虑 `defaultOn` 配件，不能把没有选择等同于原作默认。检查表情复位保留姿势/穿搭、渐出后眨眼恢复、当前分类切换回顶部。

批处理Editor连续修改blendShape后直接Camera.Render可能复用旧GPU蒙皮。审查截图须先BakeMesh呈现当前采样结果，并在实际模拟器核对；不要把这种截图缓存误诊为生产端眨眼失效。故障与最终证据记录于[自然待机验收](../../../../docs/verification/natural-idle/README.md)。
