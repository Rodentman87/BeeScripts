-- beeconfig.lua  ->  install to /home/lib/beeconfig.lua
-- The only file you should need to edit for your physical build.

local sides = require("sides")

return {
  -- Transposer sides. Checked against what is actually attached at
  -- startup: move the build and beebreeder works the new layout out
  -- by itself, and asks on the wiring screen only when it genuinely
  -- cannot tell (two chests that look alike). `beebreeder sides`
  -- edits and saves them here, keeping a beeconfig.lua.bak.
  chestSide   = sides.north,  -- side of transposer touching the chest
  apiarySide  = sides.south,  -- side of transposer touching the apiary
  scannerSide = sides.east,   -- side of transposer touching the GT scanner
  sortChestSide = sides.up,   -- chest for cleaned-out hybrid drones
                              -- (delete this line for no hybrid sweep)

  -- Split storage, all optional. With Extra Utilities filing cabinets
  -- -- one item ID each -- princesses and drones live apart and the
  -- combs go somewhere else again. Anything left unset falls back to
  -- chestSide, so the single-chest build above needs none of these.
  -- Uncomment and point them at the real sides, or let
  -- `beebreeder sides` work them out and write them here.
  -- princessSide = sides.north,  -- cabinet holding princesses
  -- droneSide    = sides.south,  -- cabinet holding drones
  -- dumpSide     = sides.up,     -- combs and everything else

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

  -- Stock floors. Every species in the library is kept at least this
  -- deep, whether or not it is in the current plan: a cross that
  -- would take a species under its floor is replaced by one that
  -- restocks it first. Everything above the floor is surplus, and
  -- surplus is what crosses are allowed to spend.
  princessFloor = 1,          -- princesses kept per species
  droneFloor    = 4,          -- drones kept per species

  -- The home screen (`beehome`, which is what the computer boots
  -- into). autoTend lets it restock a low species by itself whenever
  -- the apiary is idle; with it off, restocking is always a touch.
  autoTend   = false,
  homeRescan = 300,           -- seconds between automatic rescans

  stagnantWarn = 10,          -- warn if drone count flat for this many cycles
  chatEveryQueen = true,      -- chat message per new queen (false = milestones only)

  -- Screen glyphs. `beeprobe glyphs` shows every box-drawing and
  -- marker character the screens use; if the font lacks one, name it
  -- here (asciiOnly = {bot = true}) or swap them all (asciiGlyphs).
  asciiGlyphs = false,
  asciiOnly   = {},

  -- Climate. A plain apiary takes its climate from the biome; an
  -- alveary can be steered with a Heater/Fan/Hygroregulator. These
  -- two are the fallback for when the hive won't tell us itself.
  apiaryTemperature = "Normal",  -- Icy Cold Normal Warm Hot Hellish
  apiaryHumidity    = "Normal",  -- Arid Normal Damp
  climateAuto    = true,      -- ask the hive first, fall back to the above
  climatePenalty = 60,        -- extra planner cost for a species the hive
                              -- can't house (steers routes toward ones it can)

  -- Forestry apiary slot layout (1.7.10)
  PRINCESS_SLOT = 1,
  DRONE_SLOT    = 2,
  OUTPUT_SLOTS  = {3, 4, 5, 6, 7, 8, 9},

  DUMP_PATH = "/home/beedump.txt",
}
