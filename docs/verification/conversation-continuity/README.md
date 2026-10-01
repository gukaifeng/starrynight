# 0.80.0 会话切页与接话交互验收

2026-10-01，版本 0.80.0（107）。设计与根因见[实施记录](../../design/2026-10-01-conversation-continuity.md)。原始日志、截图、视频及安装回执存放于忽略的 `.local/checks/`。

## 已通过

- A 轮 `testThinkingSurvivesTabReturnAndReplyFinishesOnce`：26.252 秒。发送后显示三个点，切到发现再返回仍等待，原回复完成一次，无重复消息。
- A 轮 `testHiddenReplyPersistsAndSuggestedSendAnimates`：37.380 秒。等待期间离开到消息，列表收到已完成回复；返回有正文且无中断提示。「灵感接话」打开／关闭／重开／选择发送成功，选中的用户消息只出现一次。
- A 轮 `testAudioThreadPlaybackAndCachedVocalBeat`：8.547 秒。真实 AVAudioEngine 播放、音频队列、口型时间及缓存重播回归通过；新增播放中隐藏不取消 drain、隐藏段不输出、完整时长与 PCM 保留、返回恢复播放检查。
- B 轮 `testLeftSwipeInlineActionsAndDeletionConfirmation`：31.430 秒。关闭时右滑不展开、左滑展开、内容区右滑收回、空白边缘左滑展开、从操作区域右滑收回，无误触删除／隐藏；红色删除、确认保留、取消回位、不显示和撤销均通过。
- D 轮 `testReplyRightAlignmentBlankDismissAndContinuousAtmosphere`：48.661 秒，`TEST SUCCEEDED`。弹窗横竖屏右沿对齐、空白点击关闭、打开时模型仍可拖动；连续氛围向右递增、两端值、反向非档位值与重开保留均通过。最终共 5 条不同用例通过。

上述生成检查使用延迟传输 fixture；没有调用付费 AI、ASR、TTS。不是百炼网络时延测量，也不是设备帧率验收。

## 检查中发现的问题

A 轮整行左滑检查失败在旧的无障碍几何假设：手势覆盖整行后，系统报告的内容按钮 frame 包括整行操作区，因此不应再把它当作视觉内容宽度。失败录屏提取的 `.local/checks/conversation-swipe-A.png` 确认实际布局依然在右侧并排、没有覆盖文字。改为检查操作位于整行右半部、右边沿对齐、按钮分离，再实际从内容区、空白区和操作区反向拖动，检查无误触。失败结果保留在 `ConversationContinuity-A.xcresult`。

B 轮弹窗横竖屏对齐、空白关闭和模型拖动通过，但复合用例后段的氛围滑块检查失败：XCTest `adjust(toNormalizedSliderPosition:0.5)` 实际拖到了 61%，超出此前 9% 容差。截图 `.local/checks/atmosphere-continuity-B.png` 与录像保留。

C 轮改用真实触摸路径，从实时滑块位置出发；零、25%、50%、75%、最大的位置检查通过，但从最大拖回目标 37% 时实际为 44%，仍超过收紧到 4% 的误差。原生滑块的抓取偏移与手势起始阈值使自动化端点不能视作精确值。最终检查改为真正的交互合同：向右连续拖动值严格递增、两端精确关闭／最大、反向拖到任意中间值且不吸附旧档位、关窗重开保留实际值。小数精确性由既有 0.373 落盘 fixture 与连续曲线检查负责。产品滑块和氛围映射没有为测试改动，A/B/C 失败记录均保留。

## 安装与验证边界

真机 Release 编译与严格签名验证通过，构建日志 `.local/logs/host-device-20261001-182327.log`。iPhone 17 安装成功并回读 **星夜 0.80.0（107）**，回执为 `conversation-continuity-device-install.json` 和 `conversation-continuity-device-apps.json`。自动启动返回 `Locked`，没有把安装成功描述成真机操作验收；解锁后可手动打开。未卸载或清空用户档案。

未运行全部历史套件，未测 iPad 或真机持续帧率。此轮没有更改 AI 服务地址，独立公网后端仍是上一轮已明确的待决事项。
