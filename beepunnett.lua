-- beepunnett.lua  ->  install to /lib/beepunnett.lua
-- Punnett square for the pair going into the apiary: the princess's
-- two species alleles down the side, the drone's across the top,
-- and in each of the four cells the offspring genotype plus any
-- mutation that allele pair can trigger, with its chance.
--
-- Forestry rolls a mutation by picking one allele from each parent
-- at random (so each cell is a 25% draw) and trying the mutations
-- registered for that pair, and it gets two such draws per
-- offspring. The per-offspring figure below follows that; it is an
-- estimate, hence the "about" in the text.
--
-- Pure logic; the wide dashboard does the drawing.

local punnett = {}

local indexed, index = nil, nil

-- Mutations keyed by unordered parent pair, built once per cache
local function pairIndex(muts)
  if indexed == muts then return index end
  index = {}
  for _, m in ipairs(muts or {}) do
    local key = (m.a < m.b) and (m.a .. "|" .. m.b) or (m.b .. "|" .. m.a)
    local list = index[key]
    if not list then
      list = {}
      index[key] = list
    end
    list[#list + 1] = m
  end
  indexed = muts
  return index
end

local function lookup(muts, a, b)
  if not (muts and a and b) then return {} end
  local idx = pairIndex(muts)
  local key = (a < b) and (a .. "|" .. b) or (b .. "|" .. a)
  return idx[key] or {}
end

-- p, d: bee records {active=, inactive=}. Returns
--   {rows = {pActive, pInactive}, cols = {dActive, dInactive},
--    cells = {[r][c] = {p=, d=, pure=, muts={...}}}}
function punnett.square(p, d, muts)
  local rows = {p.active, p.inactive or p.active}
  local cols = {d.active, d.inactive or d.active}
  local cells = {}
  for r = 1, 2 do
    cells[r] = {}
    for c = 1, 2 do
      cells[r][c] = {p = rows[r], d = cols[c], pure = (rows[r] == cols[c]),
                     muts = lookup(muts, rows[r], cols[c])}
    end
  end
  return {rows = rows, cols = cols, cells = cells}
end

-- How the square looks for the species being bred toward.
-- Returns {pairs = cells that can mutate at all, hits = cells that
-- can produce `target`, chance = estimated per-offspring % for
-- target, purity = % of draws that are target/target}
function punnett.odds(sq, target)
  local pairs_, hits, q, pure = 0, 0, 0, 0
  for r = 1, 2 do
    for c = 1, 2 do
      local cell = sq.cells[r][c]
      if #cell.muts > 0 then pairs_ = pairs_ + 1 end
      for _, m in ipairs(cell.muts) do
        if m.r == target then
          hits = hits + 1
          q = q + 0.25 * (m.chance / 100)
        end
      end
      if cell.p == target and cell.d == target then pure = pure + 25 end
    end
  end
  local chance = (1 - (1 - q) ^ 2) * 100
  return {pairs = pairs_, hits = hits, chance = chance, purity = pure}
end

return punnett
