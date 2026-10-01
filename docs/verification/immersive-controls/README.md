# 封面、紧凑界面与开发者工具验收

2026-10-01，星夜 0.75.0（102）。实现范围见 [设计记录](../../design/2026-10-01-immersive-controls-and-developer-tools.md)。沿用已有资源，没有新增收费的图片、配音或对话生成测试。

## 已完成的验证

| 范围 | 结果 |
| --- | --- |
| 封面几何 | 11 个角色、288 项断言通过：圆形头像完整头部、不同宽高封面无未覆盖边缘、可容纳时头部在容器内；含 358/520 宽资料比例 |
| 语音状态 | 56 项顺序/恢复/修改/落区检查通过，增加取消前后识别完成、区域切换、退出取消区后普通发送 |
| 语音真实 UI | 4 项 iPhone 17 模拟器 XCTest 全通过，44.200 秒：提前识别后松手编辑、上滑取消保留键盘草稿、识别中断保留文字、横屏键盘编辑与发送 |
| 页面完整流程 | `ImmersiveRefinementTests/testDiscoveryDeveloperPagesAndConversationControls` 78.575 秒通过：弹窗两侧边距、声音滑块、氛围五档与保留、取消/重新订阅、角色手动表现移入开发页、设定分区各自显示、待机场景预览、空记录说明、发现首屏至少六个可点击角色、应用开发页 |
| 最终封面截图 | 改为 1.2:1 资料比例后单独通过 `testFullCoverProfileAndArrival`，复查资料大图和真实首次 Unity 加载背景，两侧完整填充，琪宝帽子与面部可见 |
| 服务端检查页 | 5 条 pytest 全通过：完整原文、账号/角色隔离、默认关闭/鉴权、请求原文不泄露认证头、四种场景上下文确有区别但人格设定共享；检查不增加 usage |
| 原生构建 | 开发 Debug 模拟器与签名 Release iPhone 构建通过，Unity v14 资源完整性及 33 组包内开场检查通过 |
| 真机交付 | iPhone 17 安装、启动成功；设备查询返回 `com.gukaifeng.xiaoban.dev`，0.75.0，构建 102；深度签名验证通过 |
| 分发隔离 | 使用 `--distribution` 的模拟器 Release 完整编译通过；构建产物及工程检查确认没有开发者编译标记、页面源引用、ClientAIRules 私有资源、开发者页面/手动表现视图二进制符号 |
| 归档保护 | 含 `STARRY_TEST_TOOLS` 的 Archive 脚本返回明确错误，不能意外归档开发工具 |

UI 中的设定内容切换用显式模拟器夹具检验，实际服务端分区内容和费用隔离由 Python 测试验证；未把夹具当成真实百炼生成结果。氛围档位迁移和持久化也在语音 UI 使用的隔离资料夹具中验证。旧的动作测试入口已迁移到开发者页，整个测试目标编译通过，未重跑全部历史动画用例。真实手机本轮确认安装及进程启动，没有进行逐页手动点击、120 FPS 或温控采样；本轮未做新的 iPad 真机测试。

## 发现并处理的问题

- 原有补边使用暗化模糊图及左右 mask，去掉后真正填满。初版短横幅只显示大帽子、脸被裁掉；截图审查后改为 1.2:1，并为极窄窗口下移裁切焦点。
- 胶囊加入独立订阅点击区后，原 UIKit 按钮与新 SwiftUI 按钮都暴露了相同的无障碍 ID。隐藏旧布局锚点，将 QA 运行时数据传给真正可操作的资料按钮。
- 旧的取消订阅回调会关闭当前会话，导致新胶囊的未订阅状态无法出现。取消订阅现在不打断眼前会话，下一次首页导航仍依据订阅列表。
- 开发者动作页返回时旧窗口缩放动画仍在进行，紧接着点击检查入口会点空。开发者子页面保持统一高度，动作页只做页面内切换。
- macOS 系统 Bash 3 在 `set -u` 下展开空数组失败。构建参数改为始终含平台参数的非空数组，开发与分发两种命令均可执行。

以上失败的测试结果保留在本机，不删除或隐藏失败证据。

## 本机证据

- `.local/checks/ImmersiveRefinements-A/B/C.xcresult`：修复过程中的失败与语音成功记录。
- `.local/checks/ImmersiveRefinements-D.xcresult`：完整页面流程通过及 12 张附件截图。
- `.local/checks/ImmersiveVoice-Final.xcresult`：最终 4 条语音触摸/键盘用例通过。
- `.local/checks/ImmersiveCover-Final.xcresult`：最终资料封面与加载页截图。
- `.local/checks/ui-refinements-device-final2-build.log`、`ui-refinements-device-install.json`、`ui-refinements-device-launch.json`、`ui-refinements-device-app.json`：签名构建、设备安装启动与版本核对。
- `.local/checks/ui-refinements-distribution-build.log`、`distribution-isolation.txt`：分发构建和实际产物隔离检查。可用 `scripts/check_distribution_app.py` 复跑；验证后模拟器工程已恢复为日常开发配置。
- `.local/checks/developer-archive-guard.txt`：开发构建归档保护结果。

角色截图、原始检查报告及构建大文件仅保留本机，不推送公开仓库。
