-- beeplan.lua  ->  install to /home/beeplan.lua
-- Plan a breeding route without starting the breeder.
--
--   beeplan <Target>                 owned species read from the chest
--   beeplan <Target> Forest Meadows  owned species given explicitly
--
-- Requires the mutation cache: run `beeprobe build` first.

local data    = require("beedata")
local planner = require("beeplanner")

local args = {...}
local target = args[1]
if not target then
  print("Usage: beeplan <TargetSpecies> [ownedSpecies...]")
  return
end

local muts, err = data.load()
if not muts then
  print("FAILED: " .. tostring(err))
  return
end

-- Owned species: explicit args win; otherwise scan the chest
local owned = {}
if args[2] then
  for i = 2, #args do owned[args[i]] = true end
else
  local ok, yard = pcall(require, "beeyard")
  local scanned = ok and select(1, pcall(function()
    local princesses, drones = yard.scanChest(false)
    for _, b in ipairs(princesses) do
      if b.active then owned[b.active] = true end
      if b.inactive then owned[b.inactive] = true end
    end
    for _, b in ipairs(drones) do
      if b.active then owned[b.active] = true end
      if b.inactive then owned[b.inactive] = true end
    end
    return true
  end))
  if not scanned then
    print("Could not scan chest -- list owned species as arguments instead.")
    return
  end
end

local ownedList = {}
for s in pairs(owned) do ownedList[#ownedList + 1] = s end
table.sort(ownedList)
print("Owned: " .. table.concat(ownedList, ", "))

local steps, why = planner.compute(muts, owned, target)
if not steps then
  print("NO ROUTE: " .. tostring(why))
  return
end
if #steps == 0 then
  print("You already own " .. target .. "!")
  return
end

print("")
for _, line in ipairs(planner.describe(steps)) do
  print(line)
end
