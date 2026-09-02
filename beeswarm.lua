-- beeswarm.lua  ->  install to /lib/beeswarm.lua
-- The meadow: one two-row sprite per thirty bees in the library, in
-- species color, glint species shimmering as they fly. It is drawn
-- entirely from the last scan and never touches the transposer, so it
-- costs nothing to let it run while the computer idles.
--
-- Sprites are the dashboard's bee, mirrored when it flies left. At
-- least one bee stands for every species that fits, so the meadow
-- reads as the library rather than as decoration.

local core     = require("beeui")
local colors   = require("beecolors")
local segs     = require("beesegs")
local C = core.C

local swarm = {}

local PER_BEE = 30      -- library bees one sprite stands for
local MAX     = 14      -- sprites, however big the library gets
local W_BEE   = 6       -- sprite width in cells

local WINGS = {" \\ /  ", " | |  "}
local BODY  = {right = "={;;}>", left = "<{;;}="}

local P = nil           -- {x, y, w, h} box; the inside is what we use
local bees = {}
local frame = 0
local seed = 7

-- Own generator: math.random is shared state and a meadow has no
-- business perturbing anyone else's rolls.
local function rnd()
  seed = (seed * 9301 + 49297) % 233280
  return seed / 233280
end

function swarm.init(geo)
  P, bees, frame = geo, {}, 0
end

-- Restock the meadow from a tally. One sprite per PER_BEE bees, and
-- one for every species that still fits, so a species with a single
-- princess is still represented.
function swarm.reset(tally, order)
  bees = {}
  if not P then return end
  local x0, y0 = P.x + 1, P.y + 1
  local w, h = P.w - 2 - W_BEE, P.h - 4
  for _, sp in ipairs(order or {}) do
    local e = tally[sp]
    local n = math.max(1, math.floor((e.p + e.d) / PER_BEE + 0.5))
    for _ = 1, n do
      if #bees >= MAX then return end
      bees[#bees + 1] = {sp = sp,
                         x = x0 + rnd() * math.max(1, w),
                         y = y0 + math.floor(rnd() * math.max(1, h)),
                         dir = rnd() < 0.5 and 1 or -1,
                         v = 0.3 + rnd() * 0.45,
                         ph = rnd() * 6.28}
    end
  end
end

-- Ground: two rows of grass with a few flowers standing in it.
local GRASS, GRASS2, FLOWER = 0x1F4D1A, 0x2C6B25, "*"

function swarm.ground()
  if not (P and core.hasGpu) then return end
  local y = P.y + P.h - 3
  core.fillRect(P.x + 1, y, P.w - 2, 2, GRASS)
  for i, b in ipairs(bees) do
    local x = P.x + 4 + (i - 1) * 11
    if x < P.x + P.w - 2 then core.text(x, y, FLOWER, colors.of(b.sp), GRASS) end
  end
end

-- One animation tick: move, wipe the air, redraw. The whole interior
-- above the grass is cleared in a single fillRect, which is cheaper
-- than tracking where each sprite used to be and never leaves trails.
function swarm.tick()
  if not (P and core.hasGpu) then return end
  local left, right = P.x + 1, P.x + P.w - 2 - W_BEE
  local top, bottom = P.y + 1, P.y + P.h - 4
  frame = frame + 1
  core.fillRect(left, top, P.w - 2, bottom - top + 1, C.bg)
  local wings = WINGS[frame % #WINGS + 1]
  for _, b in ipairs(bees) do
    b.x = b.x + b.dir * b.v
    if b.x > right then b.x, b.dir = right, -1 end
    if b.x < left  then b.x, b.dir = left, 1 end
    local bx = math.floor(b.x + 0.5)
    local by = math.floor(b.y + math.sin(b.ph + frame * 0.35) + 0.5)
    if by >= top and by < bottom then
      local col = colors.of(b.sp)
      core.text(bx, by, wings, C.beeWing)
      local body = BODY[b.dir > 0 and "right" or "left"]
      if colors.glint(b.sp) then
        local x = bx
        for _, r in ipairs(segs.sweep(body, col)) do
          core.text(x, by + 1, r.text, r.color)
          x = x + core.len(r.text)
        end
      else
        core.text(bx, by + 1, body, col)
      end
    end
  end
end

function swarm.count() return #bees end

return swarm
