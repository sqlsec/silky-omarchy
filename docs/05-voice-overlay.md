# 05 · WowType 和 vinput 的声波浮条

简体中文 | [English](en/05-voice-overlay.md)

## 目标

WowType 在 Hyprland 上的语音提示只是候选框里的一个话筒图标加一行字。这里换成一条毛玻璃浮条：左边是蓝紫渐变的话筒（外圈跟着音量呼吸），中间是三条蓝、紫、粉的声波曲线跟着你的真实音量起伏，右边是状态文字；识别时声波变成轻微的流光，识别出的文字在浮条里显示一下后收起。

## 原理

WowType 自带一套给外部浮条用的 D-Bus 协议（它的 GNOME 扩展就是这么画语音浮条的，但 GNOME 扩展在 Hyprland 上用不了）：

- 只要会话总线上有程序占用 `io.github.gloridust.WowType.VoiceOverlay`，WowType 就不再在候选框里画文字提示
- 说话期间每 50 ms 发一次 `State` 信号：状态（听 / 识别 / 完成 / 出错）、文字、音量（0–100）、光标位置
- 浮条每显示一个状态都要回一个 `Ack`，否则 WowType 在这次说话里退回候选框文字提示

| 文件 | 作用 |
| --- | --- |
| `voice-overlay/bridge.py` | 占用上面的名字，把 `State` 转成 JSON 行输出，并回 `Ack` |
| `voice-overlay/shell.qml` | Quickshell 浮条，在 GPU 上逐帧画声波；不接收点击，不抢焦点 |
| `config/hypr/silky-voice.lua` | 登录时启动浮条，并给它加 Hyprland 背景模糊 |

浮条固定在屏幕底部中间、Dock 上方。这里没有按光标位置摆放：Wayland 下 WowType 给出的是相对窗口的光标坐标，固定位置更稳定。

音量换算和 WowType 官方浮条一致：`-60 dB…-10 dB` 映射到 0–100，安静环境约 20 以下不起波；声波上升快、回落慢，看起来像音量表。

## 安装

```bash
./scripts/install-voice-overlay.sh
```

预览外观（用模拟的说话音量，不需要真的录音）：

```bash
SILKY_VOICE_DEMO=1 qs -c SilkyVoice
```

## 验证

```bash
busctl --user list | grep VoiceOverlay
```

应看到名字由 `python3` 占用。然后在 WowType 下按住右 Alt 说话。

## 和 Superwhisper 的冲突

WowType 的语音键是右 Alt，而 Omarchy 默认把右 Alt、Alt+Space、F9、Super+Ctrl+X 绑定为“系统听写”，后端是 Superwhisper。按右 Alt 会同时触发两者，Superwhisper 每次都会被拉起来。

处理方式：清空 `~/.config/omarchy/defaults/dictation`（原值已备份），Omarchy 就不再绑定这些听写键，也不再加载 Superwhisper 的快捷键桥；同时关闭了 Superwhisper 的开机自启。想恢复 Omarchy 的听写，在 Omarchy 菜单 Setup → Defaults → Dictation 里重新选择即可。

## vinput 的流式识别与声波

下面的改动适用于 **fcitx5-vinput 2.4.2** 和 Sherpa-ONNX 1.13.8。在已经安装 vinput 的机器上重新执行上面的安装脚本即可接入录音状态。屏幕底部的声波在录音时亮起，提交或取消后收起。流式草稿由 vinput 在输入法里显示。

[2.4.2 本机补丁](../voice-overlay/vinput-2.4.2.patch) 消除流式录音的句尾截断。它在结束前给模型补一秒静音，以解码最后一帧音频。从 vinput 已采集的音频每 50 毫秒计算一次音量，通过 D-Bus 的 `AudioLevel` 信号驱动声波。官方原版 daemon 可驱动浮条的录音状态动画。使用补丁版时，波形会跟随真实音量。

在 vinput 的 `v2.4.2` 源码目录应用补丁，再按该版本的构建步骤编译 `daemon` 目标。以当前用户已安装的 vinput 前缀设置 `CMAKE_INSTALL_PREFIX`，并让 CMake 使用上游发行包自带的 Sherpa 库和 1.13.8 头文件。把编译结果另存为 `vinput-daemon-silky`，用 `~/.config/systemd/user/vinput-daemon.service.d/50-silky-voice.conf` 覆盖 `ExecStart`，随后执行 `systemctl --user daemon-reload` 和 `systemctl --user restart vinput-daemon.service`。

本机使用 [X-ASR 480 ms 中英流式模型](https://huggingface.co/GilgameshWind/X-ASR-zh-en) 并开启热词。960 ms 版实测可用同一份词表和 BPE 模型。若已经有 960 ms 模型，可将 480 ms 版的模型文件放到同级新目录，复用原来的 `vinput-model.json` 和 `bpe.vocab`，把 `recognizer.decoding_method`、`max_active_paths` 和 `hotwords_score` 分别设为 `modified_beam_search`、`6`、`2.2`，通过 `vinput model list` 和 `vinput model use <模型 ID>` 确认并启用。

用 `busctl --user introspect org.fcitx.Vinput /org/fcitx/Vinput` 确认 `AudioLevel` 信号存在。按住右 Alt 后检查浮条、实时文本和语音音量变化。要恢复原 daemon，移除上述 systemd 覆盖并重新载入、重启服务。识别模型可单独切回 960 ms。

本机使用合成中英录音，通过 PipeWire 测试了实时文字、未加尾部静音时的完整定稿，以及录音期间浮条显示和音量数值变化。技术词可以在 `~/.config/vinput/hotwords.txt` 中调整。

## 回滚

- 删除 `hyprland.lua` 末尾的 `require("hypr.silky-voice")` 和 `~/.config/hypr/silky-voice.lua`
- `pkill -f 'qs -c SilkyVoice'`，删除 `~/.config/quickshell/SilkyVoice`

浮条一退出，WowType 下一次说话就自动回到候选框里的文字提示。
