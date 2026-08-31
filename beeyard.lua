-- beeyard.lua  ->  install to /home/lib/beeyard.lua
-- All physical-world operations: the transposer, the chest, the apiary.

local component = require("component")
local config    = require("beeconfig")
local genes     = require("beegenes")
local climate   = require("beeclimate")

local yard = {}
local tp = component.transposer

-- Sleep function used by all waits. Defaults to os.sleep; the main
-- script injects a keyboard-aware version so Q can request a halt.
yard.sleep = os.sleep

function yard.scanChest(dump)
  local princesses, drones, unanalyzed = {}, {}, {}
  local size = tp.getInventorySize(config.chestSide)
  if not size then
    error("No inventory found on chestSide -- check beeconfig")
  end
  for slot = 1, size do
    local stack = tp.getStackInSlot(config.chestSide, slot)
    if stack and dump and genes.isBee(stack) then
      require("beedump").stack(stack)
      dump = false
    end
    if genes.isBee(stack) and not genes.isAnalyzed(stack) then
      table.insert(unanalyzed, slot)
    else
      local active, inactive = genes.speciesOf(stack)
      local bee = {slot = slot, active = active, inactive = inactive,
                   size = stack and stack.size or 1,
                   fertility = genes.fertilityOf(stack),
                   tol = climate.toleranceOf(stack)}
      if genes.isPrincess(stack) then
        table.insert(princesses, bee)
      elseif genes.isDrone(stack) then
        table.insert(drones, bee)
      end
    end
  end
  return princesses, drones, unanalyzed
end

-- Run one bee through the GT scanner: insert it (no hardcoded slot --
-- GT slot layouts vary by tier/side config), then watch the scanner's
-- whole inventory until a bee reports isAnalyzed, and pull it home.
-- Returns true, or false + reason.
function yard.scanBee(chestSlot, onTick)
  local moved = tp.transferItem(config.chestSide, config.scannerSide, 1, chestSlot)
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
        tp.transferItem(config.scannerSide, config.chestSide, 64, slot)
        return true
      end
    end
  end

  -- Timed out: reclaim the bee so it isn't stranded in the machine
  local size = tp.getInventorySize(config.scannerSide) or 0
  for slot = 1, size do
    if genes.isBee(tp.getStackInSlot(config.scannerSide, slot)) then
      tp.transferItem(config.scannerSide, config.chestSide, 64, slot)
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

function yard.insertPair(p, d)
  local ok1 = tp.transferItem(config.chestSide, config.apiarySide, 1,
                              p.slot, config.PRINCESS_SLOT)
  local ok2 = tp.transferItem(config.chestSide, config.apiarySide, 1,
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

-- Startup recovery: if a previous run was stopped mid-cycle, a queen
-- may still be working in the apiary and offspring may be sitting in
-- its output slots. Wait her out and sweep everything home.
-- Returns "done" or "halted".
function yard.recover(onTick, onWarn)
  if tp.getStackInSlot(config.apiarySide, config.PRINCESS_SLOT) ~= nil then
    if yard.waitForCycle(onTick) == "halted" then
      return "halted"
    end
  end
  yard.collectOutputs(onWarn)
  return "done"
end

-- onWarn(message) is called if an output slot can't be emptied.
function yard.collectOutputs(onWarn)
  for _, slot in ipairs(config.OUTPUT_SLOTS) do
    if tp.getStackInSlot(config.apiarySide, slot) then
      local moved = tp.transferItem(config.apiarySide, config.chestSide, 64, slot)
      if moved == 0 and onWarn then
        onWarn("chest full? slot " .. slot .. " stuck")
      end
    end
  end
end

-- Post-run cleanup: sweep hybrid drones (active ~= inactive species)
-- from the processing chest into the sorting chest -- EXCEPT drones
-- that count toward the target bank (with requirePure off, a
-- Target/Other hybrid is part of the counted stock and stays).
-- Drones with unreadable genomes are left alone. Princesses are
-- never touched. Returns beesMoved, stacksStuck.
function yard.cleanDrones(target, onWarn)
  local _, drones = yard.scanChest(false)
  local movedBees, stuck = 0, 0
  for _, d in ipairs(drones) do
    local hybrid = d.active and d.inactive and d.active ~= d.inactive
    if hybrid and not genes.isWinner(d, target) then
      local moved = tp.transferItem(config.chestSide, config.sortChestSide, 64, d.slot)
      if moved > 0 then
        movedBees = movedBees + moved
      else
        stuck = stuck + 1
        if onWarn then
          onWarn("could not move drones from slot " .. d.slot ..
                 " -- sorting chest full/missing?")
        end
      end
    end
  end
  return movedBees, stuck
end

return yard
