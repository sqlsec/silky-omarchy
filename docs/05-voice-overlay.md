# 05 · WowType 语音输入的声波浮条

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

## 回滚

- 删除 `hyprland.lua` 末尾的 `require("hypr.silky-voice")` 和 `~/.config/hypr/silky-voice.lua`
- `pkill -f 'qs -c SilkyVoice'`，删除 `~/.config/quickshell/SilkyVoice`

浮条一退出，WowType 下一次说话就自动回到候选框里的文字提示。
