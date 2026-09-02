-- beeexport.lua  ->  install to /lib/beeexport.lua
-- Sending a pair OUT of the library: one pure princess and one pure
-- drone of a species, moved to the dump chest so they can go in a
-- bee house and make combs somewhere that is not the apiary.
--
-- Two things make this more than a transferItem.
--
-- Purity: a bee house pair should breed true forever, so the run
-- that feeds the export forces requirePure on for its duration
-- whatever the setting says, and the pair that leaves is checked for
-- both alleles rather than trusted to isWinner.
--
-- The floors: a drone is spent, but a princess is a LINE. So the run
-- breeds one spare over the floors first, and if the princess who
-- left was the last one the library had, the export finishes by
-- restocking her -- the same work RESTOCK LOW would do, done now
-- rather than left as a hole in the library.
--
-- Slots are fiction the moment anything leaves a filing cabinet
-- (they re-sort on every transfer), so each half of the pair is
-- found afresh immediately before its own move.

local component = require("component")
local config    = require("beeconfig")
local store     = require("beestore")
local stock     = require("beestock")
local chat      = require("beechat")

local export = {}
local tp = component.transposer

-- Pure means BOTH alleles, whatever config.requirePure happens to
-- say: half a species in a bee house is not what anyone asked for.
local function pureOne(list, species)
  for _, b in ipairs(list) do
    if b.active == species and b.inactive == species then return b end
  end
end

-- Where the pair goes. dumpSide falls back to chestSide, which on a
-- classic single-chest build IS the library: moving a bee from the
-- chest to the chest exports nothing, so say so rather than report a
-- move that did not happen.
local function destination(from)
  local s = store.sides()
  if s.dump == from then
    return nil, "the dump chest is the bee library itself -- set dumpSide"
  end
  return s.dump
end

-- Move one pure bee of `species` out; kind is "princess" or "drone".
-- Returns true, or false + why.
function export.take(species, kind)
  local princesses, drones = store.scan(false)
  local bee = pureOne(kind == "princess" and princesses or drones, species)
  if not bee then
    return false, ("no pure %s %s in the library"):format(species, kind)
  end
  local to, why = destination(bee.side)
  if not to then return false, why end
  if tp.transferItem(bee.side, to, 1, bee.slot) == 0 then
    return false, ("could not move the %s -- dump chest full?"):format(kind)
  end
  return true
end

-- The princess first: she is the half that can fail to exist, and
-- there is no point moving a drone we cannot pair her with.
function export.pair(species)
  local ok, why = export.take(species, "princess")
  if not ok then return false, why end
  ok, why = export.take(species, "drone")
  if not ok then
    return false, why .. " -- the princess is already in the dump chest"
  end
  return true
end

-- Is this species still standing after the export?
local function belowFloor(species)
  local ok, princesses, drones = pcall(store.scan, false)
  if not ok then return false end
  local tally = stock.tally(princesses, drones)
  local e = tally[species]
  return (not e) or stock.state(e) == "low"
end

--------------------------------------------------------------------
-- The whole button. `job` is what the breed screen returned;
-- runOne(target, opts) is beehomeact's runner (false = the user
-- halted); log(text, kind) is the Recent pane.
--------------------------------------------------------------------
function export.run(job, runOne, log)
  local _, df = stock.floors()
  local target = job.target
  -- One over the drone floor, so the drone that leaves is genuinely
  -- surplus; the screen's own goal wins when it asks for more.
  local goal = math.max(job.droneGoal or 0, df + 1)
  local savedPure = config.requirePure
  config.requirePure = true
  log(("Export %s: breeding a pure pair, %d drones."):format(target, goal),
      "warn")
  local ok = runOne(target, {goal = goal})
  config.requirePure = savedPure
  if not ok then return false end

  -- The home screen is the boot screen: a transposer that answers
  -- badly should cost the export, not the session.
  local fine, moved, why = pcall(export.pair, target)
  if not fine then moved, why = false, tostring(moved) end
  if not moved then
    log("Export failed: " .. why, "bad")
    chat.alert("BeeBreeder: could not export " .. target .. " -- " .. why)
    return false
  end
  log(("%s princess + drone are in the dump chest."):format(target), "good")
  chat.say("BeeBreeder: exported a pure " .. target ..
           " pair to the dump chest")

  if belowFloor(target) then
    log(("That was the last %s -- restocking her line."):format(target), "warn")
    return runOne(target, {restock = true})
  end
  return true
end

return export
