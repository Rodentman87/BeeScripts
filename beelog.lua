-- beelog.lua  ->  install to /lib/beelog.lua
-- The wide dashboard's log pane: a scrollback buffer with paging.
-- Geometry is a {x, y, w, h} box; content sits one cell inside, the
-- last inner row is the footer.

local core = require("beeui")
local C, g = core.C, core.g

local log = {}

local P = nil
local lines, off = {}, 0    -- off = how many lines scrolled back
local KEEP = 200

local function visible() return P.h - 3 end

function log.draw()
  if not (P and core.hasGpu) then return end
  local x0, w, top, n = P.x + 1, P.w - 2, P.y + 1, visible()
  local last = #lines - off
  for i = 1, n do
    local l = lines[last - n + i]
    core.line(top + i - 1, l and l.text or "", l and l.color, w, x0)
  end
  core.line(top + n, ("%s%s scroll %s %d lines kept"):format(
            g("triU"), g("triD"), g("mid"), #lines), C.dim2, w, x0)
end

function log.init(geo)
  P, lines, off = geo, {}, 0
  log.draw()
end

function log.add(text, color)
  lines[#lines + 1] = {text = text, color = color}
  while #lines > KEEP do table.remove(lines, 1) end
  log.draw()
end

-- dir = 1 pages back toward older lines, -1 toward the newest
function log.scroll(dir)
  local n = visible()
  off = math.max(0, math.min(#lines - n, off + dir * n))
  log.draw()
end

return log
