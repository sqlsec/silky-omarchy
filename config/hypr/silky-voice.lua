-- Silky Omarchy: waveform pill for WowType voice input (voice-overlay/ in this repo, installed to
-- ~/.config/quickshell/SilkyVoice). It takes over WowType's own text hint while you dictate.
hl.on("hyprland.start", function()
  -- Stagger non-critical Quickshell startup so MacLock and MacShell get first-second CPU/IO.
  hl.exec_cmd("sleep 3 && exec qs -c SilkyVoice")
end)

-- Frosted glass behind the pill; no fade from Hyprland, the pill animates itself.
hl.layer_rule({ name = "silky-voice", match = { namespace = "silky-voice" }, blur = true, ignore_alpha = 0.05, no_anim = true })
