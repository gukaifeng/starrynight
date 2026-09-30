# 多作者档案的分批导入

用于 Downloads 这类批量 ZIP/RAR/7z/嵌套 unitypackage 来源；旧琪宝/豆日向的专用转换器继续维护，不要拿旧 recipe 猜新骨架。接口契约见 `docs/character-standard/09-portable-avatar-standard.md`。

## 数据流与可恢复位置

`vrchat_batch_audit.py` → `plan_vrchat_library.py` → `inspect_vrchat_library.py` → `preflight_vrchat_library.py` → `package_vrchat_library.py` → `PortableAvatarReview.Run` → `activate_vrchat_batch.py` → 正常 Unity/iOS 构建和安装。

中间件全部在 `.local/vrchat-batch/`：index/plan、archives、每角色 stages、converted 候选、render 实际检查、inspection/package 状态。任何单角色失败只暂停该角色；用户已要求缺本体或缺依赖先跳过。原包不得修改。批次名册在 `assets/characters/import-batches.json`，最终发布名册在 `active-roster.json`。

模型审计依赖 `scripts/vrchat/audit-requirements.txt`（libarchive-c）及 7zz；转换依赖 `scripts/vrchat/requirements.txt`（Python 3.11 的 bpy/numpy/Pillow/PyYAML 与 XCP 校验器）。不要在系统 Python 混装依赖。RAR5 的系统 libarchive 曾误报 ZIP/压缩方法不支持，档案格式与成员名单以 7zz 为交叉核对依据；保留路径 NFC、递归深度、展开体积和禁止路径逃逸的检查。

```bash
.local/character-sdk-venv/bin/python scripts/vrchat_batch_audit.py \
  "/absolute/path/to/library" --output .local/vrchat-batch
.local/character-sdk-venv/bin/python scripts/plan_vrchat_library.py
python3 scripts/prepare_liltoon.py
python3 scripts/prepare_vrc_reference_data.py

# 顺序执行会写同一 stage 的 Unity 工作；--only 只限制本批，不清空其他状态。
.local/character-sdk-venv/bin/python scripts/inspect_vrchat_library.py --only chiffon,karin
.local/character-venv/bin/python scripts/preflight_vrchat_library.py --only chiffon,karin
.local/character-venv/bin/python scripts/package_vrchat_library.py --only chiffon,karin
```

计划表决定主 Prefab、版本与候选封面，先检查再用；不要仅按 ZIP 名猜主模型。Descriptor 可以位于嵌套 Prefab，候选发现沿 `m_SourcePrefab` 递归，保留作者场景与变体；仅查根节点会把 Ramune 完整角色错选成 Gomenne 简版，把 Torao 成品错选成 Parent。换主 Prefab 后重新做 Unity inspection。

`--reuse-conversion` 仅用于输入几何/运动/转换器未变、重建元数据时；转换器或 Inspector 改动后重跑相应步骤。转换回执绑定工具和几何、二进制、采样、站姿、源审计哈希；旧回执无签名时也拒绝复用。inspection stamp 绑定 source/tool SHA 和 Prefab，不能手工补 stamp 代替重跑。此检查只影响候选重建，不会使已安装的旧 XCP 包失效。

预检生成私有 `capability-preflight.json`，重新解析源图，并标记旧 inspection 是否需要更新。`graph-ready` 不等于可发布：材质、包预算、真实画面、控制复位、AI 数据与设备验证仍需完成。SDK 动画引用与未知 GUID 分开列出；官方索引仅从固定哈希的本机 SDK ZIP 读取路径，不提取或打包动画。不要把平台提供的 motion 误报为作者漏装文件，也不能因为官方索引中找得到名字就把它标成宿主已支持。

新材质固定官方 lilToon 2.3.4，由脚本恢复；禁止加载来源中的任意 shader/Editor/C#/DLL。VRChat SDK 3.10.5 仅从固定哈希档案提取官方 mask 数据到私有缓存，平台动画和 SDK 二进制不进入 App。引用确实缺失不能全局 ignore；精确中性手 fallback 之外的缺 motion 留待补齐。

## 候选复核与发布

将待核对角色名写入 `.local/vrchat-batch/review-request.json`，结构为 `{"roles":["chiffon","karin"]}`，然后：

```bash
unity run "$PWD/unity/CharacterRuntime" --timeout 900 -- \
  -executeMethod PortableAvatarReview.Run \
  -logFile "$PWD/.local/logs/vrchat-portable-review.log"
```

检查 `render/<role>.png` 的真实画面；controls 记录必须覆盖所有源控制并复位成功。默认选项 0→0 不产生变化是正常的；其他不变化要解释实际作用。记录绑定 manifest SHA，源包或转换后清单变化即失效。这个 review 不自动修改发布名册，也不能代替 App 帧率测试。

在 `import-batches.json` 建立本批 ID 和新/保留角色，才运行：

```bash
.local/character-sdk-venv/bin/python scripts/activate_vrchat_batch.py --batch vrchat-20260930-01
```

它复制私有包、原封面、更新名册与集合；替换旧生成包前移到 `.local/vrchat-batch/previous/`，不删除源文件。它**不会自动完成** AI 人设、音乐、音色、后端目录种子或安装。新来源缺少这些产品数据时按当前已授权范围补齐，不能拿另一角色声音/选项充数。

- 每位新角色在 `services/character_ai/character_profiles.json` 注册人设、公开介绍、音色说明；`profiles.py` 合并公共规则。worker 安装器必须同时复制 JSON，不能只复制 Python 文件。schemas 从注册表接受角色 ID，不恢复固定数量的 Literal。
- AI 自动表现仅开放核对过的原作表情/手势。不要把衣服、体型、任意 shader 开关自动暴露给 LLM。
- 表情可能绑定 `GestureLeft/Right` 或任意作者参数。核对 FX 实际动画再设置 `ai.kind=expression`，不能用菜单组名判断表情，也不能假设不同模型同一手势值的表情相同。共享枚举参数复位后只重放原选中项，不能遍历未选中项逐个写 0。
- 在 `media-recipes.json` 登记角色场景、配色和特效，`generate_character_media.py --only anime-ROLE --generate` 生成三张图（真实计费）。只向生图提示传自然视觉描述，完整 JSON 人设会诱发图中渲染英文表格。每张都查看，成功回执保留，不无理由重跑。
- `prepare_character_media.py` 安装三类图并记录 `bailian-generated`/哈希。保留 `source.*` 原图用作溯源；不要把 AI 重绘冒充作者图。
- Fun-Music 尚未开放时，沿用用户授权的 CC0 临时曲目，在 `music-sources.json` 登记来源。`prepare_character_music.py --only anime-ROLE` 增量编码；ZIP 音乐包用精确 `archiveMember`，不展开无关成员。激活后可 `--apply-existing` 绑定已验证音轨，不重复转码。集合与 CAF 哈希通过 `check_character_collections.py`。
- `provision_character_voices.py --characters ROLE... --allow-paid` 是真实计费，单次最多三位，持久化 job 防止不明重试。遵守本会话已给预算；不要因自动测试而批量创建音色。
- 真实 AI smoke 可 `--characters ... --skip-asr` 控制本批；常规 XCTest 使用禁用付费调用的测试参数。
- 后端新增目录采用独立 migration，角色稳定 ID 不换；不能清空账号/对话表来刷新目录。

完成正常 Unity 导出、iPhone Simulator UI 测试、signed device build 后尝试安装。本项目已有授权无需每批再问；用户设备不可用时如实记录，继续模拟器。只有实际安装及启动命令成功才把该设备交付状态写为 delivered。

## 公共回归与关键坑

公共运行时修改覆盖全部 active roster。当前 `VrchatBatchTests` 验证新旧混合、淘汰再加载、实际参数及复位；`ConversationControlsTests` 和 `NaturalIdleTests` 验证旧两位的动作/待机/输入。扩充名册时同步增量用例，不把其他角色重新下架来满足旧数量断言。

1. Unity YAML 的 ON/OFF 是名字；mask/eyelids 十六进制必须保留前导零。
2. 可达控制图以真实 layer roots 为准；孤儿旧状态不应引入不存在的 SDK 动画依赖。
3. 仅手指 Humanoid motion 不要采样 Hips；Animator 参数动画不要写一套全身默认姿态。
4. 新音色 engine 标识要同时通过 Python 和 Swift 集合校验，单边通过仍会使发现页崩溃。
5. SDK 校验、曲线采样、Editor 画面、模拟器交互和真机性能分别记录，不能相互冒充。
6. 单个角色重跑不要覆盖整库状态；需要公共能力升级时记录影响面，并使相应源/工具签名缓存失效。
7. 生成场景、Prefab、GLB、贴图、原图封面与原始采样保持私有；Git 只提交工具、约束、名册、来源哈希和文字证据。场景可从 `BuildIos.Setup` 恢复。
8. BlendTree 可独立保存在 `.asset`，并有嵌套子资产。用 GUID + fileID 保留身份，不把外部树当作动画 GUID，也不让两个相同 fileID 的外部树互相覆盖；内联图 ID 保持兼容。
9. 原包的 Modular Avatar Merge Animator 在构建时才合成控制器。解析器会记录 `unsupported-build-merge-animator`；缺少对应组装适配时不能以“菜单为零”通过，更不能运行来源脚本来消除 Missing Script。Ramune 的完整根正是此类来源。详细证据见 `docs/verification/vrchat-batch-import/preflight-02.md`。
10. Material Variant 继承父纹理、数值、颜色，显式空纹理会清除父值；shader 仍以子材质自身为准。Shizuku 的 opaque 父 / cutout 子已用 Unity API 验证；不能因 GUID 不同拒绝所有材质继承。循环、缺父和未知 shader 仍报错。
11. `.fbx`、`.asset`、`.controller` 可以包含 AnimationClip 子资产，按 `GUID:fileID` 采样，排除 Editor preview clip。Standalone `.anim` 保留旧 GUID。只打包活控制图可达 motion 和明确的 body baseline；旧版未使用动画不能拉入其他 shader 版本的材质。
12. 同档案分包用 `additionalPackages`；跨档案仅用已审计 `dependencyAssets` 的精确 GUID + 内容哈希，并绑定 inspection stamp。例：Kumaly 引用的共享 `dummy.anim` 实际在用户的 Ichigo 档案中。找到一个空动画不能推广为任意缺 motion 的替代。
13. 蒙皮只删除未被权重使用的骨索引并重映射，不能裁掉有权重骨骼。可移植 profile 的 primitive 总预算为 64，旧 profile 仍为 32。紧凑 JSON 只移除空白，不删帧或降低采样精度。
14. 表情锁/表情组切换须在手势生效、释放的组合上下文检查。源站椅限定选项在普通对话可能无效果，应注明条件，不能把参数改变当成画面改变。控件复位、曲线支持范围、设备帧率是不同证据。
