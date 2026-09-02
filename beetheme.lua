-- beetheme.lua  ->  install to /lib/beetheme.lua
-- Glyphs and colors that depend on the screen tier.
--
-- Glyphs: every non-ASCII character the screens draw is named here
-- with an ASCII stand-in, so a font that lacks one is a config line
-- away from fixed (config.asciiGlyphs = true swaps ALL of them; a
-- table config.asciiOnly = {name=true} swaps just those).
-- `beeprobe glyphs` prints the whole set for an in-game check.
--
-- Palette: a T3 GPU (depth 8) has 240 fixed colors and 16 settable
-- slots. The fixed cube has no greys at all besides black and white,
-- so slots 0-7 hold the greys the UI leans on and slots 8-15 are
-- accents: the gold tile, the glint purple, and the species on the
-- current breeding step, so those render in their exact color.
-- Lower tiers are left alone -- on a T2 the palette IS the 16
-- colors, and rewriting it would recolor everything.

local component = require("component")
local config    = require("beeconfig")

local theme = {}

-- name = {unicode, ascii}
local GLYPHS = {
  -- box drawing
  h = {"─", "-"},  v = {"│", "|"},
  tl = {"┌", "+"}, tr = {"┐", "+"}, bl = {"└", "+"}, br = {"┘", "+"},
  teeD = {"┬", "+"}, teeU = {"┴", "+"}, teeR = {"├", "+"}, teeL = {"┤", "+"},
  cross = {"┼", "+"},
  -- markers
  dot = {"●", "*"},   ring = {"○", "o"},  check = {"✓", "v"},
  block = {"█", "#"}, shade = {"░", "."}, square = {"▣", "#"},
  arrowL = {"◄", "<"}, up = {"↑", "^"}, left = {"←", "<"}, right = {"→", ">"},
  triU = {"▲", "^"}, triD = {"▼", "v"}, halt = {"■", "X"}, pause = {"❚❚", "||"},
  times = {"×", "x"}, mid = {"·", "."}, star = {"★", "*"},
  -- header icons
  route = {"◆", "R"}, chat = {"♪", "C"}, bot = {"⚙", "B"}, pure = {"◉", "P"},
  temp = {"☀", "T"},  humid = {"≈", "H"}, warn = {"⚠", "!"}, bee = {"ж", "b"},
}

function theme.g(name)
  local g = GLYPHS[name]
  if not g then return "?" end
  local only = config.asciiOnly
  if config.asciiGlyphs or (type(only) == "table" and only[name]) then
    return g[2]
  end
  return g[1]
end

-- Sorted {name, unicode, ascii} triples, for the probe
function theme.list()
  local names = {}
  for k in pairs(GLYPHS) do names[#names + 1] = k end
  table.sort(names)
  local out = {}
  for _, k in ipairs(names) do
    out[#out + 1] = {name = k, uni = GLYPHS[k][1], ascii = GLYPHS[k][2]}
  end
  return out
end

--------------------------------------------------------------------
-- Palette
--------------------------------------------------------------------
theme.GOLD  = 0x8A6400   -- tile behind a species that exists
theme.GLINT = 0xC080FF   -- enchantment shimmer

local GREYS = {0x1A1A1A, 0x333333, 0x4D4D4D, 0x666666,
               0x808080, 0x999999, 0xB3B3B3, 0xCCCCCC}
local ACCENT_BASE = 8
local accents = {}       -- current slot 8.. contents, to skip no-op writes
local slotOf = {}        -- species color -> its position in accents

local function gpu()
  if component.isAvailable("gpu") then return component.gpu end
end

function theme.depth()
  local g = gpu()
  local ok, d = pcall(function() return g and g.getDepth() end)
  return (ok and tonumber(d)) or 1
end

function theme.isDeep() return theme.depth() >= 8 end

-- Greys into slots 0-7, gold + glint into 8-9. Call once per screen.
function theme.init()
  local g = gpu()
  if not g or not theme.isDeep() then return false end
  for i, c in ipairs(GREYS) do g.setPaletteColor(i - 1, c) end
  accents, slotOf = {}, {}
  theme.accent({theme.GOLD, theme.GLINT})
  return true
end

-- Put exact colors into the accent slots (8-15), in order. Extra
-- colors beyond the eight slots are simply quantized like any other.
function theme.accent(colors)
  local g = gpu()
  if not g or not theme.isDeep() then return false end
  local n = 0
  for _, c in ipairs(colors) do
    if n >= 16 - ACCENT_BASE then break end
    if accents[n + 1] ~= c then
      g.setPaletteColor(ACCENT_BASE + n, c)
      accents[n + 1] = c
    end
    n = n + 1
  end
  return true
end

-- Exact colors for species: gold and glint stay in 8-9, species take
-- 10-15 in order of first appearance and KEEP their slot for the run.
-- Cells remember a palette index, not a color, so moving a slot would
-- recolor everything already drawn in it; once the six are spoken
-- for, further species simply quantize to the cube like before.
function theme.species(colorsOf, names)
  local g = gpu()
  if not g or not theme.isDeep() then return false end
  for _, name in ipairs(names) do
    local c = name and colorsOf(name)
    if c and not slotOf[c] and #accents < 16 - ACCENT_BASE then
      accents[#accents + 1] = c
      slotOf[c] = #accents
      g.setPaletteColor(ACCENT_BASE + #accents - 1, c)
    end
  end
  return true
end

-- OpenComputers' stock T3 ramp, so the shell looks normal after us.
function theme.restore()
  local g = gpu()
  if not g or not theme.isDeep() then return end
  for i = 0, 15 do g.setPaletteColor(i, 0x0F0F0F * (i + 1)) end
  accents = {}
end

return theme
