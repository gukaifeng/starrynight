# 立绘角色与胶囊留白 · v0.34.0 / build52

新增优可、维拉、安宁三个独立 3D 角色，发现页搜索名字即可进入。iPhone 17 模拟器验证通过，Device Release 已签名、安装到用户 iPhone，并回读版本 0.34.0 / 52。一次自动启动被系统以 Locked 拒绝；没有继续解锁询问或重试，也没有把安装成功写成真机交互／帧率验收。

## 实际画面

下面均为 App 的真实模拟器截图：

| 角色 | 默认会话 | 资料页 |
| --- | --- | --- |
| 优可 | [近景与顶部胶囊](simulator/anime-uka-portrait-idle.png) | [打开资料时保持取景](simulator/anime-uka-profile-camera-kept.png) |
| 维拉 | [近景与顶部胶囊](simulator/anime-velara-portrait-idle.png) | [打开资料时保持取景](simulator/anime-velara-profile-camera-kept.png) |
| 安宁 | [近景与顶部胶囊](simulator/anime-onyx-portrait-idle.png) | [打开资料时保持取景](simulator/anime-onyx-profile-camera-kept.png) |

身份胶囊头像仍为32pt，水平内容间距10pt、左侧10pt、右侧16pt、上下8pt。透明度、语音波纹和48pt原生触控区域保留。

## 已完成验证

- 新内容3项、原二次元内容2项测试通过。最终GLB检查覆盖三个角色各9段动作，脚底世界坐标漂移为零，四元数与表情端点连续；Uka袖代理和手臂的世界位置最大误差0.0361mm。原始挥手腕部角速度尖峰818°/s经协同平滑降至191.57°/s。
- Unity图形检查通过：三角色实际头部／发梢变化存在，主光软阴影开启，VRM眼镜连续透明。保留原始法线、MatCap与发丝emission；源图最高4K，导入采用ASTC与mipmap，不虚构低分辨率素材的精度。
- 两平台Unity导出均0错误，10角色与角色／环境catalog哈希完全一致，nativeGestureRevision 2、framingProtocol 7。Simulator Debug与Device Release构建通过，真机包通过`codesign --verify --deep --strict`。
- `IllustrationPortraitTests/testIllustratedCharactersSearchGreetAndReactToRealHeadTouches()`：117.488秒通过。发现搜索→资料→三角色会话→首次问候→真实语音播放→停止→真实屏幕摸头→资料往返，相机不变。锁定取景时实际头部响应峰值采样8.21°～8.25°，超过8°才通过；这不是仅检查点击事件计数。
- `IllustrationPortraitTests/testSavedFramingSurvivesCharacterSwitchesAndProfilePresentation()`：83.297秒通过。给优可设110%大小及右转20°，切换其他角色保持独立设置，经消息返回后恢复优可取景，打开和关闭资料不改变相机。
- 两条实际UI流程合计200.785秒、0失败。没有新增QA运行时接口，没有把0用例或未执行项目记作成功。原始结果在`.local/checks/Illustrated-Portraits-v0340.xcresult`；导出截图与runtime JSON在本目录`simulator/`。
- 一次无线安装成功，回读星夜0.34.0 / 52。一次启动返回CoreDevice10002，内层原因Locked；就此结束手机操作。模拟器恢复不带测试参数启动，保留用户原会话；Xcode工作区维持device / Release。

## 证据与边界

[内容审查](illustrated-character-audit.json)、[动作修复对比](portrait-motion-refined.json)、[材质恢复](portrait-emission-audit.json)、[Unity运行时内容](runtime-content.json)、[原生摸头结果](head-touch-results.json)、[平台一致性](platform-content.json)、[App版本](built-apps.json)、[安装](device-install.json)、[版本回读](device-app.json)、[启动被锁定拒绝](device-launch.json)。

这是二次元立绘风格的移动端渲染与有约束的骨骼／发梢运动，不是完整皮肤、布料或流体物理模拟；未承诺所有组合姿势零穿插。目标120fps配置保留，本轮没有真机持续60/120fps测量，也没有iPad测试。

优可源素材按CC-BY4.0使用并保留规定署名；维拉与安宁只供当前个人原型预览，不可随公开版本或公开源码再分发，也不开放原美术外观改作。原作者、固定来源与独立NOTICE已进入App离线署名，详见[方案与来源](../../design/2026-09-29-illustrated-portraits.md)及[署名验证](illustrated-portrait-attribution.json)。
