-- beestore.lua  ->  install to /lib/beestore.lua
-- The bee library: which transposer side keeps what, and reading it.
-- beeyard owns the apiary and the scanner and re-exports everything
-- here, so callers still say yard.scan / yard.sides.
--
-- Storage is either one processing chest (the classic build) or split
-- across Extra Utilities filing cabinets -- one item ID each, so
-- princesses and drones live apart and everything that is not a bee
-- goes to a dump chest. Every optional role falls back to chestSide.

local component = require("component")
local config    = require("beeconfig")
local genes     = require("beegenes")
local climate   = require("beeclimate")

local store = {}
local tp = component.transposer

-- Resolved live on every call: config is mutated at runtime by the
-- wiring and settings screens, so a snapshot would go stale.
function store.sides()
  local c = config.chestSide
  return {princess = config.princessSide or c,
          drone    = config.droneSide or c,
          dump     = config.dumpSide or c,
          sort     = config.sortChestSide}
end

-- Walk one inventory. getAllStacks hands back a lazy iterator on the
-- builds that have it -- one round trip instead of `size` of them,
-- which is the whole difference between a snappy and a glacial
-- rescan of a 540-slot cabinet. Empty slots arrive as a table with
-- no name; a build without the method fails on the pcall above the
-- loop and takes the slow path. fn(slot, stack) may return true to
-- stop early. Never getAll() an inventory into one table: bee NBT is
-- enormous and a cabinet holds hundreds of them.
function store.eachStack(side, fn)
  local size = tp.getInventorySize(side)
  if not size or size == 0 then return 0 end
  local ok, it = pcall(tp.getAllStacks, side)
  if ok and it ~= nil then
    for slot = 1, size do
      local got, stack = pcall(it)
      if not got or stack == nil then break end
      if type(stack) == "table" and stack.name and fn(slot, stack) then break end
    end
  else
    for slot = 1, size do
      local stack = tp.getStackInSlot(side, slot)
      if stack and fn(slot, stack) then break end
    end
  end
  return size
end

-- Read the bee storage. Returns princesses, drones (trimmed records
-- that carry the side they came from), unanalyzed ({side=, slot=})
-- and fill info ({[side] = {size=, used=}}) for the home screen.
-- Slot numbers are a snapshot only: a filing cabinet re-sorts itself
-- on every transfer, so nothing may reuse them after the first move.
function store.scan(dump)
  local princesses, drones, unanalyzed, fill = {}, {}, {}, {}
  local s = store.sides()
  for _, side in ipairs({s.princess, s.drone}) do
    if not fill[side] then
      local used = 0
      local size = store.eachStack(side, function(slot, stack)
        used = used + 1
        if dump and genes.isBee(stack) then
          require("beedump").stack(stack)
          dump = false
        end
        if genes.isBee(stack) and not genes.isAnalyzed(stack) then
          unanalyzed[#unanalyzed + 1] = {side = side, slot = slot}
        elseif genes.isBee(stack) then
          local active, inactive = genes.speciesOf(stack)
          local bee = {side = side, slot = slot, active = active,
                       inactive = inactive, size = stack.size or 1,
                       fertility = genes.fertilityOf(stack),
                       tol = climate.toleranceOf(stack)}
          if genes.isPrincess(stack) then
            princesses[#princesses + 1] = bee
          else
            drones[#drones + 1] = bee
          end
        end
      end)
      if size == 0 then
        error("Nothing attached on side " .. tostring(side) .. " -- check beeconfig")
      end
      fill[side] = {size = size, used = used}
    end
  end
  return princesses, drones, unanalyzed, fill
end

-- Slot of the first unanalyzed bee on `side` right now, or nil.
function store.findUnanalyzed(side)
  local at
  store.eachStack(side, function(slot, stack)
    if genes.isBee(stack) and not genes.isAnalyzed(stack) then
      at = slot
      return true
    end
  end)
  return at
end

--------------------------------------------------------------------
-- Hybrid sweep. Drones whose active and inactive species differ go
-- to the sorting chest -- EXCEPT ones that count toward the target
-- bank (with requirePure off a Target/Other hybrid is part of the
-- counted stock and stays). Drones with unreadable genomes are left
-- alone; princesses are never touched.
--
-- With cabinets the sort side is retired: a cabinet keeps hybrids
-- happily and they are useful carriers. So no sort side -- or one
-- that IS the drone side -- means no sweep at all.
--
-- A chest keeps its slot numbers; a cabinet re-sorts the moment a
-- stack leaves it. So every slot is re-read immediately before the
-- move and skipped when it no longer holds the drone we meant, and a
-- pass that moved anything is simply run again (bounded, so a full
-- sorting chest cannot spin here forever).
--------------------------------------------------------------------
local function stillThere(d)
  local stack = tp.getStackInSlot(d.side, d.slot)
  if not genes.isDrone(stack) then return false end
  local a, i = genes.speciesOf(stack)
  return a == d.active and i == d.inactive
end

-- Returns beesMoved, stacksStuck.
function store.cleanDrones(target, onWarn)
  local s = store.sides()
  if not s.sort or s.sort == s.drone then return 0, 0 end
  local movedBees, stuck = 0, 0
  for _ = 1, 8 do
    local _, drones = store.scan(false)
    local movedHere = 0
    stuck = 0                       -- only the last pass's failures count
    for _, d in ipairs(drones) do
      local hybrid = d.active and d.inactive and d.active ~= d.inactive
      if hybrid and not genes.isWinner(d, target) and stillThere(d) then
        local moved = tp.transferItem(d.side, s.sort, 64, d.slot)
        if moved > 0 then
          movedBees, movedHere = movedBees + moved, movedHere + 1
        else
          stuck = stuck + 1
          if onWarn then
            onWarn("could not move drones from slot " .. d.slot ..
                   " -- sorting chest full/missing?")
          end
        end
      end
    end
    if movedHere == 0 then break end
  end
  return movedBees, stuck
end

return store
