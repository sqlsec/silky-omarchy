# 05 · Waveform overlay for WowType voice input

[简体中文](../05-voice-overlay.md) | English

## Goal

On Hyprland, WowType's voice prompt is only a microphone icon and a line of text inside the candidate window. This replaces it with a frosted pill: a blue-violet gradient microphone on the left (its ring breathes with the volume), three blue, violet and pink waveforms in the middle that follow your real voice level, and a status label on the right. While recognizing, the waves turn into a soft shimmer; the recognized text flashes in the pill, then the pill folds away.

## How it works

WowType ships a D-Bus protocol for external overlays (its GNOME extension draws its voice pill that way, but GNOME extensions cannot run on Hyprland):

- As soon as any program owns `io.github.gloridust.WowType.VoiceOverlay` on the session bus, WowType stops drawing the text hint in the candidate window
- While you speak it emits a `State` signal every 50 ms: state (listening / recognizing / done / error), text, level (0–100) and cursor position
- The overlay must answer every state it shows with an `Ack`, otherwise WowType falls back to the candidate-window text hint for that utterance

| File | Role |
| --- | --- |
| `voice-overlay/bridge.py` | Owns the name above, turns `State` into JSON lines and answers with `Ack` |
| `voice-overlay/shell.qml` | Quickshell pill that draws the waves on the GPU every frame; takes no clicks and never steals focus |
| `config/hypr/silky-voice.lua` | Starts the overlay at login and gives it Hyprland background blur |

The pill sits at the bottom centre of the screen, above the Dock. It does not follow the cursor: on Wayland WowType reports window-relative cursor coordinates, so a fixed position is more reliable.

The level mapping matches WowType's own overlay: `-60 dB…-10 dB` maps to 0–100, and below about 20 (a quiet room) the waves stay flat. The waves rise fast and fall slowly, like a VU meter.

## Install

```bash
./scripts/install-voice-overlay.sh
```

Preview the look (with a simulated voice, no recording needed):

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

## Rollback

- Remove `require("hypr.silky-voice")` at the end of `hyprland.lua`, and `~/.config/hypr/silky-voice.lua`
- `pkill -f 'qs -c SilkyVoice'` and delete `~/.config/quickshell/SilkyVoice`

Once the overlay is gone, WowType's next utterance automatically goes back to the text hint in the candidate window.
