-- beewire.lua  ->  install to /lib/beewire.lua
-- Touch screen for the transposer wiring: one row per role, arrows to
-- walk it around the sides, and what is actually on each side shown
-- underneath so the choice is checkable without leaving the chair.
-- DETECT refills it from beedetect; SAVE writes beeconfig. Reached by
-- `beebreeder sides`, and automatically at startup when detection
-- cannot work the build out on its own.

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
  if #order > 0 then return order end
  return {0, 1, 2, 3, 4, 5}
end

local function step(order, from, delta)
  local at = 1
  for i, side in ipairs(order) do
    if side == from then at = i end
  end
  at = (at - 1 + delta) % #order + 1
  return order[at]
end

-- Optional roles get one extra stop on the carousel: unset, first in
-- the ring so it is one step from anywhere.
local function orderFor(role, order)
  if not role.optional then return order end
  local o = {false}
  for _, side in ipairs(order) do o[#o + 1] = side end
  return o
end

-- What "unset" means for each optional role, in its own words
local UNSET = {sortChestSide = "no hybrid sweep"}

local function label(side)
  return sides.isSet(side) and sides.sideName(side) or "unset"
end

local function note(role, side, probe)
  if sides.isSet(side) then return sides.describeSide(probe[side]) end
  return UNSET[role.key] or "uses the processing chest"
end

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

  -- Two rows per role, no blank between: seven roles have to fit
  -- above the verdict lines on an 80x25 screen as well as a 160x50.
  local function rowOf(i) return 3 + (i - 1) * 2 end

  local function draw()
    core.clearButtons()
    core.fillRect(1, 1, W, 1, C.header)
    core.text(2, 1, "BeeBreeder -- transposer wiring", C.headerFg, C.header)

    for i, role in ipairs(sides.ROLES) do
      local row = rowOf(i)
      local side = assign[role.key]
      local ring = orderFor(role, order)
      local function arrow(id, x, mark, delta)
        core.button{id = id .. i, x = x, y = row, label = "[ " .. mark .. " ]",
                    bg = C.barEmpty, onPress = function()
                      assign[role.key] = step(ring, side, delta)
                      conf[role.key] = nil; flash = nil; draw()
                    end}
      end
      core.line(row, role.label)
      arrow("less", 20, "<", -1)
      core.text(27, row, ("%-6s"):format(label(side)),
                sides.isSet(side) and C.header or C.dim2)
      arrow("more", 35, ">", 1)
      if conf[role.key] then
        core.text(42, row, CONF_TEXT[conf[role.key]],
                  CONF_COLOR[conf[role.key]] or C.dim)
      end
      core.line(row + 1, "    " .. note(role, side, probe), C.dim)
    end

    -- One verdict line: the last action if there was one, else the
    -- first problem, else the all-clear. A second problem gets the
    -- row below; the rest are the same story told again.
    local ok, problems = sides.validate(probe, assign)
    core.hline(H - 5)
    core.line(H - 3, "")
    core.line(H - 4, flash or problems[1] or
              "Looks right: every role has its own inventory.",
              (ok or flash) and C.good or C.bad)
    if not flash and problems[2] then core.line(H - 3, problems[2], C.bad) end

    local function btn(id, x, text, bg, fg, fn)
      core.button{id = id, x = x, y = H - 1, label = text,
                  bg = bg or C.barEmpty, fg = fg, onPress = fn}
    end
    btn("save", 2, "[ SAVE ]", ok and C.good or C.barEmpty,
        ok and C.headerFg or C.dim, function() if ok then state = "save" end end)
    btn("use", 12, "[ USE ONCE ]", nil, nil,
        function() if ok then state = "use" end end)
    btn("detect", 26, "[ DETECT ]", nil, nil, function()
      probe = sides.probe() or probe
      order = cycleOrder(probe)
      local a, c = detect.detect(probe)
      if a then assign, conf = a, c end
      flash = "Detected from what the transposer can see."
      draw()
    end)
    btn("cancel", 38, "[ CANCEL ]", nil, nil, function() state = "cancel" end)
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
  core.finish()   -- stock palette back before the shell gets the screen

  if state == "cancel" then return nil end
  sides.apply(assign)
  if state == "use" then return assign, "applied for this run" end
  local saved, whereOrWhy = detect.save(assign)
  if saved then return assign, "saved to " .. tostring(whereOrWhy) end
  return assign, "could not write beeconfig (" .. tostring(whereOrWhy) ..
                 ") -- applied for this run"
end

-- Headless equivalent: print what is on each side and what detection
-- makes of it. `beeprobe sides save` writes the result.
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
    local side = assign[role.key]
    print(("  %-18s %-6s (%s)"):format(role.label, label(side),
          sides.isSet(side) and (CONF_TEXT[conf[role.key]] or "?")
            or note(role, side, probe)))
  end
  local ok, problems = sides.validate(probe, assign)
  for _, p in ipairs(problems) do print("  ! " .. p) end

  if not save then
    print(ok and "Run `beeprobe sides save` to write this to beeconfig."
              or "Fix the build, or set the sides on the `beebreeder sides` screen.")
    return
  elseif not ok then
    print("Refusing to save an assignment that does not check out.")
    return
  end
  local saved, whereOrWhy = detect.save(assign)
  print(saved and ("Saved to " .. tostring(whereOrWhy))
               or ("FAILED: " .. tostring(whereOrWhy)))
end

return wire
