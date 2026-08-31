-- beebot.lua  ->  runs ON THE ROBOT (install to the robot's /home,
-- add to its /home/.shrc or run manually after boot)
--
-- The robot must be positioned FACING the foundation spot: the block
-- directly under the apiary, with the robot at that same level.
-- Hardware: inventory upgrade, inventory controller upgrade, network
-- card (wired to the same network as the PC, or wireless), and a
-- pickaxe equipped in the tool slot. Stock it with every foundation
-- block your route needs; blocks it breaks return to its inventory.

local component = require("component")
local event     = require("event")
local robot     = require("robot")

local PORT = 4477  -- must match botPort in the PC's beeconfig

local modem = component.modem
local ic    = component.inventory_controller

local function findSlot(label)
  local want = label:lower()
  for slot = 1, robot.inventorySize() do
    local s = ic.getStackInInternalSlot(slot)
    if s and s.label and s.label:lower() == want then return slot end
  end
  -- fuzzy fallback: label contained in item label
  for slot = 1, robot.inventorySize() do
    local s = ic.getStackInInternalSlot(slot)
    if s and s.label and s.label:lower():find(want, 1, true) then
      return slot
    end
  end
end

local function place(label)
  local slot = findSlot(label)
  if not slot then
    return false, "no '" .. label .. "' in robot inventory"
  end
  if robot.detect() then
    robot.swing()
    if robot.detect() then
      return false, "cannot break current foundation (tool? durability?)"
    end
  end
  robot.select(slot)
  if not robot.place() then
    return false, "place failed"
  end
  return true, label
end

modem.open(PORT)
print("beebot: listening on port " .. PORT)

while true do
  local _, _, from, port, _, tag, cmd, label = event.pull("modem_message")
  if tag == "beebot" then
    if cmd == "place" then
      local ok, why = place(tostring(label))
      modem.send(from, port, "beebot", ok and "ok" or "fail", why)
      print((ok and "placed: " or "FAILED: ") .. tostring(why))
    elseif cmd == "ping" then
      modem.send(from, port, "beebot", "ok", "pong")
    end
  end
end
