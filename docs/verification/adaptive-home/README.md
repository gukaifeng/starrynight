# 小伴 0.17.0 / 30 · 自适应角色首页

21:25 已无线更新安装到 iPhone 17，回读版本 **0.17.0 / 30** 并自动启动成功；没有卸载或清空数据。见[安装记录](device-installation.json)。workspace 保持 device / Release。

## 本版设计

首页由固定单卡改为按窗口宽高排布的角色画廊。算法优先容纳可读的角色项，再平衡比例，常规手机与 iPad 竖屏为 2 × 2，宽横屏为 4 × 1；窗口不足时减少可见数量并横向分页。分页指示仅在多页出现，仍位于角色区上方。没有纵向滚动或手动模式开关。

卡片以浅桃、浅叶、雾蓝、浅紫区分角色，真实模型头像放在拱形小窗中，使用很轻的浮动、倾转及轻点反馈。进入聊天、后台和减少动态效果时不持续浮动。不是同时运行四个 Unity 模型；没有新图片服务或模型依赖。姓名、短邀请与聊天入口分层，已有会话显示“继续聊”，不伪造在线或未读状态。

## 验证与处理

- 实际生产布局函数完成 9865 条范围/覆盖/分页检查，覆盖不同宽高、角色数量与较大字体布局。数字包含对每个角色页归属的断言，不代表运行了 9865 个 UI 场景。
- iPhone 17 `AdaptiveHome-Phone-03` 完整流程 44.509 秒、1 项零失败：四角色同屏、所有角色打开/返回、头像误触、左右横屏、账号返回。
- iPad Pro 11 英寸 M4 `AdaptiveHome-iPad-01` 完整流程 46.666 秒、1 项零失败：同屏角色、头像点击、返回、左右横屏与账号入口。
- `AdaptiveHome-Phone-01` 中定制头像保存与重启保持单项通过（31.565 秒），但同包首页测试失败，未标整包通过。
- 最终画廊实现的 iPad 四角色完整回归 `AdaptiveHome-iPad-Final` 57.380 秒、1 项零失败；本页 iPad 截图已替换为该轮结果。
- 最终 iPhone 分页专项 `AdaptiveHome-Phone-Pages-05` 17.795 秒、1 项零失败：点选到初音、纵向擦动不打开、横向翻到小乐、进入/返回、横竖屏保留当前角色。较大字体设置使布局减少为每页一个，验证的是实际分页通路，不等同于所有字号排版均已验收。
- 首轮发现标准 Button 在头像上的纵向擦动可能触发点击，导致横屏检查时实际已进入模型页；改用明确的轻点识别和独立轻点反馈，水平滑动与纵向擦动均不触发聊天。第二轮修复一个无障碍闭包的编译调用错误，之后完整流程通过。失败日志保留。

分页前两轮实际已进入多页，但父级无障碍标识覆盖了子按钮，修复为独立容器；其后发现系统吸附与头像手势组合不能可靠翻页，移除原零距离手势，分页改为显式水平偏移与轴向判定，一次最多一页、边缘弱回弹，保留独立轻点反馈。最终实测通过，失败结果仍保留。测试辅助代码也等待整张聊天入口进入屏幕后再操作，避免在点页动画中取半途截图。

本次只改原生首页与布局，沿用已经通过 portraitRevision 1 校验的 Unity 导出。没有改模型动作、镜头或语音库，也没有测量真机持续帧率。

## 实际截图

[手机竖屏](01-phone-portrait.png) · [手机横屏](02-phone-landscape.png) · [iPad 竖屏](03-ipad-portrait.png) · [iPad 横屏](04-ipad-landscape.png) · [多页状态](05-paged-home.png) · [旋转后保持所在页](06-page-restored-landscape.png)

原始日志和结果包保存在 `.local/logs/AdaptiveHome-*.log` 与 `.local/checks/AdaptiveHome-*.xcresult`。复现：

```bash
zsh scripts/test_companion.sh SIMULATOR_ID HomeCarouselTests/testFixedHomePagingSelectionAndNavigation AdaptiveHome-Repeat
xcrun swiftc -swift-version 6 -module-cache-path .local/build/SwiftModuleCache ios/CharacterHost/Features/Home/CharacterHomeLayout.swift scripts/tests/CharacterHomeLayoutTests.swift -o .local/checks/character-home-layout-tests
.local/checks/character-home-layout-tests
```
