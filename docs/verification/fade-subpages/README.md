# 同一面板中的渐变子页面 · v0.35.0 / build54

角色资料→作者→作品／关注者、资料→定制→各设置、聊天资料→长图统一在原面板中淡入淡出。返回头栏使用同一尺寸与边距，背景由根面板绘制，子页不重复加深背景。角色头像52pt、名字20pt，订阅放名字右侧；定制放简介下方左侧，关注作者只在作者页。会话顶部的小胶囊维持左上角布局。

## 实际页面

- [发现入口的角色资料](simulator/01-role-card-before-author.png)：小头像、名字旁订阅、简介下定制。
- [同一面板内的作者主页](simulator/02-author-works.png)：作者关注与作品列表。
- [会话入口的角色资料](simulator/04a-live-character-profile.png)、[其作者关注者子页](simulator/04b-live-author-followers.png)：返回位置一致，继承同一透明渐变和角色取景。
- [取景](simulator/panel-framing.png)、[角色设定](simulator/panel-profile.png)、[音乐](simulator/panel-music.png)、[聊天资料](simulator/panel-history.png)：统一顶部结构。
- [聊天资料中的长图页](simulator/07-history-export-same-panel-2.png)、[返回后保留搜索](simulator/08-history-filter-retained-2.png)：同一面板内连续两次往返。
- [恢复普通启动](simulator/normal-startup.png)：原会话及左上角小胶囊继续保留。

## 完成结果

六个不同XCTest方法最终均有通过结果，共470.288秒；较早失败轮次另行保留，不计入通过时长。Simulator Debug、Device Release原生构建与严格验签通过，两平台包均为0.35.0 / 54，见[built-apps.json](built-apps.json)。工作区已切回device / Release，模拟器恢复无QA参数的正常会话。

手机一次安装成功，回读星夜0.35.0 / 54，一次自动启动也成功。见[安装](device-install.json)、[手机版本](device-app.json)、[启动](device-launch.json)。交互流程由模拟器验证，本轮手机完成安装与启动，不把进程启动等同于所有真机交互验收。

## 验证范围与错误处理

在 iPhone17 / iOS26.4 模拟器复用六个已有XCTest方法。作者导航新增返回按钮坐标比较（容差1pt）、订阅与名字对齐、角色页无关注作者按钮；聊天资料导出新增连续两次往返、面板头栏和拖动柄坐标保持、搜索词保留与相机六项保持。作者编辑、跨身份发布／订阅／撤回、全部定制子页、键盘、共同记忆、一起、功能预览、长图生成及系统分享取消沿用实际UI流程。

初轮作者作品进入角色后，测试在页面淡入尚未完成时点击订阅，未生效。改为等待作者页离场、目标角色资料与名字就绪后只点一次，再等待保存值；未增加固定sleep或重复切换订阅。修正后该流程通过。

长图往返暴露隐藏历史页仍有辅助访问返回按钮。单纯增加accessibilityHidden／分组边界未能解决；最终保留列表和搜索的挂载，仅在覆盖期间把历史头栏替换成等高空白，使旧返回按钮真正离开视图树。失败轮次保留在本地xcresult，不计为通过。

详细实际测试、构建和设备结果见[result.json](result.json)。原始结果位于`.local/checks/Fade-Subpages-v0350.xcresult`、`Fade-Subpages-Final-v0350.xcresult`、`Fade-Subpages-History-v0350.xcresult`。

仅原生导航与布局调整，无Unity重新导出、依赖新增或数据迁移。系统分享和必要的删除确认仍使用系统组件。本次不扩展iPad、模型动作或持续帧率验收。
