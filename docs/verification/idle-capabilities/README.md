# 琪宝、豆日向：静止时的基础动态复核

日期：2026-09-29；版本0.45.0/66。本轮为源码、原始Prefab/Controller、转换包及已有0.45运行记录的复核，没有更改角色或发布新版本。用户实机反馈：旋转角色时头发与衣角会动，静止时缺少明显动态。

## 已确认

- 两角色已保留骨链与碰撞数据，App使用独立弹簧/惯性求解器；不是直接运行VRChat PhysBone。琪宝secondary-motion.json为103个骨段/33个碰撞球，豆日向41个骨段/12个碰撞球。旋转时用户观察到的衣发跟随与实现一致。
- 两角色ambientHairAngle均为0；没有持续环境微风，惯性趋于稳定后不会自行持续飘动。
- 原呼吸与原站姿确实存在，已按原2.5秒时间轴组成Idle。原始数值审查最大骨旋转变化约0.846°/1.594°，很轻微。已有0.45截图随附运行数据中，两角色idlePlaying=true、idleWeight=1，琪宝idleTime随不同采样从5.79秒增长到47.54秒。播放器标志不等同于本轮实机骨骼视觉测量；若继续排查“完全不动”，应采集实际最终骨骼/顶点差值。
- 两包保留眨眼/闭眼相关形变或手动表情，当前没有独立自动眨眼调度。不得将可选“眨眼”表情按钮当作自动眨眼已迁移。

## 关键补充：豆日向原作有自动眨眼控制器

Mamehinata_PC.prefab的FX层（type5）实际引用GUID `83bcd88bbcab770428ac7be793a3613c`，对应：

`.local/vrchat-stage/Assets/MOCHIYAMA/Mamehinata/Controller/Mamehinata_FXLayer_v1.50.controller`

已发现其 `Auto_Blink`、`Blink_Control`、`Blink_Change` 层/状态机，`EyeClose / EyeOpen / BlinkWait / CheckBlink` 状态以及 `BlinkIntervaLottery` 等间隔参数。当前XCP只转换部分原作选项与曲线，没有完整迁移这个自动状态机。用户看到不眨眼属于已有原作行为未接入，不能归因为源模型没有眨眼。

琪宝主Prefab绑定的是Kipfel_FXLayer_v1.0.3.controller，目前未在绑定控制器里发现同名自动眨眼层；包中有手动wink原表情。其自动眨眼是否通过其他路径实现，尚未完成确认，不以名称检索无结果宣称绝对不存在。

**审计规则更正**：`enableEyeLook: 0`只说明未启用Avatar Descriptor那条眼睛系统，不能证明FX控制器没有自定义自动眨眼。以后必须同时查实际绑定FX层、参数驱动、BlendTree、默认状态、定时转换、动画/材质曲线；不要擅自编造新的调度并称其为原作。

参考：原作恢复审计 `../vrchat-original-motion/source-audit.md`；0.45实机/模拟器结果 `../conversation-refinement/README.md`；[VRChat PhysBones官方说明](https://creators.vrchat.com/common-components/physbones/)。
