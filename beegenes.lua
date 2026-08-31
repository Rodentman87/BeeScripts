-- beegenes.lua  ->  install to /home/lib/beegenes.lua
-- Pure bee logic: reading genomes, scoring, and choosing breeding pairs.
-- No hardware access in this file.

local config  = require("beeconfig")
local climate = require("beeclimate")

local genes = {}

function genes.isPrincess(stack)
  return stack and stack.name == "Forestry:beePrincessGE"
end

function genes.isDrone(stack)
  return stack and stack.name == "Forestry:beeDroneGE"
end

function genes.isBee(stack)
  return genes.isPrincess(stack) or genes.isDrone(stack)
end

function genes.isAnalyzed(stack)
  return stack and stack.individual and stack.individual.isAnalyzed == true
end

local function geneSpecies(gene)
  if not gene then return nil end
  local sp = gene.species
  if type(sp) == "table" then return sp.name end
  return sp
end

-- Returns activeSpecies, inactiveSpecies (best effort)
function genes.speciesOf(stack)
  local ind = stack and stack.individual
  if not ind then return nil, nil end
  local active   = geneSpecies(ind.active)
  local inactive = geneSpecies(ind.inactive)
  if not active and ind.displayName then
    active = ind.displayName
  end
  return active, inactive
end

-- Fertility trait: how many drones a queen yields per cycle.
-- Field is best-effort; returns nil if this OC version doesn't expose it.
function genes.fertilityOf(stack)
  local ind = stack and stack.individual
  local act = ind and ind.active
  return act and act.fertility
end

function genes.label(bee)
  local s = tostring(bee.active) .. "/" .. tostring(bee.inactive)
  if bee.fertility then s = s .. " f" .. bee.fertility end
  local t = bee.tol
  if t and (t.tDown + t.tUp + t.hDown + t.hUp) > 0 then
    s = s .. (" t%d/%d"):format(t.tDown + t.tUp, t.hDown + t.hUp)
  end
  return s
end

function genes.score(bee, target)
  local s = 0
  if bee.active   == target then s = s + 4 end
  if bee.inactive == target then s = s + 2 end
  return s
end

function genes.isWinner(bee, target)
  return bee.active == target and
         (not config.requirePure or bee.inactive == target)
end

-- Total number of target-species drones, counting stack sizes
-- (identical drones stack, so one chest slot can hold many).
function genes.countTarget(drones, target)
  local n = 0
  for _, d in ipairs(drones) do
    if genes.isWinner(d, target) then
      n = n + (d.size or 1)
    end
  end
  return n
end

-- Sort by gene score, then by climate fitness for `role` ("p" or
-- "d" -- see climate.rank), then toward higher fertility. Climate
-- sits above fertility because a princess who cannot work in this
-- hive yields nothing at all, however fecund she is; on setups with
-- no species cache the climate term is constant and this is exactly
-- the old score-then-fertility order.
local function byScoreThenFert(target, role)
  return function(a, b)
    local sa, sb = genes.score(a, target), genes.score(b, target)
    if sa ~= sb then return sa > sb end
    local ca, cb = climate.rank(a, target, role), climate.rank(b, target, role)
    if ca ~= cb then return ca > cb end
    return (a.fertility or 0) > (b.fertility or 0)
  end
end

function genes.pickPair(princesses, drones, target)
  table.sort(princesses, byScoreThenFert(target, "p"))
  table.sort(drones,     byScoreThenFert(target, "d"))

  local p = princesses[1]
  local d = drones[1]

  -- Fertility-1 economy: the queen consumes one drone and yields one
  -- back, so target x target is net-zero drone growth at best. Spend a
  -- non-target "fuel" drone instead: banked target drones stay intact,
  -- and offspring still have good odds of coming out target-species.
  if genes.isWinner(p, target) and (p.fertility or 2) <= 1 then
    for _, cand in ipairs(drones) do
      if not genes.isWinner(cand, target) then
        d = cand
        break
      end
    end
  end

  -- Nobody carries target genes yet: cross two different species
  -- to maximize mutation rolls
  if d and genes.score(d, target) == 0 and genes.score(p, target) == 0 then
    for _, cand in ipairs(drones) do
      if cand.active ~= p.active then
        d = cand
        break
      end
    end
  end
  return p, d
end

-- Recipe-aware pairing for a planned mutation step: assemble
-- parentA x parentB (either orientation). When no princess actively
-- expresses a recipe parent, CONVERT the princess line toward one
-- (pairing her with a parent-species drone) instead of greedy
-- crossing -- a Rocky/Industrious princess should become an
-- Industrious princess before the Clay recipe is attempted.
-- Third return: "recipe", "convert", or nil (greedy fallback).
function genes.pickCross(princesses, drones, parentA, parentB, target)
  -- Among bees actively expressing `sp`, take the one that fits the
  -- hive best (climate.rank); chest order decides otherwise.
  local function best(list, sp, role)
    local found
    for _, b in ipairs(list) do
      if b.active == sp and (not found or
         climate.rank(b, sp, role) > climate.rank(found, sp, role)) then
        found = b
      end
    end
    return found
  end
  local function findPrincess(sp) return best(princesses, sp, "p") end
  local function findDrone(sp)    return best(drones, sp, "d") end

  -- Direct recipe: princess of one parent x drone of the other
  local p, d = findPrincess(parentA), findDrone(parentB)
  if not (p and d) then
    p, d = findPrincess(parentB), findDrone(parentA)
  end
  if p and d then return p, d, "recipe" end

  -- Conversion: prefer a princess already carrying a recipe parent
  -- as her INACTIVE allele -- crossed with a drone of that species,
  -- the next princess very likely expresses it (often purebred).
  -- Among equals the one this hive can house wins: she is the one
  -- who has to sit in the apiary as the queen.
  local bestP, bestD, bestRank = nil, nil, -1
  for _, pr in ipairs(princesses) do
    local want = (pr.inactive == parentA and parentA)
              or (pr.inactive == parentB and parentB)
    local dr = want and findDrone(want)
    if dr and climate.rank(pr, target, "p") > bestRank then
      bestP, bestD, bestRank = pr, dr, climate.rank(pr, target, "p")
    end
  end
  if bestP then return bestP, bestD, "convert" end

  -- Otherwise introduce a parent gene into the princess line, again
  -- through the princess this hive is least likely to freeze.
  local dr = findDrone(parentA) or findDrone(parentB)
  local pr = princesses[1]
  for _, cand in ipairs(princesses) do
    if climate.rank(cand, target, "p") > climate.rank(pr, target, "p") then
      pr = cand
    end
  end
  if dr and pr then return pr, dr, "convert" end

  local gp, gd = genes.pickPair(princesses, drones, target)
  return gp, gd, nil
end

return genes
