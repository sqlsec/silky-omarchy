# 05 · Waveform overlay for WowType and vinput

[简体中文](../05-voice-overlay.md) | English

## Goal

The frosted pill combines the microphone, voice status and sound-reactive waveform. For streaming vinput, live text appears above the slim waveform in the same pill. Long lines keep the latest words visible and the pill stays the same width. While recognition finishes, the waveform shimmers and the draft stays visible.

## How it works

WowType ships a D-Bus protocol for external overlays (its GNOME extension draws its voice pill that way, but GNOME extensions cannot run on Hyprland):

- As soon as any program owns `io.github.gloridust.WowType.VoiceOverlay` on the session bus, WowType stops drawing the text hint in the candidate window
- While you speak it emits a `State` signal every 50 ms: state (listening / recognizing / done / error), text, level (0–100) and cursor position
- The overlay must answer every state it shows with an `Ack`, otherwise WowType falls back to the candidate-window text hint for that utterance

| File | Role |
| --- | --- |
| `voice-overlay/bridge.py` | Owns the name above, turns `State` into JSON lines and answers with `Ack` |
| `voice-overlay/shell.qml` | Quickshell pill that animates the waveform and displays the caption without taking focus or clicks |
| `config/hypr/silky-voice.lua` | Starts the overlay at login and gives it Hyprland background blur |

The pill sits at the bottom centre of the screen, above the Dock. It does not follow the cursor: on Wayland WowType reports window-relative cursor coordinates, so a fixed position is more reliable.

The level mapping matches WowType's own overlay: `-60 dB…-10 dB` maps to 0–100, and below about 20 (a quiet room) the waves stay flat. The waves rise fast and fall slowly, like a VU meter.

## Install

```bash
./scripts/install-voice-overlay.sh
```

The installer backs up changed files as `*.bak.*` beside their installed copies. Preview with a sample caption and simulated speech:

```bash
SILKY_VOICE_DEMO=1 qs -c SilkyVoice
```

## Verify

```bash
busctl --user list | grep VoiceOverlay
```

The name should be owned by `python3`. Then hold Right Alt in WowType and speak.

## The Superwhisper clash

WowType's voice key is Right Alt, while Omarchy binds Right Alt, Alt+Space, F9 and Super+Ctrl+X to "system dictation" by default, backed by Superwhisper. Pressing Right Alt triggered both, and Superwhisper was launched every time.

Fix: `~/.config/omarchy/defaults/dictation` is emptied (the old value is backed up), so Omarchy no longer binds those dictation keys or loads Superwhisper's shortcut bridge; Superwhisper's autostart is turned off too. To bring Omarchy's dictation back, choose it again under Omarchy menu → Setup → Defaults → Dictation.

## Streaming vinput and its waveform

These changes target **fcitx5-vinput 2.4.2** with Sherpa-ONNX 1.13.8. If vinput is already installed, rerun the overlay installer above to connect it to the recording states. The overlay reads the daemon's existing `RecognitionPartial` signal and keeps the draft through recognition. Cancelling clears it, and the next recording starts with a clean caption. The stock addon still shows a copy near the cursor. The optional addon patch below moves the ordinary dictation preview entirely into the pill.

The [local 2.4.2 patch](../../voice-overlay/vinput-2.4.2.patch) pads the streaming audio with one second of silence at the end so the model can decode the last frame. It also calculates the level of the audio vinput is already capturing every 50 ms and sends it to the overlay as a D-Bus `AudioLevel` signal. A stock daemon drives the recording animation. A patched daemon makes the waveform follow your actual voice level.

Apply the patch to the vinput `v2.4.2` source tree and build its `daemon` target. Set `CMAKE_INSTALL_PREFIX` to the installed user prefix and point CMake at the release bundle's Sherpa libraries and the 1.13.8 headers. Install the result under the name `vinput-daemon-silky` and override `ExecStart` in `~/.config/systemd/user/vinput-daemon.service.d/50-silky-voice.conf`. Run `systemctl --user daemon-reload` and `systemctl --user restart vinput-daemon.service`.

### Move the cursor preview into the pill

Apply the [vinput 2.4.2 addon patch](../../voice-overlay/vinput-2.4.2-addon.patch) in the [upstream v2.4.2 source tree](https://github.com/xifan2333/fcitx5-vinput/tree/v2.4.2). It detects the bridge's `org.fcitx.Vinput.SilkyVoice` D-Bus name and suppresses the original preview during ordinary dictation. The preview falls back to the input panel if the bridge exits. Command prompts, postprocessing actions, and result candidates stay in the input panel.

Build only the Fcitx5 frontend addon. Local ASR can be disabled for this build because the installed daemon continues running the recognizer:

```bash
cmake -S . -B build-addon -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$HOME/.local/opt/fcitx5-vinput-2.4.2" \
  -DVINPUT_ENABLE_LOCAL_ASR=OFF -DBUILD_TESTING=OFF
cmake --build build-addon --target addon
```

With vinput idle, back up the loaded `fcitx5-vinput.so` and replace it with `build-addon/src/addon/fcitx5-vinput.so`. On this aarch64 installation the loaded module lives at `~/.local/opt/fcitx5-vinput-2.4.2/lib/aarch64-linux-gnu/fcitx5/fcitx5-vinput.so`. Restart Fcitx5, using `systemctl --user restart omarchy-fcitx5.service` on Omarchy. Hold Right Alt in a test editor to check that the draft stays inside the pill and the final text lands in the editor on release. Restore the backed-up module and restart Fcitx5 to roll back the addon.

### Model and waveform verification

The installation here uses the [X-ASR 480 ms Chinese-English streaming model](https://huggingface.co/GilgameshWind/X-ASR-zh-en) with hotwords. Its token and BPE model files match those in the 960 ms variant. If the 960 ms model is installed, put the 480 ms model in a sibling directory, copy the original `vinput-model.json` and `bpe.vocab`, and set `recognizer.decoding_method`, `max_active_paths`, and `hotwords_score` to `modified_beam_search`, `6`, and `2.2`, respectively. Use `vinput model list` and `vinput model use <model ID>` to verify and activate it.

Run `busctl --user introspect org.fcitx.Vinput /org/fcitx/Vinput` to verify that the `AudioLevel` signal is available. Hold Right Alt to verify the overlay, live text, and sound-reactive waveform. To restore the packaged daemon, remove the systemd override, reload systemd, and restart the service. You can switch the ASR model back to 960 ms independently.

On Hyprland, holding Right Alt in a temporary editor with synthetic audio routed through PipeWire verified that the live transcript appeared in the pill and the final result reached the editor. Closing the overlay restored the live preview beside the cursor. A separate D-Bus test checked that the draft survives meter and heartbeat updates, stays visible during recognition, and clears on cancellation or a new recording. Edit technical terms in `~/.config/vinput/hotwords.txt`.

## Rollback

To restore the previous pill, copy the saved `shell.qml.bak.*` and `bridge.py.bak.*` back to their original names in `~/.config/quickshell/SilkyVoice` and restart `qs -c SilkyVoice`. To uninstall the pill:

- Remove `require("hypr.silky-voice")` at the end of `hyprland.lua`, and `~/.config/hypr/silky-voice.lua`
- `qs kill -c SilkyVoice` and delete `~/.config/quickshell/SilkyVoice`

Once the overlay is gone, WowType's next utterance automatically goes back to the text hint in the candidate window.
