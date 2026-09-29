# v0.8.2：透明弹层与舒缓取景

## 实际结果

已将0.8.2 / build16安装到既有小伴，设备列表核实版本。手机锁屏导致自动启动被拒绝，用户解锁点击图标即可。本轮真实互动、动画与截图验证在iPhone 17／iPad Pro 11 M4模拟器完成，不将签名安装当作真机动态验证。

取景／定制镜头使用1.6秒response、0.76阻尼的连续弹簧；response不是完成时间。真实iPhone采样：250ms走28.51%的对数缩放行程，833ms首次到95%，峰值102.54%后收稳；iPad对应267ms走25.09%、850ms到95%。没有发生额外显式Snap。控件小幅调整及模型动作继续使用各自响应。

## 界面覆盖

| 界面 | 最终行为 |
| --- | --- |
| 取景、真人定制、背景／灯光 | 透明自定义面板，弹簧滑入／淡入；镜头留足过渡，取消／恢复／上下拖动连续；底层Unity不参与系统卡片缩放 |
| 音乐、我们的空间 | 相同透明展示组件，模型与房间透出；背后聊天控件淡出避免两层文字重叠，关闭后淡入 |
| 塑造角色、共同记忆、聊天与资料 | 透明导航容器和渐变底层，局部行衬底保留清晰文字；保留保存、取消、搜索和原有数据行为 |
| 我的账号、关于及来源／许可页 | 使用同一展示组件和背景；账号共享身份、退出与重新登录回归通过 |
| 首页、登录、加载／错误 | 保留原有品牌渐变和页面淡入淡出，没有另套弹窗缩放 |
| 系统键盘、菜单、分享、确认框 | 保留系统交互、动画和材质，不替换系统权限／分享流程 |

以上实际设备OS为iOS26.4。透明导航使用iOS18+的公开containerBackground；旧系统回退原生导航背景。降低透明度时回退实底，减少动态效果时原生弹层缩短为淡入淡出。设计和实现范围详见[方案](../../design/2026-09-28-soft-panels.md)。

## 最终验证

| XCTest | iPhone 17 | iPad Pro 11 M4 |
| --- | --- | --- |
| 三种登录、共享资料、持久会话与退出 | 54.200秒，通过 | 本轮最终未重复此项 |
| 空间工具→记忆／设定／历史，账号与关于 | 28.801秒，通过 | 29.223秒，通过 |
| 取景／定制、键盘、草稿后台恢复、取消／恢复、下拉关闭、上拉展开、音乐／工具 | 66.482秒，通过 | 80.665秒，通过，含横屏 |

最终五项0失败。原始结果：`.local/checks/SoftSheets-Phone-Final.xcresult`、`.local/checks/SoftSheets-iPad-Final-2.xcresult`。首轮另外验证了沉浸聊天／多轮消息／背景切换，iPhone31.642秒、iPad36.689秒；这两项属于早期构建，不冒充最终轮结果。

镜头采样iPhone2236帧／iPad2687帧，全程全屏渲染、FOV35°、额外显式Snap为0。新增`verify_panel_easing.py`检查真实打开过程的250ms进度、到达95%的时间、回弹幅度，避免“没有Snap就算足够柔和”的弱验收。原有108组构图求解及动作弹簧30／60／120Hz数学检查继续通过。本轮不作真机持续FPS结论。

## 图片与录像

- [iPhone取景](iphone17/InterfaceMotionTests/03-preview.png)、[定制](iphone17/InterfaceMotionTests/07-studio-body.png)、[打开过程连续帧](iphone17/opening-frames.png)
- [透明空间工具](iphone17/AtmosphereFlowTests/11-space-tools.png)、[角色设定](iphone17/AtmosphereFlowTests/13-profile-surface.png)、[记忆](iphone17/AtmosphereFlowTests/12-memory-surface.png)、[历史](iphone17/AtmosphereFlowTests/14-history-surface.png)
- [账号](iphone17/AtmosphereFlowTests/15-account-surface.png)、[关于](iphone17/AtmosphereFlowTests/16-about-surface.png)
- [iPad取景](ipad-pro-11/InterfaceMotionTests/03-preview.png)、[横屏恢复](ipad-pro-11/InterfaceMotionTests/11-landscape-restored.png)
- [最终版28秒真实过渡录像](iphone17/panel-transitions.mp4)：取景与拖动、恢复、音乐、工具；截取及压缩，未变速。另保留[首轮打开取景片段](iphone17/framing-opening-first-review.mp4)，其中顶部点击区域还未加高，不作为最终界面截图。

## 重要修正

首轮功能检查通过后，截图发现SwiftUI系统弹层和NavigationStack仍有白底，不能算透明验收通过。最终把应用弹层统一到公开UIPresentationController，并用导航容器背景接口清除白底。透明后又发现聊天文字重叠，因此补充背后聊天层的淡出／恢复。

桥接关闭动作需要@MainActor @Sendable，初次严格并发编译失败后修正。Binding若只在异步闭包读取，SwiftUI可能不跟踪开关依赖，实际UI测试暴露按钮未弹窗；改为同步读取状态后再安排呈现。失败结果保留在SoftSheets-Surfaces-Phone-2／3，修正后4及最终轮通过。

iPad一次test-without-building执行到了旧版本断言（期待revision1，而源码及引擎均为2），未计作通过；清除QA测试运行器并完整编译后最终两项通过，未删除用户App或资料。安装、版本查询与锁屏启动失败分别记录在`.local/checks/soft-panels-device-*.json`。
