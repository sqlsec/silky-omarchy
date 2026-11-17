-- Silky Omarchy: a record of every keybinding, for the Super+K panel (keys-panel/ in this repo).
--
-- Hyprland has no Lua call that lists binds with what they do, and `hyprctl binds` reports Lua binds as bare ids,
-- so this wraps hl.bind / hl.unbind while the config loads and remembers each bind: its keys, its description,
-- the file that made it and its dispatcher. It must be required FIRST in hyprland.lua, before Omarchy's defaults.
--
-- The panel talks to it through `hyprctl dispatch`, which runs Lua in this same state:
--   hyprctl dispatch 'function() silky_keys.dump("/run/user/1000/silky-keys.json") end'
--   hyprctl dispatch 'function() silky_keys.run(42) end'     -- does what pressing that bind's keys does

-- hl survives `hyprctl reload`, so keep the real functions from the first load instead of wrapping a wrapper.
local real = _G.silky_keys_real or { bind = hl.bind, unbind = hl.unbind }
_G.silky_keys_real = real

local binds = {}

local mod_order = { SUPER = 1, SHIFT = 2, CTRL = 3, ALT = 4 }
local mod_alias = { CONTROL = "CTRL", MOD4 = "SUPER", WIN = "SUPER", LOGO = "SUPER", META = "SUPER", MOD1 = "ALT" }

-- "super + shift + l" and "SUPER + SHIFT + L" are the same chord.
local function parse(keys)
  local mods, key = {}, ""
  for part in tostring(keys or ""):gmatch("[^+]+") do
    local p = part:gsub("^%s+", ""):gsub("%s+$", "")
    local up = p:upper()
    up = mod_alias[up] or up
    if mod_order[up] then
      mods[#mods + 1] = up
    elseif p ~= "" then
      key = p
    end
  end
  table.sort(mods, function(a, b) return mod_order[a] < mod_order[b] end)
  local norm_key = key:match("^[Cc][Oo][Dd][Ee]:") and key:lower() or key:upper()
  return mods, key, table.concat(mods, " ") .. "|" .. norm_key
end

-- The config file that made the bind, skipping Omarchy's o.bind helpers and this file.
local function caller()
  for level = 3, 12 do
    local info = debug.getinfo(level, "S")
    if not info then break end
    local src = info.source or ""
    if src:sub(1, 1) == "@" and not src:find("helpers%.lua$") and not src:find("silky%-keys%-registry%.lua$") then
      return src:sub(2)
    end
  end
  return ""
end

hl.bind = function(keys, dispatcher, opts)
  local mods, key, id = parse(keys)
  binds[#binds + 1] = {
    keys = keys, mods = mods, key = key, id = id, dispatcher = dispatcher,
    description = type(opts) == "table" and opts.description or nil,
    release = type(opts) == "table" and opts.release == true or false,
    mouse = type(opts) == "table" and opts.mouse == true or false,
    source = caller(),
  }
  return real.bind(keys, dispatcher, opts)
end

hl.unbind = function(keys, ...)
  local _, _, id = parse(keys)
  for i = #binds, 1, -1 do
    if binds[i].id == id then table.remove(binds, i) end
  end
  return real.unbind(keys, ...)
end

local function json_string(s)
  s = tostring(s or "")
  s = s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    if c == "\n" then return "\\n" end
    if c == "\t" then return "\\t" end
    return string.format("\\u%04x", c:byte())
  end)
  return '"' .. s .. '"'
end

_G.silky_keys = {
  -- Every bind that has a description, in the order the config made them.
  dump = function(path)
    local out = {}
    for i, b in ipairs(binds) do
      if b.description and b.description ~= "" then
        local mods = {}
        for _, m in ipairs(b.mods) do mods[#mods + 1] = json_string(m) end
        out[#out + 1] = string.format('{"n":%d,"mods":[%s],"key":%s,"desc":%s,"src":%s,"release":%s,"mouse":%s}',
          i, table.concat(mods, ","), json_string(b.key), json_string(b.description), json_string(b.source),
          tostring(b.release), tostring(b.mouse))
      end
    end
    local f = io.open(path .. ".tmp", "w")
    if not f then return end
    f:write("[" .. table.concat(out, ",\n") .. "]\n")
    f:close()
    os.rename(path .. ".tmp", path)
  end,

  -- Do what a press of that bind's keys does: every press bind on the chord runs, as with a real key press.
  run = function(n)
    local target = binds[n]
    if not target then return end
    for _, b in ipairs(binds) do
      if b.id == target.id and b.release == target.release then
        local d = b.dispatcher
        if type(d) == "function" then
          pcall(d)
        elseif d ~= nil then
          pcall(hl.dispatch, d)
        end
      end
    end
  end,
}
