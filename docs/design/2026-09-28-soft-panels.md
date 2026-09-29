# v0.8.2：弹层与角色共同缓动

## 问题

用户在真机上仍感到取景打开时模型突然缩小。此前检测只证明没有显式Snap，不能说明观感足够柔和：旧布局弹簧response=0.76，其95%主要行程约0.42秒，屏幕上的大幅缩放过快。相同取景参数的配置消息还可能把尚未结束的布局动画切到0.30秒控制响应。UIKit pageSheet自身拥有不透明底板与呈现变换，需要从展示路径一起处理。

## 统一设计

沿用暖白#F7F5F0、墨绿#274A43、浅玉#B8D5C5、绿灰#5B7168与现有系统字体。角色和房间继续铺满屏幕，弹层像一层由上至下变浓的薄雾：顶部18%不透明，中段66%，底部94%；标题／关键控件自带局部衬底确保可读。背景改变，文字和控件不整体透明。

- 原生取景／定制用公开UIPresentationController自定义呈现，透明背景，0.9秒阻尼弹簧滑入／淡入。底层Unity不被系统卡片缩放、不移除、不以截图代替。保留取消、完成、上拉展开、下拉关闭与辅助功能高度操作。
- Unity布局弹簧response=1.6、阻尼0.76，主要行程约0.8秒、一次轻微回弹，保留位置与速度；动作／手势维持原本独立响应。重复同值配置不得把未结束的布局过渡加速。状态回执等到收稳，最多4秒。
- SwiftUI音乐、空间工具、角色设定、记忆、历史、账号、关于也通过SoftSheetPresenter接入同一套自定义展示和SoftPanelBackground。只设置presentationBackground时，实拍仍有白底，因此最终统一容器。导航容器用iOS18+的containerBackground清底，列表隐藏系统底色、行保留局部衬底。弹层出现时聊天控件淡出，只让模型和房间透出来，关闭后聊天淡入；不改变模型构图。Sheet内文字导航继续系统或局部交叉淡入动画。
- 主页面、登录与加载沿用已有渐变和淡入淡出；系统键盘、菜单、分享与确认框保留系统的材质、交互和动画。降低透明度时采用实底，减少动态效果时原生弹层用短淡入淡出。

## 验证方式

扩展Unity数学验证：布局开始250ms只走20%–40%，750ms仍处于主要行程末段，一次受限回弹、精确收稳；108组构图求解继续验证。iPhone与iPad复用真实取景／定制／键盘／后台恢复／拖拽关闭及展开流程，补拍所有应用弹层。检查实际录屏连续帧及镜头采样，不能只用“无Snap”推导观感。签名构建、安装与启动分别记录。

参考技能：项目[Unity CLI](../../.agents/skills/unity-cli/SKILL.md)、frontend-design、缓存swiftui-pro。官方接口：[Apple presentationBackground](https://developer.apple.com/documentation/swiftui/view/presentationbackground(alignment:content:))。

实现期间的实际问题：Swift严格并发要求关闭动作声明为@MainActor @Sendable；自定义SwiftUI桥必须在updateUIViewController同步读取Binding，否则只在异步闭包读取会遗漏状态依赖、按钮不弹层。两项均由实际编译／UI用例暴露并修复，保留失败结果。
