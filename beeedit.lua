-- beeedit.lua  ->  install to /lib/beeedit.lua
-- The settings screen's working copy: what beeconfig says now, what
-- the screen has changed since, and the three widgets that change it.
--
-- Nothing here writes to disk and nothing writes to config either:
-- the screen holds edits until SAVE, so REVERT is free and a half-
-- finished thought never reaches the running engine.

local core   = require("beeui")
local config = require("beeconfig")
local frame  = require("beeframe")
local fields = require("beefields")
local C, g = core.C, core.g

local ed = {}

local base, work = {}, {}

function ed.load()
  base, work = {}, {}
  fields.each(function(f)
    base[f.key] = fields.read(f, config)
    work[f.key] = base[f.key]
  end)
end

function ed.get(key) return work[key] end
function ed.dirty(key) return work[key] ~= base[key] end

-- Changed keys, in the order they appear on screen
function ed.keys()
  local out = {}
  fields.each(function(f)
    if ed.dirty(f.key) then out[#out + 1] = f.key end
  end)
  return out
end

-- ...and their values as beeconf wants them (scales undone)
function ed.changes()
  local out = {}
  fields.each(function(f)
    if ed.dirty(f.key) then out[f.key] = fields.out(f, work[f.key]) end
  end)
  return out
end

-- Preview has to reason about the EDITED floors, not the saved ones,
-- and beestock reads them from config like everything else. So borrow
-- config for the calculation and hand it straight back -- including
-- when fn throws, which is why the pcall is here.
function ed.withFloors(fn)
  local p, d = config.princessFloor, config.droneFloor
  config.princessFloor, config.droneFloor = work.princessFloor, work.droneFloor
  pcall(fn)
  config.princessFloor, config.droneFloor = p, d
end

--------------------------------------------------------------------
-- Widgets. Column geometry matches the mockup: label, then the
-- control 22 cells in, so both columns line up down the screen.
--------------------------------------------------------------------
function ed.control(x, y, f, redraw)
  local v, changed = work[f.key], ed.dirty(f.key)
  local label = (f.icon and (g(f.icon) .. " ") or "") .. f.label
  core.text(x, y, core.clip(label, 21), C.text)
  local function press(dir)
    return function() work[f.key] = fields.bump(f, work[f.key], dir) redraw() end
  end
  if f.kind == "bool" then
    core.button{id = f.key, x = x + 22, y = y,
                label = v and ("[ " .. g("check") .. " ]") or "[   ]",
                bg = changed and C.header or (v and C.good or C.barEmpty),
                fg = v and C.headerFg or C.text, onPress = press(1)}
    return
  end
  -- A number gets - and +, a scale gets the two arrows: one steps by
  -- a fixed amount, the other walks a list, and they must not look
  -- like the same control.
  local wide = (f.kind == "cycle")
  core.button{id = f.key .. "-", x = x + 22, y = y,
              label = wide and ("[ " .. g("arrowL") .. " ]") or "[ - ]",
              bg = C.barEmpty, onPress = press(-1)}
  core.text(x + (wide and 28 or 29), y,
            wide and ("%-8s"):format(v) or ("%4s"):format(v),
            changed and C.headerFg or C.text, changed and C.header or nil)
  core.button{id = f.key .. "+", x = x + (wide and 37 or 35), y = y,
              label = wide and ("[ " .. g("arrowR") .. " ]") or "[ + ]",
              bg = C.barEmpty, onPress = press(1)}
end

-- A column of groups and fields from row `y`. Every group after the
-- first gets a blank row above it. Returns the row after the column.
function ed.column(x, y, list, right, redraw)
  for i, f in ipairs(list) do
    if f.group then
      if i > 1 then y = y + 1 end
      frame.group(x - 1, y, f.group, right)
    else
      ed.control(x, y, f, redraw)
    end
    y = y + 1
  end
  return y
end

return ed
