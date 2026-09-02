-- beecross.lua  ->  install to /lib/beecross.lua
-- Draws the Punnett square (beepunnett) into the wide dashboard's
-- "This cross" pane: princess alleles down the side, drone alleles
-- across the top, offspring genotype in each cell with any mutation
-- that allele pair can trigger, and a summary line underneath.
--
-- Pane inner rows: 1 column headers, 2 rule, 3-5 first princess
-- allele, 6 rule, 7-9 second allele, 11 summary.

local core    = require("beeui")
local colors  = require("beecolors")
local punnett = require("beepunnett")
local C, g = core.C, core.g

local cross = {}

local P, muts = nil, nil
local LABEL_W, CELL_W = 14, 30    -- label column, then two cells

function cross.init(geo, m)
  P, muts = geo, m
  core.fillRect(P.x + 1, P.y + 1, P.w - 2, P.h - 2)
end

-- Write segments left to right from x, clipped at maxX (species
-- names run to 17 characters; the cells do not). No shimmer here.
local function at(x, y, list, maxX)
  for _, s in ipairs(list) do
    local text = tostring(s.text)
    local room = maxX - x + 1
    if room <= 0 then return end
    if core.len(text) > room then text = core.sub(text, 1, room) end
    core.text(x, y, text, s.color or (s.species and colors.of(s.species)) or C.text, s.bg)
    x = x + core.len(text)
  end
end

local function geno(a, b)
  return {{text = tostring(a), species = a}, {text = "/", color = C.dim},
          {text = tostring(b), species = b}}
end

local function mutLine(m)
  return {{text = "  " .. g("star") .. " " .. g("right") .. " ", color = C.warn},
          {text = m.r, species = m.r},
          {text = (" %.0f%%"):format(m.chance), color = C.warn}}
end

-- Three lines for one cell
local function cellLines(cell)
  local l1 = geno(cell.p, cell.d)
  if cell.pure then l1[#l1 + 1] = {text = "   pure", color = C.dim2} end
  local l2 = cell.muts[1] and mutLine(cell.muts[1])
             or {{text = "  no mutation pair", color = C.dim2}}
  local l3 = cell.muts[2] and mutLine(cell.muts[2])
             or {{text = "  25%", color = C.dim}}
  return {l1, l2, l3}
end

function cross.show(p, d, target)
  if not (P and core.hasGpu) then return end
  local sq = punnett.square(p, d, muts)
  local x0 = P.x + 2
  local D1, D2 = x0 + LABEL_W, x0 + LABEL_W + 1 + CELL_W
  local CA, CB = D1 + 2, D2 + 2
  local endA, endB, endL = D2 - 1, P.x + P.w - 2, D1 - 1   -- clip limits
  local y = P.y + 1
  core.fillRect(P.x + 1, y, P.w - 2, P.h - 2)

  local function rule(row)
    core.text(x0, row, string.rep(g("h"), LABEL_W + 2 * (CELL_W + 1)), C.frame)
    core.text(D1, row, g("cross"), C.frame)
    core.text(D2, row, g("cross"), C.frame)
  end
  local function bars(row)
    core.text(D1, row, g("v"), C.frame)
    core.text(D2, row, g("v"), C.frame)
  end

  bars(y)
  at(CA, y, {{text = "D  ", color = C.dim}, {text = sq.cols[1], species = sq.cols[1]}}, endA)
  at(CB, y, {{text = "D  ", color = C.dim}, {text = sq.cols[2], species = sq.cols[2]}}, endB)
  rule(y + 1)
  for r = 1, 2 do
    local top = y + 2 + (r - 1) * 4
    local la, lb = cellLines(sq.cells[r][1]), cellLines(sq.cells[r][2])
    for i = 1, 3 do
      bars(top + i - 1)
      at(CA, top + i - 1, la[i], endA)
      at(CB, top + i - 1, lb[i], endB)
    end
    at(x0, top, {{text = "P  ", color = C.dim}, {text = sq.rows[r], species = sq.rows[r]}}, endL)
    if r == 1 then rule(top + 3) end
  end

  local o = punnett.odds(sq, target)
  local sum
  if o.hits > 0 then
    sum = {{text = ("%d of 4 allele pairs can mutate %s "):format(o.pairs, g("mid")), color = C.dim},
           {text = target, species = target},
           {text = (" about %.0f%% per offspring"):format(o.chance), color = C.dim}}
  elseif o.purity > 0 then
    sum = {{text = target, species = target},
           {text = ("/%s in %d%% of draws %s no mutation needed"):format(
                    target, o.purity, g("mid")), color = C.dim}}
  else
    sum = {{text = "No path to ", color = C.dim}, {text = target, species = target},
           {text = (" from this pair %s converting the princess line"):format(g("mid")),
            color = C.dim}}
  end
  at(x0, y + 10, sum, endB)
end

return cross
