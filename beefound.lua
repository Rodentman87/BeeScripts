-- beefound.lua  ->  install to /home/lib/beefound.lua
-- Foundation-block automation, PC side: parse mutation conditions
-- for a required foundation and ask the beebot robot to place it
-- over the network. Requires a network card (wired or wireless) on
-- both the computer and the robot.

local component = require("component")
local event     = require("event")
local computer  = require("computer")
local config    = require("beeconfig")

local found = {}

-- Extract the foundation block name from a condition string, e.g.
-- "Requires Callisto Cold Ice Block as a foundation." -> that name.
-- Returns nil when the condition needs no foundation.
function found.parse(cond)
  if not cond or cond == "" then return nil end
  local block = cond:match("[Rr]equires (.-) as a foundation")
  if block then
    return (block:gsub("^%s+", ""):gsub("%s+$", ""))
  end
  return nil
end

-- Ask the robot to place `label` as the foundation. Returns ok, why.
function found.ensure(label)
  if not component.isAvailable("modem") then
    return false, "no network card on this computer"
  end
  local modem = component.modem
  local port = config.botPort or 4477
  modem.open(port)
  modem.broadcast(port, "beebot", "place", label)
  local deadline = computer.uptime() + (config.botTimeout or 10)
  while true do
    local remaining = deadline - computer.uptime()
    if remaining <= 0 then
      return false, "robot did not respond"
    end
    local ev, _, _, _, _, tag, status, why =
      event.pull(remaining, "modem_message")
    if ev and tag == "beebot" then
      return status == "ok", why
    end
  end
end

-- Per-cycle upkeep for the engine: when the current step needs a
-- different foundation than the one in place, have the robot swap
-- it. Remembers what it placed and what it already complained about,
-- so a missing block is retried quietly every cycle (restocking the
-- robot self-heals) while an offline robot stops the retries.
-- Returns "placed", "failed" or nil (nothing to do); why on failure.
local lastPlaced, alerted = nil, nil

function found.reset() lastPlaced, alerted = nil, nil end

function found.maintain(needed)
  if not (config.botEnabled and needed) or needed == lastPlaced then
    return nil
  end
  local ok, why = found.ensure(needed)
  if ok then
    lastPlaced, alerted = needed, nil
    return "placed"
  end
  if why == "robot did not respond" then lastPlaced = needed end
  local fresh = (alerted ~= needed)
  alerted = needed
  return "failed", why, fresh
end

return found
