-- beespecies.lua  ->  install to /home/lib/beespecies.lua
-- Species-registry cache: every species' preferred climate, pulled
-- from listAllSpecies on the apiculture tile and stored compactly
-- so the RAM-heavy registry call only has to happen once.
--
-- Cache format (/home/beedata/species.dat), one species per line:
--   name|temperature|humidity
-- Values are stored verbatim as the registry spells them; beeclimate
-- is what maps them onto its scales, so a pack that says "HELLISH"
-- and one that says "Hellish" both work without a rebuild.

local data = require("beedata")

local species = {}

local FILE   = "/home/beedata/species.dat"
local SAMPLE = "/home/beedata/species_sample.txt"

-- Registry values may be plain strings or tables; either way we want
-- something a human (and beeclimate) can read back.
local function text(v)
  if type(v) == "table" then
    v = data.field(v, "name", "ident", "uid", "value")
  end
  return v ~= nil and tostring(v) or ""
end

--------------------------------------------------------------------
-- Sample: capture the real entry shape so field guesses can be
-- checked before trusting the cache.
--------------------------------------------------------------------
function species.sample(count)
  local serialization = require("serialization")
  local api, err = data.apiculture()
  if not api then return nil, err end
  if not api.listAllSpecies then
    return nil, "component has no listAllSpecies method"
  end
  local ok, list = pcall(api.listAllSpecies)
  if not ok then return nil, "listAllSpecies failed: " .. tostring(list) end

  data.ensureDir()
  local f = io.open(SAMPLE, "w")
  if not f then return nil, "cannot write " .. SAMPLE end
  count = math.min(count or 5, #list)
  f:write(("== %d species; first %d ==\n\n"):format(#list, count))
  for i = 1, count do
    f:write(serialization.serialize(list[i], math.huge) .. "\n\n")
  end
  f:close()
  return #list
end

--------------------------------------------------------------------
-- Build: extract name + climate for every species into the cache.
-- Entries are released as we go, as in beedata.build().
--------------------------------------------------------------------
function species.build()
  local api, err = data.apiculture()
  if not api then return nil, err end
  if not api.listAllSpecies then
    return nil, "component has no listAllSpecies method"
  end
  local ok, list = pcall(api.listAllSpecies)
  if not ok then return nil, "listAllSpecies failed: " .. tostring(list) end

  data.ensureDir()
  local f = io.open(FILE, "w")
  if not f then return nil, "cannot write " .. FILE end

  local written, skipped = 0, 0
  for i = 1, #list do
    local e = list[i]
    local name = text(data.field(e, "name", "displayName", "uid"))
    local t = text(data.field(e, "temperature", "temp",
                                 "preferredTemperature"))
    local h = text(data.field(e, "humidity", "humid",
                                 "preferredHumidity"))
    if name ~= "" and (t ~= "" or h ~= "") then
      f:write(("%s|%s|%s\n"):format(name, t, h))
      written = written + 1
    else
      skipped = skipped + 1
    end
    list[i] = false
  end
  f:close()
  list = nil
  if collectgarbage then collectgarbage("collect") end
  return written, skipped
end

--------------------------------------------------------------------
-- Load: species name -> {temp = string, humid = string}
--------------------------------------------------------------------
function species.load()
  local f = io.open(FILE, "r")
  if not f then
    return nil, "no species cache -- run `beeprobe build`"
  end
  local out = {}
  for line in f:lines() do
    local n, t, h = line:match("([^|]*)|([^|]*)|([^|]*)")
    if n and n ~= "" then out[n] = {temp = t, humid = h} end
  end
  f:close()
  return out
end

return species
