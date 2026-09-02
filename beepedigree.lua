-- beepedigree.lua  ->  install to /lib/beepedigree.lua
-- The route as a tiny pedigree: one dot per species in its species
-- color, ancestors above, the target on the bottom row. State lives
-- in the cell behind the dot: nothing for not-yet, a gold tile for a
-- species that exists, and the working step inverted (black dot on a
-- species-color tile) pulsing against plain on every spinner tick.
--
-- Works on the node tree from beetree.build. Tidy layout: one column
-- per leaf, one blank column between siblings, a parent centered
-- under its children, two rows per level.

local core   = require("beeui")
local colors = require("beecolors")
local C, g = core.C, core.g

local ped = {}

-- Annotates nodes with x (1-based column), d (depth) and w (subtree
-- width). Returns {w=, h=, nodes={{x,y,node}}, joins={{y,x1,x2,xm}}}
-- with the target on row h.
function ped.layout(root)
  local depth = 0
  local function place(n, x0, d)
    n.d = d
    if d > depth then depth = d end
    if #n.kids == 0 then
      n.x, n.w = x0, 1
      return
    end
    local cx = x0
    for _, k in ipairs(n.kids) do
      place(k, cx, d + 1)
      cx = cx + k.w + 1
    end
    n.w = cx - 1 - x0
    n.x = math.floor((n.kids[1].x + n.kids[#n.kids].x) / 2)
  end
  place(root, 1, 0)

  local out = {w = root.w, h = depth * 2 + 1, nodes = {}, joins = {}}
  local function walk(n)
    local y = (depth - n.d) * 2 + 1
    out.nodes[#out.nodes + 1] = {x = n.x, y = y, node = n}
    if #n.kids > 0 then
      out.joins[#out.joins + 1] = {y = y - 1, x1 = n.kids[1].x,
                                   x2 = n.kids[#n.kids].x, xm = n.x}
      for _, k in ipairs(n.kids) do walk(k) end
    end
  end
  walk(root)
  return out
end

-- Paint a layout with its top-left cell at (ox, oy). `flap` picks
-- the pulse phase of the working node; the caller alternates it.
-- Connectors only need drawing once, so pass full=true the first
-- time and false on pulse ticks to touch just the dots.
function ped.draw(lay, ox, oy, flap, full)
  if not core.hasGpu then return end
  if full ~= false then
    for _, j in ipairs(lay.joins) do
      local y = oy + j.y - 1
      core.text(ox + j.x1 - 1, y,
                g("bl") .. string.rep(g("h"), j.x2 - j.x1 - 1) .. g("br"), C.frame)
      core.text(ox + j.xm - 1, y, g("teeD"), C.frame)
    end
  end
  local dot = g("dot")
  for _, p in ipairs(lay.nodes) do
    local n, col = p.node, colors.of(p.node.sp)
    local x, y = ox + p.x - 1, oy + p.y - 1
    if n.state == "have" then
      core.text(x, y, dot, col, C.gold)
    elseif n.state == "now" then
      if flap then core.text(x, y, dot, C.headerFg, col)
      else core.text(x, y, dot, col, C.bg) end
    else
      core.text(x, y, dot, col, C.bg)
    end
  end
end

return ped
