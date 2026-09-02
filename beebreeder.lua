-- beebreeder.lua  ->  install to /home/beebreeder.lua
-- Entry point: parse args (or run the setup screen), load the
-- mutation cache, hand off to the engine.
--
-- Usage:
--   beebreeder                          interactive setup screen
--   beebreeder <targetSpecies>          plan route (needs `beeprobe build`)
--   beebreeder <targetSpecies> direct   greedy mode, no planner
--   beebreeder dump                     write one bee's raw data to a file
--   beebreeder sides                    transposer wiring screen

local config = require("beeconfig")
local data   = require("beedata")
local run    = require("beerun")

local args = {...}
local target = args[1]

if target == "sides" then
  local wire = require("beewire")
  if require("beeui").hasGpu then
    local assign, note = wire.run()
    print(assign and ("Sides " .. note) or "Sides left alone.")
  else
    wire.report(args[2] == "save")
  end
  return
end

-- Nothing works until the transposer is pointing at the right
-- blocks, so that comes before everything else. A rearranged build
-- is usually recognized on sight and simply used; anything detection
-- cannot call goes to the wiring screen rather than being guessed.
local status, note = require("beedetect").autoheal()
if status == "fixed" then
  -- The screen is cleared the moment a setup or dashboard opens, so
  -- say it in chat too: this is the sort of thing to notice later.
  print("Transposer sides moved -- using " .. note)
  print("`beebreeder sides` writes that into beeconfig permanently.")
  require("beechat").say("BeeBreeder: transposer sides moved -- using " .. note)
elseif status == "unresolved" then
  print("Transposer wiring needs a look: " .. tostring(note))
  local wire = require("beewire")
  local assign, why = wire.run()
  if not assign then
    wire.report(false)
    return
  end
  print("Sides " .. why)
end

if target == "dump" then
  local yard = require("beeyard")
  yard.scan(true)
  return
end

-- Load the mutation cache unless direct mode was requested
local muts = nil
if args[2] ~= "direct" then
  muts = (data.load())
end

-- No species named: pick one on screen. The wide breed screen shows
-- one-step crosses from the cabinets and the plan side by side;
-- beesetup is still the 80x25 (and no-cache) version.
if not target then
  local job
  local wide, screen = pcall(require, "beebreedui")
  if wide and muts and require("beeui").isWide() then
    local yard  = require("beeyard")
    local stock = require("beestock")
    local ok, p, d = pcall(yard.scan, false)
    local tally, order = stock.tally(ok and p or {}, ok and d or {})
    job = screen.run(tally, order, muts)
  else
    job = require("beesetup").run()
  end
  if not job then
    print("Usage: beebreeder [<targetSpecies> [direct]] | dump | sides")
    return
  end
  target = job.target
  config.requirePure    = job.requirePure
  config.droneGoal      = job.droneGoal
  config.chatEveryQueen = job.chatEveryQueen
end

run.start(target, muts)
