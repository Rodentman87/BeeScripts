-- beeui.lua  ->  install to /lib/beeui.lua
-- Core UI toolkit: palette, drawing primitives, touch-button
-- registry, and the event pump. Screens are built on top of this:
-- beedash (running dashboard) and beesetup (setup screen).
-- Degrades to no-ops (and print-based flows) without a GPU.
--
-- All widths are measured in characters, not bytes: box drawing and
-- markers are multi-byte, and `#s` on them lies. Use core.len/sub.

local component = require("component")
local term      = require("term")
local keyboard  = require("keyboard")
local unicode   = require("unicode")
local theme     = require("beetheme")
local input     = require("beeinput")

local core = { hasGpu = component.isAvailable("gpu") and component.isAvailable("screen") }
local gpu = core.hasGpu and component.gpu or nil

local W, H = 80, 25

core.keys = keyboard.keys
core.len  = unicode.len
core.sub  = unicode.sub
core.g    = theme.g      -- named glyphs with ASCII fallbacks

core.C = {
  bg       = 0x000000,
  text     = 0xFFFFFF,
  dim      = 0x999999,
  dim2     = 0x666666,
  header   = 0xFFDB00,   -- bee yellow
  headerFg = 0x000000,
  good     = 0x00CC00,
  warn     = 0xFFDB00,
  bad      = 0xFF3333,
  barEmpty = 0x333333,
  frame    = 0x666666,   -- panel borders
  gold     = theme.GOLD,
  beeWing  = 0xCCCCCC,
  beeBody  = 0xFFDB00,
}
local C = core.C

function core.size() return W, H end
-- Wide layouts need two 79-column panes side by side
function core.isWide() return W >= 120 end

-- Fresh screen: clears halt state, buttons, key handler, display
function core.begin()
  input.reset()
  if not core.hasGpu then return end
  gpu.setResolution(gpu.maxResolution())
  W, H = gpu.getResolution()
  theme.init()
  gpu.setBackground(C.bg)
  gpu.setForeground(C.text)
  term.clear()
end

function core.clip(text, max)
  text = tostring(text)
  max = max or (W - 2)
  if core.len(text) > max then text = core.sub(text, 1, max - 3) .. "..." end
  return text
end

function core.text(x, y, str, fg, bg)
  if not core.hasGpu then return end
  if bg then gpu.setBackground(bg) end
  gpu.setForeground(fg or C.text)
  gpu.set(x, y, str)
  gpu.setBackground(C.bg)
  gpu.setForeground(C.text)
end

function core.fillRect(x, y, w, h, bg)
  if not core.hasGpu then return end
  gpu.setBackground(bg or C.bg)
  gpu.fill(x, y, w, h, " ")
  gpu.setBackground(C.bg)
end

-- Row helper: clear `width` cols from x0 (default 1), write at x0+1
function core.line(row, str, fg, width, x0)
  if not core.hasGpu then return end
  x0 = x0 or 1
  width = width or (W - x0 + 1)
  gpu.fill(x0, row, width, 1, " ")
  gpu.setForeground(fg or C.text)
  gpu.set(x0 + 1, row, core.clip(str, width - 2))
  gpu.setForeground(C.text)
end

-- Draw colored text segments on one row: segs = {{text=, color=, bg=}, ...}
-- Clears `width` cols from x0, then writes segments left to right,
-- truncating at the right edge.
function core.segs(row, segs, width, x0)
  if not core.hasGpu then return end
  x0 = x0 or 1
  width = width or (W - x0 + 1)
  local right = x0 + width - 1
  gpu.fill(x0, row, width, 1, " ")
  local x = x0 + 1
  for _, s in ipairs(segs) do
    local text = tostring(s.text)
    local n = core.len(text)
    if x + n - 1 > right then
      n = math.max(0, right - x + 1)
      text = core.sub(text, 1, n)
    end
    if n == 0 then break end
    if s.bg then gpu.setBackground(s.bg) end
    gpu.setForeground(s.color or C.text)
    gpu.set(x, row, text)
    if s.bg then gpu.setBackground(C.bg) end
    x = x + n
  end
  gpu.setForeground(C.text)
end

function core.hline(row, label)
  if not core.hasGpu then return end
  gpu.setForeground(C.dim)
  local mid = label and (" " .. label .. " ") or ""
  local side = W - core.len(mid)
  gpu.set(1, row, string.rep("-", math.floor(side / 2)) .. mid ..
                  string.rep("-", math.ceil(side / 2)))
  gpu.setForeground(C.text)
end

-- Titled box in box-drawing glyphs; the inside is x+1..x+w-2,
-- y+1..y+h-2. Title sits in the top edge in header yellow.
function core.panel(x, y, w, h, title)
  if not core.hasGpu then return end
  local g = core.g
  gpu.setForeground(C.frame)
  gpu.set(x, y, g("tl") .. string.rep(g("h"), w - 2) .. g("tr"))
  gpu.set(x, y + h - 1, g("bl") .. string.rep(g("h"), w - 2) .. g("br"))
  for row = y + 1, y + h - 2 do
    gpu.set(x, row, g("v"))
    gpu.set(x + w - 1, row, g("v"))
  end
  if title then
    title = core.clip(title, w - 6)
    gpu.set(x + 2, y, g("teeL") .. " ")
    gpu.set(x + 4 + core.len(title), y, " " .. g("teeR"))
    gpu.setForeground(C.header)
    gpu.set(x + 4, y, title)
  end
  gpu.setForeground(C.text)
end

--------------------------------------------------------------------
-- Touch buttons: register with an onPress callback; the pump
-- (beeinput) dispatches touches. Use w= for a custom hit width and
-- invisible=true for touch regions that don't draw anything.
--------------------------------------------------------------------
function core.button(b)
  if not core.hasGpu then return end
  if not b.invisible then
    core.text(b.x, b.y, b.label, b.fg or C.text, b.bg or C.barEmpty)
  end
  input.add(b, core.len(b.label or " "))
end

core.clearButtons  = input.clearButtons
core.setKeyHandler = input.setKeyHandler
core.halt          = input.halt
core.haltRequested = input.haltRequested
core.pump          = input.pump
core.sleep         = input.sleep

function core.cursorBottom()
  if core.hasGpu then term.setCursor(1, H) end
end

-- Leaving a screen for the shell: stock palette back, cursor down
function core.finish()
  theme.restore()
  core.cursorBottom()
end

return core
