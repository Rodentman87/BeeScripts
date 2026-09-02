-- beestatus.lua  ->  install to /lib/beestatus.lua
-- What only the hardware knows, in the shape the home screen wants:
-- how stale the caches are, how full each side is, whether a queen is
-- working, whether the wiring still checks out, what climate the hive
-- provides. beepop reasons about the library; this reads the world.

local core     = require("beeui")
local config   = require("beeconfig")
local yard     = require("beeyard")
local sides    = require("beesides")
local climate  = require("beeclimate")
local computer = require("computer")
local C, g = core.C, core.g

local status = {}

local CACHES = {mutations = "/home/beedata/mutations.dat",
                species   = "/home/beedata/species.dat"}
local STALE = 7 * 24 * 3600     -- a week old is worth a REBUILD button

local ROLE_ICON = {chestSide = "cabinet", princessSide = "princess",
                   droneSide = "drone", dumpSide = "bin",
                   apiarySide = "apiary", scannerSide = "flask",
                   sortChestSide = "wire"}

local idleSince, wasBusy = computer.uptime(), false

--------------------------------------------------------------------
-- filesystem.lastModified answers in real-world milliseconds and
-- os.time() means different things on different builds. Where the two
-- agree the age is real; where they do not the arithmetic comes out
-- negative or absurd, and then we say nothing rather than something
-- wrong. A missing file is a different answer again: no cache at all.
--------------------------------------------------------------------
local function ageOf(path)
  local fs = require("filesystem")
  if not fs.exists(path) then return nil, false end
  local ok, ms = pcall(fs.lastModified, path)
  if not ok or type(ms) ~= "number" or ms <= 0 then return nil, true end
  local now = os.time()
  if now < 1e11 then now = now * 1000 end       -- seconds, not millis
  local secs = (now - ms) / 1000
  if secs < 0 or secs > 10 * 365 * 86400 then return nil, true end
  return secs, true
end

local function ageText(secs)
  if not secs then return "?" end
  if secs < 3600 then return math.max(1, math.floor(secs / 60)) .. "m" end
  if secs < 86400 then return math.floor(secs / 3600) .. "h" end
  return math.floor(secs / 86400) .. "d"
end

-- nil when there is no mutation cache at all
function status.cache()
  local secs, exists = ageOf(CACHES.mutations)
  if not exists then return nil end
  return {secs = secs, age = ageText(secs), stale = (secs or 0) > STALE}
end

function status.apiary()
  local ok, busy = pcall(yard.busy)
  busy = (ok and busy) == true
  if busy ~= wasBusy then
    idleSince, wasBusy = computer.uptime(), busy
  end
  local mins = math.floor((computer.uptime() - idleSince) / 60)
  local when = mins >= 60 and ("%dh%02dm"):format(math.floor(mins / 60), mins % 60)
               or (mins .. "m")
  return {busy = busy, text = (busy and "working " or "idle ") .. when}
end

function status.climateText()
  local hive = climate.apiary()
  return ("%s %s %s %s"):format(g("temp"), climate.tempName(hive.temp),
                                g("humid"), climate.humidName(hive.humid))
end

-- How full a side is. `fill` is yard.scan's per-side table; the dump
-- side is never scanned for bees, so it is counted here.
function status.fillOf(side, fill)
  if not side then return nil end
  if fill and fill[side] then return fill[side] end
  local used = 0
  local size = yard.eachStack(side, function() used = used + 1 end)
  if size == 0 then return nil end
  return {size = size, used = used}
end

-- "P 29/540 . D 203/540 . dump 9/27" for the Attention line. Slots
-- used, not bees: drones stack, and how full the cabinet is getting
-- is the thing worth knowing.
function status.fillText(fill)
  local s = yard.sides()
  local bits = {}
  local function add(icon, side)
    local f = status.fillOf(side, fill)
    if f then
      bits[#bits + 1] = ("%s %d/%d"):format(g(icon), f.used, f.size)
    end
  end
  add("princess", s.princess)
  add("drone", s.drone)
  if s.dump ~= s.princess and s.dump ~= s.drone then add("bin", s.dump) end
  return table.concat(bits, " " .. g("mid") .. " ")
end

-- The header strip's extras plus everything beepop.attention wants
function status.extra(fill, sidesOk, nextScan)
  local ap = status.apiary()
  local cache = status.cache()
  return {cache = cache, apiary = ap.text, busy = ap.busy,
          fill = status.fillText(fill),
          climate = status.climateText(), sidesOk = sidesOk,
          cacheAge = cache and cache.age or nil, nextScan = nextScan,
          uptime = ageText(computer.uptime())}
end

--------------------------------------------------------------------
-- The two right-hand panes, as segment rows
--------------------------------------------------------------------
function status.hiveLines(extra, last)
  local rows = {{{text = g("apiary") .. " ", color = C.dim},
                 {text = extra.apiary or "?"}}}
  if last then
    rows[#rows + 1] = {{text = (last.ok and g("check") or g("fail")) .. " ",
                        color = last.ok and C.good or C.bad},
                       {text = last.species, species = last.species},
                       {text = " " .. last.note, color = C.dim}}
  else
    rows[#rows + 1] = {{text = "nothing bred yet this session", color = C.dim2}}
  end
  rows[#rows + 1] = {{text = extra.climate or "", color = C.text},
                     {text = "  " .. g("apiary"), color = C.dim2}}
  return rows
end

-- One line per side: its letter, what lives there, how full it is
function status.wiringLines(fill, cache)
  local rows, line = {}, {}
  for side = 0, 5 do
    local role
    for _, r in ipairs(sides.ROLES) do
      if config[r.key] == side and not role then role = r.key end
    end
    if role then
      local f = status.fillOf(side, fill)
      local text = ("%s %s %s"):format(sides.sideName(side):sub(1, 1):upper(),
        g(ROLE_ICON[role] or "same"), f and (f.used .. "/" .. f.size) or "")
      line[#line + 1] = {text = ("%-24s"):format(text)}
      if #line == 3 then
        rows[#rows + 1] = line
        line = {}
      end
    end
  end
  if #line > 0 then rows[#rows + 1] = line end
  rows[#rows + 1] = {}
  rows[#rows + 1] = {{text = g("route") .. " ", color = C.dim},
                     {text = cache and ("mutation cache " .. cache.age .. " old")
                             or "no mutation cache -- run `beeprobe build`",
                      color = cache and C.text or C.bad}}
  return rows
end

-- Repaint a pane with rows this module built
function status.paint(pane, rows)
  local segs = require("beesegs")
  for i = 1, pane.h - 2 do
    segs.set(pane.y + i, rows[i] or {}, pane.w - 2, pane.x + 1)
  end
end

return status
