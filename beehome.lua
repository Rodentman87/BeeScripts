-- beehome.lua  ->  install to /home/beehome.lua
-- The screen the computer boots into: the library, what is under its
-- floor, and one touch to fix it. Breeding, settings, wiring and the
-- updater all launch from here and hand control back when they finish.
--
-- beebreeder is still the CLI and still works exactly as it did; this
-- is the thing you look at when you are not typing. beehomeact holds
-- the state and does the work -- this is the program around it.

local core   = require("beeui")
local config = require("beeconfig")
local data   = require("beedata")
local ui     = require("beehomeui")
local act    = require("beehomeact")

-- Nothing works until the transposer is pointing at the right blocks,
-- so that comes before the screen, exactly as beebreeder does it.
local status, note = require("beedetect").autoheal()
if status == "fixed" then
  print("Transposer sides moved -- using " .. tostring(note))
elseif status == "unresolved" then
  act.setSides(false)
  print("Transposer wiring needs a look: " .. tostring(note))
  if core.hasGpu and require("beewire").run() then act.setSides(true) end
end

act.setMuts((data.load()))

-- The home layout is built for a 160x50 wall and does not fold down
-- to 80x25. On anything smaller (or with no screen at all) say what
-- is in the library and hand over to the commands that do fit.
if not (core.hasGpu and core.isWide()) then
  pcall(act.scan)
  local t = act.totals()
  print(("BeeHome: %d species, %d princesses, %d drones")
        :format(t.species, t.p, t.d))
  local tally = act.tally()
  for _, sp in ipairs(act.lowSpecies()) do
    print(("  low: %-16s %d princesses, %d drones")
          :format(sp, tally[sp].p, tally[sp].d))
  end
  print("The home screen needs a touch screen 120 columns or wider.")
  print("Use `beebreeder <Species>` and `beeprobe sides` from here.")
  return
end

act.start()

while true do
  core.pump(config.animDelay or 0.5)
  ui.tick()
  if core.haltRequested() then break end
  local wanted = act.taken()
  if wanted == "shell" then break end
  if wanted then act.run(wanted) end

  if act.due() >= (config.homeRescan or 300) then
    act.scan()
    act.redraw()
  end
  -- Auto-tend: an idle apiary with something under its floor is a job
  -- nobody should have to ask for. The toggle is deliberately not
  -- saved -- leaving the hive free for hand use is a per-sitting call.
  -- A restock that cannot finish turns it off rather than trying the
  -- same impossible species over and over.
  if config.autoTend and act.totals().low > 0 and not act.busy() then
    if not act.restockLow("auto-tend") then
      config.autoTend = false
      act.redraw()
    end
  end
end

core.finish()
print("BeeHome closed. Type `beehome` to come back.")
