# 固定角色、封面和专属音乐验收 · 0.37.0 / 56

已完成7个不同的iPhone17模拟器流程，最终全部通过，有效通过执行合计363.430秒。Simulator Debug、Device Release与严格验签通过；两包均0.37.0/56且内含20个CAF音源。手机一次安装成功并回读同版本；一次自动启动因设备Locked被系统拒绝，未等待/重试。手机解锁后点开星夜即可。未把安装成功当作真机交互验收，未测iPad或持续硬件FPS。

## 交付行为

- 10个内置角色的1024×768实际3D封面、两列发现卡、36pt搜索和资料106pt焦点横幅；发现没有作者分栏，角色→作者→作品仍可完整往返。
- 胶囊10pt小静音图标，原生命中区域36×44pt；点击只改变语音自动播放，不打开资料。头部触摸仍触发反应，拖动捏合不改变相机。
- 作者定义在创建后固定；只保留音乐、记忆、聊天资料。定制标题与角色/作者返回头栏一致，名字位于同一行末尾。旧个人外观字段不覆盖定义，旧聊天和记忆保留。
- 每位内置角色2首不同的原创音乐，共20首；既有trackID保持，实例选项/音量/静音隔离，CAF/ALAC随App内置。创建角色当前继承底座封面和只读音乐文件，选项ID和偏好独立；尚无按创建实例上传/生成独立封面的入口。
- 聊天高度固定0.60；默认15pt，14–24pt全局字号在我的→设置→聊天字号修改。消息、输入、历史一致，跨角色、账号、重启保留。

## 实际验证

| 流程 | 成功耗时 |
|---|---:|
| 既有iOS核心入口：固定定义、角色音乐、关系、迁移与持久化 | 4.173s |
| 订阅与关注分离、资料作者作品导航和头栏布局 | 99.823s |
| 胶囊静音和仅三个个人设置页、不改变相机 | 43.550s |
| 真正摸头、拖动及捏合后镜头不变 | 27.569s |
| 全局15→24→15、角色/账号切换和重启、历史同步 | 96.670s |
| 初音night/day与Luma新CAF实际播放、切换恢复音乐偏好 | 75.566s |
| 紧凑发现→角色→作者→作品→逐层返回 | 16.079s |

核心入口输出67项作者/订阅检查和175项集合、隐私、客人轮次、搜索、持久化检查，并执行全局字体迁移断言。实际音乐证据要求AVAudioPlayer播放中、时间>0.3s、音频采样计数增长、解码时长>19s、源角色/文件名/sha匹配；不是仅检验文件存在。初音返回后day/15%及静音保留，Luma独立orbit/35%。资源层20首PCM、乐谱和文件哈希互异，无损回译逐样本一致。

首轮发现流程在保存截图后失败：通用截图辅助代码试图读取只在会话存在的customizationButton。修为先检查元素存在，未放宽导航断言，重跑16.079秒通过。原失败轮次保留在result.json和原xcresult，不计成功。独立Mac Swift执行被系统拒绝的问题使用既有iOS DEBUG核心入口完成，不修改系统签名环境。

主界面截图已逐项复核。最后仅将资料提示「声音外观可调整」改为音乐/记忆提示，按钮文字改「定制相处」，再编译两包；早期UI附件中可能保留该旧文案，流程/布局不变。

## 证据

- [汇总JSON](result.json)、[两平台包版本与资源](builds.json)、[核心断言](evidence/social-core-results.txt)
- [紧凑发现页](screens/authored-04-compact-discovery.png)、[三项相处设置](screens/authored-02-personal-settings.png)、[资料封面](screens/01-role-card-before-author.png)
- [正常启动会话](screens/final-normal-launch.png)、[全局字号设置](screens/global-font-03-restored-default.png)
- [初音音乐恢复证据](evidence/authored-music-04-miku-choice-restored-player.txt)、[Luma播放器证据](evidence/authored-music-03-luma-playing-player.txt)
- [手机安装](device-install.json)、[版本回读](device-app.json)、[一次启动结果](device-launch.json)
- [封面目录与渲染](../character-covers/render-report.json)、[专属音乐资源审计](../character-music/README.md)

最终工作区device / Release；iPhone17模拟器恢复不带测试参数普通会话，其他手机模拟器保持关闭。详细方案在[设计说明](../../design/2026-09-29-authored-characters-and-covers.md)，标准更新在[角色集合](../../character-standard/character-collections.md)。
