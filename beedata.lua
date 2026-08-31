-- beedata.lua  ->  install to /home/lib/beedata.lua
-- Mutation-graph extraction from the Forestry apiculture tile
-- (via an Adapter block), cached compactly on disk so the huge
-- raw table only ever has to fit in RAM once.
--
-- Cache format (/home/beedata/mutations.dat), one mutation per line:
--   parentA|parentB|result|chance|conditions
--
-- NOTE: the field names in compact() below are a best guess at the
-- registry format. Run `beeprobe` first and check sample.txt -- if
-- the real fields differ, fix the field() calls in compact().

local component     = require("component")
local serialization = require("serialization")
local filesystem    = require("filesystem")

local data = {}

local CACHE_DIR   = "/home/beedata"
local MUT_FILE    = CACHE_DIR .. "/mutations.dat"
local SAMPLE_FILE = CACHE_DIR .. "/sample.txt"

local function ensureDir()
  if not filesystem.exists(CACHE_DIR) then
    filesystem.makeDirectory(CACHE_DIR)
  end
end

-- Find the bee-housing component regardless of its exact registered
-- name (seen in the wild as tile_for_apiculture_0_name and similar).
-- An Adapter on an Alveary registers under THAT block's name, so the
-- alveary spellings count too -- and a candidate that actually
-- exposes the registry beats one that merely looks right, which is
-- what settles it when both hives have an Adapter on them.
-- Exported: beespecies and beeyard reach the same tile through it.
local HIVE_NAMES = {"apiculture", "alveary", "apiary", "beehouse"}

local function looksLikeHive(name)
  for _, k in ipairs(HIVE_NAMES) do
    if name:find(k, 1, true) then return true end
  end
  return false
end

local function findApiculture()
  local fallback = nil
  for addr, name in component.list() do
    if looksLikeHive(name:lower()) then
      local proxy = component.proxy(addr)
      -- The registry methods are what beedata and beespecies came
      -- for; a hive without them can still answer climate questions.
      if proxy and (proxy.getBeeBreedingData or proxy.listAllSpecies) then
        return proxy
      end
      fallback = fallback or proxy
    end
  end
  if fallback then return fallback end
  return nil, "no bee housing component -- Adapter next to the apiary or alveary?"
end

-- Pick the first present field from a list of candidate names
local function field(t, ...)
  if type(t) ~= "table" then return nil end
  for _, k in ipairs({...}) do
    if t[k] ~= nil then return t[k] end
  end
  return nil
end

data.apiculture = findApiculture
data.ensureDir  = ensureDir
data.field      = field

-- A species reference may be a plain string or a table; dig out
-- something usable either way.
local function speciesName(v)
  if type(v) == "table" then
    return field(v, "name", "uid", "displayName")
  end
  return v
end

--------------------------------------------------------------------
-- Probe: capture the real format so we can verify assumptions.
-- Writes entry samples + the component's full method list.
--------------------------------------------------------------------
function data.probe(sampleCount)
  local api, err = findApiculture()
  if not api then return nil, err end

  ensureDir()
  local f = io.open(SAMPLE_FILE, "w")
  if not f then return nil, "cannot write " .. SAMPLE_FILE end

  f:write("== methods on " .. api.address:sub(1, 8) .. " ==\n")
  for m in pairs(component.methods(api.address)) do
    f:write("  " .. m .. "\n")
  end

  local ok, muts = pcall(api.getBeeBreedingData)
  if not ok then
    f:close()
    return nil, "getBeeBreedingData failed: " .. tostring(muts)
  end

  f:write(("\n== %d mutation entries; first %d ==\n\n")
          :format(#muts, math.min(sampleCount or 5, #muts)))
  for i = 1, math.min(sampleCount or 5, #muts) do
    f:write(serialization.serialize(muts[i], math.huge) .. "\n\n")
  end
  f:close()
  return #muts
end

--------------------------------------------------------------------
-- Build: extract everything into the compact disk cache.
-- Writes each line immediately so peak memory stays close to the
-- unavoidable cost of the registry call itself.
--------------------------------------------------------------------
local function compact(m)
  local a = speciesName(field(m, "allele1", "parent1", "firstParent"))
  local b = speciesName(field(m, "allele2", "parent2", "secondParent"))
  local r = speciesName(field(m, "result", "child", "resultAllele"))
  local c = field(m, "chance", "baseChance") or 0
  local cond = field(m, "specialConditions", "conditions")
  if type(cond) == "table" then
    cond = table.concat(cond, "; ")
  end
  if not (a and b and r) then return nil end
  return ("%s|%s|%s|%s|%s"):format(a, b, r, tostring(c), tostring(cond or ""))
end

function data.build()
  local api, err = findApiculture()
  if not api then return nil, err end

  local ok, muts = pcall(api.getBeeBreedingData)
  if not ok then
    return nil, "getBeeBreedingData failed: " .. tostring(muts)
  end

  ensureDir()
  local f = io.open(MUT_FILE, "w")
  if not f then return nil, "cannot write " .. MUT_FILE end

  local written, skipped = 0, 0
  for i = 1, #muts do
    local line = compact(muts[i])
    if line then
      f:write(line .. "\n")
      written = written + 1
    else
      skipped = skipped + 1
    end
    muts[i] = false  -- release each entry as we go
  end
  f:close()
  muts = nil
  -- OpenOS's sandbox does not expose collectgarbage, so this is only
  -- a nudge where it exists; dropping the table above is what
  -- actually frees the memory either way.
  if collectgarbage then collectgarbage("collect") end
  return written, skipped
end

--------------------------------------------------------------------
-- Load: read the compact cache back for the planner.
-- Returns list of {a=, b=, r=, chance=, cond=} and a species set.
--------------------------------------------------------------------
function data.load()
  local f = io.open(MUT_FILE, "r")
  if not f then
    return nil, "no cache -- run `beeprobe build` first"
  end
  local muts, species = {}, {}
  for line in f:lines() do
    local a, b, r, c, cond = line:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)")
    if a and b and r then
      table.insert(muts, {a = a, b = b, r = r,
                          chance = tonumber(c) or 0, cond = cond})
      species[a], species[b], species[r] = true, true, true
    end
  end
  f:close()
  return muts, species
end

return data
