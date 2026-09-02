-- beecfgui.lua  ->  install to /lib/beecfgui.lua
-- The settings screen: beeconfig edited in place. Two columns of
-- typed controls (beeedit owns those and the working copy behind
-- them), changed values in gold until they are saved, and under
-- Writes the exact lines SAVE will patch into the file.
--
-- Sides are shown, not edited: WIRING opens beewire, which checks
-- what it is told against what the transposer can actually see.

local core   = require("beeui")
local config = require("beeconfig")
local frame  = require("beeframe")
local fields = require("beefields")
local ed     = require("beeedit")
local conf   = require("beeconf")
local stock  = require("beestock")
local segs   = require("beesegs")
local sides  = require("beesides")
local C, g = core.C, core.g

local cfgui = {}

local ROLE_ICON = {chestSide = "cabinet", princessSide = "princess",
                   droneSide = "drone", dumpSide = "bin",
                   apiarySide = "apiary", scannerSide = "flask",
                   sortChestSide = "wire"}

-- One letter per side, then the icon of whatever lives there. A side
-- with no role at all is simply absent.
local function sidesRow(x, y)
  local list = {}
  for side = 0, 5 do
    local role
    for _, r in ipairs(sides.ROLES) do
      if config[r.key] == side and not role then role = r.key end
    end
    if role then
      list[#list + 1] = {text = ("%s %s    "):format(
        sides.sideName(side):sub(1, 1):upper(), g(ROLE_ICON[role] or "same"))}
    end
  end
  if #list == 0 then list = {{text = "no sides configured", color = C.dim2}} end
  segs.set(y, list, 40, x - 1)
end

-- Which species the EDITED floors would leave short, and what putting
-- them right would cost. Nothing to say without a scan.
local function previewRow(x, y, tally, order)
  if not tally then
    segs.set(y, {{text = "no scan yet", color = C.dim2}}, 76, x - 1)
    return
  end
  local list, total = {}, 0
  ed.withFloors(function()
    local pf, df = stock.floors()
    for _, sp in ipairs(order) do
      local e = tally[sp]
      if stock.state(e) == "low" then
        for _, l in ipairs(stock.restockPlan(tally, sp)) do total = total + l.cycles end
        if #list < 12 then
          if #list > 0 then
            list[#list + 1] = {text = " " .. g("mid") .. " ", color = C.dim}
          end
          local short = (e.p < pf) and (pf - e.p) or (df - e.d)
          local icon  = (e.p < pf) and g("princess") or g("drone")
          list[#list + 1] = {text = sp, species = sp}
          list[#list + 1] = {text = (" %d%s"):format(short, icon), color = C.dim}
        end
      end
    end
  end)
  if #list == 0 then
    list = {{text = "everything is at or above its floor", color = C.good}}
  else
    table.insert(list, 1, {text = g("triD") .. " ", color = C.bad})
    list[#list + 1] = {text = ("  ~%d cyc"):format(total), color = C.dim}
  end
  segs.set(y, list, 76, x - 1)
end

--------------------------------------------------------------------
-- tally/order come from stock.tally (nil is fine -- Preview simply
-- says there has been no scan); status is the header strip's extras,
-- passed straight through to beeframe. Returns "back".
--------------------------------------------------------------------
function cfgui.run(tally, order, status)
  if not core.hasGpu then
    print("The settings screen needs a GPU/screen; edit beeconfig by hand.")
    return
  end
  core.begin()
  local W, H = core.size()
  local right = math.min(78, W - 2)
  local state, flash = nil, nil
  ed.load()

  local draw
  draw = function()
    core.clearButtons()
    frame.header(g("bot"), frame.statusItems(status))
    core.text(2, 2, tostring(conf.path() or "beeconfig.lua"), C.dim2)
    frame.divider(frame.DIV, 3, H - 3)
    ed.column(3, 4, fields.LEFT, right, draw)
    local y = ed.column(83, 4, fields.RIGHT, W - 2, draw) + 1

    frame.group(82, y, "Sides", W - 2)
    sidesRow(83, y + 1)
    core.button{id = "wiring", x = 123, y = y + 1,
                label = "[ " .. g("wire") .. " WIRING ]", bg = C.barEmpty,
                onPress = function() state = "wiring" end}
    y = y + 3
    frame.group(82, y, "Preview", W - 2)
    previewRow(83, y + 1, tally, order or {})
    y = y + 3
    frame.group(82, y, "Writes", W - 2)

    -- Exactly what SAVE would patch in, line for line
    local keys, changes = ed.keys(), ed.changes()
    local lines = conf.lines(changes, keys)
    for i = 1, 8 do
      core.line(y + i, lines[i] or "", C.header, 76, 82)
    end
    core.line(H - 2, flash or (#keys == 0 and "no changes"
              or ("%d unsaved"):format(#keys)),
              flash and C.good or (#keys > 0 and C.warn or C.dim2))

    frame.bar(H, {
      {id = "save", label = "[ " .. g("check") .. " SAVE ]",
       bg = #keys > 0 and C.good or C.barEmpty,
       fg = #keys > 0 and C.headerFg or C.dim,
       onPress = function()
         if #keys == 0 then return end
         local ok, why = conf.write(changes, "set on the settings screen")
         flash = ok and ("saved to " .. tostring(why))
                     or ("NOT saved: " .. tostring(why))
         if ok then ed.load() end
         draw()
       end},
      {id = "revert", label = "[ " .. g("revert") .. " REVERT ]",
       onPress = function() ed.load() flash = nil draw() end},
      {id = "back", label = "[ " .. g("left") .. " BACK ]",
       onPress = function() state = "back" end},
    })
    frame.hint("home")
  end

  local function quitOnQ()
    core.setKeyHandler(function(_, code)
      if code == core.keys.q then state = "back" end
    end)
  end

  quitOnQ()
  segs.reset()
  draw()
  while state ~= "back" do
    core.pump(config.animDelay or 0.5)
    segs.tick()
    -- The wiring screen takes the whole display and hands it back;
    -- unsaved edits survive it, because they live in beeedit.
    if state == "wiring" then
      state = nil
      core.setKeyHandler(nil)
      require("beewire").run()
      core.begin()
      quitOnQ()
      segs.reset()
      draw()
    end
  end
  core.setKeyHandler(nil)
  return "back"
end

return cfgui
