-- beepreview.lua  ->  install to /home/lib/beepreview.lua
-- Plan preview for the settings screen: route summary, per-step
-- lines in species colors, and preparation notes (foundation
-- blocks, dimensions/biomes, unreachable targets).

local core    = require("beeui")
local segs    = require("beesegs")
local data    = require("beedata")
local planner = require("beeplanner")
local found   = require("beefound")
local climate = require("beeclimate")
local advice  = require("beeadvice")
local C = core.C

local preview = {}

local function ownedFromChest()
  local ok, yard = pcall(require, "beeyard")
  if not ok then return nil end
  local owned = {}
  local ok2 = pcall(function()
    local princesses, drones = yard.scan(false)
    for _, list in ipairs({princesses, drones}) do
      for _, bee in ipairs(list) do
        if bee.active then owned[bee.active] = true end
      end
    end
  end)
  if not ok2 then return nil end
  return owned
end

-- Render the preview into rows top..bottom (top gets a divider).
function preview.show(target, top, bottom)
  core.hline(top, "Plan")
  local row = top + 1
  local function line(l)
    if row <= bottom then segs.set(row, l); row = row + 1 end
  end
  local function fill()
    while row <= bottom do segs.set(row, {}); row = row + 1 end
  end

  local muts = (data.load())
  if not muts then
    line({{text = "No mutation cache -- run `beeprobe build` for a preview.",
           color = C.warn}})
    return fill()
  end
  local owned = ownedFromChest()
  if not owned then
    line({{text = "Could not scan chest -- preview unavailable.", color = C.warn}})
    return fill()
  end
  if owned[target] then
    line({{text = target, species = target},
          {text = " already in the chest -- will bank drones."}})
    return fill()
  end

  local hive = climate.autodetect()
  local steps, why = planner.compute(muts, owned, target, climate.routeCost)
  if not steps then
    line({{text = "NO ROUTE: ", color = C.bad},
          {text = tostring(why)}})
    line({{text = "Add starter species to the chest, then reopen setup.",
           color = C.dim}})
    return fill()
  end

  local cyc = 0
  for _, s in ipairs(steps) do cyc = cyc + s.expCycles end
  line({{text = ("Route: %d steps, ~%d cycles expected  (hive %s)")
         :format(#steps, cyc, hive.text), color = C.good}})

  -- Collect preparation notes from step conditions
  local notes = {}
  for _, s in ipairs(steps) do
    -- Climate is a preparation note like any other: it is something
    -- to sort out before the run, not a surprise ten cycles in.
    local st = climate.status(s.result)
    if st and not st.ok then
      notes[#notes + 1] = ("%s wants %s -- %s"):format(s.result, st.want,
                          advice.tolerance(st))
    end
    if s.cond and s.cond ~= "" then
      local block = found.parse(s.cond)
      if block then
        notes[#notes + 1] = ("Foundation: %s (for %s)"):format(block, s.result)
      end
      for part in s.cond:gmatch("[^;]+") do
        part = part:gsub("^%s+", ""):gsub("%s+$", "")
        if #part > 0 and not part:match("[Rr]equires .- as a foundation") then
          notes[#notes + 1] = ("%s (for %s)"):format(part, s.result)
        end
      end
    end
  end

  local noteRoom = math.min(#notes, 3)
  local stepRoom = math.max(1, (bottom - row + 1) - noteRoom
                               - (#notes > 3 and 1 or 0))
  for i = 1, math.min(#steps, stepRoom) do
    local s = steps[i]
    line(segs.cross(i .. " ", s.a, s.b, s.result,
                    (" (%.0f%%)"):format(s.chance)))
  end
  if #steps > stepRoom then
    line({{text = ("  +%d more steps"):format(#steps - stepRoom),
           color = C.dim}})
  end
  for i = 1, noteRoom do
    line({{text = "! " .. notes[i], color = C.warn}})
  end
  if #notes > 3 then
    line({{text = ("! +%d more notes"):format(#notes - 3), color = C.warn}})
  end
  fill()
end

return preview
