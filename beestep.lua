-- beestep.lua  ->  install to /home/lib/beestep.lua
-- Per-cycle evaluation: replan from current stock, announce step
-- changes, drive the route pane, and track drone-farming stagnation.

local config  = require("beeconfig")
local ui      = require("beedash")
local genes   = require("beegenes")
local chat    = require("beechat")
local planner = require("beeplanner")
local climate = require("beeclimate")
local advice  = require("beeadvice")

local step = {}

local announcedStep, prevStep
local doneSteps
local warnedNoRoute, warnedClimate
local bestDroneCount, stagnantCycles
local stepCycles              -- evaluations spent on the current step

function step.reset()
  announcedStep, prevStep = nil, nil
  doneSteps = {}
  warnedNoRoute, warnedClimate = false, nil
  bestDroneCount, stagnantCycles = 0, 0
  stepCycles = 0
end

-- The route pane gets the whole plan (steps, owned set, roll count)
-- for the tree view, plus the compact done/cur/nxt/tail digest.
local function drawRoute(stepInfo, planSteps, sub, goalN, owned)
  local r = {done = doneSteps, owned = owned, rolls = stepCycles}
  if stepInfo then
    r.steps = planSteps
    r.cur = {a = stepInfo.a, b = stepInfo.b, r = sub,
             chance = stepInfo.chance, exp = stepInfo.expCycles}
    local n = planSteps[2]
    if n then r.nxt = {a = n.a, b = n.b, r = n.result} end
    if #planSteps > 2 then
      local cyc = 0
      for i = 3, #planSteps do cyc = cyc + planSteps[i].expCycles end
      r.tail = ("  +%d more steps (~%d cycles)"):format(#planSteps - 2, cyc)
    end
  else
    r.cur = {bank = sub, goal = goalN}
  end
  ui.route(r)
end

local function announce(stepInfo, sub, stepKey, owned, target)
  if stepKey == announcedStep then return end
  announcedStep = stepKey
  bestDroneCount, stagnantCycles, stepCycles = 0, 0, 0
  -- A completed mutation step means the species now EXISTS (some bee
  -- actively expresses it) -- right for intermediates, but never list
  -- the overall target as done: the bank line represents it, and with
  -- requirePure a hybrid is nowhere near finished.
  if prevStep and owned[prevStep.result] and prevStep.result ~= target then
    doneSteps[#doneSteps + 1] = prevStep.result
  end
  prevStep = stepInfo
  if stepInfo then
    local msg = ("%s + %s -> %s (%.0f%%)")
                :format(stepInfo.a, stepInfo.b, sub, stepInfo.chance)
    ui.log("Now working: " .. msg, "good")
    chat.say("BeeBreeder step: " .. msg)
    if stepInfo.cond and stepInfo.cond ~= "" then
      ui.log("NOTE: " .. stepInfo.cond, "warn")
      chat.alert("BeeBreeder: " .. sub .. " needs -- " .. stepInfo.cond)
    end
  end
end

-- The bare species allele is not the whole story: a bee of this
-- species already in the chest may carry tolerance the allele lacks,
-- and then there is nothing to warn about. Judge on the best we own.
local function bestStatus(sub, lists)
  local st = climate.status(sub)
  if not st or st.ok then return st end
  for _, list in ipairs(lists) do
    for _, bee in ipairs(list) do
      if bee.active == sub and bee.tol then
        local mine = climate.status(sub, bee.tol)
        if mine and mine.ok then return mine end
      end
    end
  end
  return st
end

-- Climate verdict for the species we are working on, onto the
-- dashboard's climate row. The loud part (log + chat) fires once per
-- species: a hive that cannot house this bee is a standing problem,
-- not news every cycle. When something in the chest already carries
-- the tolerance to cover the gap, say so -- pair selection is
-- steering toward it, and that is the fix that needs no alveary.
local function watchClimate(sub, princesses, drones)
  local st = bestStatus(sub, {princesses, drones})
  ui.climate(st)
  if not st or st.ok or warnedClimate == sub then return end
  warnedClimate = sub
  ui.log(advice.line(st), "warn")
  local donor = climate.donor(drones, st) or climate.donor(princesses, st)
  if donor then
    ui.log(("%s in the chest carries %s -- favoring it as a partner.")
           :format(tostring(donor.active), advice.tolerance(st)), "good")
  else
    ui.log("Fix: " .. advice.fix(st), "warn")
  end
  chat.alert("BeeBreeder: " .. advice.line(st))
end

-- Evaluate one pass of the loop. Returns:
--   {sub, stepInfo, isFinal, goalN, winner, droneCount}
function step.evaluate(princesses, drones, muts, target)
  -- "Owned" = actively expressed; inactive alleles can't go in an apiary
  local owned = {}
  for _, list in ipairs({princesses, drones}) do
    for _, bee in ipairs(list) do
      if bee.active then owned[bee.active] = true end
    end
  end

  local sub, stepInfo, planSteps = target, nil, nil
  if muts and not owned[target] then
    local steps, why = planner.compute(muts, owned, target, climate.routeCost)
    if steps and #steps > 0 then
      planSteps = steps
      stepInfo = steps[1]
      sub = stepInfo.result
    elseif not steps and not warnedNoRoute then
      warnedNoRoute = true
      ui.log("Planner: " .. tostring(why), "warn")
      ui.log("Falling back to greedy crossing.", "warn")
      chat.alert("BeeBreeder: no route to " .. target .. " -- greedy mode")
    end
  end

  local isFinal = (sub == target)
  local goalN = isFinal and config.droneGoal or config.intermediateDrones
  local stepKey = stepInfo
    and (stepInfo.a .. "+" .. stepInfo.b .. ">" .. sub)
    or ("bank:" .. sub)
  announce(stepInfo, sub, stepKey, owned, target)
  stepCycles = stepCycles + 1
  drawRoute(stepInfo, planSteps or {}, sub, goalN, owned)
  watchClimate(sub, princesses, drones)

  local droneCount = genes.countTarget(drones, sub)
  local finalCount = (not isFinal) and genes.countTarget(drones, target) or nil
  ui.chest(#princesses, #drones, droneCount, goalN, sub, finalCount, config.droneGoal)

  local winner = nil
  for _, p in ipairs(princesses) do
    if genes.isWinner(p, sub) then winner = p break end
  end

  -- Stagnation watchdog during the final drone-farming phase
  if winner and isFinal then
    if droneCount > bestDroneCount then
      bestDroneCount, stagnantCycles = droneCount, 0
    else
      stagnantCycles = stagnantCycles + 1
      if stagnantCycles % config.stagnantWarn == 0 then
        ui.log(("No drone growth in %d cycles -- low fertility? Add a")
               :format(stagnantCycles), "warn")
        ui.log("high-fertility drone (e.g. f3) to the chest to fix it.", "warn")
        chat.alert(("BeeBreeder: no drone growth in %d cycles -- add a high-fertility drone")
                   :format(stagnantCycles))
      end
    end
  end

  return {sub = sub, stepInfo = stepInfo, isFinal = isFinal,
          goalN = goalN, winner = winner, droneCount = droneCount}
end

return step
