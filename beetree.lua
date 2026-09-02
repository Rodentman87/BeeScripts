-- beetree.lua  ->  install to /lib/beetree.lua
-- The breeding route as an indented tree: target at the root, the
-- two recipe parents beneath each step, and so on down to species
-- already in the chest. Pure layout work -- build() makes the node
-- tree, rows() turns it into colored segment rows for beesegs.
--
-- Folding rules keep it short: a species that exists in the chest is
-- a leaf (check mark when it was bred this run, dot when it was
-- there already), and a species whose subtree is drawn elsewhere
-- becomes a one-line reference with an up arrow instead of repeating.
--
-- node = {sp=, state="now"|"todo"|"have"|"ref", step=?, kids={}}

local core  = require("beeui")
local found = require("beefound")
local C, g = core.C, core.g

local tree = {}

local META_X = 30   -- column (within the pane) where odds begin

-- steps: planner output, parents before children (last = target).
-- owned: species -> true for what exists in the chest.
-- current: result species of the step being worked, or nil.
function tree.build(steps, owned, current)
  if not steps or #steps == 0 then return nil end
  local byResult = {}
  for _, s in ipairs(steps) do byResult[s.result] = s end
  local drawn = {}
  local function node(sp)
    local n = {sp = sp, kids = {}}
    local s = byResult[sp]
    if owned[sp] or not s then
      n.state = "have"
    elseif drawn[sp] then
      n.state = "ref"
    else
      drawn[sp] = true
      n.state = (sp == current) and "now" or "todo"
      n.step = s
      n.kids[1] = node(s.a)
      n.kids[2] = node(s.b)
    end
    return n
  end
  return node(steps[#steps].result)
end

-- Odds, the "now" marker, and any condition, for an internal node
local function meta(n, opts)
  local s, list = n.step, {}
  if not s then return list end
  list[#list + 1] = {text = ("%3.0f%%  ~%d cyc"):format(s.chance, s.expCycles),
                     color = C.dim}
  if n.state == "now" then
    local t = "   " .. g("arrowL") .. " now"
    if opts.rolls then
      t = t .. (" %s roll %d of ~%d"):format(g("mid"), opts.rolls, s.expCycles)
    end
    list[#list + 1] = {text = t, color = C.warn}
  end
  local block = found.parse(s.cond)
  if block then
    list[#list + 1] = {text = "   " .. g("square") .. " " .. block, color = C.warn}
  elseif s.cond and s.cond ~= "" then
    list[#list + 1] = {text = "   " .. g("warn") .. " " .. s.cond, color = C.warn}
  end
  return list
end

-- opts: {done = set of species bred this run, rolls = cycles spent
-- on the current step}. Returns {{segs=, node=}, ...} top to bottom.
function tree.rows(root, opts)
  opts = opts or {}
  local done = opts.done or {}
  local rows = {}
  local function emit(n, prefix, branch, isLast, depth)
    local segs = {}
    if branch ~= "" then segs[1] = {text = prefix .. branch, color = C.frame} end
    if n.state == "now" then
      segs[#segs + 1] = {text = n.sp, color = C.headerFg, bgSpecies = n.sp}
    else
      segs[#segs + 1] = {text = n.sp, species = n.sp}
    end
    if n.state == "have" then
      segs[#segs + 1] = {text = " " .. g(done[n.sp] and "check" or "dot"), color = C.good}
    elseif n.state == "ref" then
      segs[#segs + 1] = {text = " " .. g("up"), color = C.dim2}
    else
      local used = core.len(prefix .. branch) + core.len(n.sp)
      segs[#segs + 1] = {text = string.rep(" ", math.max(1, META_X - used))}
      for _, m in ipairs(meta(n, opts)) do segs[#segs + 1] = m end
      if depth == 0 then segs[#segs + 1] = {text = "   target", color = C.dim2} end
    end
    rows[#rows + 1] = {segs = segs, node = n}
    local childPrefix = prefix
    if branch ~= "" then
      childPrefix = prefix .. (isLast and "   " or (g("v") .. "  "))
    end
    for i, k in ipairs(n.kids) do
      local last = (i == #n.kids)
      emit(k, childPrefix, (last and g("bl") or g("teeR")) .. g("h") .. " ", last, depth + 1)
    end
  end
  emit(root, "", "", true, 0)
  return rows
end

-- Cut a row list down to maxRows, ending in a "+N more" line
function tree.fit(rows, maxRows)
  if #rows <= maxRows then return rows end
  local out = {}
  for i = 1, maxRows - 1 do out[i] = rows[i] end
  out[maxRows] = {segs = {{text = ("  +%d more"):format(#rows - maxRows + 1),
                          color = C.dim}}}
  return out
end

-- One-line summary: steps left, cycles expected, time at the current
-- pace (avgCycle in seconds; omitted when there is no average yet).
function tree.summary(steps, avgCycle)
  local cyc = 0
  for _, s in ipairs(steps) do cyc = cyc + s.expCycles end
  local text = ("%d step%s left %s ~%d cycles expected")
               :format(#steps, #steps == 1 and "" or "s", g("mid"), cyc)
  if avgCycle and avgCycle > 0 then
    local secs = math.floor(cyc * avgCycle)
    local h, m = math.floor(secs / 3600), math.floor((secs % 3600) / 60)
    local t = h > 0 and ("~%dh%02dm"):format(h, m) or ("~%dm"):format(math.max(1, m))
    text = text .. (" %s %s at current pace"):format(g("mid"), t)
  end
  return text
end

return tree
