# 恢复预览角色为会话包

此参考用于几何已审核但因VRChat依赖仅发布为预览的模型。实际结果见
[16角色验收](../../../../docs/verification/sixteen-companions/README.md)。

- 原控制IR、作者默认状态及avatar-motions是来源，不能只按文件名猜情绪。
  BlendTree按默认/控制参数解析真实子动作；静态脸部读取原曲线权重。
- vrchat_conversation_projection逐层筛完整图。未知motion不替为空clip，只有已核对
  的三个SDK中性代理允许用宿主rest。省略层/GUID/控制写coverage并保留全部原IR。
- 移动、视点、VR输入不等于站立聊天。参数变化不等于视觉通过，菜单数不是身体动画数。
- 原作静态脸部可独立恢复：头部renderer和morph存在、曲线权重恒定、绑定预算合规。
  动态表情不能截一帧冒充预设。MA/NDMF数据须来自官方隔离构建及GUID/fileID核验。
- 超旧分组容量显式使用avatar-controls@2和performance@3，旧边界、GLB/文件预算
  保持。@2可用严格递增的track采样时刻，仅恒定transform做两端点无损压缩。

已有私有stage/IR/媒体的示例（不是从公开Git重建许可资产的办法）：

```bash
.local/character-venv/bin/python scripts/prepare_companion_packages.py
unity run "$PWD/unity/CharacterRuntime" --timeout 1800 -- \
  -buildTarget iOS -executeMethod PortableAvatarReview.RunCompanions16 \
  -logFile "$PWD/.local/logs/companion-controls.log"
unity run "$PWD/unity/CharacterRuntime" --timeout 1800 -- \
  -buildTarget iOS -executeMethod PortableAvatarReview.RunCompanionFaces \
  -logFile "$PWD/.local/logs/companion-faces.log"
.local/character-sdk-venv/bin/python scripts/activate_companion_packages.py
```

最后仅preflight。新批次审查controls/faces、物理和render及同一manifest哈希后才用
--apply，保留旧包/native rollback。激活后别重跑已完成候选的旧prepare，origin变化
拒绝是保护，不删标记绕过。后续新批次应准备自己的候选和审查目录。

媒体复用在companion-adaptations列供体，复制为角色自己作用域，验证来源SHA。
用户已取消生图，只有新明确授权才能改策略。服务器音色别名、初见合成及动态缓存
在独立server仓库处理，认证与voice ID不放公共角色包。

脸部组复位不能清其他原控。恢复控制器后用CharacterModelAutonomyReview.RunPrepared
验证有/无口型的全部支持角色，它显式打开场景。若作者tracking禁宿主眨眼，应证明
作者眼皮有真实变化。最后实际导出、验证Simulator/Device，校对authoring初见清单
与所有已启用会话角色一致，再逐模型UI及真实对话/语音检查。
