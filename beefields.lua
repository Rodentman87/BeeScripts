-- beefields.lua  ->  install to /lib/beefields.lua
-- What the settings screen can edit: one table, two columns, in the
-- order they appear. beecfgui draws it; beeconf writes it.
--
-- kind "num"   -- minus / plus, clamped to min..max, stepping by step
--      "bool"  -- a tick box
--      "cycle" -- left / right through `options`
-- `scale` means the setting is a fraction of a second and is edited
-- in whole units of it (animDelay 0.5s edits as 5 at scale 0.1), so
-- nobody has to type a decimal point with two buttons.
-- `def` is the in-code default: a deployed beeconfig predates half
-- of these keys, and a nil would make the whole row unusable.

local fields = {}

fields.TEMPS  = {"Icy", "Cold", "Normal", "Warm", "Hot", "Hellish"}
fields.HUMIDS = {"Arid", "Normal", "Damp"}

fields.LEFT = {
  {group = "Breeding"},
  {label = "goal", icon = "drone", key = "droneGoal", kind = "num",
   def = 16, min = 1, max = 999},
  {label = "pure", icon = "pure", key = "requirePure", kind = "bool", def = false},
  {label = "per queen", icon = "chat", key = "chatEveryQueen",
   kind = "bool", def = true},
  {label = "stall warn", key = "stagnantWarn", kind = "num",
   def = 10, min = 1, max = 999},
  {group = "Floors"},
  {label = "floor", icon = "princess", key = "princessFloor", kind = "num",
   def = 1, min = 0, max = 64},
  {label = "floor", icon = "drone", key = "droneFloor", kind = "num",
   def = 4, min = 0, max = 999},
  {label = "auto-tend", icon = "pure", key = "autoTend", kind = "bool", def = false},
  {label = "rescan s", icon = "rescan", key = "homeRescan", kind = "num",
   def = 300, min = 30, max = 3600, step = 30},
  {group = "Timing"},
  {label = "poll s", key = "pollDelay", kind = "num", def = 5, min = 1, max = 60},
  {label = "tick x0.1 s", key = "animDelay", kind = "num",
   def = 0.5, min = 1, max = 50, scale = 0.1},
  {label = "shimmer x0.05 s", key = "shimmerStep", kind = "num",
   def = 0.25, min = 1, max = 40, scale = 0.05},
  {label = "scan timeout s", key = "scanTimeout", kind = "num",
   def = 90, min = 10, max = 600, step = 10},
  {group = "Screen"},
  {label = "ASCII glyphs", key = "asciiGlyphs", kind = "bool", def = false},
}

fields.RIGHT = {
  {group = "Climate"},
  {label = "ask hive", icon = "apiary", key = "climateAuto",
   kind = "bool", def = true},
  {label = "fallback", icon = "temp", key = "apiaryTemperature",
   kind = "cycle", def = "Normal", options = fields.TEMPS},
  {label = "fallback", icon = "humid", key = "apiaryHumidity",
   kind = "cycle", def = "Normal", options = fields.HUMIDS},
  {label = "penalty", key = "climatePenalty", kind = "num",
   def = 60, min = 0, max = 500, step = 10},
  {group = "Robot"},
  {label = "robot", icon = "bot", key = "botEnabled", kind = "bool", def = false},
  {label = "port", key = "botPort", kind = "num", def = 4477, min = 1, max = 65535},
  {label = "timeout s", key = "botTimeout", kind = "num", def = 10, min = 1, max = 120},
}

-- Every editable field, both columns, in screen order
function fields.each(fn)
  for _, list in ipairs({fields.LEFT, fields.RIGHT}) do
    for _, f in ipairs(list) do
      if f.key then fn(f) end
    end
  end
end

-- The value as the screen edits it: scaled settings become whole
-- units, everything else is itself.
function fields.read(f, config)
  local v = config[f.key]
  if v == nil then v = f.def end
  if f.scale then return math.floor((v or 0) / f.scale + 0.5) end
  if f.kind == "bool" then return v == true end
  return v
end

-- ...and back again, ready for beeconf.write
function fields.out(f, v)
  if f.scale then return v * f.scale end
  return v
end

-- One press of a control. dir is -1 or 1; bool ignores it.
function fields.bump(f, v, dir)
  if f.kind == "bool" then return not v end
  if f.kind == "cycle" then
    local at = 1
    for i, o in ipairs(f.options) do
      if o == v then at = i end
    end
    return f.options[(at - 1 + dir) % #f.options + 1]
  end
  local n = v + dir * (f.step or 1)
  return math.max(f.min or 0, math.min(f.max or 9999, n))
end

return fields
