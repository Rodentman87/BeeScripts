-- beeclimate.lua  ->  install to /home/lib/beeclimate.lua
-- Climate model: the climate a species needs, the climate the hive
-- provides, and whether breeding can close the gap. The wording of
-- a mismatch lives in beeadvice; no hardware access here (species
-- climate comes off beespecies' cache, the hive reading through
-- beeyard).
--
-- Forestry's rules, which shape everything below: a species'
-- PREFERRED temperature/humidity is fixed by the species allele --
-- you cannot breed a Hellish bee into liking Normal -- but tolerance
-- IS a separate, heritable gene pair widening the band around that
-- preference (None / Up N / Down N / Both N). So getting a bee to
-- work at Normal/Normal means breeding in enough tolerance to cover
-- the gap, or moving the climate to the bee with an alveary.

local config = require("beeconfig")

local climate = {}

local TEMPS  = {"Icy", "Cold", "Normal", "Warm", "Hot", "Hellish"}
local HUMIDS = {"Arid", "Normal", "Damp"}

-- Scale lookup. Accepts "NORMAL", "Normal", "EnumTemperature.HOT",
-- or a table carrying the name. Anything unrecognized (including
-- Forestry's NONE) returns nil, which every caller reads as "no
-- opinion" -- we stay quiet rather than guess and warn wrongly.
local function value(list, v)
  if type(v) == "table" then v = v.name or v.ident or v.uid or v.value end
  if type(v) ~= "string" then return nil end
  local s = v:lower()
  for i, name in ipairs(list) do
    if s:find(name:lower(), 1, true) then return i end
  end
  return nil
end

function climate.temp(v)      return value(TEMPS, v) end
function climate.humid(v)     return value(HUMIDS, v) end
function climate.tempName(n)  return TEMPS[n]  or "?" end
function climate.humidName(n) return HUMIDS[n] or "?" end

-- Tolerance allele -> steps allowed down, steps allowed up.
-- Accepts "None", "Up 1", "UP_1", "Down 2", "Both 3", or a table.
function climate.tolerance(v)
  if type(v) == "table" then v = v.name or v.ident or v.uid or v.value end
  if v == nil then return 0, 0 end
  local s = tostring(v):lower()
  local n = tonumber(s:match("%d+")) or 0
  if n == 0 then return 0, 0 end
  if s:find("both", 1, true) then return n, n end
  if s:find("down", 1, true) then return n, 0 end
  if s:find("up",   1, true) then return 0, n end
  return n, n
end

-- Tolerance genes off an item stack, as {tDown, tUp, hDown, hUp}.
-- Reads the ACTIVE alleles -- what the bee expresses, and so what
-- decides whether she can work. Field names vary between builds,
-- hence the fallbacks; nil is "unknown", not "no tolerance".
function climate.toleranceOf(stack)
  local act = stack and stack.individual and stack.individual.active
  if type(act) ~= "table" then return nil end
  local t = act.temperatureTolerance or act.toleranceTemperature
             or act.tempTolerance
  local h = act.humidityTolerance or act.toleranceHumidity
             or act.humidTolerance
  if t == nil and h == nil then return nil end
  local td, tu = climate.tolerance(t)
  local hd, hu = climate.tolerance(h)
  return {tDown = td, tUp = tu, hDown = hd, hUp = hu}
end

-- Where the numbers come from: the species cache and the hive
local registry = nil

local function reg()
  if registry then return registry end
  registry = {}
  -- A missing or unreadable cache is normal, not fatal: no registry
  -- simply means no climate opinions anywhere downstream.
  local ok, list = pcall(function() return require("beespecies").load() end)
  for name, e in pairs((ok and list) or {}) do
    registry[name] = {temp  = climate.temp(e.temp),
                      humid = climate.humid(e.humid)}
  end
  return registry
end

-- Preferred temperature, humidity for a species (scale numbers),
-- or nil, nil when the species cache has nothing to say.
function climate.prefer(species)
  local e = species and reg()[species]
  if not e then return nil, nil end
  return e.temp, e.humid
end

local apiary = nil

-- nil arguments fall back to beeconfig, so a tile that exposes
-- nothing still gives the Normal/Normal baseline of a plain apiary.
function climate.setApiary(t, h)
  local dt, dh = climate.temp(t), climate.humid(h)
  apiary = {
    temp     = dt or climate.temp(config.apiaryTemperature) or 3,
    humid    = dh or climate.humid(config.apiaryHumidity)   or 2,
    detected = (dt or dh) ~= nil,
  }
  apiary.text = climate.tempName(apiary.temp) .. "/" ..
                climate.humidName(apiary.humid)
  return apiary
end

function climate.apiary() return apiary or climate.setApiary(nil, nil) end

-- Ask the hive what climate it provides; beeconfig wins when
-- climateAuto is off. Cheap enough to call once a cycle, so an
-- Alveary Heater added mid-run is noticed without a restart.
function climate.autodetect()
  local t, h
  if config.climateAuto ~= false then
    local ok, yard = pcall(require, "beeyard")
    if ok then
      local got, a, b = pcall(yard.detectClimate)
      if got then t, h = a, b end
    end
  end
  return climate.setApiary(t, h)
end

-- How far the hive would have to move for this bee, in steps:
-- 0 = fine, positive = the hive must go up, negative = down.
local function gap(pref, down, up, actual)
  if not pref then return 0 end
  local lo, hi = pref - (down or 0), pref + (up or 0)
  if actual < lo then return lo - actual end
  if actual > hi then return hi - actual end
  return 0
end

-- Can `tol` close the gaps this verdict reports? A hive that must
-- warm up needs the bee to tolerate downward, and vice versa.
local function covers(tol, st)
  tol = tol or {}
  local t = (st.temp  > 0) and (tol.tDown or 0) or (tol.tUp or 0)
  local h = (st.humid > 0) and (tol.hDown or 0) or (tol.hUp or 0)
  return math.abs(st.temp) <= t and math.abs(st.humid) <= h
end

-- Verdict for keeping `species` in the hive while carrying tolerance
-- `tol` (nil = bare species, no tolerance). Returns nil when the
-- registry knows nothing about the species -- callers stay silent
-- then rather than invent a warning.
function climate.status(species, tol)
  local pt, ph = climate.prefer(species)
  if not (pt or ph) then return nil end
  local a = climate.apiary()
  tol = tol or {}
  local st = {
    species = species, apiary = a.text,
    temp  = gap(pt, tol.tDown, tol.tUp, a.temp),
    humid = gap(ph, tol.hDown, tol.hUp, a.humid),
    want  = (pt and climate.tempName(pt)  or "?") .. "/" ..
            (ph and climate.humidName(ph) or "?"),
  }
  st.ok = (st.temp == 0 and st.humid == 0)
  return st
end

-- Rank a candidate as a partner for breeding `species`. role "p" =
-- princess: SHE becomes the queen (a queen carries the princess's
-- own genome), so her climate decides whether the hive ticks at all.
-- role "d" = drone: only his genes travel, so donating tolerance is
-- his whole contribution. Constant when the registry is silent,
-- leaving pair ordering as it was on setups with no species cache.
function climate.rank(bee, species, role)
  local st = species and climate.status(species)
  if not st then return 0 end
  if role == "d" then return covers(bee.tol, st) and 1 or 0 end
  local mine = bee.active and climate.status(bee.active, bee.tol)
  return ((not mine or mine.ok) and 2 or 0) + (covers(bee.tol, st) and 1 or 0)
end

-- First bee in the list whose tolerance already closes this gap.
function climate.donor(bees, st)
  for _, b in ipairs(bees or {}) do
    if b.tol and covers(b.tol, st) then return b end
  end
  return nil
end

-- Extra planner cost for a species the hive cannot house: a soft
-- nudge, so a climate-friendly route wins when the odds are close,
-- without ever hiding the only route there is.
function climate.routeCost(species)
  local st = climate.status(species)
  if not st or st.ok then return 0 end
  return config.climatePenalty or 60
end

return climate
