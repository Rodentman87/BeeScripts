-- beesides.lua  ->  install to /lib/beesides.lua
-- Auto-discovery of which transposer side each inventory is on, so
-- the build can be rearranged without hand-editing beeconfig.
--
-- The transposer answers, per side: is there an inventory, how big,
-- what block is it (getInventoryName -- best effort, not every
-- driver answers) and what is in it. That names the apiary and the
-- scanner outright. The two chests are the same block, so they are
-- told apart by their contents: the processing chest is the one
-- holding PRINCESSES (cleanDrones only ever sends drones to the
-- sorting chest). Anything still ambiguous is left for beewire to
-- ask about -- guessing wrong puts bees in the wrong box.

local component = require("component")
local config    = require("beeconfig")

local S = {}

S.NAMES = {[0] = "down", "up", "north", "south", "west", "east"}

S.ROLES = {
  {key = "chestSide",     label = "Processing chest", kind = "chest"},
  {key = "apiarySide",    label = "Apiary / alveary", kind = "apiary"},
  {key = "scannerSide",   label = "GT scanner",       kind = "machine"},
  {key = "sortChestSide", label = "Sorting chest",    kind = "chest"},
}

local BEE = {
  ["forestry:beeprincessge"] = "princess",
  ["forestry:beedronege"]    = "drone",
  ["forestry:beequeenge"]    = "queen",
}

local APIARY  = {"apicult", "apiary", "alveary", "beehouse", "bee.house"}
local CHEST   = {"chest", "crate", "barrel", "drawer", "storage", "container"}
local MACHINE = {"scanner", "machine", "gt.block"}

local function kw(s, list)
  for _, k in ipairs(list) do
    if s:find(k, 1, true) then return true end
  end
  return false
end

-- What a side looks like, or nil for "no opinion" (no name from the
-- driver, or a name we don't recognize). nil must never warn.
local function kindOf(info)
  local block = tostring(info and info.block or ""):lower()
  if block == "" then return nil end
  if kw(block, APIARY)  then return "apiary"  end
  if kw(block, CHEST)   then return "chest"   end
  if kw(block, MACHINE) then return "machine" end
  return nil
end
S.kindOf = kindOf

local function try(fn, ...)
  if not fn then return nil end
  local ok, v = pcall(fn, ...)
  if ok then return v end
  return nil
end

function S.sideName(side)
  return S.NAMES[side] or ("side " .. tostring(side))
end

--------------------------------------------------------------------
-- Look at all six sides. Returns probe[0..5], each entry:
--   {side, name, size, block, princesses, drones, queens, items}
-- size is nil when nothing is attached to that side.
--------------------------------------------------------------------
function S.probe()
  if not component.isAvailable("transposer") then
    return nil, "no transposer -- is the computer wired to one?"
  end
  local tp = component.transposer
  local p = {}
  for side = 0, 5 do
    local info = {side = side, name = S.NAMES[side],
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

-- One line describing what is on a side, for the screen and reports.
function S.describeSide(info)
  if not info or not info.size then return "nothing attached" end
  local bits = {tostring(info.block or "unnamed block"), info.size .. " slots"}
  if info.queens > 0     then bits[#bits + 1] = info.queens .. " queen" end
  if info.princesses > 0 then bits[#bits + 1] = info.princesses .. " princess" end
  if info.drones > 0     then bits[#bits + 1] = info.drones .. " drones" end
  if info.items == 0     then bits[#bits + 1] = "empty" end
  return table.concat(bits, ", ")
end

function S.current()
  local a = {}
  for _, role in ipairs(S.ROLES) do a[role.key] = config[role.key] end
  return a
end


--------------------------------------------------------------------
-- Is an assignment usable? Structure first (something there, no two
-- roles on one side), then the block name where we have one -- that
-- is what catches a chest and an apiary having been swapped.
--------------------------------------------------------------------
function S.validate(probe, assign)
  local problems, seen = {}, {}
  for _, role in ipairs(S.ROLES) do
    local side = assign[role.key]
    local info = type(side) == "number" and probe[side] or nil
    if not info or not info.size then
      problems[#problems + 1] = ("%s: nothing on the %s side")
                                :format(role.label, S.sideName(side))
    elseif seen[side] then
      problems[#problems + 1] = ("%s: shares the %s side with %s")
                                :format(role.label, S.sideName(side), seen[side])
    else
      seen[side] = role.label
      local kind = kindOf(info)
      if kind and kind ~= role.kind then
        problems[#problems + 1] = ("%s: the %s side is %s")
                                  :format(role.label, S.sideName(side), info.block)
      end
    end
  end
  -- The sorting chest only ever receives drones. Princesses sitting
  -- in it while the processing chest has none is the two chests
  -- being the wrong way round -- the one swap block names cannot
  -- see. Both halves of that are required: a princess turning up in
  -- the sorting chest on its own is the user's business, not a fault.
  local proc, sort = probe[assign.chestSide], probe[assign.sortChestSide]
  if proc and sort and proc.size and sort.size
     and sort.princesses > 0 and proc.princesses == 0 then
    problems[#problems + 1] = "Chests look swapped: the princesses are in the sorting chest"
  end
  return #problems == 0, problems
end

-- Take an assignment for this run. config is shared by every module
-- (package.loaded), so this is all it takes -- no reboot.
function S.apply(assign)
  for _, role in ipairs(S.ROLES) do
    if assign[role.key] then config[role.key] = assign[role.key] end
  end
end

return S
