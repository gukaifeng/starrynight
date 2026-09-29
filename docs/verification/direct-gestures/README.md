# 直接手势验证 · 小伴0.6.2 / build10

2026-09-28。XCTest向真实Unity视图发送拖动和双指触摸，从Unity事件读取角度、大小和头部命中次数；不是只检查按钮文字。

| 设备 | 完整流程 | 结果 |
| --- | --- | --- |
| iPhone17隔离模拟器 | 拖动到边界、反向、放大／缩小、精细面板同步与取消、背景输入锁定、重启恢复、聊天滚动隔离、面板修改后继续拖动、头部点击恢复 | 通过，51.547秒，0失败 |
| iPad Pro11 M4模拟器 | 同一流程，另验证横屏旋转后拖动 | 通过，54.147秒，0失败 |

证据包：`.local/checks/DirectGestures-Phone-2.xcresult`、`.local/checks/DirectGestures-iPad-1.xcresult`。版本与结果见 [results.json](results.json)。常用iPhone模拟器首轮出现脚本首个手势之前的额外输入，失败记录保留；最终在独立设备验证，未放宽正确性断言。

手机四次拖动／缩放后，实际角度约−12.31°、大小90%，头部误触0次；重启恢复相同值。见 [动作后的画面](iphone17/01-direct-gesture.png)、[引擎事件](iphone17/01-direct-gesture-runtime.json)以及[重启后的事件](iphone17/02-restored-gesture-runtime.json)。

平板横屏后的实际效果：[画面](ipad-pro-11/04-ipad-landscape-gesture.png)／[引擎事件](ipad-pro-11/04-ipad-landscape-gesture-runtime.json)。

## 本轮范围

保留±20°角度及90%–110%大小范围，直接手势与精细面板共用参数。没有修改角色资产品质或增加逐帧存盘。没有在本轮进行真机帧率实测；模拟器触摸验证不等于真机性能验证。

0.6.2/build10设备Release构建与深度签名验证通过，本轮未安装到手机。常用iPhone17模拟器已安装新版并以普通模式打开小夏；workspace保留device配置。
