# v0.8.1：半屏聊天与长距离渐变

## 设计与关键决策

- 延续小伴的暖白 #F7F5F0、墨绿 #274A43、浅玉 #B8D5C5、次级绿灰 #5B7168；保持现有系统字体、消息与输入框样式。此次重点是让角色与聊天共享画面，通过透明度变化形成边界。
- 普通聊天区从“屏高34%，且最多320点”改为屏高50%；由消息列表获得增加的高度，输入框和功能按钮不放大。3D仍全屏渲染，聊天高度不改变相机构图。
- 底部遮罩从聊天区上方16点开始，到屏底缓慢增加至80%不透明度。采用17个等距采样点逼近 smoothstep(t)=t²(3−2t)，首尾斜率缓和；原方案在渐变长度34%处已经达到48%不透明度，新的同一比例约21%。
- 消息列表上沿的淡出由高度7%扩至26%（最大80点），采用缓入缓出的多段透明度；保留大部分消息区域完全可读，无滚动条。“回到最近”提示淡入淡出。
- 键盘弹出时按剩余可用高度分配更多历史空间，跟随系统动画曲线。iPad横屏键盘继续靠右显示聊天。编辑面板仍淡出聊天、沿用原有镜头弹簧；遮罩从当前presentation值继续动画，连续打断不直接跳到新值。
- 延续“减少动态效果”“降低透明度”适配，无新增模糊滤镜、图片或运行依赖；本轮不修改Unity导出。

技能参考：[frontend-design](/Users/gukaifeng/.codex/skills/frontend-design/SKILL.md)、项目缓存的Paul Hudson swiftui-pro。渐变位置和颜色使用Apple提供的可动画属性：[CAGradientLayer.locations](https://developer.apple.com/documentation/quartzcore/cagradientlayer/locations)。

## 验证

实际iOS XCTest五项通过，0失败；原始结果分别在 `.local/checks/ChatFade-Phone-1.xcresult` 与 `.local/checks/ChatFade-iPad-1.xcresult`。

| 项目 | iPhone 17 | iPad Pro 11 M4 |
| --- | --- | --- |
| 多轮聊天、历史滚动、键盘、静夜背景（iPad含横屏） | 30.923秒，通过 | 38.809秒，通过 |
| 键盘→面板、预览／取消、后台恢复草稿、下拉／展开、音乐／空间弹窗 | 59.536秒，通过 | 72.111秒，通过 |
| Luma／初音头部点击与无遮挡 | 20.322秒，通过 | 本轮未重复此项 |
| 竖屏聊天区高度 | 437点／874点屏高＝50% | 605点／1210点屏高＝50% |
| 多轮对话时消息列表可用高度 | 241.33点 | 409点 |

高度来自UI自动化读取的实际布局；正常字号、未弹键盘时测量。消息显示条数取决于文本长度和字体大小。测试验证扩大后的历史滚动不会转动背后模型，最新消息可返回；脸部点击及全屏房间继续可用。

界面回归的真实镜头采样分别1974／2384条，均保持全屏渲染、FOV35°、额外显式相机Snap为0；`verify_interface_motion.py` 全部通过。截图与连续帧目视检查没有发现渐变硬边或面板恢复时的跳变；这不是所有设备／所有界面的绝对保证，也不作为真机FPS测试。

- [iPhone多轮聊天](iphone17/conversation/03-conversation.png)、[向前翻历史](iphone17/conversation/03a-earlier-messages.png)、[静夜背景](iphone17/conversation/04-night-conversation.png)
- [iPad竖屏](ipad-pro-11/conversation/03-conversation.png)、[横屏](ipad-pro-11/conversation/05-ipad-landscape.png)、[横屏键盘](ipad-pro-11/conversation/06-ipad-landscape-keyboard.png)
- [约46秒实际模拟器过渡录像](iphone17/interface-transitions.mp4)，只截取和压缩、未变速，不作为实际FPS证明。

## 交付

真机Release签名构建、深度验签、安装完成。设备App列表确认小伴 `com.gukaifeng.xiaoban.dev` 为 **0.8.1 / build15**；用户资料保留。手机锁屏导致自动启动被系统拒绝，未将安装成功算作真机交互通过，解锁后点击小伴即可体验。

普通iPhone 17模拟器也安装并启动0.8.1，按正常登录状态展示；QA模拟器关闭，workspace保留device配置。
