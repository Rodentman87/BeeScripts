-- beesegs.lua  ->  install to /home/lib/beesegs.lua
-- Species-colored text segments for the dashboard and setup screens.
-- A segment is {text=, species=?, color=?}: explicit color wins, else
-- the species' authentic color, else plain text color.
--
-- Glint species get a traveling shimmer: a 2-char purple window
-- sweeps across the word, driven by real time (computer.uptime), so
-- input-heavy screens can call tick() as often as they like without
-- speeding it up. config.shimmerStep = seconds per sweep advance.

local core     = require("beeui")
local colors   = require("beecolors")
local config   = require("beeconfig")
local computer = require("computer")
local C = core.C

local segs = {}

segs.GLINT = 0xC080FF  -- enchantment-purple shimmer color

local SPAN = 2         -- width of the traveling window, in chars
local GAP  = 4         -- rest steps between sweeps of one word

local liveRows = {}    -- row -> {segs=list, width=n}; glint rows re-render
local lastStep = -1

local function curStep()
  return math.floor(computer.uptime() / (config.shimmerStep or 0.25))
end

function segs.reset()
  liveRows = {}
  lastStep = -1
end

-- Split text into runs: base color except a purple window whose
-- position derives from the shared clock. Wraps per-word with a gap.
function segs.sweep(text, base, step)
  text = tostring(text)
  step = step or curStep()
  local n = #text
  local pos = (step % (n + SPAN + GAP)) - SPAN + 1
  local a, b = math.max(1, pos), math.min(n, pos + SPAN - 1)
  if b < a then
    return {{text = text, color = base}}
  end
  local runs = {}
  if a > 1 then runs[#runs + 1] = {text = text:sub(1, a - 1), color = base} end
  runs[#runs + 1] = {text = text:sub(a, b), color = segs.GLINT}
  if b < n then runs[#runs + 1] = {text = text:sub(b + 1), color = base} end
  return runs
end

local function render(entry, step)
  local out = {}
  for _, s in ipairs(entry.segs) do
    if s.species and colors.glint(s.species) then
      for _, r in ipairs(segs.sweep(s.text, colors.of(s.species), step)) do
        out[#out + 1] = r
      end
    else
      local color = s.color or (s.species and colors.of(s.species)) or C.text
      out[#out + 1] = {text = s.text, color = color}
    end
  end
  return out
end

local function drawRow(row, entry, step)
  core.segs(row, render(entry, step), entry.width)
end

-- Draw a segment row and remember it (for shimmer re-rendering)
function segs.set(row, list, width)
  local entry = {segs = list, width = width}
  liveRows[row] = entry
  drawRow(row, entry, curStep())
end

local function entryHasGlint(entry)
  for _, s in ipairs(entry.segs) do
    if s.species and colors.glint(s.species) then return true end
  end
  return false
end

function segs.redrawGlints(step)
  for row, entry in pairs(liveRows) do
    if entryHasGlint(entry) then drawRow(row, entry, step) end
  end
end

-- Heartbeat: call as often as you like (every pump/buzz). Redraws
-- glint rows only when the wall-clock step actually advanced.
function segs.tick()
  local step = curStep()
  if step ~= lastStep then
    lastStep = step
    segs.redrawGlints(step)
  end
end

-- Segment builders ------------------------------------------------

-- "P: Active/Inactive f2" with each allele in its species color
function segs.bee(prefix, bee)
  local list = {{text = prefix},
    {text = tostring(bee.active),   species = bee.active},
    {text = "/"},
    {text = tostring(bee.inactive), species = bee.inactive}}
  if bee.fertility then
    list[#list + 1] = {text = " f" .. bee.fertility, color = C.dim}
  end
  return list
end

-- "A + B -> R (suffix)" with each species in its own color
function segs.cross(prefix, a, b, r, suffix)
  local list = {{text = prefix},
    {text = tostring(a), species = a}, {text = " + "},
    {text = tostring(b), species = b}, {text = " -> "},
    {text = tostring(r), species = r}}
  if suffix then list[#list + 1] = {text = suffix, color = C.dim} end
  return list
end

return segs
