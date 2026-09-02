-- beeinput.lua  ->  install to /lib/beeinput.lua
-- Touch-button registry and the event pump behind beeui. Screens
-- never require this directly: beeui re-exports it as core.button,
-- core.pump, core.sleep and friends. No drawing happens here; beeui
-- paints a button's label and then hands the hit box over.

local event    = require("event")
local keyboard = require("keyboard")
local computer = require("computer")

local input = {}

local haltFlag = false
local buttons = {}
local keyHandler = nil

-- Fresh screen: forget buttons, key handler, and any pending halt
function input.reset()
  haltFlag = false
  buttons = {}
  keyHandler = nil
end

function input.clearButtons() buttons = {} end

-- b = {id=, x=, y=, w=, onPress=}; x2 is the inclusive right edge
function input.add(b, width)
  b.x2 = b.x + (b.w or width or 1) - 1
  buttons[b.id] = b
end

function input.remove(id) buttons[id] = nil end

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
function input.setKeyHandler(fn) keyHandler = fn end
function input.halt() haltFlag = true end
function input.haltRequested() return haltFlag end

function input.pump(timeout)
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
function input.sleep(seconds)
  local deadline = computer.uptime() + seconds
  while true do
    local remaining = deadline - computer.uptime()
    if remaining <= 0 then return end
    input.pump(remaining)
  end
end

return input
