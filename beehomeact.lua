-- beehomeact.lua  ->  install to /lib/beehomeact.lua
-- What the home screen DOES: hold the last scan, paint it, and run
-- the thing a button asked for. beehomeui owns where it all sits;
-- beehome is just the program around this. Buttons never act
-- directly: they name what they want, this remembers it, and the main
-- loop picks it up between ticks -- so a breeding run never starts
-- from inside a touch callback with a half-painted screen behind it.

local core   = require("beeui")
local config = require("beeconfig")
local data   = require("beedata")
local yard   = require("beeyard")
local run    = require("beerun")
local pop    = require("beepop")
local ui     = require("beehomeui")
local info   = require("beestatus")
local stock  = require("beestock")
local chat   = require("beechat")
local computer = require("computer")
local C, g = core.C, core.g

local act = {}

local muts, sidesOk, lastRun = nil, true, nil
local princesses, drones, fill = {}, {}, {}
local rows, totals, attention, tally, order
local extra, lastScan, want = {}, 0, nil

function act.setMuts(m) muts = m end
function act.setSides(ok) sidesOk = ok end
function act.totals() return totals or {species = 0, p = 0, d = 0, low = 0} end
function act.busy() return extra.busy == true end
function act.lowSpecies() return tally and stock.low(tally, order) or {} end
function act.tally() return tally end
function act.due() return computer.uptime() - lastScan end

-- What a button asked for, once. Reading it clears it.
function act.taken()
  local a = want
  want = nil
  return a
end

--------------------------------------------------------------------
-- Reading the world
--------------------------------------------------------------------
local function rebuild()
  local left = (config.homeRescan or 300) - (computer.uptime() - lastScan)
  extra = info.extra(fill, sidesOk, math.max(0, math.floor(left)) .. "s")
  rows, totals, attention, tally, order = pop.build(princesses, drones, extra)
end

function act.scan()
  local ok, p, d, un, f = pcall(yard.scan, false)
  if ok then
    princesses, drones, fill = p, d, f
    if #un > 0 then
      ui.log(("%d unanalyzed bees -- any run puts them through the scanner")
             :format(#un), "warn")
    end
  else
    princesses, drones, fill = {}, {}, {}
    ui.log("Scan failed: " .. tostring(p), "bad")
  end
  lastScan = computer.uptime()
  rebuild()
end

function act.redraw()
  rebuild()
  ui.header(extra)
  ui.totals(pop.totalsSegs(totals, extra))
  ui.population(rows, totals, function(sp) want = "restock " .. sp end)
  ui.attention(attention, function(a) want = a end)
  info.paint(ui.geo().hive, info.hiveLines(extra, lastRun))
  info.paint(ui.geo().wiring, info.wiringLines(fill, extra.cache))
  ui.meadow(tally, order)
  ui.drawLog()
  ui.controlBar(function(a) want = a end)
end

-- Every sub-screen takes the whole display, so coming back means a
-- fresh frame, a fresh scan and a full repaint.
local function afterScreen()
  ui.init(extra)
  act.scan()
  act.redraw()
end

function act.start()
  ui.init({})
  act.scan()
  ui.log(muts and "Mutation cache loaded."
         or "No mutation cache -- run `beeprobe build`.",
         muts and "good" or "warn")
  act.redraw()
end

--------------------------------------------------------------------
-- Running things
--------------------------------------------------------------------
-- run.start writes the goal through to config on purpose; home has no
-- business inheriting a restock's floor as its drone goal afterwards.
local function runOne(target, opts)
  local saved = config.droneGoal
  run.start(target, muts, opts)
  local halted = core.haltRequested()
  config.droneGoal = saved
  lastRun = {species = target, ok = not halted,
             note = halted and "halted" or "finished"}
  afterScreen()
  ui.log({{text = (halted and g("fail") or g("check")) .. " ",
           color = halted and C.bad or C.good},
          {text = target, species = target},
          {text = halted and " halted" or " done", color = C.dim}})
  return not halted
end

-- Walk every species under its floor. Returns false the moment one of
-- them does not come back up -- the caller (auto-tend especially) must
-- not go round again on a species the engine has already given up on.
function act.restockLow(why)
  local low = act.lowSpecies()
  if #low == 0 then
    ui.log("Nothing is under its floor.", "good")
    return true
  end
  if why then
    chat.say(("BeeBreeder: %s -- restocking %d species"):format(why, #low))
    ui.log(("%s: restocking %d species"):format(why, #low), "warn")
  end
  for _, sp in ipairs(low) do
    if not runOne(sp, {restock = true}) then return false end
    local e = tally[sp]
    if e and stock.state(e) == "low" then
      ui.log("Could not restock " .. sp .. " -- stopping here.", "bad")
      return false
    end
  end
  return true
end

local function breed()
  local ok, screen = pcall(require, "beebreedui")
  local job
  if ok and core.isWide() then
    job = screen.run(tally, order, muts, extra)
  else
    job = require("beesetup").run()
  end
  if not job then return afterScreen() end
  if job.requirePure ~= nil then config.requirePure = job.requirePure end
  if job.chatEveryQueen ~= nil then config.chatEveryQueen = job.chatEveryQueen end
  runOne(job.target, {goal = job.droneGoal})
end

-- The registry call behind this wants most of the machine's RAM, so it
-- can fail here where it would succeed from a cold shell. Say so.
local function rebuildCache()
  ui.log("Rebuilding the mutation cache -- this takes a while.", "warn")
  local ok, n, err = pcall(data.build)
  if ok and n then
    pcall(function() require("beespecies").build() end)
    muts = (data.load())
    ui.log(("Cached %d mutations."):format(n), "good")
  else
    ui.log("Cache build failed: " .. tostring(ok and err or n), "bad")
    ui.log("Reboot and run `beeprobe build` from the shell for more RAM.", "warn")
  end
  act.redraw()
end

local ACTIONS = {
  breed = breed,
  restock = function() act.restockLow() end,
  rebuild = rebuildCache,
  settings = function()
    require("beecfgui").run(tally, order, extra)
    afterScreen()
  end,
  wiring = function()
    require("beewire").run()
    sidesOk = true
    afterScreen()
  end,
  rescan = function() act.scan() act.redraw() end,
  update = function()
    require("shell").execute("beeupdate")
    afterScreen()
  end,
}

function act.run(a)
  local sp = a:match("^restock (.+)$")
  if sp then return runOne(sp, {restock = true}) end
  local fn = ACTIONS[a]
  if fn then fn() end
end

return act
