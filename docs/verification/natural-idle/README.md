# 自然待机验收 · 0.46.0 / 67

当前范围：琪宝、豆日向，角色包2.1.0；仅iPhone。源资产保持原状，新增行为按[设计](../../design/2026-09-30-natural-idle.md)明确区分原作数据与App适配。完整能力定义见[制作标准](../../character-standard/07-natural-idle-standard.md)。

## 已完成的引擎与数据检查

- 全角色包预检通过。当前发布目录仍仅两角色，各自的音乐、背景与表现独立；集合版本从2.0.0同步为2.1.0。
- 30项SDK契约测试通过，其中7项新增覆盖缺失眼睑、嘴型冲突、无效姿势/表情引用、错误眨眼间隔与重复形变。
- `NaturalIdleReview.Run` 最终通过，见[runtime-review.json](runtime-review.json)。两角色各以60/120 Hz步进，24秒自然待机均出现4次眨眼，峰值闭合琪宝1.0、豆日向约0.998。原始形变的真实顶点位移通过，不能以播放标志代替。
- 最终头、胸骨发生实际变化。源呼吸叠加到琪宝6种、豆日向3种原静态姿势，默认Idle和睡眠不重复叠加；表情优先、嘴型保留、跨角色复位与非活动角色停止均通过。
- 完全冻结身体的额外检查仍能测到头发与衣物末端移动，证明微风无需用户拖动或身体呼吸激发。所有骨链有限值及原角度约束通过，共1,973,956次逐帧/逐链断言。
- 60/120 Hz是数值步进频率，不是实体手机持续60/120 FPS测量；暂不据此承诺帧率。

采样网格图：琪宝[睁眼](anime-kipfel-open.png)/[闭眼](anime-kipfel-blink.png)，豆日向[睁眼](anime-mamehinata-open.png)/[闭眼](anime-mamehinata-blink.png)。这些是批处理Editor实际采样形变的渲染，手机画面验证单独记录。

## 发现并处理的问题

1. **源能力遗漏**：豆日向FX里有自动眨眼，旧转换没有保留Auto_Blink形变及调度。保留形变后映射源关闭/打开时长与间隔分支；初次延时、平滑曲线仍标为App适配。琪宝使用原闭眼形变与本地时序。
2. **静态姿势覆盖呼吸**：原静态站/坐等高层姿势会盖住Idle。加法呼吸层只随这些姿势权重生效，使用原骨轴、原曲线和Idle同步时间，避免默认呼吸加倍。
3. **短发微风被数值截断**：最初冻结身体时豆日向头发位移为0，但衣物仍动。诊断有非零弹簧速度，位移却在Vector3.RotateTowards微小角度处理时被舍去。改为范围内保留原预测向量，超限才做atan2角度投影，并用叉积保留旋转精度；两种步频最终都通过。没有靠加大风力掩盖问题。
4. **批处理截图缓存**：Camera.Render在无Editor帧循环时会复用旧GPU蒙皮，使权重已闭合的截图仍睁眼。审查截图改为BakeMesh当前采样，再呈现网格；生产运行路径未做这种替换。
5. **集合检查顺序**：首次转换后、Unity尚未重建角色目录时集合版本检查失败；真正Setup刷新目录后通过，没有放宽版本一致性检查。

原始失败日志保存于 `.local/logs/natural-idle-unity-review*.log`、`natural-idle-wind-diagnosis.log`。模型转包日志为 `natural-idle-conversion.log`，SDK测试为 `natural-idle-sdk-tests.log`。模型原始ZIP与原Prefab未修改；不宣称完整迁移VRChat网络、Contacts或SDK控制器。

## 模拟器与设备交付

- Unity Simulator/Device 两平台真实导出通过，导出清单含 `autonomyRevision:1`；构建脚本拒绝旧运行时。模拟器Debug与真机Release均编译成功，Release严格验签通过。
- iPhone17 / iOS26.4 模拟器实际UI流程通过，1项完整双角色流程95.719秒、0失败。连续记录3061帧，琪宝42.36秒内观察到8次新增眨眼，豆日向40.90秒内5次，两角色均有最终骨骼和衣发位移。样本含说话、停留及表情切换，不是FPS测量。见[实时采样报告](simulator-live-review.json)、[代表帧](simulator-live-frames.json)和[模拟器截图](simulator/)。
- 正常启动（无测试参数）恢复，运行日志无异常；[约22秒演示视频](simulator/natural-idle-preview.mp4)保留无触摸待机效果。视频压缩版用于观看，不用于测量渲染性能。
- **0.46.0/67已通过Wi-Fi安装iPhone17**，设备读回版本一致。自动启动被系统Locked拒绝后未重试或等待用户；用户解锁后点星夜即可使用。见[设备记录](device-installation.json)。不把安装成功写成真机已运行/帧率已测。
- Xcode结果：`.local/checks/Natural-Idle-v046.xcresult`。普通模拟器运行日志：`.local/logs/natural-idle-normal.stdout.log`、`natural-idle-normal.stderr.log`。
