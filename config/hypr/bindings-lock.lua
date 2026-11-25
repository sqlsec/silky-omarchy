
-- Silky Omarchy: Super+Ctrl+L locks with MacLock too (Super+L already does, from MacShell's macshell.lua).
o.rebind("SUPER + CTRL + L", "Lock system", "silky-lock")

-- Silky Omarchy: lid close locks with MacLock instead of omarchy-system-lid-close (omarchy.lock).
o.rebind("switch:on:Lid Switch", nil, "silky-lid-close", { locked = true })
o.rebind("switch:on:Apple SMC power/lid events", nil, "silky-lid-close", { locked = true })
o.rebind("switch:on:cros_ec_buttons", nil, "silky-lid-close", { locked = true })
