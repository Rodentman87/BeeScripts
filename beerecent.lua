-- beerecent.lua  ->  install to /lib/beerecent.lua
-- The home screen's Recent pane: a ring buffer of events, newest at
-- the bottom, each stamped with how long ago it happened rather than
-- with a clock -- there is no clock in here, and "18m" is the thing
-- you actually want to know.
--
-- An entry is a string or a ready-made segment list, so a run finishing
-- can name its species in the species' own color.

local core     = require("beeui")
local segs     = require("beesegs")
local computer = require("computer")
local C, g = core.C, core.g

local recent = {}

local P = nil
local entries, off = {}, 0
local KEEP = 200

local KIND = {good = C.good, warn = C.warn, bad = C.bad}

function recent.init(geo)
  P, off = geo, 0
  recent.draw()
end

function recent.clear() entries, off = {}, 0 end

local function ago(t)
  local s = math.max(0, math.floor(computer.uptime() - t))
  if s < 60 then return s .. "s" end
  if s < 3600 then return math.floor(s / 60) .. "m" end
  return math.floor(s / 3600) .. "h"
end

local function visible() return P and (P.h - 3) or 10 end

function recent.draw()
  if not (core.hasGpu and P) then return end
  local room = visible()
  local last = #entries - off
  for i = 1, room do
    local e = entries[last - room + i]
    local row = {}
    if e then
      row[1] = {text = ("%-5s"):format(ago(e.t)), color = C.dim2}
      for _, s in ipairs(e.segs) do row[#row + 1] = s end
    end
    segs.set(P.y + i, row, P.w - 2, P.x + 1)
  end
  core.line(P.y + P.h - 2, ("%s%s scroll %s %d kept"):format(
            g("triU"), g("triD"), g("mid"), #entries), C.dim2, P.w - 2, P.x + 1)
end

-- `what` is a string (colored by `kind`) or a segment list
function recent.add(what, kind)
  entries[#entries + 1] = {t = computer.uptime(),
    segs = type(what) == "string"
           and {{text = what, color = KIND[kind] or C.text}} or what}
  while #entries > KEEP do table.remove(entries, 1) end
  off = 0
  recent.draw()
end

-- dir = 1 pages back toward older entries, -1 toward the newest
function recent.scroll(dir)
  local room = visible()
  off = math.max(0, math.min(math.max(0, #entries - room), off + dir * room))
  recent.draw()
end

return recent
