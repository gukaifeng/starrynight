# 角色封面、头像、场景和音乐制作

制作清单为 `assets/characters/media-recipes.json`，以 `active-roster.json` 为实际名册。工具只在开发机运行，App 加载已打包资源，不在启动或切换角色时重新调用付费生成。

## 文件与职责

- `scripts/generate_character_media.py`：百炼制作，从相邻 `starrynight-server` 仓库读取私有 `Settings`。角色人格来自 AI 服务设定，参考图来自已有 `Cover_*.imageset/source.*`。封面和头像用参考图编辑，背景使用纯环境生成。
- `.local/character-media/<id>/`：私有母版及回执（模型、提示、源图哈希、请求 ID、usage、成品哈希）；旧版保留在 `revisions/`。原始 VRChat 源包不改。
- `scripts/prepare_character_media.py`：验证回执后安装原生封面/头像和 Unity 场景图，更新目录。`CharacterCoverBuilder` 校验 `bailian-generated` 封面且不以截图覆盖。
- `CharacterAtmospheres.json`：双方共用 schema v1，资源路径、哈希、粒子类型、配色与密度；Unity 导出戳保存目录哈希，旧导出不能混入新宿主。
- `music-sources.json` 与 `scripts/prepare_character_music.py`：网络音乐过渡方案。每角色 `/theme` 一首，CAF/ALAC 与音频审计留本机，公开源码保留出处、署名、哈希和实现。

## 恢复与制作顺序

先按 [Git 与资源恢复](git-workflow.md)恢复合法取得的源包、转换结果、封面参考图及 Python 环境。优先安全恢复已有 `.local/character-media` 和原生/Unity 忽略资源，避免重复付费。

```bash
# 仅查看计划，不发起收费请求。
../starrynight-server/.local/character-ai-venv/bin/python scripts/generate_character_media.py

# 明确需要新制作时执行；已完成同指纹会复用。
../starrynight-server/.local/character-ai-venv/bin/python scripts/generate_character_media.py --generate

# 查看每张母版后安装，检查多余人物、错误文字和裁切。
python3 scripts/prepare_character_media.py
python3 scripts/check_character_media.py

# 当前网络曲目恢复，不调用音乐模型，需要 ffmpeg。
python3 scripts/prepare_character_music.py
python3 scripts/check_character_collections.py

# 两平台重导，使图片进入 Unity Data。
python3 scripts/export_unity_ios.py --platform simulator
python3 scripts/export_unity_ios.py --platform device
```

失败或提交后中断的任务不自动重试。查看回执后才加 `--retry-failed`，可用 `--only anime-kipfel --kinds cover` 限定范围。输出 URL 只接受阿里 OSS/CDN，经 HTTPS 下载，限制文件长度；Key 不写日志、回执、App 或 Git。

封面焦点需在实际手机/平板资料卡中确认，不能只相信提示坐标。背景 2048² 是当前清晰度与包体/显存取舍，并非 4K/8K；ASTC 6×6、无 mip、aspect-fill 与小幅视差。背景不是真正可走入的三维房间，也不包含静态角色。

## 完整头部的头像与封面取景

0.73 起每个 `media-recipes.json` 角色可以提供 `headBounds: {x, y, width, height}`，坐标相对于封面母版归一化到 0–1，原点为左上角。矩形应包住头、头顶发丝、耳朵、帽子和饰品；不必纳入垂到腰部的长发和身体。安装脚本将它保留到 `CharacterCoverCatalog.json`。

原生圆形头像使用同一张完整封面及头部矩形，矩形对角线适配圆形可视区并留少量余量，避免普通居中裁切削掉耳朵、头饰。卡片/横幅共用此标注但采用不同的头部占高，宽屏两侧使用模糊低对比原图填充。没有标注的旧角色继续沿用原焦点逻辑，字段为可选且向后兼容。

不要通过放大一张已经切掉头顶的头像来修复。先检查封面母版能否完整包含头部，再测量标注；生成新母版后必须重新确认标注。`CharacterArtworkLayoutTests.swift` 检查圆形包含关系与多个卡片比例，最终仍须在发现页、资料页、会话胶囊和加载背景实际查看。

## Fun-Music 开通后

当前 API 实测 403，用户已申请等待批准。获准后执行：

```bash
../starrynight-server/.local/character-ai-venv/bin/python scripts/generate_character_media.py --kinds music --generate --retry-failed
python3 scripts/prepare_character_music.py --ai
python3 scripts/check_character_collections.py
```

先听生成结果，检查无人声、风格、循环和响度，再构建。`--ai` 要求各角色已有完成回执与对应音频，不在导入时生成。只换音乐不需要重建 Unity；原生工程生成器按集合唯一 music asset 打包，旧音乐留本机但不进入 App。

## 复验与边界

`check_character_media.py` 校验十二张母版/安装结果的尺寸、角色归属、哈希与双方目录；`check_character_collections.py` 校验音乐隔离、PCM 与循环证据。Key、签名 URL、角色模型及生成衍生图不传公开仓库。生成图片的参考版权边界与原始角色相同，CC0 音乐来源单独记录。

使用前按最新[百炼图像接口](https://help.aliyun.com/zh/model-studio/qwen-image-generation-and-editing-api-reference)与 [Fun-Music API](https://help.aliyun.com/zh/model-studio/fun-music-api)核对能力；本轮版本与真实测试见[实施记录](design/2026-09-30-character-atmosphere-and-voice.md)。
