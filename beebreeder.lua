-- beebreeder.lua  ->  install to /home/beebreeder.lua
-- Entry point: parse args (or run the setup screen), load the
-- mutation cache, hand off to the engine.
--
-- Usage:
--   beebreeder                          interactive setup screen
--   beebreeder <targetSpecies>          plan route (needs `beeprobe build`)
--   beebreeder <targetSpecies> direct   greedy mode, no planner
--   beebreeder dump                     write one bee's raw data to a file

local config = require("beeconfig")
local data   = require("beedata")
local run    = require("beerun")

local args = {...}
local target = args[1]

if target == "dump" then
  local yard = require("beeyard")
  yard.scanChest(true)
  return
end

if not target then
  local setup = require("beesetup")
  local job = setup.run()
  if not job then
    print("Usage: beebreeder [<targetSpecies> [direct]] | dump")
    return
  end
  target = job.target
  config.requirePure    = job.requirePure
  config.droneGoal      = job.droneGoal
  config.chatEveryQueen = job.chatEveryQueen
end

-- Load the mutation cache unless direct mode was requested
local muts = nil
if args[2] ~= "direct" then
  muts = (data.load())
end

run.start(target, muts)
