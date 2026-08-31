-- beewire.lua  ->  install to /lib/beewire.lua
-- Touch screen for the transposer wiring: one row per role, arrows
-- to walk it around the sides, and what is actually on each side
-- shown underneath so the choice is checkable without leaving the
-- chair. DETECT refills it from beedetect; SAVE writes beeconfig.
--
-- Reached by `beebreeder sides`, and automatically at startup when
-- detection cannot work the build out on its own.

local core   = require("beeui")
local config = require("beeconfig")
local sides  = require("beesides")
local detect = require("beedetect")
local C = core.C

local wire = {}

local CONF_COLOR = {sure = C.good, likely = C.warn, guess = C.bad}
local CONF_TEXT  = {sure = "detected", likely = "probably", guess = "GUESS"}

-- Sides worth stepping through: the ones with an inventory. If the
-- transposer sees nothing at all, offer all six rather than nothing.
local function cycleOrder(probe)
  local order = {}
  for side = 0, 5 do
    if probe[side] and probe[side].size then order[#order + 1] = side end
  end
  if #order == 0 then
    for side = 0, 5 do order[#order + 1] = side end
  end
  return order
end

local function step(order, from, delta)
  local at = 1
  for i, side in ipairs(order) do
    if side == from then at = i end
  end
  at = (at - 1 + delta) % #order + 1
  return order[at]
end

--------------------------------------------------------------------
function wire.run()
  if not core.hasGpu then return nil end
  local probe, err = sides.probe()
  if not probe then
    print("Transposer wiring: " .. tostring(err))
    return nil
  end

  core.begin()
  local W, H = core.size()
  local order = cycleOrder(probe)
  local assign = sides.current()
  local conf, state = {}, nil
  local flash = nil                     -- one-line result of the last action

  local function rowOf(i) return 4 + (i - 1) * 3 end

  local function draw()
    core.clearButtons()
    core.fillRect(1, 1, W, 1, C.header)
    core.text(2, 1, "BeeBreeder -- transposer wiring", C.headerFg, C.header)

    for i, role in ipairs(sides.ROLES) do
      local row = rowOf(i)
      local side = assign[role.key]
      core.line(row, role.label)
      core.button{id = "less" .. i, x = 20, y = row, label = "[ < ]",
                  bg = C.barEmpty, onPress = function()
                    assign[role.key] = step(order, side, -1)
                    conf[role.key] = nil; flash = nil; draw()
                  end}
      core.text(27, row, ("%-6s"):format(sides.sideName(side)), C.header)
      core.button{id = "more" .. i, x = 35, y = row, label = "[ > ]",
                  bg = C.barEmpty, onPress = function()
                    assign[role.key] = step(order, side, 1)
                    conf[role.key] = nil; flash = nil; draw()
                  end}
      if conf[role.key] then
        core.text(42, row, CONF_TEXT[conf[role.key]],
                  CONF_COLOR[conf[role.key]] or C.dim)
      end
      core.line(row + 1, "    " .. sides.describeSide(probe[side]), C.dim)
    end

    local ok, problems = sides.validate(probe, assign)
    core.hline(H - 5)
    core.line(H - 4, "")
    core.line(H - 3, "")
    if flash then
      core.line(H - 4, flash, C.good)
    elseif ok then
      core.line(H - 4, "Looks right: every role has its own inventory.", C.good)
    else
      core.line(H - 4, problems[1], C.bad)
      if problems[2] then core.line(H - 3, problems[2], C.bad) end
    end

    core.button{id = "save", x = 2, y = H - 1, label = "[ SAVE ]",
                bg = ok and C.good or C.barEmpty,
                fg = ok and C.headerFg or C.dim,
                onPress = function() if ok then state = "save" end end}
    core.button{id = "use", x = 12, y = H - 1, label = "[ USE ONCE ]",
                bg = C.barEmpty,
                onPress = function() if ok then state = "use" end end}
    core.button{id = "detect", x = 26, y = H - 1, label = "[ DETECT ]",
                bg = C.barEmpty, onPress = function()
                  probe = sides.probe() or probe
                  order = cycleOrder(probe)
                  local a, c = detect.detect(probe)
                  if a then assign, conf = a, c end
                  flash = "Detected from what the transposer can see."
                  draw()
                end}
    core.button{id = "cancel", x = 38, y = H - 1, label = "[ CANCEL ]",
                bg = C.barEmpty, onPress = function() state = "cancel" end}
    core.line(H - 2, "SAVE writes beeconfig; USE ONCE lasts for this run only.",
              C.dim)
  end

  -- core.begin above cleared any handler; ours goes on after it
  core.setKeyHandler(function(_, code)
    if code == core.keys.q then state = "cancel" end
  end)
  draw()
  while not state do
    core.pump(config.animDelay or 0.5)
  end
  core.setKeyHandler(nil)

  if state == "cancel" then return nil end
  if state == "use" then
    sides.apply(assign)
    return assign, "applied for this run"
  end
  local saved, whereOrWhy = detect.save(assign)
  if not saved then
    sides.apply(assign)
    return assign, "could not write beeconfig (" .. tostring(whereOrWhy) ..
                   ") -- applied for this run"
  end
  return assign, "saved to " .. tostring(whereOrWhy)
end

--------------------------------------------------------------------
-- Headless equivalent: print what is on each side and what detection
-- makes of it. `beeprobe sides save` writes the result.
--------------------------------------------------------------------
function wire.report(save)
  local probe, err = sides.probe()
  if not probe then
    print("FAILED: " .. tostring(err))
    return
  end
  print("Transposer sides:")
  for side = 0, 5 do
    print(("  %-6s %s"):format(sides.sideName(side), sides.describeSide(probe[side])))
  end

  local assign, conf = detect.detect(probe)
  if not assign then
    print("Nothing to assign: " .. tostring(conf))
    return
  end
  print("Detected:")
  for _, role in ipairs(sides.ROLES) do
    print(("  %-18s %-6s (%s)"):format(role.label,
          sides.sideName(assign[role.key]),
          CONF_TEXT[conf[role.key]] or "?"))
  end
  local ok, problems = sides.validate(probe, assign)
  for _, p in ipairs(problems) do print("  ! " .. p) end

  if not save then
    print(ok and "Run `beeprobe sides save` to write this to beeconfig."
              or "Fix the build, or set the sides on the `beebreeder sides` screen.")
    return
  end
  if not ok then
    print("Refusing to save an assignment that does not check out.")
    return
  end
  local saved, whereOrWhy = detect.save(assign)
  print(saved and ("Saved to " .. tostring(whereOrWhy))
               or ("FAILED: " .. tostring(whereOrWhy)))
end

return wire
