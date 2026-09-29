# v0.7.2 / build13 界面过渡验收

2026-09-28。修正弹窗让位、恢复、键盘和前后台切换导致的模型突变；构图协议升级到5。

## 验收结果

| 场景 | 结果 |
| --- | --- |
| Unity 偏心构图数学检查 | 108种宽高比／尺度／角度／区域组合，全部通过 |
| iPhone 17 界面完整流程 | 58.913秒，1项通过，0失败 |
| iPad Pro 11英寸 M4 界面完整流程 | 74.844秒，1项通过，0失败，含横屏键盘及面板恢复 |
| 三角色动作连切、自动恢复 | 44.438秒，通过 |
| 直接旋转／缩放、保存、精细面板及点击分离 | 49.693秒，通过 |
| Unity Simulator／Device 导出 | 均通过，framingProtocol=5 |
| 真机 Release 构建、深度验签与安装 | 通过；安装后查询确认0.7.2/build13 |

界面流程实际操作了：输入时打开面板、近景／全身切换、后台恢复未保存草稿、恢复推荐／取消、外观身形和面容切换、下拉关闭、展开大面板再关闭、音乐和空间弹窗。每次恢复验证保存的取景、镜头距离及可交互状态；关闭编辑器后键盘保持收起。

## 连续性证据

- iPhone采集1999个真实镜头状态，657个处于过渡中；iPad采集2340个，782个处于过渡中。两者全程renderViewport=(0,0,1,1)、FOV=35°、额外显式Snap次数=0。
- [iPhone采样断言](iphone17/continuity.json)、[iPad采样断言](ipad-pro-11/continuity.json)。同目录保留完整layout-motion.jsonl和Unity事件，非截图推算。
- [实际iPhone模拟器录屏](iphone17/interface-transitions.mp4)，约58秒，包含键盘、编辑、恢复和弹窗。仅裁掉开头系统桌面并压缩大小，没有重排或加速动画。
- [聊天页](iphone17/01-conversation.png)、[取景预览](iphone17/03-preview.png)、[恢复草稿](iphone17/05-resumed-draft.png)、[关闭弹窗后](iphone17/09-popups-restored.png)。
- [iPad横屏输入](ipad-pro-11/10-landscape-keyboard.png)、[iPad横屏恢复](ipad-pro-11/11-landscape-restored.png)。
- 测试包、版本及数值索引：[results.json](results.json)。

物理渲染面积不再跟随sheet瞬变。状态采样只在显式QA参数下启用；正常启动没有每帧桥接／写盘。这里验证连续性与行为回归，没有重测真机持续FPS，也不把60fps编码录屏当成设备实测帧率。

## 发现与处理

第一轮基础流程在iPhone和iPad都通过，但录像暴露旧输入焦点在弹窗关闭后自动恢复，导致键盘再出现一次。新增“恢复后键盘隐藏”的断言；第二轮仅将SwiftUI FocusState设为false仍失败。最终在原生编辑期间禁用聊天输入，并在关闭完成时同步焦点，第三轮iPhone、第二轮iPad全部通过。保留失败xcresult，未将旧通过结果冒充最终结果。

实现决策见[界面动画方案](../../design/2026-09-28-interface-motion.md)，关键问题归档开发记录E40。

## 交付状态

已更新安装到配对的iPhone17（原有小伴Bundle ID与用户资料保留）。手机锁屏使自动启动被系统拒绝，未将安装成功当成真机启动／肉眼验证成功；解锁点击图标即可。普通iPhone17模拟器已更新并打开小夏聊天，QA模拟器关闭，workspace保持device配置。
