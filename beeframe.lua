-- beeframe.lua  ->  install to /lib/beeframe.lua
-- The chrome the four BeeHome screens share: the header bar with its
-- icon strip, the vertical divider down the middle, group rules, the
-- control bar along the bottom and the "Q -> somewhere" hint.
--
-- Everything here is layout only. A screen owns its own content and
-- its own buttons' behaviour; this owns where they sit, so home,
-- breed, settings and update cannot drift apart from each other.

local core    = require("beeui")
local config  = require("beeconfig")
local climate = require("beeclimate")
local C, g = core.C, core.g

local frame = {}

frame.DIV = 80          -- column the two panes split on, at 160 wide

-- The strip of state that is true wherever you are: how stale the
-- caches are, whether chat and the robot are on, the hive's climate,
-- whether the wiring checked out, how long we have been up. Bright =
-- on, dim = off, exactly as the dashboard header does it.
-- extra: {cacheAge = "2d", sidesOk = bool, uptime = "4h12m"}
function frame.statusItems(extra)
  extra = extra or {}
  local hive = climate.apiary()
  return {
    {g("route") .. " " .. (extra.cacheAge or "?"), extra.cacheAge ~= nil},
    {g("chat"), config.chatEveryQueen},
    {g("bot"), config.botEnabled},
    {("%s %s %s %s %s"):format(g("temp"), climate.tempName(hive.temp),
      g("humid"), climate.humidName(hive.humid),
      g(extra.climateOk == false and "warn" or "check")),
     extra.climateOk ~= false},
    {g("wire") .. " " .. g(extra.sidesOk == false and "warn" or "check"),
     extra.sidesOk ~= false},
    {extra.uptime or "", true},
  }
end

-- Title left, icon strip right-aligned. items = {{text, on}, ...}
function frame.header(title, items)
  if not core.hasGpu then return end
  local W = core.size()
  core.fillRect(1, 1, W, 1, C.header)
  core.text(2, 1, "BeeHome " .. g("smallR") .. " " .. title, C.headerFg, C.header)
  local total = 0
  for _, it in ipairs(items or {}) do total = total + core.len(it[1]) + 3 end
  local x = W - total
  for _, it in ipairs(items or {}) do
    core.text(x, 1, it[1], it[2] and C.headerFg or C.dim2, C.header)
    x = x + core.len(it[1]) + 3
  end
end

function frame.divider(x, y1, y2)
  if not core.hasGpu then return end
  for y = y1, y2 do core.text(x, y, g("v"), C.dim2) end
end

-- A group heading with a rule running out to `right`
function frame.group(x, y, title, right)
  if not core.hasGpu then return end
  core.text(x, y, title, C.header)
  local from = x + core.len(title) + 1
  if right > from then
    core.text(from, y, string.rep(g("h"), right - from), C.frame)
  end
end

-- Control bar. list = {{id=, label=, bg=, fg=, onPress=, text=}, ...};
-- an entry with `text` instead of `label` is a plain caption between
-- buttons (the drone goal sits between its - and + that way).
-- Returns the column after the last one.
function frame.bar(y, list)
  if not core.hasGpu then return 2 end
  local W = core.size()
  core.fillRect(1, y, W, 1)
  local x = 2
  for _, b in ipairs(list) do
    if b.text then
      core.text(x, y, b.text, b.fg or C.text)
      x = x + core.len(b.text) + 2
    else
      core.button{id = b.id, x = x, y = y, label = b.label,
                  bg = b.bg or C.barEmpty, fg = b.fg, onPress = b.onPress}
      x = x + core.len(b.label) + 2
    end
  end
  return x
end

-- "Q -> home" in the bottom right, the same promise on every screen
function frame.hint(where, y)
  if not core.hasGpu then return end
  local W, H = core.size()
  local text = "Q " .. g("right") .. " " .. where
  core.text(W - core.len(text) - 3, y or H, text, C.dim2)
end

return frame
