-- beeattach.lua  ->  install to /lib/beeattach.lua
-- What is attached to each transposer side: size, block name (best
-- effort -- not every driver answers getInventoryName) and a count
-- of the bees inside. Pure looking; beesides decides what it means
-- and re-exports these so callers keep saying sides.probe.

local component = require("component")

local A = {}

A.NAMES = {[0] = "down", "up", "north", "south", "west", "east"}

local BEE = {
  ["forestry:beeprincessge"] = "princess",
  ["forestry:beedronege"]    = "drone",
  ["forestry:beequeenge"]    = "queen",
}

local function try(fn, ...)
  if not fn then return nil end
  local ok, v = pcall(fn, ...)
  return ok and v or nil
end

--------------------------------------------------------------------
-- Look at all six sides. Returns probe[0..5], each entry:
--   {side, name, size, block, princesses, drones, queens, items}
-- size is nil when nothing is attached to that side. Only the first
-- 64 slots are counted: a cabinet packs from the front, so that is
-- plenty to tell what it holds without walking all 540.
--------------------------------------------------------------------
function A.probe()
  if not component.isAvailable("transposer") then
    return nil, "no transposer -- is the computer wired to one?"
  end
  local tp = component.transposer
  local p = {}
  for side = 0, 5 do
    local info = {side = side, name = A.NAMES[side],
                  princesses = 0, drones = 0, queens = 0, items = 0}
    local size = try(tp.getInventorySize, side)
    if size and size > 0 then
      info.size = size
      info.block = try(tp.getInventoryName, side)
      for slot = 1, math.min(size, 64) do
        local stack = try(tp.getStackInSlot, side, slot)
        if stack then
          info.items = info.items + 1
          local kind = BEE[tostring(stack.name):lower()]
          if kind == "princess" then
            info.princesses = info.princesses + (stack.size or 1)
          elseif kind == "drone" then
            info.drones = info.drones + (stack.size or 1)
          elseif kind == "queen" then
            info.queens = info.queens + 1
          end
        end
      end
    end
    p[side] = info
  end
  return p
end

-- One line describing a side, for the screen and the reports.
function A.describeSide(info)
  if not info or not info.size then return "nothing attached" end
  local bits = {tostring(info.block or "unnamed block"), info.size .. " slots"}
  if info.queens > 0     then bits[#bits + 1] = info.queens .. " queen" end
  if info.princesses > 0 then bits[#bits + 1] = info.princesses .. " princess" end
  if info.drones > 0     then bits[#bits + 1] = info.drones .. " drones" end
  if info.items == 0     then bits[#bits + 1] = "empty" end
  return table.concat(bits, ", ")
end

return A
