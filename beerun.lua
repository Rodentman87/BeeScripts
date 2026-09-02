-- beerun.lua  ->  install to /home/lib/beerun.lua
-- The breeding engine loop: scan, analyze, evaluate, cross, repeat.

local config = require("beeconfig")
local ui     = require("beedash")
local genes  = require("beegenes")
local yard   = require("beeyard")
local chat   = require("beechat")
local step   = require("beestep")
local found  = require("beefound")
local climate = require("beeclimate")

local run = {}

local cycle = 0

local function queenTick(label)
  return function(elapsed)
    ui.status(("%s... %ds"):format(label, math.floor(elapsed)))
    ui.buzz()
    return ui.haltRequested()
  end
end

local function userHalt()
  ui.status("HALTED")
  ui.log("Stopped by user (Q or button).", "warn")
  ui.done()
end

local function warnLog(msg) ui.log("WARN: " .. msg, "warn") end

local function analyzeAll(unanalyzed)
  ui.status(("Scanning %d bees"):format(#unanalyzed))
  local okCount = 0
  for _, slot in ipairs(unanalyzed) do
    local ok, why = yard.scanBee(slot, function() ui.buzz() end)
    if ok then okCount = okCount + 1 else warnLog(why) end
  end
  if okCount == 0 then
    ui.status("HALTED")
    ui.log("Scanner not working -- fix it and rerun.", "bad")
    chat.alert("BeeBreeder halted: scanner not responding (power?)")
    return false
  end
  return true
end

local function finish(target, info)
  ui.log(("Princess slot %d + %d drones"):format(info.winner.slot, info.droneCount), "good")
  ui.status("Cleaning chest")
  local movedBees, stuck = yard.cleanDrones(target, warnLog)
  if movedBees > 0 then
    ui.log(("Swept %d hybrid drones to the sorting chest"):format(movedBees), "good")
  end
  if stuck > 0 then
    chat.alert("BeeBreeder: sorting chest full -- some hybrids left behind")
  end
  ui.status("DONE")
  ui.banner((" SUCCESS after %d cycles: %s x%d "):format(cycle, target, info.droneCount))
  chat.say(("BeeBreeder DONE: %s princess + %d drones after %d cycles (%d hybrids swept)")
           :format(target, info.droneCount, cycle, movedBees))
end

-- Run one breeding cycle. Returns false if the user halted mid-wait.
local function breedCycle(princesses, drones, info)
  local p, d, mode
  if info.stepInfo then
    p, d, mode = genes.pickCross(princesses, drones,
                                 info.stepInfo.a, info.stepInfo.b, info.sub)
  else
    p, d = genes.pickPair(princesses, drones, info.sub)
  end

  cycle = cycle + 1
  ui.cycle(cycle)
  ui.pair(p, d, info.stepInfo, info.sub)
  ui.log(("C%d%s: %s x %s"):format(cycle, mode and (" [" .. mode .. "]") or "",
         genes.label(p), genes.label(d)))
  if config.chatEveryQueen then
    chat.say(("BeeBreeder cycle %d: queen from %s x %s")
             :format(cycle, genes.label(p), genes.label(d)))
  end
  ui.status("Inserting pair")

  -- A queen carries the PRINCESS's genome, so her climate alone
  -- decides whether the hive ticks at all: an inhospitable one just
  -- freezes her and the wait below would never end. Insert anyway --
  -- the reading may be wrong, and fixing the climate frees her.
  local st = climate.status(p.active, p.tol)
  if st and not st.ok then
    ui.climate(st)   -- the climate row spells out both ways to fix it
    ui.log(("Queen will stall: %s wants %s, hive is %s")
           :format(st.species, st.want, st.apiary), "bad")
  end

  yard.insertPair(p, d)
  ui.queenStart()
  if yard.waitForCycle(queenTick("Queen working")) == "halted" then
    return false
  end
  ui.queenDone()
  ui.status("Collecting output")
  yard.collectOutputs(warnLog)
  return true
end

function run.start(target, muts)
  ui.init(target, muts)
  yard.sleep = ui.sleep  -- make all waits keyboard/touch-aware
  step.reset()
  found.reset()
  cycle = 0
  ui.log("Breeding toward: " .. target)
  ui.log("Press Q (or the HALT button) to stop gracefully.")
  local hive = climate.autodetect()
  ui.log(("Hive climate: %s (%s)"):format(hive.text,
         hive.detected and "read from the hive" or "from beeconfig"))
  if muts then
    ui.log("Mutation graph loaded -- planner active.", "good")
  else
    ui.log("No mutation cache -- greedy mode. (Run `beeprobe build`.)", "warn")
  end
  chat.say("BeeBreeder online -- target: " .. target)

  -- Recover from a previous run stopped mid-cycle
  if yard.recover(queenTick("Old queen finishing"), warnLog) == "halted" then
    userHalt()
    return
  end

  while true do
    if ui.haltRequested() then userHalt() return end
    -- PAUSE (wide dashboard button): the queen already finished and
    -- her output is home, so waiting here loses nothing.
    while ui.pauseRequested() and not ui.haltRequested() do
      ui.status("PAUSED -- press RESUME")
      ui.buzz()
      ui.sleep(config.animDelay or 0.5)
    end
    if ui.haltRequested() then userHalt() return end

    climate.autodetect()  -- an alveary block added mid-run should count
    local princesses, drones, unanalyzed = yard.scanChest(false)

    if #unanalyzed > 0 then
      if not analyzeAll(unanalyzed) then break end
    else
      ui.stock(princesses, drones)
      local info = step.evaluate(princesses, drones, muts, target)

      if #princesses == 0 then
        ui.status("HALTED")
        ui.log("No princesses in chest!", "bad")
        chat.alert("BeeBreeder halted: no princesses in chest")
        break
      end

      if info.winner and info.isFinal and info.droneCount >= config.droneGoal then
        finish(target, info)
        return
      end

      if #drones == 0 then
        ui.status("HALTED")
        ui.log("Out of drones -- add more bees.", "bad")
        chat.alert("BeeBreeder halted: out of drones -- add more bees")
        break
      end

      -- Foundation automation: when the current step needs a
      -- different foundation block, have the robot swap it first.
      local needed = info.stepInfo and found.parse(info.stepInfo.cond)
      if config.botEnabled and needed then ui.status("Foundation: " .. needed) end
      local outcome, why, fresh = found.maintain(needed)
      if outcome == "placed" then
        ui.log("Robot placed foundation: " .. needed, "good")
        chat.say("BeeBreeder: foundation swapped to " .. needed)
      elseif outcome == "failed" and fresh then
        ui.log("Foundation FAIL: " .. tostring(why), "bad")
        chat.alert(("BeeBreeder: robot couldn't place %s -- %s")
                   :format(needed, tostring(why)))
      end

      if not breedCycle(princesses, drones, info) then
        userHalt()
        return
      end
    end
  end

  ui.done()
end

return run
