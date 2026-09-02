-- beeroute.lua  ->  install to /lib/beeroute.lua
-- The wide dashboard's route pane: the plan as an indented tree
-- (beetree) with the dot pedigree (beepedigree) tucked into the
-- top-right corner when it fits beside the rows, and a summary line
-- along the bottom. Also loads the current step's species into the
-- exact-color palette slots.

local core   = require("beeui")
local config = require("beeconfig")
local segs   = require("beesegs")
local colors = require("beecolors")
local tree   = require("beetree")
local ped    = require("beepedigree")
local theme  = require("beetheme")
local C = core.C

local route = {}

local P = nil
local pedLay, pedX, pedY = nil, 0, 0
local current = nil          -- species being bred right now

function route.init(geo)
  P, pedLay, current = geo, nil, nil
end

function route.current() return current end

local function rowWidth(row)
  local n = 0
  for _, s in ipairs(row.segs) do n = n + core.len(s.text) end
  return n
end

-- r = {steps=, owned=, done=, cur=, rolls=} from beestep.drawRoute
function route.show(r, target, avgCycle)
  if not (P and core.hasGpu) then return end
  local ix, iy, iw, ih = P.x + 1, P.y + 1, P.w - 2, P.h - 2
  -- Palette first: the step's species get exact slots before anything
  -- this cycle is painted in them.
  if r.cur then
    theme.species(colors.of, {r.cur.a, r.cur.b, r.cur.r, r.cur.bank, target})
  end
  core.fillRect(ix, iy, iw, ih)
  pedLay = nil
  local rows = {}
  local root = r.steps and r.cur and tree.build(r.steps, r.owned or {}, r.cur.r)
  if root then
    current = r.cur.r
    local done = {}
    for _, sp in ipairs(r.done or {}) do done[sp] = true end
    rows = tree.fit(tree.rows(root, {done = done, rolls = r.rolls}), ih - 2)
    local widest = 0
    for _, row in ipairs(rows) do widest = math.max(widest, rowWidth(row)) end
    local lay = ped.layout(root)
    if lay.w + widest + 4 <= iw and lay.h <= ih - 2 then
      pedLay, pedX, pedY = lay, ix + iw - lay.w - 1, iy
      ped.draw(lay, pedX, pedY, false, true)
    end
    segs.set(iy + ih - 1, {{text = tree.summary(r.steps, avgCycle), color = C.dim}}, iw, ix)
  elseif r.cur and r.cur.bank then
    current = r.cur.bank
    rows = {{segs = {{text = "Banking "}, {text = r.cur.bank, species = r.cur.bank},
             {text = (" to %d %sdrones"):format(r.cur.goal,
                      config.requirePure and "pure " or "")}}}}
  else
    current = nil
  end
  for i = 1, ih - 2 do
    local row = rows[i]
    local w = iw
    if pedLay and i <= pedLay.h then w = pedX - ix - 1 end
    segs.set(iy + i - 1, row and row.segs or {}, w, ix)
  end
end

-- Pulse the pedigree's working node (called from the spinner)
function route.tick(flap)
  if pedLay then ped.draw(pedLay, pedX, pedY, flap, false) end
end

return route
