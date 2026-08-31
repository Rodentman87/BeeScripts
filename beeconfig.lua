-- beeconfig.lua  ->  install to /home/lib/beeconfig.lua
-- The only file you should need to edit for your physical build.

local sides = require("sides")

return {
  chestSide   = sides.north,  -- side of transposer touching the chest
  apiarySide  = sides.south,  -- side of transposer touching the apiary
  scannerSide = sides.east,   -- side of transposer touching the GT scanner
  sortChestSide = sides.up,   -- chest for cleaned-out hybrid drones
  scanTimeout = 90,           -- seconds before giving up on a scan (power?)
  botEnabled  = false,        -- foundation-swapping robot (see beebot.lua)
  botPort     = 4477,         -- network port shared with the robot
  botTimeout  = 10,           -- seconds to wait for the robot's reply
  pollDelay   = 5,            -- seconds between apiary checks
  animDelay   = 0.5,          -- seconds between UI/spinner ticks
  shimmerStep = 0.25,         -- seconds per glint shimmer sweep advance
  requirePure = false,        -- true = wait for princess with BOTH genes = target
  droneGoal   = 16,           -- also breed this many target-species drones
  intermediateDrones = 4,     -- soft drone goal shown for plan steps
  stagnantWarn = 10,          -- warn if drone count flat for this many cycles
  chatEveryQueen = true,      -- chat message per new queen (false = milestones only)

  -- Forestry apiary slot layout (1.7.10)
  PRINCESS_SLOT = 1,
  DRONE_SLOT    = 2,
  OUTPUT_SLOTS  = {3, 4, 5, 6, 7, 8, 9},

  DUMP_PATH = "/home/beedump.txt",
}
