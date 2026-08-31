-- beedump.lua  ->  install to /home/lib/beedump.lua
-- `beebreeder dump`: write one bee's raw genome to a file and print
-- the handful of fields the breeder actually relies on. This is the
-- quickest way to check that your pack's OpenComputers driver names
-- things the way beegenes and beeclimate expect -- especially the
-- tolerance alleles, whose field names vary between builds.

local serialization = require("serialization")
local config  = require("beeconfig")
local genes   = require("beegenes")
local climate = require("beeclimate")
local advice  = require("beeadvice")

local dump = {}

function dump.stack(stack)
  -- Full blob goes to a file (way too big for a T1 screen)
  local f = io.open(config.DUMP_PATH, "w")
  if f then
    f:write(serialization.serialize(stack, math.huge))
    f:close()
    print("Full dump written to " .. config.DUMP_PATH)
    print("Browse it with:  edit " .. config.DUMP_PATH)
  else
    print("Could not write " .. config.DUMP_PATH)
  end

  -- Short summary of just the fields the breeder relies on
  print("--- summary ---")
  print("name:  " .. tostring(stack.name))
  print("label: " .. tostring(stack.label))
  local ind = stack.individual
  if not ind then
    print("individual: NIL  <-- genome not readable!")
    return
  end
  print("analyzed: " .. tostring(ind.isAnalyzed))
  local active, inactive = genes.speciesOf(stack)
  print("active species:   " .. tostring(active))
  print("inactive species: " .. tostring(inactive))

  local tol = climate.toleranceOf(stack)
  if tol then
    print(("tolerance: temp -%d/+%d  humidity -%d/+%d")
          :format(tol.tDown, tol.tUp, tol.hDown, tol.hUp))
  else
    print("tolerance: NOT READABLE  <-- check the allele field names")
    print("           in beeclimate.toleranceOf against the dump file.")
  end
  local st = active and climate.status(active, tol)
  if st then
    print("climate:  " .. advice.line(st))
  else
    print("climate:  unknown species -- run `beeprobe build`")
  end
end

return dump
