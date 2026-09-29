# 会话输入、手机取景与动态空间 · 0.36.0 / 55

本轮交付四项：空白轻触收键盘但保留草稿；以实际窗口安全区避开角色头顶遮挡；六套角色配套空间细节与局部动态；作者与角色资料使用同一小头像／名字／关系按钮布局。

## 内容检查

- [十角色安全区投影](safe-area-projection.json)：40组模型／窗口，82,560个角点投影，9,600个连续转动采样。测试覆盖顶部遮挡、侧边遮挡、不同尺寸、两种取景与缩放转角极值；检查竖屏用户距离不变、重复布局无漂移、初帧最终构图。最小误差约-4.77e-7（浮点误差，容差2e-5）。不把测试窗口当作硬编码设备表。
- [六套背景几何与运动](environment-motion.json)：16～68个Renderer、9,680～51,162顶点、3～14个动态节点。实际采样3秒，窗帘最大下摆位移约2.4cm、植物转角约0.82～1.35°，帘顶固定；隐藏后局部时间停止，原配色与净空绑定通过。
- [生成素材与散列](generated-art.json)：三张1536×1024远景以内置imagegen制作，保存工程；完整提示见[生成记录](../../../unity/CharacterRuntime/Assets/EnvironmentArt/generation.json)。导入保留非二次幂原始尺寸，iOS ASTC6×6与mipmap；不同窗型单独材质，按比例裁切，不拉伸。

Unity Simulator、Device两份导出均已完成，目录散列一致，framingProtocol均为8，包含10角色、6背景与40项角色范围音频，见[导出一致性](export-consistency.json)。签名与安装最终状态在结果段单独记录，不把内容检查作为真机持续帧率验证。

## 关键修正

- 保留输入区真实几何，背景手势只解除焦点，设置不取消、不延迟原触摸；完整输入／语音／发送区及原生控件排除，模型触头可同时识别。
- 把手机窗口安全区单独送入Unity，键盘、弹窗及聊天高度不进入安全边界。先约束目标，再约束实际弹簧帧；仅做必要相机补偿，保留用户偏好。framingProtocol升8，拒绝旧导出。
- 角色和作者用同一个52pt头像、20pt名字、名字旁28pt视觉／44pt点击关系按钮组件，减少两页后续尺寸漂移。
- 生成前审查修复了海边可换色Surface为空、庭院跨中心网格合并导致净空包围盒误报；保留真实净空校验。水面、帘布、植物节点显式排除静态合并。
- 远景图片先补按比例裁切，再修正Unity默认非二次幂重采样会提前拉伸图片的问题。最终图片尺寸与裁切按原始3:2处理。
- 首轮缩略图露出有限场景边缘，改为正对场景、固定3:2比例与38°视角，重拍空间缩略图；实际会话使用独立的安全取景。

设计详见[本轮方案](../../design/2026-09-29-safe-portrait-and-living-scenes.md)、[安全取景](../../design/2026-09-29-safe-area-framing.md)、[配套空间](../../design/2026-09-29-refined-environments.md)。不新增在线服务，不测试iPad。系统减少动态偏好尚未跨接Unity背景，App隐藏／暂停则停止背景更新。

## 实际手机窗口与交互

- iPhone 17模拟器：作者／角色统一身份栏102.798秒，空白收键盘／草稿保留／头触与发送38.305秒，原有真实头触／拖拽／双指缩放42.088秒，初音及优可最终场景安全区取景37.230秒，均通过。
- iPhone 17e模拟器：最终场景实际窗口安全取景37.380秒，八类面板、键盘及菜单的相机稳定163.896秒，均通过。实际UIKit窗口分别402×874pt／顶部62pt和390×844pt／顶部47pt；引擎安全边界分别72pt和57pt，留10pt额外头顶空间，不靠缩小角色避让。
- [初音实际会话](simulator/safe-frame-default.png)、[17e优可实际会话](simulator-17e/safe-frame-uka.png)、[角色资料](simulator/04a-live-character-profile.png)、[作者资料](simulator/04b-live-author-profile.png)、[收键盘后保留草稿](simulator/keyboard-blank-dismiss-keeps-draft.png)。

实际会话复核进一步修复小院：原GLB地面缺UV，材质替换无法显纹理；现为独立网格生成米单位UV，构建断言长度、跨度与顶面面积。低石沿及九组错落植物衔接远景，作为结构保留，关闭可选摆设不再露直线接缝。原模型和镜头不变，重新生成两端场景并验证。

## 验证过程中修正的测试问题

环境UI首轮把AX中的桥接快照当连续帧数据，静置后ambientTime不再刷新而超时。随后两次真实头触采样间隔不足1.8秒，第二次被既有动作去重拒绝；最后还发现nativeHeadHit读取到了弹层打开时的缓存。最终采样用真实资料往返后的一次头触刷新事件，再检查命中与时间推进，不改生产行为，不新增轮询或放宽动态阈值。早期三批失败xcresult与日志均保留于.local/checks及.local/logs，最终环境通过结果单独记录。

## 最终环境流程

- 室内、重启及跨角色隔离98.704秒通过：初音静夜→柔光影棚、灰绿配色／关闭摆设→重启保留→Luma影棚原配色／摆设开启→小院→回初音仍保留其影棚定制。
- 日间、花园及海边93.938秒通过：小夏晴日客厅→花园粉色／关闭摆设→海边默认配色／摆设开启→返回花园恢复原配置。普通会话内确认窗帘／植物／水面的背景时间真实推进。
- 共选择8次有效执行（7个不同方法，含两种手机窗口的同一安全取景用例），累计614.339秒；最终环境批2项0失败。各项对应日志、xcresult路径与历史失败标识见[result.json](result.json)。
- 实际效果：[静夜](simulator/environment-01-evening-conversation.png)、[晴日客厅](simulator/environment-07-sunroom-conversation.png)、[花园](simulator/environment-08-personalized-garden-conversation.png)、[海边](simulator/environment-09-seaside-conversation.png)、[Luma小院](simulator/environment-05-courtyard-conversation.png)、[普通启动](simulator/normal-launch.png)。

空间卡片和图像的裁剪区域补明确contentShape，验收先检查原生卡片已选择再确认引擎切换；完整两条环境路径实际通过。普通启动不带QA参数，17e模拟器恢复关闭。

## 构建与交付

Simulator Debug、Device Release均为星夜0.36.0 / 55，严格验签通过，见[built-apps.json](built-apps.json)。手机一次安装成功，回读确认0.36.0 / 55；一次自动启动被系统Locked拒绝，不等待、不重试。用户解锁后可自行点开已更新的星夜。此次未执行真机交互或持续帧率验收，未测试iPad。

[手机安装](device-install.json)、[仅本App的版本回读](device-app.json)、[启动拒绝](device-launch.json)分别保留。Xcode工作区为device / Release，原应用标识和资料保留；iPhone 17模拟器恢复正常无测试参数启动。[约12秒待机效果录像](simulator/normal-idle.mp4)为实际模拟器无声录屏，预览高1280px；完整分辨率原文件留在.local/checks/immersive-normal-idle-original.mp4。
