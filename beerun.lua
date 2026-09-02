-- beerun.lua  ->  install to /home/lib/beerun.lua
-- The breeding engine loop: scan, analyze, evaluate, cross, repeat.

local config = require("beeconfig")
local ui     = require("beedash")
local genes  = require("beegenes")
local yard   = require("beeyard")
local chat   = require("beechat")
local step   = require("beestep")
local gate   = require("beegate")
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

-- One pass per bee the scan found, but each bee is looked up afresh
-- by yard.scanBee: cabinets re-sort on every transfer, so the slot
-- numbers in this list are stale after the first one moves. Only the
-- SIDE each bee was on survives the trip.
local function analyzeAll(unanalyzed)
  ui.status(("Scanning %d bees"):format(#unanalyzed))
  local okCount = 0
  for _, u in ipairs(unanalyzed) do
    local ok, why = yard.scanBee(u.side, function() ui.buzz() end)
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

-- The sweep is a no-op without a sorting chest, which is the normal
-- state once the library lives in cabinets: they keep hybrids
-- happily, and hybrids are useful carriers.
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
  local word = gate.restocking() and "RESTOCKED" or "SUCCESS"
  ui.status("DONE")
  ui.banner((" %s after %d cycles: %s x%d "):format(word, cycle, target,
            info.droneCount))
  chat.say(("BeeBreeder %s: %s princess + %d drones after %d cycles (%d hybrids swept)")
           :format(word, target, info.droneCount, cycle, movedBees))
end

-- Run one breeding cycle. Returns false if the user halted mid-wait.
local function breedCycle(princesses, drones, info, target)
  local p, d, mode = gate.pick(princesses, drones, info, target)
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

-- opts (all optional): {restock = true} stops at the stock floors and
-- says RESTOCKED; {goal = n} sets the drone goal for this run. Both
-- leave config.droneGoal changed on purpose -- the screens read it
-- live -- so a caller that wants its old value back saves it first.
function run.start(target, muts, opts)
  gate.reset(opts)
  ui.init(target, muts)
  yard.sleep = ui.sleep  -- make all waits keyboard/touch-aware
  step.reset()
  found.reset()
  cycle = 0
  ui.log(gate.restocking() and ("Restocking: " .. target)
         or ("Breeding toward: " .. target))
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
    local princesses, drones, unanalyzed = yard.scan(false)

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

      if gate.reached(info, princesses) then
        finish(target, info)
        return
      end

      if #drones == 0 then
        ui.status("HALTED")
        ui.log("Out of drones -- add more bees.", "bad")
        chat.alert("BeeBreeder halted: out of drones -- add more bees")
        break
      end

      step.foundation(info)
      if not breedCycle(princesses, drones, info, target) then
        userHalt()
        return
      end
    end
  end

  ui.done()
end

return run
