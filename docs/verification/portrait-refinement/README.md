# 星夜 0.33.0 / build51：头部互动与二次元精修

iPhone 17 模拟器已更新并正常启动；真机 Release 构建与严格验签通过。一次安装返回 CoreDevice 1011：系统未找到指定 iPhone，立即停止，没有重试或要求用户等待。**本轮没有安装到手机**；签名包在 `.local/build/DeviceDerivedData/Build/Products/Release-iphoneos/CharacterHost.app`，Xcode 工作区保持 device / Release。

## 已实现

- 公共摸头回应改为独立头颈叠加动作，约1.8秒、有起止缓冲、服从角色转头限幅；身体动作及新语音回合不会抢占。正在反应时连点不重置动作。
- 聊天渐变中近乎完全透明的上沿让触摸穿透到角色，可读气泡和输入控件仍正常使用。单击不再等待被锁定开关禁用的旋转／缩放识别器。锁定取景时仍可摸头；旋转缩放继续需要解锁。
- 小光、小诗、晴川使用官方 Unity Toon Shader 分区材质，恢复原模型法线／头发 MatCap，新增明暗层次与细描边，调整补光预算以保留白发和脸部细节。颜色定制同步改变阴影色；头像重新渲染。
- 以原作者的 Idle 和 Relax 制作30秒循环，加轻微呼吸、不等间隔眨眼／双眨眼与受限次级摆动，脚底保持稳定；原九段动作保留。三个包升级到1.1.0，头像按包版本刷新。

## 验证与证据

4个不同 XCTest 方法通过，另有2项内容回归检查。完整方法、用例时间和构建记录见 [result.json](result.json)。

- 最大70%聊天区域、取景锁定状态：7个角色全部命中原生触摸层并出现实际头部偏转，采样峰值8.2°～16°，相机距离不变。见 [各角色数值](head-reactions.json)。没有只以点击计数作为通过依据。
- 普通启动、关闭资料卡、切到消息再回会话后仍可摸头；解锁后的单指转向和双指缩放通过。最终删除识别器依赖后，手势流程再次通过。
- 小诗正在执行 Relax 时摸头，反应峰值15.98°，身体状态仍为 Relax，证明反应没有被整身动作抢占。见 [运行状态](simulator/refined-shino-touch-during-relax-runtime.json)。
- 小诗换发色、切小光检查默认色、再回小诗检查保存值通过；还原默认色后返回会话。
- Unity 两平台导出0错误；原生 Debug / Release 均通过，Release严格验签通过。未新增iPad测试，未将模拟器帧率或120目标配置写成真机持续120 FPS保证。

## 图片

- [小诗会话](simulator/refined-shino-conversation.png)、[小光会话](simulator/refined-vita-conversation.png)
- [小诗换色](simulator/refined-shino-tinted.png)、[放松动作期间摸头](simulator/refined-shino-touch-during-relax.png)
- [小诗渲染参考](after/anime-shino.png)、[小光渲染参考](after/anime-vita.png)
- [最终普通启动的模拟器](normal-simulator.png)

`before` 保存旧渲染参考，`after` 保存新渲染与骨骼幅度记录；场景光比也经过调整，不把它们描述为只改变单个材质参数的严格A/B实验。

## 处理过的问题

旧版普通启动点击在模拟器通过，所以没有断言复现了手机上每一种失败。修复的是已确认的透明区截触、身体动作租约竞争及单击与可禁用识别器的耦合。真机安装失败后，手机实际触摸仍留待连机核验。

官方 Toon 的裁切模式差异曾导致睫毛黑块，补光叠加曾令白发过曝，均经过图片检查修正。Unity图形Editor在构建前着色器重载阶段SIGSEGV，使用已有无图形导出入口恢复；一次错误的UIKit属性调用已移除。另一次XCTest只发现0用例，验证脚本明确失败，枚举后重新实际执行。以上失败没有计入成功验收。

设计、来源与兼容约定见 [方案](../../design/2026-09-29-head-touch-and-anime-refinement.md)；关键开发记录见 [E81](../../development-notes.md)。
