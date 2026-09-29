# 自然注视验证 · 小伴0.8.3 / build17

已完成引擎与实际模拟器验证，并签名安装到已配对iPhone。设备列表确认0.8.3／17；自动启动被Locked阻止。真机上的动态效果仍需解锁点开App体验，不将安装成功当作真机性能验收。

## 可以直接看

- [iPhone朝左后的对视](iphone17/02-human-left.png)／[朝右后的对视](iphone17/03-human-right.png)
- [iPad横屏](ipad-pro-11/06-ipad-landscape.png)
- [实际iPad录屏片段](ipad-pro-11/gaze-and-panels.mp4)：22秒，左右拖动、取景展开与恢复、触头动作；从原始录像20秒处截取，仅压缩尺寸、没有变速。横屏之后的画面未放进该竖屏短片。
- [侧向引擎近景](real-woman-35-5.png)／[背面自动收回](real-woman-150-0.png)。这些是引擎定点渲染，与App截图分开标注。

## 实际结果

| 检查 | 结果 |
| --- | --- |
| 三角色引擎检查 | 13,317帧通过；含侧向、背面、上下目标与全部按钮／摇头动作 |
| 未写动画曲线的骨骼 | 每个角色反复2,000次更新／还原，无累积扭转 |
| 60／120Hz响应 | 一秒相同目标的差约0.0000076°，是运动算法一致性，不是渲染FPS测量 |
| iPhone 17 XCTest | 完整注视流程44.356秒，通过 |
| iPad Pro 11 M4 XCTest | 含横屏完整流程50.098秒，通过 |
| iPhone运行时采样 | 1,418条，261条稳定对视样本；最大数学视线误差0.0524° |
| iPad运行时采样 | 1,587条，281条稳定对视样本；最大数学视线误差0.0443° |
| 转圈背面样本 | iPhone21条／iPad20条，注视目标权重均为0 |
| 鞠躬样本 | iPhone139条／iPad122条，让出注视并保留动作 |

“视线误差”是已校准眼骨朝向与虚拟镜头方向的夹角，不是用户眼动测量或像素级瞳孔识别。真实运行时最大头颈左右角约38.91°，所有样本均在50°／上22°／下28°与眼球12°／上8°／下10°范围内。静态极端角度另外由引擎覆盖，日常拖动范围仍为左右20°。

完整报告：[结果索引](results.json)、[引擎报告](engine-review.json)、[iPhone运行时验证](iphone17/runtime-verification.json)、[iPad运行时验证](ipad-pro-11/runtime-verification.json)、[设备安装状态](device-installation.json)。截图旁附对应的运行状态JSON。

## 错误处理与复现

首轮iPhone用例错误地假定取景角与转头角的符号相反；实际前向镜头坐标中两者同号，角色的数学视线与实际画面均正确。将断言改为“头部与实际目标方向同向”，重新运行iPhone／iPad均通过。失败结果保留在.local/checks/Gaze-Phone-1.xcresult。

simctl后台截图／录像不能依赖终端的相对路径，首次录屏因路径未解析而失败；改用绝对路径后成功。首个iPhone录像未捕获完整操作，不作为交付证据，使用iPad完整运行中的片段。

源代码补充调整后重新导出模拟器和设备，检查IL2CPP产物含最新分支与gazeRevision，避免使用导出过程中已经编译的旧快照。最后通过的结果为.local/checks/Gaze-Phone-2.xcresult和.local/checks/Gaze-iPad.xcresult。

复现引擎：通过Unity CLI执行GazeReview.Run()；复现模拟器：CharacterHostUITests/GazeFlowTests；解析运行时采样：python3 scripts/verify_gaze.py docs/verification/gaze/iphone17/runtime.jsonl。

角度、动作优先级与资料来源见[设计记录](../../design/2026-09-28-natural-gaze.md)。现有头发／服装仍依赖各自蒙皮，新角色或新的大幅动作需要继续做形变复查。
