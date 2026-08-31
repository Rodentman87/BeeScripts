-- beesetup.lua  ->  install to /home/lib/beesetup.lua
-- Interactive setup screen: search the species registry, pick a
-- target, adjust settings, start. Needs the mutation cache
-- (`beeprobe build`) for the species list, and a screen.

local core   = require("beeui")
local config = require("beeconfig")
local data   = require("beedata")
local segs   = require("beesegs")
local preview = require("beepreview")
local C = core.C

local setup = {}

local function speciesList()
  local muts, species = data.load()
  if not muts then return nil, species end
  local list = {}
  for s in pairs(species) do list[#list + 1] = s end
  table.sort(list)
  return list
end

--------------------------------------------------------------------
-- Screen 1: searchable species picker
--------------------------------------------------------------------
local function pickSpecies(list)
  local W, H = core.size()
  local query, sel, results = "", 1, {}
  local picked, cancelled = nil, false
  local maxRows = H - 8

  local function filter()
    results = {}
    local q = query:lower()
    for _, s in ipairs(list) do
      if q == "" or s:lower():find(q, 1, true) then
        results[#results + 1] = s
        if #results >= maxRows then break end
      end
    end
    if sel > #results then sel = math.max(1, #results) end
  end

  local function draw()
    core.clearButtons()
    core.fillRect(1, 1, W, 1, C.header)
    core.text(2, 1, "BeeBreeder Setup -- pick a target species", C.headerFg, C.header)
    core.line(3, "Search: " .. query .. "_")
    core.hline(4)
    for i = 1, maxRows do
      local row = 4 + i
      local s = results[i]
      if s then
        segs.set(row, {
          {text = (i == sel and "> " or "  "),
           color = (i == sel) and C.warn or C.text},
          {text = s, species = s}})
        core.button{id = "pick" .. i, x = 1, y = row, w = W,
                    invisible = true,
                    onPress = function() sel = i; picked = results[i] end}
      else
        segs.set(row, {})
      end
    end
    core.line(H - 2, "Type to search - arrows + Enter, or touch a name", C.dim)
    core.button{id = "cancel", x = 2, y = H - 1, label = "[ CANCEL ]",
                bg = C.barEmpty, fg = C.text,
                onPress = function() cancelled = true end}
  end

  core.setKeyHandler(function(char, code)
    if code == core.keys.enter and results[sel] then
      picked = results[sel]
    elseif code == core.keys.up then
      sel = math.max(1, sel - 1)
    elseif code == core.keys.down then
      sel = math.min(math.max(#results, 1), sel + 1)
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
  while not picked and not cancelled do
    core.pump(config.animDelay or 0.5)
    segs.tick()
  end
  core.setKeyHandler(nil)
  return picked
end

--------------------------------------------------------------------
-- Screen 2: settings + start
--------------------------------------------------------------------
local function settings(job)
  local W, H = core.size()
  local state = nil  -- "start" | "back" | "cancel"

  local function draw()
    core.clearButtons()
    core.fillRect(1, 1, W, 1, C.header)
    core.text(2, 1, "BeeBreeder Setup -- settings", C.headerFg, C.header)
    segs.set(3, {{text = "Target: ", color = C.good},
                 {text = job.target, species = job.target}})

    core.line(5, "Purity: require Target/Target for princess and drone bank")
    core.button{id = "pure", x = 2, y = 6,
                label = job.requirePure and "[ PURE: ON  ]" or "[ PURE: OFF ]",
                bg = job.requirePure and C.good or C.barEmpty,
                fg = job.requirePure and C.headerFg or C.text,
                onPress = function() job.requirePure = not job.requirePure; draw() end}

    core.line(8, "Drone bank goal for the final species")
    core.button{id = "dminus", x = 2, y = 9, label = "[ - ]",
                bg = C.barEmpty, onPress = function()
                  job.droneGoal = math.max(1, job.droneGoal - 1); draw()
                end}
    core.text(9, 9, ("%3d"):format(job.droneGoal))
    core.button{id = "dplus", x = 14, y = 9, label = "[ + ]",
                bg = C.barEmpty, onPress = function()
                  job.droneGoal = job.droneGoal + 1; draw()
                end}

    core.line(11, "Chat message for every new queen (vs milestones only)")
    core.button{id = "chatq", x = 2, y = 12,
                label = job.chatEveryQueen and "[ CHAT/QUEEN: ON  ]" or "[ CHAT/QUEEN: OFF ]",
                bg = job.chatEveryQueen and C.good or C.barEmpty,
                fg = job.chatEveryQueen and C.headerFg or C.text,
                onPress = function() job.chatEveryQueen = not job.chatEveryQueen; draw() end}

    core.button{id = "start", x = 2, y = H - 1, label = "[ START ]",
                bg = C.good, fg = C.headerFg,
                onPress = function() state = "start" end}
    core.button{id = "back", x = 13, y = H - 1, label = "[ BACK ]",
                bg = C.barEmpty, onPress = function() state = "back" end}
    core.button{id = "cancel2", x = 23, y = H - 1, label = "[ CANCEL ]",
                bg = C.barEmpty, onPress = function() state = "cancel" end}
    core.line(H - 2, "Enter = start", C.dim)
  end

  core.setKeyHandler(function(_, code)
    if code == core.keys.enter then state = "start" end
  end)

  segs.reset()
  draw()
  -- One-time plan preview: route, odds, and preparation notes.
  -- Toggle redraws leave these rows alone; the shimmer keeps them.
  preview.show(job.target, 13, H - 3)
  while not state do
    core.pump(config.animDelay or 0.5)
    segs.tick()
  end
  core.setKeyHandler(nil)
  return state
end

--------------------------------------------------------------------
function setup.run()
  local list, err = speciesList()
  if not list then
    print("Setup needs the mutation cache: " .. tostring(err))
    return nil
  end
  if not core.hasGpu then
    print("The setup screen needs a GPU/screen; pass a species name instead.")
    return nil
  end

  core.begin()
  local job = {
    requirePure    = config.requirePure,
    droneGoal      = config.droneGoal,
    chatEveryQueen = config.chatEveryQueen,
  }

  while true do
    job.target = pickSpecies(list)
    if not job.target then return nil end
    core.begin()
    local state = settings(job)
    if state == "start" then return job end
    if state == "cancel" then return nil end
    core.begin()  -- "back": around again to the picker
  end
end

return setup
