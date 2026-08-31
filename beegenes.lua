-- beegenes.lua  ->  install to /home/lib/beegenes.lua
-- Pure bee logic: reading genomes, scoring, and choosing breeding pairs.
-- No hardware access in this file.

local config = require("beeconfig")

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

-- Sort by gene score, tiebreak toward higher fertility -- breeding
-- fecundity into the line helps every future cycle.
local function byScoreThenFert(target)
  return function(a, b)
    local sa, sb = genes.score(a, target), genes.score(b, target)
    if sa ~= sb then return sa > sb end
    return (a.fertility or 0) > (b.fertility or 0)
  end
end

function genes.pickPair(princesses, drones, target)
  table.sort(princesses, byScoreThenFert(target))
  table.sort(drones,     byScoreThenFert(target))

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

function genes.dumpStack(stack)
  local serialization = require("serialization")

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
end

-- Recipe-aware pairing for a planned mutation step: assemble
-- parentA x parentB (either orientation). When no princess actively
-- expresses a recipe parent, CONVERT the princess line toward one
-- (pairing her with a parent-species drone) instead of greedy
-- crossing -- a Rocky/Industrious princess should become an
-- Industrious princess before the Clay recipe is attempted.
-- Third return: "recipe", "convert", or nil (greedy fallback).
function genes.pickCross(princesses, drones, parentA, parentB, target)
  local function findPrincess(sp)
    for _, p in ipairs(princesses) do
      if p.active == sp then return p end
    end
  end
  local function findDrone(sp)
    for _, d in ipairs(drones) do
      if d.active == sp then return d end
    end
  end

  -- Direct recipe: princess of one parent x drone of the other
  local p, d = findPrincess(parentA), findDrone(parentB)
  if not (p and d) then
    p, d = findPrincess(parentB), findDrone(parentA)
  end
  if p and d then return p, d, "recipe" end

  -- Conversion: prefer a princess already carrying a recipe parent
  -- as her INACTIVE allele -- crossed with a drone of that species,
  -- the next princess very likely expresses it (often purebred).
  for _, pr in ipairs(princesses) do
    if pr.inactive == parentA or pr.inactive == parentB then
      local want = (pr.inactive == parentA) and parentA or parentB
      local dr = findDrone(want)
      if dr then return pr, dr, "convert" end
    end
  end
  -- Otherwise introduce a parent gene into the princess line
  local dr = findDrone(parentA) or findDrone(parentB)
  if dr and princesses[1] then
    return princesses[1], dr, "convert"
  end

  local gp, gd = genes.pickPair(princesses, drones, target)
  return gp, gd, nil
end

return genes
