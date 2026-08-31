-- beeui.lua  ->  install to /home/lib/beeui.lua
-- Core UI toolkit: palette, drawing primitives, touch-button
-- registry, and the event pump. Screens are built on top of this:
-- beedash (running dashboard) and beesetup (setup screen).
-- Degrades to no-ops (and print-based flows) without a GPU.

local component = require("component")
local term      = require("term")
local event     = require("event")
local keyboard  = require("keyboard")
local computer  = require("computer")

local core = { hasGpu = component.isAvailable("gpu") and component.isAvailable("screen") }
local gpu = core.hasGpu and component.gpu or nil

local W, H = 80, 25
local haltFlag = false
local buttons = {}
local keyHandler = nil

core.keys = keyboard.keys

core.C = {
  bg       = 0x000000,
  text     = 0xFFFFFF,
  dim      = 0x999999,
  header   = 0xFFDB00,   -- bee yellow
  headerFg = 0x000000,
  good     = 0x00CC00,
  warn     = 0xFFDB00,
  bad      = 0xFF3333,
  barEmpty = 0x333333,
  beeWing  = 0xCCCCCC,
  beeBody  = 0xFFDB00,
}
local C = core.C

function core.size() return W, H end

-- Fresh screen: clears halt state, buttons, key handler, display
function core.begin()
  haltFlag = false
  buttons = {}
  keyHandler = nil
  if not core.hasGpu then return end
  gpu.setResolution(gpu.maxResolution())
  W, H = gpu.getResolution()
  gpu.setBackground(C.bg)
  gpu.setForeground(C.text)
  term.clear()
end

function core.clip(text, max)
  text = tostring(text)
  max = max or (W - 2)
  if #text > max then text = text:sub(1, max - 3) .. "..." end
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

-- Row helper: clear the first `width` cols of a row, write at col 2
function core.line(row, str, fg, width)
  if not core.hasGpu then return end
  width = width or W
  gpu.fill(1, row, width, 1, " ")
  gpu.setForeground(fg or C.text)
  gpu.set(2, row, core.clip(str, width - 2))
  gpu.setForeground(C.text)
end

-- Draw colored text segments on one row: segs = {{text=, color=}, ...}
-- Clears the first `width` cols, then writes segments left to right,
-- truncating at the width.
function core.segs(row, segs, width)
  if not core.hasGpu then return end
  width = width or W
  gpu.fill(1, row, width, 1, " ")
  local x = 2
  for _, s in ipairs(segs) do
    local text = tostring(s.text)
    if x + #text > width then
      text = text:sub(1, math.max(0, width - x))
    end
    if #text == 0 then break end
    gpu.setForeground(s.color or C.text)
    gpu.set(x, row, text)
    x = x + #text
  end
  gpu.setForeground(C.text)
end

function core.hline(row, label)
  if not core.hasGpu then return end
  gpu.setForeground(C.dim)
  local mid = label and (" " .. label .. " ") or ""
  local side = W - #mid
  gpu.set(1, row, string.rep("-", math.floor(side / 2)) .. mid ..
                  string.rep("-", math.ceil(side / 2)))
  gpu.setForeground(C.text)
end

--------------------------------------------------------------------
-- Touch buttons: register with an onPress callback; the pump
-- dispatches touches. Use w= for a custom hit width and
-- invisible=true for touch regions that don't draw anything.
--------------------------------------------------------------------
function core.clearButtons() buttons = {} end

function core.button(b)
  if not core.hasGpu then return end
  if not b.invisible then
    core.text(b.x, b.y, b.label, b.fg or C.text, b.bg or C.barEmpty)
  end
  b.x2 = b.x + (b.w or #(b.label or " ")) - 1
  buttons[b.id] = b
end

local function dispatchTouch(x, y)
  for _, b in pairs(buttons) do
    if y == b.y and x >= b.x and x <= b.x2 and b.onPress then
      b.onPress(b)
    end
  end
end

--------------------------------------------------------------------
-- Event pump. Touches go to buttons. Keys go to the key handler if
-- one is set (interactive screens); otherwise Q flags a halt.
--------------------------------------------------------------------
function core.setKeyHandler(fn) keyHandler = fn end
function core.halt() haltFlag = true end
function core.haltRequested() return haltFlag end

function core.pump(timeout)
  local ev, _, a, b = event.pull(timeout)
  if ev == "key_down" then
    if keyHandler then
      keyHandler(a, b)          -- char, code
    elseif b == keyboard.keys.q then
      haltFlag = true
    end
  elseif ev == "touch" then
    dispatchTouch(a, b)
  end
  return ev
end

-- os.sleep replacement that keeps pumping events while waiting
function core.sleep(seconds)
  local deadline = computer.uptime() + seconds
  while true do
    local remaining = deadline - computer.uptime()
    if remaining <= 0 then return end
    core.pump(remaining)
  end
end

function core.cursorBottom()
  if core.hasGpu then term.setCursor(1, H) end
end

return core
