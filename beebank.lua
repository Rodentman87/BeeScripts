-- beebank.lua  ->  install to /lib/beebank.lua
-- Keeping the library full: the ladder that replaces a cross which
-- would take a species under its stock floor with one that restocks
-- it instead. beestock decides what is low; this decides what to
-- breed about it. Pure logic, no hardware and no screens.
--
-- The ladder runs AFTER the planner and after pair selection, never
-- inside them. The planner still works on "exists", which is what
-- makes replanning every cycle, self-healing and lucky skips work;
-- this only ever swaps the pair the engine was about to breed.

local genes   = require("beegenes")
local climate = require("beeclimate")
local stock   = require("beestock")

local bank = {}

local function copy(list)
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  return out
end

-- Drones we are allowed to burn: species with more than the floor,
-- plus `also`, the species being banked -- its drone comes straight
-- back out of the queen, and then some.
local function spendable(tally, drones, also)
  local _, df = stock.floors()
  local out = {}
  for _, dr in ipairs(drones) do
    local e = tally[dr.active]
    if dr.active == also or not e or e.d > df then out[#out + 1] = dr end
  end
  return out
end

-- The princess with the most to spare, hive fitness breaking ties:
-- she is the one who has to sit in the apiary as the queen, and a
-- queen this climate cannot house never finishes her cycle at all.
local function sparePrincess(tally, want)
  local pf = stock.floors()
  local best, bestSpare, bestRank
  for _, e in pairs(tally) do
    local spare = e.p - pf
    if spare > 0 then
      for _, pr in ipairs(e.princesses) do
        local rank = climate.rank(pr, want, "p")
        if not best or spare > bestSpare
           or (spare == bestSpare and rank > bestRank) then
          best, bestSpare, bestRank = pr, spare, rank
        end
      end
    end
  end
  return best
end

-- BANK: a princess of sp under a drone that costs us nothing. Her own
-- species first, because those offspring are sp for certain.
-- genes.pickPair already orders drones for a target and already knows
-- to spend fuel rather than the bank at fertility 1.
local function bankPair(tally, drones, sp)
  local e = tally[sp]
  local pr = e and e.princesses[1]
  if not pr then return nil end
  local pool = (#e.drones > 0) and e.drones or spendable(tally, drones, sp)
  if #pool == 0 then pool = drones end
  local _, d = genes.pickPair({pr}, copy(pool), sp)
  if not d then return nil end
  return pr, d
end

-- CONVERT: a princess we can spare, put under a drone of sp, so the
-- next princess of that line expresses sp. Worth doing even on the
-- last sp drone -- a princess of sp is worth more than the drone was.
local function convertPair(tally, drones, sp)
  local e = tally[sp]
  if not (e and #e.drones > 0) then return nil end
  local pr = sparePrincess(tally, sp)
  if not pr then return nil end
  local _, d = genes.pickPair({pr}, copy(e.drones), sp)
  return pr, d or e.drones[1]
end

--------------------------------------------------------------------
-- The gate. Returns p, d, mode, note. mode nil with note nil means
-- the pair was already safe and is unchanged; mode nil WITH a note
-- means nothing safe was available and the caller should say so once
-- before breeding the pair anyway.
--------------------------------------------------------------------
function bank.gate(tally, princesses, drones, p, d, target)
  local safe, why = stock.safe(tally, p, d)
  if safe then return p, d end
  local pf, df = stock.floors()

  -- The drone about to be spent is the last one holding its species
  -- at the floor: rebuild that species instead of eating it. With a
  -- princess of it in hand that is banking; without one it is a
  -- conversion, and that is worth doing on the very last drone.
  local de = tally[d.active]
  if de and (de.d - 1) < df then
    local p2, d2 = bankPair(tally, drones, d.active)
    if p2 then
      return p2, d2, "bank", ("banking %s back to %d drones"):format(d.active, df)
    end
    p2, d2 = convertPair(tally, drones, d.active)
    if p2 then
      return p2, d2, "convert", ("converting a princess toward " .. d.active)
    end
  end

  -- She is the last princess of her species and the drone is foreign,
  -- so the line ends with this cross. Deepen her drone bank while it
  -- is thin; once it is deep enough, breed a second princess for it.
  local pe = tally[p.active]
  if pe and pe.p <= pf and d.active ~= p.active then
    local p2, d2
    if pe.d < df + 1 then
      p2, d2 = bankPair(tally, drones, p.active)
    else
      p2, d2 = convertPair(tally, drones, p.active)
    end
    if p2 then
      return p2, d2, "secure", ("securing the " .. p.active .. " line")
    end
  end

  -- Nothing safe exists: no surplus princess anywhere. Breed the pair
  -- we were given; the note is what gets logged and chatted.
  return p, d, nil, why
end

return bank
