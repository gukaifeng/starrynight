# Third-party resources

## Hatsune Miku Append — Tda / monjo3456

The second character uses **Tda式初音ミク・アペンド**, modeled by **Tda**, edited by **monjo3456** (1.06), adapted for this personal, noncommercial Model Space viewer. Character copyright: **Crypton Future Media, Inc.** This is not an official model endorsement or App.

Source files were obtained from the public [hecomi/StereoAR-for-Unity adapted-model directory](https://github.com/hecomi/StereoAR-for-Unity/tree/master/Assets/MikuMikuDance%20for%20Unity/PMD/Tda%E5%BC%8F%E5%88%9D%E9%9F%B3%E3%83%9F%E3%82%AF%E3%83%BB%E3%82%A2%E3%83%9A%E3%83%B3%E3%83%89%E6%94%B9%E5%A4%89Ver1.06). The repository's code license does **not** replace the model's own terms. Original Japanese terms, the author's English reference translation, the editor's ReadMe, source URLs and SHA-256 hashes are preserved under `unity/CharacterRuntime/Assets/MikuCharacter/Source/`. `MODELSPACE_ADAPTATION.md` records this project's changes. A UTF-8 copy of all notices ships in `MikuCredits.txt` and can be read from the App's About screen.

The original [Piapro character guidelines](https://piapro.jp/license/character_guideline) and original model terms continue to apply. This implementation is for the user's current private noncommercial testing; do not infer permission to sell the character, redistribute unmodified original model data, or transplant its parts into unrelated models. The original Japanese terms take precedence over translations.

Project changes: import-time PMX conversion, compact face/body meshes, linear skinning adaptation, URP materials, mipmaps and ASTC textures, three facial expressions, original short gestures and touch interaction. The model retains its Tda identity. No source choreography, music, synthesized voice, MMD runtime or third-party executable is included. The earlier procedural fan-model experiment was replaced after visual review and is not the shipping character.

## RobotExpressive

Creator: Tomás Laulhé (Quaternius). Example asset modifications: Don McCurdy.

The pinned three.js r180 model README declares CC0 1.0. The model is now used by the independent XCP sample character 小乐 and ships in the prototype App; the project does not claim authorship or endorsement.

Source and preserved notices:

- `unity/CharacterRuntime/Assets/ThirdParty/RobotExpressive/SOURCE_README.md`
- `unity/CharacterRuntime/Assets/ThirdParty/RobotExpressive/LICENSE_NOTICE.md`
- `unity/CharacterRuntime/Assets/ThirdParty/RobotExpressive/asset-lock.json`

## Unity Editor packages and URP template

The Unity project settings, sample scene, and pipeline assets originate from the URP template distributed with Unity 6000.3.25f1 (`com.unity.template.urp-blank` 17.0.14). Template caches and tutorial scripts were not copied. Project dependencies are configured for URP 17.3.0 and glTFast 6.16.1.

Unity Editor, its bundled packages, and externally downloaded packages remain subject to their respective licenses. Package archives preserve their original license and notice files. Download provenance and fixed versions are recorded in `docs/package-downloads.json`; the archives are local dependencies excluded from version control.


## 历史品牌图形（v0.2–v0.5）

2026-09-27 为本项目通过内置 image_gen 工具生成瓷玉对话环与珍珠图形，作为栩屿 / XUYU 的 App 图标及品牌标记。原始输出保存在 `assets/brand/xuyu-icon-master.png`，历史提示词保存在 `assets/brand/archive/xuyu-image-prompt.txt`。品牌图形未使用初音未来或其他现有角色的肖像、商标作为素材。原生界面的品牌文字使用系统字体。

## v0.3 本机开源语音

- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)，1.13.8，Apache-2.0；依赖锁文件 `local-services/voice/requirements.lock`。
- [SenseVoice](https://github.com/QwenAudio/SenseVoice)，MIT；ONNX 分发源 `csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17`，固定 revision `2365baeacb507f821a0c8120fcee3d484dba7a07`。
- [MeloTTS](https://github.com/myshell-ai/MeloTTS)，MIT；ONNX 分发源 `csukuangfj/vits-melo-tts-zh_en`，固定 revision `a0d5c6a264c0ef92d70d8661d8cc502d79627cd6`。
- 分发包原始许可证与说明保存在 `local-services/voice/licenses/`；文件哈希在 `models.lock.json`。v0.3 时仅供 Mac 服务加载；自 v0.7.0 起，这两个模型及许可随 iOS App 分发。

- Debug 语音集成验证录音 `SpeechTestFixture.wav` 来自上述固定 SenseVoice 分发的 `test_wavs/zh.wav`，遵循其随附 MIT 许可；只有显式测试启动参数会显示识别样本按钮。普通录音入口仍使用麦克风。
- Kokoro v1.1 中文 int8 仅用于本机对比，未选择为默认语音依赖；其评估锁文件与记录单独保留。评估包中的模型为 Apache-2.0，espeak-ng 语言数据另属其 GPL 许可体系，不能将整个包统称为 Apache-2.0。

## v0.5 内置背景音乐

「岛上的午后」「月光潮汐」由本项目 `scripts/generate_soundscapes.py` 编排并使用振荡器合成，不使用第三方录音、采样或现成曲谱。每段为 48 秒立体声循环，生成参数与 SHA-256 记录于 `docs/verification/atmosphere/music-assets.json`。离线生成仅复用已有隔离环境中的 NumPy；运行时使用 Apple AVFoundation，没有新增第三方音频运行库。


## 小伴品牌图形（v0.5.1 起）

2026-09-27 为本项目通过内置 image_gen 生成暖白与浅桃色的双对话气泡标识。原图为 `assets/brand/xiaoban-icon-master.png`，完整提示词为 `docs/brand-image-prompt.txt`。iOS App 图标与页内标识仅做尺寸缩放，中文“小伴”与罗马字 XIAOBAN 使用系统字体原生排版。图形不采用现有角色形象作为输入。

## 小夏写实角色（0.6）

MakeHuman Community / MPFB 生成的成年虚构女性，基础网格、目标、骨架和系统资产 CC0；皮肤 OnlyTheGhosts、裤子 MRT（MargaretToigo）来自官方 CC0 包。Elvaerwyn 的 Daisy Hair / Short Side Do 为 CC-BY，Mindfront 的 Knitted Sweater 01 为 CC BY 4.0。已保留作者、来源、修改说明及官方资产包记录：[完整署名](ios/CharacterHost/Resources/RealCharacterCredits.txt)、[逐资产出处与哈希](unity/CharacterRuntime/Assets/ThirdParty/MakeHuman/provenance.json)。

MPFB 2.0.17（GPL-3.0）与 Blender bpy 4.5.3 仅在本机用于制作，不随应用分发代码；产物按对应资产许可使用。官方说明：https://static.makehumancommunity.org/about/license.html 。

## v0.7 iOS 离线推理库

- 使用 sherpa-onnx 1.13.8 官方静态 iOS XCFramework，以及其 Swift Package 指定的 ONNX Runtime 静态 XCFramework 1.28.1（依赖包标签 1.28.2）。二进制 URL 与上游 SHA-256 固定在 `scripts/prepare_ios_speech.py`，支持 arm64 真机和模拟器。
- 源项目许可证、ONNX Runtime 第三方通知、Melo / SenseVoice 模型许可随 `VoiceModels` 目录打包；App 的“关于 → 离线语音开源许可”可离线查看。原文、固定来源及哈希在 `assets/voice/`。
- **不能把官方完整 TTS 预编译库整体称为 Apache-2.0。** 静态产物中实际包含 Piper phonemize（MIT）与 eSpeak NG 代码（GPL-3.0 及其子组件许可）；已记录其上游固定源码并附带许可。Melo 当前配置使用词典路径，并不意味着链接后二进制自动排除了 eSpeak；已用最终可执行文件中的 `_espeak_Initialize` 符号确认。当前仍是个人原型，公开发行前应构建仅含所需后端的运行库，或按完整依赖许可安排源码与分发。本轮不是商业发布许可审查结论。
- eSpeak 固定源码：`https://github.com/csukuangfj/espeak-ng/tree/ed530aa113046142eb5115cf2fc9157854d0ffe1`；Piper phonemize：`https://github.com/csukuangfj/piper-phonemize/tree/f3ff95afc03640bc1399e113e83361192a2fafb4`。版本取自 sherpa-onnx v1.13.8 官方 CMake 依赖定义。

## XEP environment integration example

`environment-packages/imported/courtyard` is original static geometry authored for this project and dedicated under CC0-1.0. The five built-in scene builders use project-authored geometry and materials; they do not contain downloaded environment assets.

## v0.28 二次元角色与会话动作

- 小光、小诗、晴川分别适配 pixiv / VRoid 的旧版 Vita、Sendagaya Shino、Sakurada Fumiriya CC0 模型。原作者名称、源 VRM 元数据和来源说明保留在角色包中；App 内昵称与设定为本项目配置，不表示原作者背书。本次不包含另有许可条款的 AvatarSample A/B/C。
- 九段动作取自 Hanami 的 Overte 动画转换文件，按其单独的 Apache-2.0 资产声明使用；原始来源为 High Fidelity / Vircadia / Overte。仅使用动画数据，没有集成 Hanami 的应用代码或 Rocketbox 资产。
- 固定提交、原始 URL、SHA-256、大小在 [资源锁文件](assets/characters/anime-sources.lock.json)。各角色包的 `LICENSE.txt` 包含原始署名、Apache-2.0 全文、Hanami NOTICE 与修改说明；构建时并入 App 的 `CharacterPackageCredits.txt`，可离线查看。
- 本项目适配包括 VRM 0 骨架坐标归一化、站姿稳定、动作平滑起止、眨眼、材质分组合并、移动端纹理导入和受限次级摆动。来源、官方许可链接与重建方法见 [方案记录](docs/design/2026-09-29-anime-ensemble.md)。

## v0.33 二次元渲染与自然待机

- 使用 Unity Technologies 官方 [Unity Toon Shader](https://github.com/Unity-Technologies/com.unity.toonshader) 0.15.1-preview；间接依赖 Film Internal Utilities 0.20.0-preview。两者遵循 Unity Companion License，不能称为 MIT 包。本项目只使用渲染包，没有导入 Unity-chan 示例模型、贴图或其他示例美术。
- 官方包 URL、版本和 SHA-256 写入 `docs/package-downloads.json`；本机 UPM 使用固定归档，Unity 生成完整依赖锁。原始许可文本随 `UnityToonCredits.txt` 打包，也并入关于页面的角色与场景许可。
- 角色包 1.1.0 恢复原 VRoid 法线与头发 MatCap；原有 Overte / Hanami 动作数据经循环、少量 Relax 混合和呼吸调整，形成 30 秒待机，另有非等间隔眨眼。未引入新的模型作者、音乐或下载的可执行代码。

## v0.34 近景立绘角色

### 优可 / CG-CA Uka

Original attribution: **CG-CA Uka (c) 2023-2024 by Nagoya Institute of Technology, Moonshot R&D Goal 1 Avatar Symbiotic Society**.

- 原作者仓库：[mmdagent-ex/uka](https://github.com/mmdagent-ex/uka/tree/659f0d1a740fec68bb2817dc9c694a35e7a15f12)，固定提交 `659f0d1a740fec68bb2817dc9c694a35e7a15f12`，采用 [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/)，并保留作者的使用指南。逐文件来源与 SHA-256 见 `assets/characters/uka-sources.lock.json`。
- 原模型、纹理和随附 VMD 动作的作者不变。星夜适配包括 PMX 到 glTF 转换、移动端材质与骨骼绑定、呼吸动作与温和手势、衣袖代理骨骼和受限头发／长衣次级运动；不表示原作者参与、认可或背书本应用。原英文 README、规定署名、许可链接和修改说明保留在 `character-packages/imported/anime-uka/LICENSE.txt`。
- 「优可」是本机角色设定的显示名；来源页同时显示原名 Uka，不能把本应用的角色整理者身份等同于 3D 素材原作者。

### 维拉 / Velara 与安宁 / Onyx — 本机个人预览

- 原作者 **Nitral / Nitral Studios**，Copyright 2024 Nitral Studios。来源：[test157t/VRM-Assets-Pack-For-Silly-Tavern](https://github.com/test157t/VRM-Assets-Pack-For-Silly-Tavern/tree/f3191f2eb30dd9adf2305c4fdb16627363c5ec8a)，固定提交 `f3191f2eb30dd9adf2305c4fdb16627363c5ec8a`；原始 URL、摘要和内嵌元数据在 `assets/characters/portrait-vrm-sources.lock.json`。
- 两款遵循 [VRM Public License 1.0](https://vrm.dev/en/licenses/1.0/) 与原文件许可设置：允许所有人进行 Avatar Use，要求署名，但 `allowRedistribution=false`、`modification=prohibited`。原仓库的宽泛使用说明不用于抹去这些更具体的限制。本地包保留 `source-meta.json` 及完整声明。
- 这次只用于用户自己 Mac、模拟器和自用设备的个人原型。§1(11) 将 Model/Avatar Use 必需的复制排除于公众再分发，§2(a)(7) 允许行使已有使用权必需的技术格式转换；本项目据此做运行时格式与骨骼适配，保留原几何、纹理、颜色和脸型，并禁用美术外观编辑。**不得把这两款资产上传公开仓库、单独分发，或随公众版 App 发布；对外发行和美术改作需要原作者相应授权。**
- 对话动作来自独立的 Overte / Hanami Apache-2.0 数据，与角色美术许可分开。保留 High Fidelity、Vircadia、Overte、Undi95 的版权及上游 `NOTICE.md`；没有将本地 avatar 文件错误标记为 Apache-2.0。

`scripts/generate_asset_credits.py` 从角色包生成离线署名，被原有 `generate_host.py` 复用。`CharacterSourceCredits.json` 供「角色资料 → 模型素材与署名」读取，`CharacterPackageCredits.txt` 供「关于 → 角色与场景许可」读取；两条路径均保留原名、原作者、固定来源、主许可、独立 NOTICE 和本地预览许可元数据。界面中的「星夜」作者身份表示角色设定与整理者，已有说明明确区分素材原作者。


## Kipfel 1.1.1 PC（历史 1.0.3） / Mamehinata PC 1.53 — もち山金魚 (MOCHIYAMA)

User-provided archives, locally converted into `anime-kipfel` and `anime-mamehinata`. Original source hashes are in `assets/characters/vrchat-sources.lock.json`; archive/prefab/material/physics audits are in `docs/verification/vrchat-import/`. The original artist retains rights. These are **private local preview assets, not open-source models or publicly redistributable app content**. Current author terms v1.60 (2026-09-07) require contacting the licensor for software/game integration distribution; historical acquisition terms were not retroactively determined. See the primary sources and analysis in `docs/design/2026-09-29-vrchat-feasibility-research.md`.

Adaptation preserves the default authored clothing and main model appearance, normalizes metre units, maps expressions and visemes, retargets separately licensed Overte/Hanami Apache-2.0 conversational motion, and substitutes the host's own bounded secondary motion and mobile Toon materials. Some lilToon layers, the separate Mame NameTag accessory, VRC FX/Contacts/PhysBone behavior and platform actions are not reproduced; conversion reports state the differences. No VRChat SDK DLL, scripts, default animations, or sample materials are included in the app. LICENSE.txt, source metadata, and upstream animation NOTICE are carried into the native offline asset credits.

Blender bpy is a build-time conversion tool only. It does not ship in the iOS application.

## Local reply similarity — BGE / FastEmbed / ONNX Runtime

StarryNight's development AI worker uses [BAAI/bge-small-zh-v1.5](https://huggingface.co/BAAI/bge-small-zh-v1.5) (MIT), the [Qdrant ONNX conversion](https://huggingface.co/Qdrant/bge-small-zh-v1.5) (MIT), [FastEmbed](https://github.com/qdrant/fastembed) (Apache-2.0), and [ONNX Runtime](https://github.com/microsoft/onnxruntime) (MIT). The model is used locally for reply similarity; no text is sent to an embedding API. The weights are runtime downloads and are not included in this public source repository or the iPhone app. The upstream snapshot and file hashes are pinned in `services/character_ai/novelty-model.lock.json`; Python dependencies are pinned in `requirements.lock`. Provision with `scripts/prepare_reply_novelty.py`. This does not replace Alibaba's separately billed dialogue/TTS services or their terms.

## v0.60 — Chiffon / Karin and the portable avatar adapter

- User-supplied Chiffon 1.00 and Karin 1.11 are by **こまど / komado（あまとうさぎ）**. Creator pages: [Chiffon](https://komado.booth.pm/items/5354471), [Karin](https://komado.booth.pm/items/3470989). Models, original art, textures and sampled controls remain local private-preview assets under the original terms; the public repository includes only source tooling, schemas and provenance hashes. No general redistribution grant is implied.
- [lilToon 2.3.4](https://github.com/lilxyzw/lilToon/releases/tag/2.3.4) is MIT-licensed. Its license, bundled third-party notices and VRC Light Volumes shader-include license are preserved in `ios/CharacterHost/Resources/LilToonCredits.txt` and included in generated offline app credits. `scripts/prepare_liltoon.py` pins the original source archive hash.
- VRChat SDK 3.10.5 is a private reference input for known mask data and control semantics, subject to its [SDK license](https://hello.vrchat.com/legal/sdk). No SDK DLL, arbitrary source scripts or platform animation clips are installed in the production Unity project or shipped in the App. `prepare_vrc_reference_data.py` extracts only five mask data files into the private dependency cache.
- The portable adapter preserves author control data but uses explicitly documented host standing, neutral-hand and bounded secondary-motion adaptations where applicable. These are not claims of numerical PhysBone equivalence or complete VRChat platform support. See the [portable avatar standard](docs/character-standard/09-portable-avatar-standard.md).
