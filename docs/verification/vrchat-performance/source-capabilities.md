# VRChat 原作表现与菜单审计

本报告只声明来源能力与可转换目录；实际 App 是否可见、动作是否正确，以最终运行验收为准。静态姿势、服饰开关、零秒表情不计作长动画。

来源文件通过原审计 SHA-256 校验后读取。Unity YAML 仅使用安全数据解析；没有执行来源脚本。菜单控制条件列为原控制器关联，不声称已经完整模拟 VRChat Animator 图。

## kipfel

99 个源片段，其中 68 个零秒片段。目录 82 项；分类 {"pose": 10, "ears": 8, "tail": 7, "expression": 42, "hands": 8, "appearance": 7}。所有源片段均计入保留/配对/省略记录。

### 原菜单

| 菜单 | 选项 | 参数 / 值 | 迁移属性 |
|---|---|---|---|
| ExMenu_Emotes | Wave | `VRCEmote` / 1 | VRChat SDK builtin emote, source motion is external |
| ExMenu_Emotes | Clap | `VRCEmote` / 2 | VRChat SDK builtin emote, source motion is external |
| ExMenu_Emotes | Point | `VRCEmote` / 3 | VRChat SDK builtin emote, source motion is external |
| ExMenu_Emotes | Cheer | `VRCEmote` / 4 | VRChat SDK builtin emote, source motion is external |
| ExMenu_Emotes | Dance | `VRCEmote` / 5 | VRChat SDK builtin emote, source motion is external |
| ExMenu_Emotes | Backflip | `VRCEmote` / 6 | VRChat SDK builtin emote, source motion is external |
| ExMenu_Emotes | SadKick | `VRCEmote` / 7 | VRChat SDK builtin emote, source motion is external |
| ExMenu_Emotes | Die | `VRCEmote` / 8 | VRChat SDK builtin emote, source motion is external |
| Kipfel_ExMenu | Outfit | `` / 1 | submenu |
| Kipfel_ExMenu | Pet | `` / 1 | submenu |
| Kipfel_ExMenu | Motion | `` / 1 | submenu |
| Kipfel_ExSubMenu_Outfit_Sub | Cap | `Outfit_Cap` / 1 | local appearance switch |
| Kipfel_ExSubMenu_Outfit_Sub | Bag | `Outfit_Bag` / 1 | local appearance switch |
| Kipfel_ExSubMenu_Outfit_Sub | Vest | `Outfit_Vest` / 1 | local appearance switch |
| Kipfel_ExSubMenu_Outfit_Sub | Shirts | `Outfit_Shirts` / 1 | local appearance switch |
| Kipfel_ExSubMenu_Outfit_Sub | Shorts | `Outfit_Shorts` / 1 | local appearance switch |
| Kipfel_ExSubMenu_Outfit_Sub | Boots | `Outfit_Boots` / 1 | local appearance switch |
| Kipfel_ExSubMenu_Outfit_Sub | Socks | `Outfit_Socks` / 1 | local appearance switch |
| Kipfel_ExMenu_kisekae | Pet | `` / 1 | submenu |
| Kipfel_ExMenu_kisekae | motion | `` / 1 | submenu |
| Kipfel_ExSubMenu_Pet | PetOFF | `PetMode` / 0 | interaction mode; reimplement with App touch inputs |
| Kipfel_ExSubMenu_Pet | Happy | `PetMode` / 1 | interaction mode; reimplement with App touch inputs |
| Kipfel_ExSubMenu_Pet | Unhappy | `PetMode` / 2 | interaction mode; reimplement with App touch inputs |
| Kipfel_ExSubMenu_Outfit | Outfit | `` / 1 | submenu |
| Kipfel_ExSubMenu_Outfit | Glasses | `Outfit_Glasses` / 1 | local appearance switch |
| Kipfel_ExSubMenu_Outfit | Sleeve Change | `Outfit_Shirt_Sleeve_Short` / 1 | local appearance switch |

### 表现目录

| 分组 | 中文名称 | 源片段 | 种类 |
|---|---|---|---|
| pose | 安静睡眠 | `kipfel_afk_sleep_loop.anim` | motion |
| pose | 睡醒起身 | `kipfel_afk_sleep_to_stand.anim` | motion |
| pose | 躺下入睡 | `kipfel_afk_stand_to_sleep.anim` | motion |
| ears | 展开耳朵 | `kipfel_CatEar_active.anim` | motion |
| ears | 垂下 | `kipfel_CatEar_down.anim` | preset |
| ears | 自然状态 | `kipfel_CatEar_idle.anim` | preset |
| ears | 收起耳朵 | `kipfel_CatEar_inactive.anim` | preset |
| ears | 左耳轻动 | `kipfel_CatEar_pyoko_left.anim` | motion |
| ears | 耳朵轻动 | `kipfel_CatEar_pyoko_loop.anim` | motion |
| ears | 右耳轻动 | `kipfel_CatEar_pyoko_right.anim` | motion |
| ears | 竖起 | `kipfel_CatEar_up.anim` | preset |
| tail | 低垂摇尾 | `kipfel_CatTail_downwag.anim` | motion |
| tail | 自然状态 | `kipfel_CatTail_idle.anim` | preset |
| tail | 蓬起尾巴 | `kipfel_CatTail_puff.anim` | motion |
| tail | 卷起尾巴 | `kipfel_CatTail_roll.anim` | motion |
| tail | 竖起 | `kipfel_CatTail_up.anim` | preset |
| tail | 轻摆尾巴 | `kipfel_CatTail_updown.anim` | motion |
| tail | 竖起摇尾 | `kipfel_CatTail_upwag.anim` | motion |
| expression | 打哈欠 | `kipfel_facial_akubi.anim` | preset |
| expression | 生气 | `kipfel_facial_angry.anim` | preset |
| expression | 猫眼 | `kipfel_facial_cateye.anim` | preset |
| expression | 猫眼二 | `kipfel_facial_cateye2.anim` | preset |
| expression | 猫咪微笑 | `kipfel_facial_catsmile.anim` | preset |
| expression | 鼓起脸颊 | `kipfel_facial_cheek.anim` | preset |
| expression | 自信 | `kipfel_facial_confidence.anim` | preset |
| expression | 自信二 | `kipfel_facial_confidence2.anim` | preset |
| expression | 含泪 | `kipfel_facial_cry2.anim` | preset |
| expression | 自然神态一 | `kipfel_facial_default 1.anim` | preset |
| expression | 自然神态二 | `kipfel_facial_default 2.anim` | preset |
| expression | 自然神态三 | `kipfel_facial_default 3.anim` | preset |
| expression | 自然神态四 | `kipfel_facial_default 4.anim` | preset |
| expression | 晕乎乎 | `kipfel_facial_guruguru.anim` | preset |
| expression | 开心二 | `kipfel_facial_happy2.anim` | preset |
| expression | 微张嘴（固定嘴型） | `kipfel_facial_he(LipSyncOFF).anim` | preset |
| expression | 微张嘴 | `kipfel_facial_he.anim` | preset |
| expression | 认真盯住 | `kipfel_facial_hunt.anim` | preset |
| expression | 闪亮眼睛二 | `kipfel_facial_kirakira2.anim` | preset |
| expression | 嘟嘴 | `kipfel_facial_muu.anim` | preset |
| expression | 俏皮一笑 | `kipfel_facial_niyari.anim` | motion |
| expression | 脸色发白 | `kipfel_facial_pale.anim` | motion |
| expression | 吐舌二 | `kipfel_facial_pero2.anim` | motion |
| expression | 熟睡表情 | `kipfel_facial_sleep.anim` | preset |
| expression | 眨眼二 | `kipfel_facial_wink2.anim` | preset |
| expression | 好吃 | `kipfel_facial_yummy.anim` | preset |
| expression | 被摸头的开心 | `kipfel_facial_happy.anim` | motion |
| expression | 被摸头的不满 | `kipfel_facial_unhappy.anim` | preset |
| expression | 黑眼 | `kipfel_facial_blackeye.anim` | motion |
| expression | 哭泣 | `kipfel_facial_cry.anim` | motion |
| expression | 自然神态 | `kipfel_facial_default.anim` | preset |
| expression | 疑惑 | `kipfel_facial_doubt.anim` | preset |
| expression | 得意 | `kipfel_facial_doya.anim` | motion |
| expression | 呆住 | `kipfel_facial_flehmen.anim` | motion |
| expression | 轻轻惊叹 | `kipfel_facial_ho.anim` | motion |
| expression | 闪亮眼睛 | `kipfel_facial_kirakira.anim` | motion |
| expression | 安心 | `kipfel_facial_nagomi.anim` | preset |
| expression | 猫咪表情 | `kipfel_facial_nya.anim` | motion |
| expression | 吐舌 | `kipfel_facial_pero.anim` | motion |
| expression | 微笑 | `kipfel_facial_smile.anim` | preset |
| expression | 白眼 | `kipfel_facial_whiteeye.anim` | motion |
| expression | 眨眼 | `kipfel_facial_wink.anim` | preset |
| hands | 握拳 | `kipfel_hand_fist.anim` | preset |
| hands | 手指枪 | `kipfel_hand_gun.anim` | preset |
| hands | 放松双手 | `kipfel_hand_idle.anim` | preset |
| hands | 张开手掌 | `kipfel_hand_open.anim` | preset |
| hands | 剪刀手 | `kipfel_hand_peace.anim` | preset |
| hands | 指向 | `kipfel_hand_point.anim` | preset |
| hands | 摇滚手势 | `kipfel_hand_rock.anim` | preset |
| hands | 点赞 | `kipfel_hand_thumbs_up.anim` | preset |
| pose | 轻轻呼吸 | `kipfel_breath.anim` | motion |
| pose | 蹲姿 | `kipfel_crouch_still.anim` | preset |
| pose | 下落姿态 | `kipfel_fall_short.anim` | preset |
| pose | 俯卧一 | `kipfel_prone01_still.anim` | preset |
| pose | 俯卧二 | `kipfel_prone02_still.anim` | preset |
| pose | 坐姿 | `kipfel_sit.anim` | preset |
| pose | 自然站姿 | `kipfel_stand_still.anim` | preset |
| appearance | 挎包 | `kipfel_outfit_Bag_ON.anim` | toggle |
| appearance | 靴子 | `kipfel_outfit_Boots_ON.anim` | toggle |
| appearance | 帽子 | `kipfel_outfit_Cap_ON.anim` | toggle |
| appearance | 眼镜 | `kipfel_outfit_Glasses_ON.anim` | toggle |
| appearance | 短袖样式 | `kipfel_outfit_Shirt_sleeve_short.anim` | toggle |
| appearance | 袜子 | `kipfel_outfit_Socks_ON.anim` | toggle |
| appearance | 背心 | `kipfel_outfit_Vest_ON.anim` | toggle |

### 未开放 / 内部控制

- `LipSyncON_AnimationOFF.anim`：VRChat 内部眨眼/口型/碰撞/自触碰控制或空片段，不是独立可见表演。
- `_Empty.anim`：VRChat 内部眨眼/口型/碰撞/自触碰控制或空片段，不是独立可见表演。
- `Contact_Pet_AllowSelf_OFF.anim`：VRChat 内部眨眼/口型/碰撞/自触碰控制或空片段，不是独立可见表演。
- `Contact_Pet_AllowSelf_ON.anim`：VRChat 内部眨眼/口型/碰撞/自触碰控制或空片段，不是独立可见表演。
- `PBC_Ground_OFF(ColliderActive).anim`：VRChat 内部眨眼/口型/碰撞/自触碰控制或空片段，不是独立可见表演。
- `PBC_Ground_ON(ColliderInactive).anim`：VRChat 内部眨眼/口型/碰撞/自触碰控制或空片段，不是独立可见表演。
- `kipfel_outfit_Shirt_OFF.anim`：保留基础上装与短裤；移除可能露出身体，不开放脱除。
- `kipfel_outfit_Shirt_ON.anim`：保留基础上装与短裤；移除可能露出身体，不开放脱除。
- `kipfel_outfit_Shorts_OFF.anim`：保留基础上装与短裤；移除可能露出身体，不开放脱除。
- `kipfel_outfit_Shorts_ON.anim`：保留基础上装与短裤；移除可能露出身体，不开放脱除。

### 原模型形变与默认可见性

| Renderer | 默认激活 | Renderer 开关 | 原形变数量 |
|---|---|---|---|
| `Body` | True | True | 372 |
| `Body_Base` | True | True | 51 |
| `Cat_Ear` | False | True | 0 |
| `Cat_Tail` | True | True | 4 |
| `Hair_Back` | True | True | 0 |
| `Hair_Base` | True | True | 0 |
| `Hair_Bun` | True | True | 2 |
| `Hair_BunRibbon` | True | True | 1 |
| `Hair_Front` | True | True | 12 |
| `Hair_Side` | True | True | 3 |
| `Item_Bag` | True | True | 1 |
| `Item_Boots` | True | True | 0 |
| `Item_DressingPad` | True | True | 0 |
| `Item_FishBone` | True | True | 0 |
| `Item_Glasses` | False | True | 2 |
| `Item_NameTag` | True | True | 0 |
| `Outfit_Cap` | True | True | 0 |
| `Outfit_Shirts` | True | True | 6 |
| `Outfit_Shorts` | True | True | 0 |
| `Outfit_Socks` | True | True | 0 |
| `Outfit_Vest` | True | True | 1 |
| `UnderWear_Pants` | True | True | 1 |
| `UnderWear_Tops` | True | True | 0 |

全部形变名称、原始权重、每个浮点关键帧、控制器状态/转换、外部 GUID 见同目录 `source-capabilities.json`。

## mamehinata

64 个源片段，其中 55 个零秒片段。目录 49 项；分类 {"appearance": 4, "expression": 25, "ears": 4, "tail": 4, "pose": 4, "hands": 8}。所有源片段均计入保留/配对/省略记录。

### 原菜单

| 菜单 | 选项 | 参数 / 值 | 迁移属性 |
|---|---|---|---|
| ExMenu_Emotes | Wave | `VRCEmote` / 1 | VRChat SDK builtin emote, source motion is external |
| ExMenu_Emotes | Clap | `VRCEmote` / 2 | VRChat SDK builtin emote, source motion is external |
| ExMenu_Emotes | Point | `VRCEmote` / 3 | VRChat SDK builtin emote, source motion is external |
| ExMenu_Emotes | Cheer | `VRCEmote` / 4 | VRChat SDK builtin emote, source motion is external |
| ExMenu_Emotes | Dance | `VRCEmote` / 5 | VRChat SDK builtin emote, source motion is external |
| ExMenu_Emotes | Backflip | `VRCEmote` / 6 | VRChat SDK builtin emote, source motion is external |
| ExMenu_Emotes | SadKick | `VRCEmote` / 7 | VRChat SDK builtin emote, source motion is external |
| ExMenu_Emotes | Die | `VRCEmote` / 8 | VRChat SDK builtin emote, source motion is external |
| Mamehinata_ExMenu_kisekae | Pet | `` / 1 | submenu |
| Mamehinata_ExMenu_kisekae | motion | `` / 1 | submenu |
| Mamehinata_ExMenu | Costume | `` / 1 | submenu |
| Mamehinata_ExMenu | Pet | `` / 1 | submenu |
| Mamehinata_ExMenu | motion | `` / 1 | submenu |
| Mamehinata_ExSubMenu_Pet | PetOFF | `PetMode` / 0 | interaction mode; reimplement with App touch inputs |
| Mamehinata_ExSubMenu_Pet | Happy | `PetMode` / 1 | interaction mode; reimplement with App touch inputs |
| Mamehinata_ExSubMenu_Pet | Unhappy | `PetMode` / 2 | interaction mode; reimplement with App touch inputs |
| Mamehinata_ExSubMenu_Costume | Yakke | `C_Yakke` / 1 | local appearance switch |
| Mamehinata_ExSubMenu_Costume | Shorts | `C_Shorts` / 1 | local appearance switch |
| Mamehinata_ExSubMenu_Costume | Shoes | `C_Shoes` / 1 | local appearance switch |
| Mamehinata_ExSubMenu_Costume | Sun Visor | `C_SunVisor` / 1 | local appearance switch |
| Mamehinata_ExSubMenu_Costume | Body Bag | `C_BodyBag` / 1 | local appearance switch |
| Mamehinata_ExSubMenu_Costume | Dog Collar | `C_DogCollar` / 1 | local appearance switch |

### 表现目录

| 分组 | 中文名称 | 源片段 | 种类 |
|---|---|---|---|
| appearance | 斜挎包 | `C_BodyBag_ON.anim` | toggle |
| appearance | 项圈 | `C_DogCollar_ON.anim` | toggle |
| appearance | 鞋子 | `C_Shoes_ON.anim` | toggle |
| appearance | 遮阳帽 | `C_SunVisor_ON.anim` | toggle |
| expression | 生气 | `F_anger.anim` | preset |
| expression | 灿烂笑容 | `F_bigsmile.anim` | preset |
| expression | 哭泣 | `F_cry.anim` | motion |
| expression | 委屈 | `F_cry_hau.anim` | preset |
| expression | 得意 | `F_doya.anim` | preset |
| expression | 流口水 | `F_drool.anim` | preset |
| expression | 兴奋 | `F_exciting.anim` | motion |
| expression | 疑问 | `F_hatena.anim` | preset |
| expression | 惊叹 | `F_hoo.anim` | preset |
| expression | 闪亮眼睛 | `F_kirakira.anim` | preset |
| expression | 嘟嘴 | `F_muu.anim` | preset |
| expression | 微笑 | `F_smile.anim` | preset |
| expression | 紧张冒汗 | `F_sweat.anim` | preset |
| expression | 被摸头的开心 | `Pet_happy.anim` | preset |
| expression | 被摸头的不满 | `Pet_unhappy.anim` | preset |
| expression | 震惊 | `F_donbiki.anim` | preset |
| expression | 龇牙 | `F_garuru.anim` | preset |
| expression | 晕乎乎 | `F_guruguru.anim` | preset |
| expression | 鼓脸 | `F_hukure.anim` | preset |
| expression | 哼一声 | `F_hunsu.anim` | preset |
| expression | 闹别扭 | `F_musu.anim` | preset |
| expression | 吐舌 | `F_pero.anim` | preset |
| expression | 舔嘴角 | `F_perori.anim` | preset |
| expression | 惊讶 | `F_surprise.anim` | preset |
| expression | 闪亮眨眼 | `F_wink_kira.anim` | preset |
| ears | 垂下 | `DogEar_Down.anim` | motion |
| ears | 耳朵轻动 | `DogEar_Pyoko.anim` | motion |
| ears | 竖起 | `DogEar_Up.anim` | preset |
| tail | 低垂摇尾 | `DogTail_DownWag.anim` | motion |
| tail | 竖起 | `DogTail_Up.anim` | preset |
| tail | 轻摆尾巴 | `DogTail_UpDown.anim` | motion |
| tail | 竖起摇尾 | `DogTail_UpWag.anim` | motion |
| ears | 自然耳尾 | `Dog_Default.anim` | preset |
| pose | 轻轻呼吸 | `Mamehinata_breath.anim` | motion |
| pose | 蹲姿 | `Mamehinata_crouch_still.anim` | preset |
| hands | 握拳 | `Mamehinata_fist.anim` | preset |
| hands | 手指枪 | `Mamehinata_gun.anim` | preset |
| hands | 放松双手 | `Mamehinata_hands_idle.anim` | preset |
| hands | 张开手掌 | `Mamehinata_open.anim` | preset |
| hands | 剪刀手 | `Mamehinata_peace.anim` | preset |
| hands | 指向 | `Mamehinata_point.anim` | preset |
| hands | 摇滚手势 | `Mamehinata_rock.anim` | preset |
| pose | 坐姿 | `Mamehinata_sit.anim` | preset |
| pose | 自然站姿 | `Mamehinata_stand.anim` | preset |
| hands | 点赞 | `Mamehinata_thumbs_up.anim` | preset |

### 未开放 / 内部控制

- `C_Shorts_OFF.anim`：保留基础上装与短裤；移除可能露出身体，不开放脱除。
- `C_Shorts_ON.anim`：保留基础上装与短裤；移除可能露出身体，不开放脱除。
- `C_Yakke_OFF.anim`：保留基础上装与短裤；移除可能露出身体，不开放脱除。
- `C_Yakke_ON.anim`：保留基础上装与短裤；移除可能露出身体，不开放脱除。
- `_DefaultFace.anim`：VRChat 内部眨眼/口型/碰撞/自触碰控制或空片段，不是独立可见表演。
- `_Empty.anim`：VRChat 内部眨眼/口型/碰撞/自触碰控制或空片段，不是独立可见表演。
- `_EyeState_BlinkOFF.anim`：VRChat 内部眨眼/口型/碰撞/自触碰控制或空片段，不是独立可见表演。
- `_EyeState_BlinkON.anim`：VRChat 内部眨眼/口型/碰撞/自触碰控制或空片段，不是独立可见表演。
- `_EyeState_EyeClose.anim`：VRChat 内部眨眼/口型/碰撞/自触碰控制或空片段，不是独立可见表演。
- `_EyeState_EyeOpen.anim`：VRChat 内部眨眼/口型/碰撞/自触碰控制或空片段，不是独立可见表演。
- `_LipOFF.anim`：VRChat 内部眨眼/口型/碰撞/自触碰控制或空片段，不是独立可见表演。

### 原模型形变与默认可见性

| Renderer | 默认激活 | Renderer 开关 | 原形变数量 |
|---|---|---|---|
| `Body` | True | True | 184 |
| `Body_Base` | True | True | 51 |
| `Dog_Ear` | True | True | 0 |
| `Dog_Tail` | True | True | 0 |
| `Hair_Back` | True | True | 7 |
| `Hair_Base` | True | True | 1 |
| `Item_BodyBag` | True | True | 0 |
| `Item_DogCollar` | True | True | 0 |
| `Outfit_Shorts` | True | True | 0 |
| `Outfit_Yakke` | True | True | 1 |
| `Shoes_Sneakers` | True | True | 3 |
| `Under_Spats` | True | True | 6 |
| `Under_Tops` | True | True | 0 |

全部形变名称、原始权重、每个浮点关键帧、控制器状态/转换、外部 GUID 见同目录 `source-capabilities.json`。

## 明确边界

- Wave、Clap、Point、Cheer、Dance、Backflip、SadKick、Die 是两个菜单均引用的 VRCEmote 项，不能仅凭菜单存在就称原作者已提供这些身体动作。动作控制器引用的外部 GUID 已逐个列出。
- PetMode 是关闭/开心/不满的触碰响应模式，原作对应表情可迁移，网络 Contacts 和他人手部输入需要 App 语义重建。
- 上装、短裤 OFF 不开放；其来源仍完整列入覆盖记录。配件开关不等于完整捏人编辑器。
- Mamehinata 的 SunVisor / NameTag 是额外 Prefab/FBX，不能假定主 FBX 已包含；以最终转换的绑定检查结果为准。
- 原动画 YAML 两种列表格式（带 serializedVersion 与直接 curve）及带 Unicode 转义的日文形变都已解析。动态表情时序位于 sourceMorphCurves，末帧不能代替整个表演。
