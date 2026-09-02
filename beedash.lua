-- beedash.lua  ->  install to /lib/beedash.lua
-- The dashboard the engine talks to. Nothing is drawn here: once the
-- screen resolution is known (after the first core.begin) this hands
-- every call to the layout that fits -- beecompact for 80x25 and
-- smaller, beewide for 120 columns and up. config.layout = "compact"
-- or "wide" forces one; anything else (or nothing) is automatic.
--
-- A layout may leave a method out (the compact one has no stock
-- pane, no pause button, no queen timing); such calls are no-ops
-- that return nil, so the engine never has to ask which layout it
-- got.

local core   = require("beeui")
local config = require("beeconfig")

local ui = {hasGpu = core.hasGpu}
local impl = nil

local function noop() end

local function pick()
  if impl then return impl end
  core.begin()                      -- resolution is known after this
  local want = config.layout or "auto"
  local wide = (want == "wide") or (want ~= "compact" and core.isWide())
  impl = require(wide and "beewide" or "beecompact")
  return impl
end

setmetatable(ui, {__index = function(t, k)
  local fn = function(...)
    local f = pick()[k]
    if f == nil then return noop() end
    return f(...)
  end
  rawset(t, k, fn)
  return fn
end})

return ui
