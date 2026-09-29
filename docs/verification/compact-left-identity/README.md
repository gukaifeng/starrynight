# 左上角小胶囊 · 0.34.1 / build53

会话头像与名字胶囊按0.875比例缩小：头像32→28pt、字体16→14pt、视觉高度48→42pt，内边距／间距／细边线与阴影同步缩小。胶囊放在安全区左侧16pt，视觉顶部距安全区约9pt，颜色与透明度沿用月白等现有主题。

原生点击高度保持48pt，宽度按实际名字及内边距计算，并约束在安全区内，避免将原先居中的宽按钮搬到左侧后留下不可见的模型触摸阻挡区。SwiftUI视觉层继续不接收点击，真实按钮仍进入原资料卡。非会话浏览态保留原有居中约束及返回按钮；切换时先停用旧约束，再启用当前模式约束。

没有修改Unity或角色包，没有重导模型。复用现有`CharacterIdentityTests/testProfileDiscoveryAndHeaderNavigation()`验证真实点击、资料→定制→返回、发现切换角色与相机不变。首轮41.129秒通过；约束切换顺序修订后的最终版本41.201秒通过，1个不同XCTest方法、0失败。Simulator Debug、Device Release及严格验签通过，两包版本0.34.1 / 53。一次手机安装成功并回读版本；一次自动启动因Locked被拒绝，无重试。模拟器恢复普通启动，工作区device / Release。


[普通启动实际截图](simulator/normal-startup.png) · [初音胶囊与播放波纹](simulator/identity-capsule-header.png) · [Luma胶囊](simulator/identity-round-header.png) · [资料关闭后](simulator/identity-capsule-after-dismiss.png)。

[安装记录](device-install.json)、[版本回读](device-app.json)、[启动结果](device-launch.json)、[两平台版本](built-apps.json)。
