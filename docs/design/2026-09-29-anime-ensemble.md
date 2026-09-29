# 星夜 0.28：三个开源二次元角色

本轮增加三个实际可交互的 3D 角色，沿用 XCP 1.1 和 XCC 1.0。发现页、资料卡、创建底座、对话、朗读、触头、视线、头像和外观都由原有数据接口接入。原有四个角色及用户存档不替换。

| 角色 | 原模型 | 风格 | 可见三角形 | 材质分组优化 |
| --- | --- | --- | ---: | ---: |
| 小光 | VRoid Vita（旧版 CC0） | 银白短发、异色瞳、幻想服装 | 26,130 | 82 → 16 |
| 小诗 | VRoid Sendagaya Shino | 深蓝长发、安静校园风 | 31,211 | 67 → 17 |
| 晴川 | VRoid Sakurada Fumiriya | 短发蓝眼、清爽少年 | 39,548 | 102 → 17 |

## 资源与许可选择

模型使用 pixiv / VRoid 旧版 CC0 模型。对应 VRM 文件的元数据明确标记 CC0；作者的[旧版样例说明](https://vroid.pixiv.help/hc/en-us/articles/4402614652569)、[Shino 说明](https://vroid.pixiv.help/hc/en-us/articles/360013482714-Sendagaya-Shino)和[Fumiriya 说明](https://vroid.pixiv.help/hc/en-us/articles/360014788554-Sakurada-Fumiriya)保留在来源记录中。下载使用 madjin/vrm-samples 的固定提交公开镜像，SHA-256 锁定，未执行下载的代码。新的 AvatarSample A/B/C 不在本轮资源中，它们不是 CC0，且另有角色创建服务等条件。

动作使用 Overte / High Fidelity 的人形动画，经 Hanami 转换为 VRMA 的数据文件。[上游许可证](https://github.com/overte-org/overte/blob/master/LICENSE)和[转换作者对这些文件的独立 Apache-2.0 声明](https://github.com/Undi95/Hanami/blob/6787685c8d40e4e79bffbb0d389b478f32ef88d6/vrma/NOTICE.md)均已核对。只取明确归属 Overte 的九段动作；没有集成 Hanami 应用代码、Rocketbox 角色或其他未核验资源。包内保留完整署名、Apache-2.0 正文、NOTICE 和本轮修改说明，App 原有许可证汇总会带入这些声明。

下载直接通过公开 HTTPS 完成，没有遇到模型下载拦截，没有更改公司的安全配置。网页直连有 403 时使用已经可访问的浏览工具核对作者说明；没有尝试绕过安全软件。

完整文件、版本、哈希在 [anime-sources.lock.json](../../assets/characters/anime-sources.lock.json)。重建命令：

```sh
.local/character-venv/bin/python scripts/prepare_anime_characters.py --fetch
.local/character-sdk-venv/bin/python scripts/validate_characters.py
unity run "$PWD/unity/CharacterRuntime" -- -buildTarget iOS -executeMethod AnimeEnsembleReview.Prepare -logFile "$PWD/.local/logs/anime-unity-prepare.log"
```

## 动作与适配

每个角色含自然待机、抬手招呼、点头、摇头、侧耳倾听、思考、讲述、放松、认真回应，共九段。源动作是作者制作的人形动画，不能称为本轮原创动作或声称是真人动捕。动作的会话构图保持不变，主动问候不触发全身招手；用户显式要求动作时才通过角色自己的语义映射解析。

首次实际渲染发现：VRMA 的 FBX 局部轴不等于 VRoid 归一化骨骼轴，直接按名字拷贝会把腿折到头顶。修复采用 [pixiv three-vrm 官方实现](https://github.com/pixiv/three-vrm/blob/dev/packages/three-vrm-animation/src/VRMAnimationLoaderPlugin.ts)中的归一化关系：`父骨骼世界静置旋转 × 动画局部旋转 × 当前骨骼世界静置旋转的逆`；再处理 VRM 0 的朝向。转换器拒绝尚未支持的非单位目标绑定旋转，避免静默导错其他模型。

会话动作保留上身、手肘、手指的协调时序；下肢及骨盆保持稳定，减少比例变化后的滑步。动作开头约 0.48 秒、结尾约 0.58 秒使用五次平滑曲线归位，动画播放器保留 0.32 秒交叉淡入。肩部增加小幅固定间距；模型保持自己的比例，不采用夸张根位移。眨眼、情绪、口型各走独立 morph；当前音量驱动开口，未来可传入五个独立 viseme。

头部最大转向 38°、抬头 16°、低头 20°，超出舒适范围仍由平台逐渐释放注视。头发和裙摆使用原模型链条与碰撞球进行受限弹簧计算，发链偏转上限 16°、裙摆 8°，帧间隔异常或重新启用会复位；不是完整布料物理系统。没有宣称任意角度、任意定制组合都绝不穿模。

聊天可说“抬手”“点点头”“摇摇头”“侧耳倾听一下”“想一想”“轻声讲述”“放松一下”“认真回应”。请求从当前角色及当前姿势允许的动作中匹配；不支持时明确回复还不会，不借用另一个角色的动作。否定指令不触发动作用词。无需恢复已经隐藏的动作栏。

## 清晰度与性能取舍

保留原始网格、面部 morph 和贴图；同材质且同顶点数据的分组合并，不靠删掉细节减绘制。Unity 材质使用现有 SoftPortrait 柔和二次元着色及阴影。源 PNG 经 Unity TextureImporter 生成最高 2K、ASTC 4×4、mipmap、各向异性过滤，避免 glTF 内嵌纹理直接作为未压缩 RGBA32 进入渲染材质。头发透明采用裁剪和 4× MSAA，避免大量半透明层叠。

第二次检查发现默认颜色参数把深色头发替换成白色。修复为从线性 glTF 原色转换到正确的 sRGB 初始选项，仅修改主发色层，保留发背与高光差异；头像使用修复后的真实模型重新生成。

源动作采样为 30 Hz，Unity 连续插值在实际显示帧执行；不能把采样率当作渲染帧率。沿用 App 的 60 / 120 Hz 策略，模拟器只验功能、构图和渲染，真机持续 60/120 FPS 尚不能据此保证。

## 隔离与明确边界

三个 XCC 集合各自声明动作、背景、声音节奏、音乐和默认空间，偏好仍按账号和角色实例保存。都可调整发色氛围、服装色调，并使用现有空间和灯光编辑器。声音仍共用已内置的中文离线音色，角色以语速区分；本轮未制作三个专属声线。音乐复用已有只读音频文件，不共享可编辑状态。

三个角色目前声明站立会话动作，没有声明未经制作/验证的坐、蹲、躺。新角色可用作创建底座，但任意体型重塑、换发型、换服装网格并不在本轮资源中。全部运行内容随 App 打包，运行不依赖 Mac 或网络；更多模型的运行时下载属于后续分发工作。

验证结果见 [交付证据](../verification/anime-ensemble/README.md)。
