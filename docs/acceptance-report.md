# 验收报告模板 · 双设备 V1 模型查看版

所有运行结果初始为 NOT TESTED，不是通过证明。D01：iPhone 17 标准版；D02：11 英寸 iPad Pro（M4，2024）。

实施依据：[V1 完整开发方案](design/2026-09-25-v1-development-plan.md)。保留原交接文档 T01–T23，新增 NV01–NV12 覆盖首页、旋转/缩放/复位、iPad 扩展布局与异常时序。原用例定义见[交接方案第 14 节](../ios_3d_mvp_technical_spec_v1_1.md)。

文档/源码版本：待填。构建标识：待填。环境记录：待填。

| 用例 | D01 结果 | D02 结果 | 分设备证据 / 日志 / 说明 |
|---|---|---|---|
| T01 | NOT TESTED | NOT TESTED | 待填 |
| T02 | NOT TESTED | NOT TESTED | 待填 |
| T03 | NOT TESTED | NOT TESTED | 待填 |
| T04 | NOT TESTED | NOT TESTED | 待填 |
| T05 | NOT TESTED | NOT TESTED | 待填 |
| T06 | NOT TESTED | NOT TESTED | 待填 |
| T07 | NOT TESTED | NOT TESTED | 待填 |
| T08 | NOT TESTED | NOT TESTED | 待填 |
| T09 | NOT TESTED | NOT TESTED | 待填 |
| T10 | NOT TESTED | NOT TESTED | 待填 |
| T11 | NOT TESTED | NOT TESTED | 待填 |
| T12 | NOT TESTED | NOT TESTED | 待填 |
| T13 | NOT TESTED | NOT TESTED | 待填 |
| T14 | NOT TESTED | NOT TESTED | 待填 |
| T15 | NOT TESTED | NOT TESTED | 待填 |
| T16 | NOT TESTED | NOT TESTED | 待填 |
| T17 | NOT TESTED | NOT TESTED | 待填 |
| T18 | NOT TESTED | NOT TESTED | 待填 |
| T19 | NOT TESTED | NOT TESTED | 待填 |
| T20 | NOT TESTED | NOT TESTED | 待填 |
| T21 | NOT TESTED | NOT TESTED | 待填 |
| T22 | NOT TESTED | NOT TESTED | 待填 |
| T23 | NOT TESTED | NOT TESTED | 待填 |

T14–T16 等构建项可共用同一证据，注明引用；运行与性能用例不得互相替代。T18 对两台均适用；无执行环境写 NOT TESTED，不能按“没有高刷硬件”写 N/A。T18 的 PASS 仅表示诊断执行并留证，持续 120 是否达标必须在下表另写。

## V1 新增功能验收

| 用例 | 操作与期望 | D01 结果 | D02 结果 | 分设备证据 / 说明 |
|---|---|---|---|---|
| NV01 | 首页显示真实模型缩略图；点击卡片或按钮均打开唯一内置模型，重复点击只进入一次 | NOT TESTED | NOT TESTED | 待填 |
| NV02 | 单指水平环绕 360°、上下俯仰；无跳变/翻转/无限自转，触点取消后可继续操作 | NOT TESTED | NOT TESTED | 待填 |
| NV03 | 双指张开放大、收拢缩小；近远限制有效，不穿入模型，不产生非法视角 | NOT TESTED | NOT TESTED | 待填 |
| NV04 | 任意旋转/缩放后点击复位，恢复同一默认中心、角度和距离，清除旧手势 | NOT TESTED | NOT TESTED | 待填 |
| NV05 | 单指 → 双指 → 单指连续切换，不突然旋转或缩放；手指离开后无旧触点残留 | NOT TESTED | NOT TESTED | 待填 |
| NV06 | 从返回/复位按钮开始的触摸不转动模型；透明空白区域可操作模型 | NOT TESTED | NOT TESTED | 待填 |
| NV07 | 任意视角返回再打开，复用运行时并恢复默认视角；20 次循环均正常 | NOT TESTED | NOT TESTED | 可与 T09 共用逐设备证据 |
| NV08 | iPad 全部声明方向下布局、按钮、默认取景和手势正确，旋转中不重复初始化 | N/A | NOT TESTED | D01 本版仅竖屏；竖屏仍执行 T22 |
| NV09 | iPad 系统窗口尺寸变化及恢复后无崩溃/永久黑屏；控件可达、取景及触摸坐标准确 | N/A | NOT TESTED | D01 不涉及 iPad 窗口操作；记录 D02 实际系统与模式 |
| NV10 | 加载过程中返回，再收到 ready/error 不抢窗口；重复请求、超时、后台恢复有正确页面 | NOT TESTED | NOT TESTED | 待填，含异常时序复现步骤 |
| NV11 | 冷启动与再次进入分别测从点击到可见可交互的时间，记录中位数/最大值及目标差异 | NOT TESTED | NOT TESTED | 暂定冷 ≤ 5 秒、再次进入 ≤ 1 秒 |
| NV12 | 大字号下页面可读可滚动；返回/复位有无障碍标签；减少动态效果下复位无动画 | NOT TESTED | NOT TESTED | 待填 |

新增运行用例尚未执行。N/A 仅表示该设备不在特定用例范围，不是已通过；无设备或无法复现时使用 NOT TESTED。

## 分设备性能记录

| 指标 | D01 | D02 |
|---|---|---|
| 实际系统 / 应用构建 | 待填 | 待填 |
| 实际渲染宽高 / 比例 / 画质 | 待填 | 待填 |
| 编译配置 / Development Build / 诊断模式 | 待填 | 待填 |
| 采样区间 / 环境温度 | 待填 | 待填 |
| 充电 / 录屏 / 调试器 | 待填 | 待填 |
| 低电量 / 帧率限制 / 热状态 | 待填 | 待填 |
| 60 目标下平均 / P95 / P99 帧耗时 | 待填 | 待填 |
| 60 档基线结论 | NOT TESTED | NOT TESTED |
| 120 目标下平均 / P95 / P99 帧耗时 | 待填 | 待填 |
| 持续 120 的证据、达标/未达标结论 | 未测，不推断通过 | 未测，不推断通过 |
| 20 次页面循环 | NOT TESTED | NOT TESTED |
| 10 分钟运行与内存趋势 | NOT TESTED | NOT TESTED |
| 最终呈现证据 / Unity 循环 FPS 区别 | 待填 | 待填 |
| 冷启动进入时间：样本 / 中位数 / 最大值 | 待填 | 待填 |
| 20 次再次进入：中位数 / 最大值 | 待填 | 待填 |
| 内存：首次进入 / 返回 / 预热 / 循环结束 | 待填 | 待填 |

## 交接

干净重建：NOT TESTED。签名到期后重装：D01 / D02 均 NOT TESTED。不得把未等到实际到期写为到期重装通过。

## 总结

D01：已实现 / 已验证 / 未验证 / 已知限制，分别填写。

D02：已实现 / 已验证 / 未验证 / 已知限制，分别填写。

整体：缺少任一设备的必需验证时，只能“部分完成”，不能宣称双设备适配完成。范围外设备不构成阻塞，也不宣称支持。
