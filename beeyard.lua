-- beeyard.lua  ->  install to /lib/beeyard.lua
-- The apiary and the scanner: putting a pair in, waiting the queen
-- out, emptying the output slots. The bee library it draws from --
-- which side keeps princesses, drones and everything else -- lives in
-- beestore and is re-exported here, so callers still say yard.scan.

local component = require("component")
local config    = require("beeconfig")
local genes     = require("beegenes")
local store     = require("beestore")

local yard = {}
local tp = component.transposer

-- Sleep function used by all waits. Defaults to os.sleep; the main
-- script injects a keyboard-aware version so Q can request a halt.
yard.sleep = os.sleep

yard.sides       = store.sides
yard.eachStack   = store.eachStack
yard.scan        = store.scan
yard.cleanDrones = store.cleanDrones

-- Run one bee through the GT scanner: insert it (no hardcoded slot --
-- GT slot layouts vary by tier/side config), then watch the scanner's
-- whole inventory until a bee reports isAnalyzed, and pull it home.
-- The bee is found afresh HERE rather than taken from a slot number
-- the caller saved: cabinets re-sort on every insert, so slots from
-- an older scan are fiction. Returns true, or false + reason.
function yard.scanBee(side, onTick)
  local from = store.findUnanalyzed(side)
  if not from then return false, "no unanalyzed bee left to scan" end
  local moved = tp.transferItem(side, config.scannerSide, 1, from)
  if moved == 0 then
    return false, "scanner refused item -- check scannerSide/side config"
  end

  local step = config.animDelay or 0.5
  local waited = 0
  while waited < config.scanTimeout do
    yard.sleep(step)
    waited = waited + step
    if onTick then onTick(waited) end

    local size = tp.getInventorySize(config.scannerSide) or 0
    for slot = 1, size do
      local stack = tp.getStackInSlot(config.scannerSide, slot)
      if genes.isBee(stack) and genes.isAnalyzed(stack) then
        tp.transferItem(config.scannerSide, side, 64, slot)
        return true
      end
    end
  end

  -- Timed out: reclaim the bee so it isn't stranded in the machine,
  -- back to the side it came from rather than wherever is default.
  local size = tp.getInventorySize(config.scannerSide) or 0
  for slot = 1, size do
    if genes.isBee(tp.getStackInSlot(config.scannerSide, slot)) then
      tp.transferItem(config.scannerSide, side, 64, slot)
    end
  end
  return false, "scan timed out -- machine powered?"
end

-- Best-effort read of the climate the hive reports, through the same
-- Adapter the mutation registry comes from. A plain apiary takes it
-- from the biome; an alveary shifts it with a Heater/Fan/
-- Hygroregulator. Returns temperature, humidity spelled as the tile
-- spells them, or nil when this build's driver exposes neither --
-- beeclimate then falls back to the beeconfig values.
function yard.detectClimate()
  local ok, data = pcall(require, "beedata")
  local api = ok and data.apiculture() or nil
  if not api then return nil, nil end
  local function ask(...)
    for _, m in ipairs({...}) do
      if api[m] then
        local got, v = pcall(api[m])
        if got and v ~= nil then return v end
      end
    end
    return nil
  end
  return ask("getTemperature", "getBiomeTemperature", "temperature"),
         ask("getHumidity", "getBiomeHumidity", "humidity")
end

-- The pair comes from wherever each bee was found, which is not the
-- same side once princesses and drones live in separate cabinets.
function yard.insertPair(p, d)
  local ok1 = tp.transferItem(p.side, config.apiarySide, 1,
                              p.slot, config.PRINCESS_SLOT)
  local ok2 = tp.transferItem(d.side, config.apiarySide, 1,
                              d.slot, config.DRONE_SLOT)
  if ok1 == 0 or ok2 == 0 then
    error("Failed to insert bees into apiary -- check beeconfig")
  end
end

-- onTick(elapsedSeconds) is called after every animation tick so the
-- caller can update a UI without this module knowing about screens.
-- If onTick returns true, the wait aborts and "halted" is returned.
-- Returns "done" when the queen has finished her cycle.
-- The transposer itself is only queried every pollDelay seconds.
function yard.waitForCycle(onTick)
  local step = config.animDelay or 0.5
  local elapsed, sinceCheck = 0, 0
  while true do
    yard.sleep(step)
    elapsed = elapsed + step
    sinceCheck = sinceCheck + step
    if onTick and onTick(elapsed) then
      return "halted"
    end
    if sinceCheck >= config.pollDelay then
      sinceCheck = 0
      if tp.getStackInSlot(config.apiarySide, config.PRINCESS_SLOT) == nil then
        return "done"
      end
    end
  end
end

-- Is a queen working right now? The home screen asks before it
-- offers to start anything of its own.
function yard.busy()
  return tp.getStackInSlot(config.apiarySide, config.PRINCESS_SLOT) ~= nil
end

-- Startup recovery: if a previous run was stopped mid-cycle, a queen
-- may still be working in the apiary and offspring may be sitting in
-- its output slots. Wait her out and sweep everything home.
-- Returns "done" or "halted".
function yard.recover(onTick, onWarn)
  if yard.busy() then
    if yard.waitForCycle(onTick) == "halted" then
      return "halted"
    end
  end
  yard.collectOutputs(onWarn)
  return "done"
end

-- Empty the apiary's output slots, each stack to the side that keeps
-- that kind of thing. A refusal (cabinet full, or one that will not
-- take an unanalyzed bee) falls back to the dump side before it
-- becomes a warning: a stuck output slot stalls the whole run.
-- onWarn(message) is called if a slot still cannot be emptied.
function yard.collectOutputs(onWarn)
  local s = store.sides()
  for _, slot in ipairs(config.OUTPUT_SLOTS) do
    local stack = tp.getStackInSlot(config.apiarySide, slot)
    if stack then
      local to = (genes.isPrincess(stack) and s.princess)
              or (genes.isDrone(stack) and s.drone) or s.dump
      local moved = tp.transferItem(config.apiarySide, to, 64, slot)
      if moved == 0 and to ~= s.dump then
        moved = tp.transferItem(config.apiarySide, s.dump, 64, slot)
      end
      if moved == 0 and onWarn then
        onWarn("storage full? apiary slot " .. slot .. " stuck")
      end
    end
  end
end

return yard
