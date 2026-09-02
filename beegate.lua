-- beegate.lua  ->  install to /lib/beegate.lua
-- The stock gate as the engine sees it: choose the pair the plan
-- wants, let beestock veto it, and say what happened. beestock stays
-- pure; the logging, the chat and the run's idea of "done" live here.
--
-- State that must survive a replan (which note we last said, what we
-- have already complained about in chat, whether this run is a
-- restock) is module-local with an explicit reset, the same shape
-- beestep uses.

local config = require("beeconfig")
local ui     = require("beedash")
local genes  = require("beegenes")
local chat   = require("beechat")
local stock  = require("beestock")
local bank   = require("beebank")

local gate = {}

local lastNote, chatted
local restock = false

-- opts: {restock = true} breeds only up to the stock floors;
-- {goal = n} sets the drone goal for this run. Both write through to
-- config.droneGoal on purpose -- every screen reads it live -- so a
-- caller that wants its old value back saves it first.
function gate.reset(opts)
  opts = opts or {}
  lastNote, chatted = nil, {}
  restock = opts.restock == true
  local _, df = stock.floors()
  if restock then
    config.droneGoal = math.max(1, df)
  elseif opts.goal then
    config.droneGoal = opts.goal
  end
end

function gate.restocking() return restock end

-- Pick this cycle's pair: the plan's choice first (recipe-aware when
-- there is a step, greedy otherwise), then the gate on top of it.
-- Returns princess, drone, mode -- the gate's mode when it stepped
-- in, otherwise pickCross's own ("recipe" / "convert" / nil).
function gate.pick(princesses, drones, info, target)
  local p, d, mode
  if info.stepInfo then
    p, d, mode = genes.pickCross(princesses, drones,
                                 info.stepInfo.a, info.stepInfo.b, info.sub)
  else
    p, d = genes.pickPair(princesses, drones, info.sub)
  end

  local tally = stock.tally(princesses, drones)
  local p2, d2, gateMode, note = bank.gate(tally, princesses, drones,
                                            p, d, target)
  -- The same note every cycle is noise: only a change is news. A
  -- note with no mode is the gate giving up, which is worth a chat
  -- message -- once per distinct reason, not once per cycle.
  if note and note ~= lastNote then
    lastNote = note
    ui.log("Stock: " .. note, gateMode and "good" or "warn")
    if not gateMode and not chatted[note] then
      chatted[note] = true
      chat.alert("BeeBreeder: " .. note)
    end
  elseif not note then
    lastNote = nil
  end
  return p2, d2, gateMode or mode
end

-- Done, for this run's definition of done. A restock only has to put
-- the species back on its feet -- a princess and a drone bank at the
-- floor -- rather than reach the full droneGoal.
function gate.reached(info, princesses)
  if not (info.winner and info.isFinal) then return false end
  if not restock then return info.droneCount >= config.droneGoal end
  local pf, df = stock.floors()
  local n = 0
  for _, p in ipairs(princesses) do
    if genes.isWinner(p, info.sub) then n = n + (p.size or 1) end
  end
  return n >= pf and info.droneCount >= df
end

return gate
