# 草莓表情衔接修复 · 0.83.2（113）

## 结论与边界

用户报告草莓说话时切换表情、动作结束回默认有卡顿感。逐帧检查确认主因在 App 的 Portable Animator 适配与 AI 参数调度；没有发现模型网格损坏的证据。原控制器 Gesture 过渡约 0.1 秒、FX 手势表情约 0.085 秒，部分面部效果为零秒切换，这种源设定也放大了近景对话的突变感。

审查使用草莓 1.03 已发布 Prefab、真实 Unity Animator 和导入曲线；原始归档及模型包不改动。不调用 AI、TTS 或图片生成服务。Editor 60/120 Hz 求值用于检查相邻姿态连续性，**不代表真机 60/120 FPS**，也不能排除其他场景的 GPU 或系统掉帧。

## 确认的问题

1. 缺失的 SDK 中性手势代理被统一替换成全身 Host baseline；在 FX 表情层中，它错误覆盖较低的手势层。源表情进入／退出时，这个身体覆盖会突然消失／重现。修复前一个手指关节相邻帧曾跳约 81.53°。
2. Host baseline 只补了骨骼曲线，未明确持有真实默认 morph。交出表情后，笑眼残留约 1.96% 权重，某些脸红效果未真正恢复。
3. AI 只设置新 cue 的参数，没有清除同组上一个 cue 的另一只手。两只手都能驱动同一脸部，较高的右手表情层因此遮住新左手表情。
4. 先 reset、再逐条恢复选择时，reset 内部 `Animator.Update(0)` 提前求值；全局 reset 的 `Rebind()` 则立即恢复所有动画属性。它们不适合可见的连续表演。
5. 单纯修正参数和延长过渡还不够：空 FX 中性状态会在交接最后一帧才放开下层。中间版本的左／右手交接仍出现单帧 100% morph 跳变，因此增加了针对中性代理表情层的平滑权重释放。

## 实施

- 底层 Host baseline 显式写入角色导入时每个 morph 的默认值，保留非零默认，不把默认等同于全零。
- FX 中的 SDK 中性代理改为无身体曲线的空 FX；身体／手指基线仍由下层负责。依据 VRChat 官方[Playable Layers](https://creators.vrchat.com/avatars/playable-layers/)的分层语义，不把完整身体站姿放入中性脸部代理。
- 只对 AI 白名单参数控制、没有 exit time 的短 Gesture/FX 转换设置至少 0.32 秒；更长转换、定时动作、服装及其他控制保持原语义。中性代理所在表情层使用 SmoothStep 权重释放，避免另一只手最后一帧突然出现。离散贴图／开关仍是离散属性，不声称都能插值。
- 新增 `performance.replace`：一个分组的完整选中 ID 在一条命令中校验、提交；无效请求不修改状态。AI cue 替换组内旧 cue，结束后一次恢复接管前的用户快照；其他组不受影响。旧 `select/reset` 接口保留。
- 可见的 reset/replace 不再 Rebind 或提前 Update。Rebind 留在初始绑定、构建和离线审查的立即重置路径。
- 运行状态中的 `performanceTransitioning` 包含原生 Animator 转换及权重过渡。

## 逐帧结果

下表为 60 Hz 求值；morph 数值为归一化后的最大相邻帧变化，非百分制 Unity 原值。只比较同一检查的输入和最终目标，不用参数已选中来替代视觉连续性验证。

| 场景 | 修复前 | 修复后 |
|---|---:|---:|
| 默认 → 笑脸 | 19.61% | 8.78% |
| 笑脸 → 嘟嘴 | 19.61% | 5.21% |
| 笑脸 → 分组默认 | 19.61%，最终有残留 | 8.77%，最终无残留 |
| 笑脸 → 全部默认 | 100% | 8.77% |
| 脸红开／关 | 瞬切或未复原 | 5.21%，完成后准确到目标 |
| 右手笑脸 → 左手难过 | 旧右手参数残留，新表情被遮挡 | 11.30%，旧参数清除、交接完整 |

最终 18 个 60/120 Hz 场景记录通过，其中保留一个直接设置左右手的负对照；16 个修复路径检查限制 morph 相邻变化与骨骼跳变，并核对默认、用户原笑脸及左右手参数。Swift 原生参数序列化/恢复检查覆盖 11 个角色。

诊断工具：`Assets/Editor/AvatarTransitionReview.cs`。在已生成正确 Prefab 后执行 `Run`；`STARRY_TRANSITION_ASSERT=1` 启用连续性断言，`STARRY_TRANSITION_REPORT` 指定私有报告位置。`STARRY_TRANSITION_REBUILD=1` 仅供开发调试，会重建草莓的生成控制器，之后需要正式 PrepareExport 重建引用，不能直接拿旧 Prefab 打包。`ValidateRoster` 检查所有 Portable 角色的 AI 选项原子替换、无效输入无副作用、用户快照恢复和有限数值。

诊断脚本必须激活默认关闭的资源 Prefab，并启用原生 Animator、关闭旧 Animation 播放器；首次探针漏了激活步骤，得到全零和 Animator 未播放警告，已作废重跑。不能把这种探针失效解释为原模型无动画。

原始逐帧数据、构建日志、设备回执和 UI 结果留在 `.local/checks/ichigo-*`，不公开上传角色曲线或模型资源。

## 构建与设备验证

- Unity 最终导出 Prefab 再次执行 18 个逐帧场景通过，避免仅证明临时内存控制器正确。
- 9 个 Portable 角色、142 个 AI 选项：替换、无效请求无副作用、原快照恢复、数值有效性通过。
- 两个早期适配角色（琪宝／豆日向）全部 130 个原作选项的替换和快照恢复通过。首次测试错误假设早期 manifest 含 `ai.automatic`，导致覆盖数为零而失败；这些标记实际在宿主目录生成，修正为枚举完整原作选项后重新通过，没有跳过失败。
- Swift 信号 JSON 检查覆盖 11 个角色；显式空选择、同组默认手势与原用户选择均保留在同一消息中。
- 信号 Schema 增补可选 `selections`；2 个有效与 6 个无效输入检查通过。
- iPhone 17 模拟器 Debug 构建通过；`VrchatBatchTests/testIchigoExpressionChangesAndDefaultRecovery` 51.382 秒通过，实际打开草莓、依次切换表情、恢复默认、回到会话。检查了截图，角色正常渲染。结果包 `IchigoTransitions113.xcresult`；该 UI 测试不承担帧率证明。
- 真机 Release 签名构建、`codesign --verify --deep --strict` 通过。iPhone 17 安装成功，设备查询读回 `com.gukaifeng.xiaoban.dev` **0.83.2 / 113**；回执为 `ichigo-device-install113.json` 和 `ichigo-device-apps113.json`。本轮没有自动启动真机 App 触发付费 AI，也没有重新采集真机帧率。
