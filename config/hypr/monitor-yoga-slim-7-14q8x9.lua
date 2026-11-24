-- Lenovo Yoga Slim 7 14Q8X9 built-in panel: use the native 90 Hz mode so
-- touch, window dragging and MacShell animations are not limited to 60 Hz.
hl.monitor({ output = "eDP-1", mode = "2944x1840@90", position = "0x0", scale = 2 })

-- External BOE 0x0A52 (3840x2400, 60-120 Hz continuous):
-- On Snapdragon X Elite (x1e80100), DPU max_core_clk_rate is capped at 575 MHz
-- in the device tree opp-table (2-LM -> 1150 MHz; adjusted by 1.05 -> ~1095 MHz
-- max pixel clock), so the EDID 120 Hz timing (1176.01 MHz) is rejected as
-- MODE_CLOCK_HIGH by dpu_crtc_mode_valid. Using the panel's exact EDID blanking
-- (4000x2450) at 110 Hz (1078.00 MHz) stays inside both the 575 MHz DPU limit
-- (565.95 MHz/LM) and uncompressed DP 1.4 HBR3 4-lane bandwidth (25.87 Gbps).
hl.monitor({
  output = "desc:BOE 0x0A52",
  mode = "modeline 1078.00 3840 3888 3920 4000 2400 2403 2408 2450 -hsync -vsync",
  position = "1472x-319",
  scale = 2,
})
