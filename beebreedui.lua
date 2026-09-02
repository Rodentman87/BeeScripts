-- beebreedui.lua  ->  install to /lib/beebreedui.lua
-- The wide breed screen: one screen where there used to be two. What
-- is one cross away from the cabinets is a list of buttons, what is
-- two is a row of chips, everything else is a search box, and the
-- right half is the plan for whatever is selected.
--
-- beesetup is still the 80x25 version and is what beehome falls back
-- to. Returns a job {target, requirePure, droneGoal, chatEveryQueen}
-- or nil when the user backs out.
--
-- The same screen serves EXPORT: pass exportPair and the only
-- difference here is what the header and the start button say -- the
-- picker, the plan and the preview are the ones you already know.
-- beeexport does the rest once the job comes back with export set.

local core   = require("beeui")
local config = require("beeconfig")
local frame  = require("beeframe")
local segs   = require("beesegs")
local pick   = require("beepick")
local cands  = require("beecands")
local brief  = require("beebrief")
local C, g = core.C, core.g

local breedui = {}

local G = {}

local function geometry()
  local W, H = core.size()
  local LW = math.min(frame.DIV - 1, math.floor(W / 2) - 1)
  local top, bottom = 3, H - 3
  G.one    = {x = 1, y = top, w = LW, h = 13}
  G.two    = {x = 1, y = top + 13, w = LW, h = 4}
  G.search = {x = 1, y = top + 17, w = LW, h = bottom - (top + 17) + 1}
  G.brief  = {x = LW + 2, y = top, w = W - LW - 1, h = bottom - top + 1}
  G.div, G.btnRow, G.bottom = LW + 1, H, bottom
  return W, H
end

local function speciesList(muts)
  local set, list = {}, {}
  for _, m in ipairs(muts or {}) do
    set[m.a], set[m.b], set[m.r] = true, true, true
  end
  for s in pairs(set) do list[#list + 1] = s end
  table.sort(list)
  return list
end

--------------------------------------------------------------------
-- tally/order from beestock.tally; status is the header strip's extras
--------------------------------------------------------------------
function breedui.run(tally, order, muts, status, exportPair)
  if not (core.hasGpu and core.isWide()) then return nil end
  core.begin()
  local W, H = geometry()
  local job = {requirePure = config.requirePure,
               droneGoal = config.droneGoal,
               chatEveryQueen = config.chatEveryQueen,
               export = exportPair or nil}
  local owned = pick.owned(tally)
  local one   = pick.oneStep(muts, owned, tally)
  local two   = pick.twoStep(muts, owned, one)
  local sum   = pick.summary(owned, one, two)
  local all   = speciesList(muts)
  local query, sel, state = "", nil, nil
  local hits, routes = {}, {}

  -- One planner run per species, remembered for the life of this
  -- screen: the cabinets cannot change while it is open, so the
  -- answer cannot either, and typing must stay cheap.
  local function route(sp)
    if routes[sp] == nil then
      local n, cyc, steps = pick.stepsAway(muts, owned, sp)
      routes[sp] = {steps = n, cycles = cyc, plan = steps or {}}
    end
    return routes[sp]
  end

  local function filter()
    hits = {}
    local q = query:lower()
    local room = G.search.h - 4
    for _, s in ipairs(all) do
      if q == "" or s:lower():find(q, 1, true) then
        local r = route(s)
        hits[#hits + 1] = {species = s, steps = r.steps, cycles = r.cycles}
        if #hits >= room then break end
      end
    end
  end

  local draw
  local function choose(sp)
    sel = sp
    draw()
  end

  draw = function()
    core.clearButtons()
    frame.header(exportPair and (g("right") .. " Export a pair")
                 or (g("play") .. " Breed"), frame.statusItems(status))
    segs.set(2, {{text = ("%d owned %s %d one step %s %d two steps %s %d out of season")
      :format(sum.owned, g("mid"), sum.one, g("mid"), sum.two, g("mid"),
              sum.offSeason), color = C.dim}}, W)
    frame.divider(G.div, 3, G.bottom)
    core.panel(G.one.x, G.one.y, G.one.w, G.one.h, "One step")
    core.panel(G.two.x, G.two.y, G.two.w, G.two.h, "Two steps")
    core.panel(G.search.x, G.search.y, G.search.w, G.search.h, "Search")
    core.panel(G.brief.x, G.brief.y, G.brief.w, G.brief.h, "Preview")
    cands.oneStep(G.one, one, sel, choose)
    cands.twoStep(G.two, two, choose)
    cands.search(G.search, query, hits, sel, choose)
    brief.show(G.brief, sel, sel and route(sel) or nil, owned, tally)

    local bar = {
      {id = "start", label = ("[ %s %s %s ]"):format(
       exportPair and g("right") or g("play"),
       exportPair and "EXPORT" or "START", sel or "..."),
       bg = sel and C.good or C.barEmpty,
       fg = sel and C.headerFg or C.dim,
       onPress = function() if sel then state = "start" end end},
      {id = "pure", label = ("[ %s PURE: %s ]"):format(g("pure"),
       job.requirePure and "ON " or "OFF"),
       bg = job.requirePure and C.good or nil,
       fg = job.requirePure and C.headerFg or nil,
       onPress = function() job.requirePure = not job.requirePure draw() end},
      {id = "gminus", label = "[ - ]",
       onPress = function() job.droneGoal = math.max(1, job.droneGoal - 1) draw() end},
      {text = ("goal %d"):format(job.droneGoal)},
      {id = "gplus", label = "[ + ]",
       onPress = function() job.droneGoal = job.droneGoal + 1 draw() end},
      {id = "chat", label = ("[ %s CHAT: %s ]"):format(g("chat"),
       job.chatEveryQueen and "ON " or "OFF"),
       bg = job.chatEveryQueen and C.good or nil,
       fg = job.chatEveryQueen and C.headerFg or nil,
       onPress = function() job.chatEveryQueen = not job.chatEveryQueen draw() end},
      {id = "home", label = "[ " .. g("left") .. " HOME ]",
       onPress = function() state = "home" end},
    }
    frame.bar(G.btnRow, bar)
    frame.hint("home")
  end

  -- Typing filters, the arrows walk the hits, Enter starts. Q only
  -- leaves while the search box is empty, so it stays typable; the
  -- search is a substring match, so a species starting with Q is
  -- still reachable by typing any later part of its name.
  local function moveSel(delta)
    local at = 0
    for i, h in ipairs(hits) do
      if h.species == sel then at = i end
    end
    at = math.max(1, math.min(#hits, at + delta))
    if hits[at] then sel = hits[at].species end
  end

  core.setKeyHandler(function(char, code)
    if code == core.keys.enter and sel then
      state = "start"
    elseif code == core.keys.q and query == "" then
      state = "home"
    elseif code == core.keys.up then
      moveSel(-1)
    elseif code == core.keys.down then
      moveSel(1)
    elseif code == core.keys.back then
      query = query:sub(1, -2)
      filter()
    elseif char and char >= 32 and char < 127 then
      query = query .. string.char(char)
      filter()
    end
    draw()
  end)

  segs.reset()
  filter()
  draw()
  while not state do
    core.pump(config.animDelay or 0.5)
    segs.tick()
  end
  core.setKeyHandler(nil)
  if state ~= "start" or not sel then return nil end
  job.target = sel
  return job
end

return breedui
