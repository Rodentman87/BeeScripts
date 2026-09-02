-- beecands.lua  ->  install to /lib/beecands.lua
-- The breed screen's left column: what is one cross away, what is two,
-- and a search box for everything else. beebreedui owns the frame and
-- what picking something does; this owns the three lists.
--
-- A row out of season is greyed and its button is inert rather than
-- hidden: knowing that Merry exists and wants December is the useful
-- half of the answer.

local core = require("beeui")
local segs = require("beesegs")
local colors = require("beecolors")
local C, g = core.C, core.g

local cands = {}

--------------------------------------------------------------------
-- One step: both parents in the cabinets, the result not.
-- list entries come from beepick.oneStep.
--------------------------------------------------------------------
function cands.oneStep(P, list, sel, onPick)
  if not core.hasGpu then return end
  local head = P.y + 1
  core.line(head, "", nil, P.w - 2, P.x + 1)
  core.text(P.x + 8, head, "result", C.dim)
  core.text(P.x + 22, head, "parents", C.dim)
  core.text(P.x + 47, head, "%", C.dim)
  core.text(P.x + 52, head, "~cyc", C.dim)
  core.text(P.x + 59, head, "needs", C.dim)

  -- Interior row 1 is the column header and the last is the overflow
  -- line, so the candidates get everything between.
  local room = P.h - 4
  for i = 1, room do
    local c = list[i]
    local y = head + i
    segs.set(y, {}, P.w - 2, P.x + 1)
    if c then
      local grey = (c.season == false)
      local row = {}
      if grey then
        row[#row + 1] = {text = c.result, color = C.dim2}
      elseif c.result == sel then
        row[#row + 1] = {text = c.result, color = C.headerFg, bgSpecies = c.result}
      else
        row[#row + 1] = {text = c.result, species = c.result}
      end
      segs.set(y, row, 13, P.x + 7)

      local par = {{text = c.a, color = grey and C.dim2 or nil,
                    species = (not grey) and c.a or nil}}
      if c.lowA then par[#par + 1] = {text = g("triD"), color = C.bad} end
      par[#par + 1] = {text = " + ", color = grey and C.dim2 or C.dim}
      par[#par + 1] = {text = c.b, color = grey and C.dim2 or nil,
                       species = (not grey) and c.b or nil}
      if c.lowB then par[#par + 1] = {text = g("triD"), color = C.bad} end
      segs.set(y, par, 22, P.x + 21)

      core.text(P.x + 45, y, ("%3d%%"):format(math.floor(c.chance + 0.5)),
                grey and C.dim2 or C.text)
      core.text(P.x + 52, y, "~" .. c.expCycles, C.dim2)
      if c.season ~= nil then
        core.text(P.x + 59, y, core.clip(g("moon") .. " " ..
                  (c.cond ~= "" and c.cond or "seasonal"), 17),
                  grey and C.dim2 or C.warn)
      elseif c.cond and c.cond ~= "" then
        core.text(P.x + 59, y, core.clip(c.cond, 16), C.warn)
      end
      core.button{id = "one" .. i, x = P.x + 2, y = y,
                  label = "[ " .. g("play") .. " ]",
                  bg = grey and C.barEmpty or C.good,
                  fg = grey and C.dim2 or C.headerFg,
                  onPress = function() if not grey then onPick(c.result) end end}
    end
  end
  core.line(P.y + P.h - 2, #list > room
            and ("+%d more"):format(#list - room) or "",
            C.dim2, P.w - 2, P.x + 1)
end

--------------------------------------------------------------------
-- Two steps: chips, because there is nothing to say about them yet
--------------------------------------------------------------------
function cands.twoStep(P, list, onPick)
  if not core.hasGpu then return end
  local y = P.y + 1
  core.line(y, "", nil, P.w - 2, P.x + 1)
  local x = P.x + 2
  for i, sp in ipairs(list) do
    local label = "[ " .. sp .. " ]"
    if x + core.len(label) > P.x + P.w - 2 then break end
    core.button{id = "two" .. i, x = x, y = y, label = label,
                bg = C.barEmpty, fg = nil,
                onPress = function() onPick(sp) end}
    -- The button paints in plain text; recolor the name itself
    core.text(x + 2, y, sp, colors.of(sp), C.barEmpty)
    x = x + core.len(label) + 2
  end
end

--------------------------------------------------------------------
-- Search: the typed text with its cursor on the first row, results
-- under a rule. hits are {species, steps, cycles, chance}.
--------------------------------------------------------------------
function cands.search(P, query, hits, sel, onPick)
  if not core.hasGpu then return end
  segs.set(P.y + 1, {{text = query}, {text = g("caret"), color = C.warn}},
           P.w - 2, P.x + 1)
  core.text(P.x + 2, P.y + 2, string.rep(g("h"), P.w - 5), C.frame)
  local room = P.h - 4
  for i = 1, room do
    local h = hits[i]
    local y = P.y + 2 + i
    segs.set(y, {}, P.w - 2, P.x + 1)
    if h then
      core.text(P.x + 2, y, (h.species == sel) and ">" or " ", C.warn)
      segs.set(y, {{text = h.species, species = h.species}}, 13, P.x + 3)
      local far = h.steps and (h.steps == 0 and "owned"
                  or ("%d step%s"):format(h.steps, h.steps == 1 and "" or "s"))
      core.text(P.x + 18, y, far or g("fail"), far and C.dim or C.bad)
      if h.chance then
        core.text(P.x + 28, y, ("%d%%"):format(math.floor(h.chance + 0.5)), C.text)
      end
      if h.cycles and h.cycles > 0 then
        core.text(P.x + 33, y, ("~%d cyc"):format(h.cycles), C.dim)
      end
      core.button{id = "hit" .. i, x = P.x + 1, y = y, w = P.w - 2,
                  invisible = true, onPress = function() onPick(h.species) end}
    end
  end
end

return cands
