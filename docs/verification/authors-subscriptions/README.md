# 角色订阅与作者关注验证 · 星夜 0.31.0 / 48

已实现本机可用的角色订阅、作者关注、作者资料编辑、公开作品、发现搜索和账号隔离。手机已通过一次无线安装更新，版本回读0.31.0 / 48；自动启动因Locked被拒绝，没有等待或重试。模拟器已恢复普通参数运行，并实际迁移其旧目录为v2、保留v1备份。

## 自动化结果

环境：iPhone17模拟器、iOS26.4，Simulator Debug。下表只列实际执行且通过的结果；早期失败和零用例运行不计为通过。共6个不同XCTest方法，217.791秒，其中1个承载123项数据断言、5条为实际界面流程。

| 验证 | 结果 | 耗时 |
|---|---|---:|
| 新关系、v1迁移、旧集合、账号隔离、游客交接、持久化、权限边界 | 64 + 59 = 123项通过 | 4.677秒 |
| 订阅／作者关注独立，多层返回，首页／消息，模型六项取景保持 | 通过 | 37.414秒 |
| 作者编辑，A发布、B搜索／关注／订阅，A撤回，B失效项移除，重启保存 | 通过 | 77.111秒 |
| 取消当前最后一个订阅，首页／消息空状态，重启不恢复默认订阅 | 通过 | 19.510秒 |
| 发现作者作品进入Luma，再从会话作者页切到小夏，弹层关闭后完成导航 | 通过 | 34.776秒 |
| 原有对话长图入口反复打开、返回、定制聊天资料入口和模型取景保持 | 通过 | 44.303秒 |

核心覆盖：旧followed只迁移到角色订阅、不自动关注作者；显式空列表、原顺序、最近角色；稳定作者ID；新建、更新、撤回、重新公开；不能修改他人作者资料或发布他人角色；已知ID不能绕过私有可见性；不可用订阅可移除；两种关系不互相创建／删除；游客关系交接一次；未知版本和写入失败不破坏原档案。所有临时核心测试在独立目录运行。

取景检查比较distance、framingSize、framingAngle、pitch、yaw、cameraFov六项，并检查framingMotionActive为false。本轮未重新进行逐帧长时间性能采样，不以这些断言代替真机FPS结论。

完整机器结果：[result.json](result.json)；核心输出：[core-results.txt](core-results.txt)。XCTest原始结果目录记录在JSON中：R3的核心与空状态方法通过，两个UI问题在R4复跑通过，Navigation结果包含最终会话跳转及导出入口回归。

## 页面截图

- [角色资料：订阅与作者关注分开](screenshots/13-role-subscription-card.png)
- [作者主页与公开角色](screenshots/12-public-author-profile.png)
- [发现页作者模式](screenshots/11-discover-authors.png)
- [我的：订阅／关注／角色／聊过](screenshots/14-my-independent-relations.png)
- [订阅角色列表](screenshots/15-subscribed-roles.png)
- [自己的作者资料修改后](screenshots/05-my-author-profile.png)
- [另一个身份关注作者后的关注者列表](screenshots/08-local-follower.png)
- [作品撤回后保留可移除的订阅占位](screenshots/09-withdrawn-role.png)
- [未订阅任何角色的首页](screenshots/10-no-subscriptions.png)
- [普通启动，保留已有聊天](screenshots/16-normal-launch.png)

## 构建与交付

- Device Release成功，codesign --verify --deep --strict通过。
- Bundle ID仍为com.gukaifeng.xiaoban.dev，保留现有应用和资料；不是卸载重装。
- 一次安装成功、版本回读0.31.0 / 48，一次启动请求被手机锁定拒绝。手机解锁后可手动打开新版。
- 工作区保留device / Release；模拟器普通参数运行。没有新增iPad测试、真机UI自动化或Unity重新导出。
- 后端仍未部署；公开作品、作者关系及关注者数量来自本机体验身份。没有伪造网络用户、粉丝、通知或同步结果。

## 重跑专项

```sh
zsh scripts/test_companion.sh EFA3B59D-3939-4659-B60B-123516393F43 \
 'AuthorSubscriptionUITests/testCoreMigrationAndSocialContracts(),AuthorSubscriptionUITests/testIndependentRelationshipsAndAuthorNavigation(),AuthorSubscriptionUITests/testAuthorEditingPublicationAndOtherIdentity(),AuthorSubscriptionUITests/testUnsubscribeCurrentRoleShowsPersistentEmptyHome(),AuthorSubscriptionUITests/testAuthorWorksOpenConversationsAfterDismissal()' \
 Author-Subscription-Review
```

结果名应使用新名字，避免覆盖已有xcresult。测试脚本自动切换模拟器工作区；结束后若要用Xcode运行真机，执行`python3 scripts/generate_host.py --platform device`。

设计与迁移见[方案](../../design/2026-09-29-authors-and-subscriptions.md)，尚未部署的服务接口见[契约](../../api/authors-subscriptions-v1.md)，关键错误处理与取舍记录在[开发记录E78](../../development-notes.md)。
