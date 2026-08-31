-- beeprobe.lua  ->  install to /home/beeprobe.lua
-- Stage-1 tool for the generic breeder.
--
--   beeprobe          capture format samples to /home/beedata/sample.txt
--   beeprobe build    extract mutation graph + species climate to cache
--   beeprobe stats    summarize the cached graph
--   beeprobe species  sample the species registry (colors? climate?)
--   beeprobe climate  does this hive report its own climate?
--   beeprobe sides    what is on each transposer side (add `save`
--                     to write the detected wiring to beeconfig)
--
-- Run right after a fresh reboot for maximum free RAM -- the
-- registry call materializes the whole mutation table at once.

local data = require("beedata")
local species = require("beespecies")
local computer = require("computer")

local args = {...}
local mode = args[1] or "probe"

print(("Free RAM: %d KB"):format(math.floor(computer.freeMemory() / 1024)))

if mode == "probe" then
  print("Probing apiculture registry...")
  local n, err = data.probe(5)
  if not n then
    print("FAILED: " .. tostring(err))
    print("If this is an out-of-memory error, add RAM and reboot first.")
    return
  end
  print(("%d mutations in registry."):format(n))
  print("Samples + method list written to /home/beedata/sample.txt")
  print("Check the field names there before running `beeprobe build`.")

elseif mode == "build" then
  print("Extracting full mutation graph (this can take a moment)...")
  local written, errOrSkipped = data.build()
  if not written then
    print("FAILED: " .. tostring(errOrSkipped))
    return
  end
  print(("Cached %d mutations (%d entries skipped -- unrecognized shape)")
        :format(written, errOrSkipped))
  if errOrSkipped > 0 then
    print("Skipped entries mean the field guesses in beedata.lua need")
    print("adjusting -- check sample.txt and fix compact().")
  end

  -- Second pass: each species' preferred climate, for the warnings
  print("Extracting species climate...")
  local spWritten, spErrOrSkipped = species.build()
  if not spWritten then
    print("Species climate SKIPPED: " .. tostring(spErrOrSkipped))
    print("Breeding still works; climate warnings stay silent.")
  else
    print(("Cached climate for %d species (%d without one)")
          :format(spWritten, spErrOrSkipped))
  end

elseif mode == "species" then
  print("Probing species registry...")
  local n, err = species.sample(5)
  if not n then
    print("FAILED: " .. tostring(err))
    return
  end
  print(("%d species in registry."):format(n))
  print("Samples written to /home/beedata/species_sample.txt")
  print("Check the temperature/humidity spelling there against the")
  print("scales in beeclimate.lua if climate warnings look wrong.")

elseif mode == "climate" then
  -- Sweep every climate-ish method the tile exposes, not just the
  -- names beeyard.detectClimate guesses at, and show the RAW return
  -- value. A method that answers with a number rather than a name is
  -- dropped on purpose (an enum ordinal we cannot safely place on a
  -- scale) -- this is where you would see that happening.
  local component = require("component")
  local climate   = require("beeclimate")
  local api, apiErr = data.apiculture()
  if not api then
    print("FAILED: " .. tostring(apiErr))
    return
  end
  print("Climate-ish methods on " .. api.address:sub(1, 8) .. ":")
  local any = false
  for m in pairs(component.methods(api.address)) do
    local lower = m:lower()
    if lower:find("temp") or lower:find("humid")
       or lower:find("climate") or lower:find("biome") then
      any = true
      local ok, v = pcall(api[m])
      if type(v) == "table" then
        v = require("serialization").serialize(v, math.huge)
      end
      print(("  %s() -> %s [%s]"):format(m, tostring(v),
            ok and type(v) or "call failed"))
    end
  end
  if not any then
    print("  none -- this driver does not report the hive's climate.")
    print("  Set apiaryTemperature/apiaryHumidity in beeconfig; that")
    print("  is the whole source of truth then, and it is enough.")
  end
  local hive = climate.autodetect()
  print(("In effect: %s (%s)"):format(hive.text,
        hive.detected and "read from the hive" or "from beeconfig"))

elseif mode == "sides" then
  require("beewire").report(args[2] == "save")

elseif mode == "stats" then
  local muts, species = data.load()
  if not muts then
    print("FAILED: " .. tostring(species))
    return
  end
  local count = 0
  for _ in pairs(species) do count = count + 1 end
  print(("Cache: %d mutations across %d species."):format(#muts, count))

else
  print("Usage: beeprobe [probe|build|stats|species|climate|sides]")
end
