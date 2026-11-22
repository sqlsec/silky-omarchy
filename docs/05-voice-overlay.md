# 05 · WowType 和 vinput 的声波浮条

简体中文 | [English](en/05-voice-overlay.md)

## 目标

毛玻璃浮条把话筒、语音状态和声波放在同一个胶囊里。vinput 的实时转写显示在细声波上方，长句优先保留最新说出的文字，浮条宽度保持稳定。收尾识别时声波轻微流动，草稿会继续显示。

## 原理

WowType 自带一套给外部浮条用的 D-Bus 协议（它的 GNOME 扩展就是这么画语音浮条的，但 GNOME 扩展在 Hyprland 上用不了）：

- 只要会话总线上有程序占用 `io.github.gloridust.WowType.VoiceOverlay`，WowType 就不再在候选框里画文字提示
- 说话期间每 50 ms 发一次 `State` 信号：状态（听 / 识别 / 完成 / 出错）、文字、音量（0–100）、光标位置
- 浮条每显示一个状态都要回一个 `Ack`，否则 WowType 在这次说话里退回候选框文字提示

| 文件 | 作用 |
| --- | --- |
| `voice-overlay/bridge.py` | 占用上面的名字，把 `State` 转成 JSON 行输出，并回 `Ack` |
| `voice-overlay/shell.qml` | Quickshell 浮条，显示字幕和动态声波，不接收点击或焦点 |
| `config/hypr/silky-voice.lua` | 登录时启动浮条，并给它加 Hyprland 背景模糊 |

浮条固定在屏幕底部中间、Dock 上方。这里没有按光标位置摆放：Wayland 下 WowType 给出的是相对窗口的光标坐标，固定位置更稳定。

音量换算和 WowType 官方浮条一致：`-60 dB…-10 dB` 映射到 0–100，安静环境约 20 以下不起波；声波上升快、回落慢，看起来像音量表。

## 安装

```bash
./scripts/install-voice-overlay.sh
```

安装器会在被覆盖的文件旁保留 `*.bak.*` 备份。可以用示例字幕和模拟音量预览外观：

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

下面的改动适用于 **fcitx5-vinput 2.4.2** 和 Sherpa-ONNX 1.13.8。在已经安装 vinput 的机器上重新执行上面的安装脚本即可接入录音状态。浮条直接读取 daemon 已有的 `RecognitionPartial` 信号，实时草稿会保留到收尾识别。取消时清空草稿，每次新录音从空字幕开始。原版 Fcitx5 插件仍会在光标旁显示一份草稿，可用下面的插件补丁把普通听写预览完全移入浮条。

[2.4.2 本机补丁](../voice-overlay/vinput-2.4.2.patch) 消除流式录音的句尾截断。它在结束前给模型补一秒静音，以解码最后一帧音频。从 vinput 已采集的音频每 50 毫秒计算一次音量，通过 D-Bus 的 `AudioLevel` 信号驱动声波。官方原版 daemon 可驱动浮条的录音状态动画。使用补丁版时，波形会跟随真实音量。

在 vinput 的 `v2.4.2` 源码目录应用补丁，再按该版本的构建步骤编译 `daemon` 目标。以当前用户已安装的 vinput 前缀设置 `CMAKE_INSTALL_PREFIX`，并让 CMake 使用上游发行包自带的 Sherpa 库和 1.13.8 头文件。把编译结果另存为 `vinput-daemon-silky`，用 `~/.config/systemd/user/vinput-daemon.service.d/50-silky-voice.conf` 覆盖 `ExecStart`，随后执行 `systemctl --user daemon-reload` 和 `systemctl --user restart vinput-daemon.service`。

### 把光标旁的预览移入浮条

在[上游 v2.4.2 源码目录](https://github.com/xifan2333/fcitx5-vinput/tree/v2.4.2)应用 [vinput 2.4.2 插件补丁](../voice-overlay/vinput-2.4.2-addon.patch)。插件检测桥接程序的 `org.fcitx.Vinput.SilkyVoice` D-Bus 名称，有浮条时将普通听写预览交给浮条。桥接程序退出后，输入面板恢复原有预览。命令提示、后处理操作和结果候选仍由原输入面板显示。

只编译 Fcitx5 前端插件。此次构建可以关闭本地 ASR，识别仍由已安装的 daemon 执行：

```bash
cmake -S . -B build-addon -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$HOME/.local/opt/fcitx5-vinput-2.4.2" \
  -DVINPUT_ENABLE_LOCAL_ASR=OFF -DBUILD_TESTING=OFF
cmake --build build-addon --target addon
```

在 vinput 空闲时备份当前载入的 `fcitx5-vinput.so`，用 `build-addon/src/addon/fcitx5-vinput.so` 替换。本机 aarch64 版本位于 `~/.local/opt/fcitx5-vinput-2.4.2/lib/aarch64-linux-gnu/fcitx5/fcitx5-vinput.so`。在 Omarchy 上执行 `systemctl --user restart omarchy-fcitx5.service` 重启输入法。在测试编辑器按住右 Alt，检查草稿只出现在浮条内，松开后定稿进入编辑器。恢复备份的插件并重启 Fcitx5 即可撤销插件补丁。

### 模型与声波验证

本机使用 [X-ASR 480 ms 中英流式模型](https://huggingface.co/GilgameshWind/X-ASR-zh-en) 并开启热词。960 ms 版实测可用同一份词表和 BPE 模型。若已经有 960 ms 模型，可将 480 ms 版的模型文件放到同级新目录，复用原来的 `vinput-model.json` 和 `bpe.vocab`，把 `recognizer.decoding_method`、`max_active_paths` 和 `hotwords_score` 分别设为 `modified_beam_search`、`6`、`2.2`，通过 `vinput model list` 和 `vinput model use <模型 ID>` 确认并启用。

用 `busctl --user introspect org.fcitx.Vinput /org/fcitx/Vinput` 确认 `AudioLevel` 信号存在。按住右 Alt 后检查浮条、实时文本和语音音量变化。要恢复原 daemon，移除上述 systemd 覆盖并重新载入、重启服务。识别模型可单独切回 960 ms。

在本机 Hyprland 的临时编辑器按住右 Alt，用 PipeWire 播放合成语音，确认录音时草稿显示在浮条里，松开后定稿进入编辑器。关闭浮条后，实时草稿恢复到光标旁。另用隔离的 D-Bus 会话确认音量和心跳更新保留草稿、收尾识别继续显示草稿、取消或重新录音清空草稿。技术词可以在 `~/.config/vinput/hotwords.txt` 中调整。

## 回滚

如需恢复上一版，把 `~/.config/quickshell/SilkyVoice` 里备份的 `shell.qml.bak.*` 和 `bridge.py.bak.*` 恢复为原文件名，然后重启 `qs -c SilkyVoice`。如需卸载浮条：

- 删除 `hyprland.lua` 末尾的 `require("hypr.silky-voice")` 和 `~/.config/hypr/silky-voice.lua`
- `qs kill -c SilkyVoice`，删除 `~/.config/quickshell/SilkyVoice`

浮条一退出，WowType 下一次说话就自动回到候选框里的文字提示。
