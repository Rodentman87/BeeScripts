-- beeplanner.lua  ->  install to /home/lib/beeplanner.lua
-- Breeding-route planner. Given the cached mutation graph, the
-- species you currently own, and a target, computes the cheapest
-- ordered chain of mutations to breed.
--
-- This is an AND-graph search, not plain shortest-path: every
-- mutation needs BOTH parents bred first. A species' cost is
--   cost(parentA) + cost(parentB) + expected cycles (~100/chance)
-- memoized per species, so cheap high-chance routes beat short
-- low-chance ones.

local planner = {}

local INF = math.huge

-- muts:  list of {a=, b=, r=, chance=, cond=} from beedata.load()
-- owned: set (species -> true) of species you already have
-- target: species display name
-- Returns ordered list of steps {result, a, b, chance, cond,
-- expCycles} with parents always before children, or nil + reason.
function planner.compute(muts, owned, target)
  if owned[target] then
    return {}, "already owned"
  end

  local byResult = {}
  for _, m in ipairs(muts) do
    local list = byResult[m.r]
    if not list then
      list = {}
      byResult[m.r] = list
    end
    list[#list + 1] = m
  end

  if not byResult[target] then
    return nil, ("no mutation produces %q -- check spelling/case"):format(target)
  end

  local memo, visiting = {}, {}

  local function cost(s)
    if owned[s] then return 0 end
    local m = memo[s]
    if m then return m.cost end
    if visiting[s] then return INF end  -- cycle guard
    local options = byResult[s]
    if not options then
      memo[s] = {cost = INF}
      return INF
    end
    visiting[s] = true
    local best, bestMut = INF, nil
    for _, opt in ipairs(options) do
      local chance = opt.chance > 0 and opt.chance or 1
      local c = cost(opt.a) + cost(opt.b) + (100 / chance)
      if c < best then
        best, bestMut = c, opt
      end
    end
    visiting[s] = nil
    memo[s] = {cost = best, mut = bestMut}
    return best
  end

  if cost(target) >= INF then
    return nil, ("no breeding path from your current bees to %q"):format(target)
  end

  -- Walk chosen mutations into an ordered, deduplicated step list
  local steps, added = {}, {}
  local function emit(s)
    if owned[s] or added[s] then return end
    local entry = memo[s]
    local m = entry and entry.mut
    if not m then return end
    added[s] = true
    emit(m.a)
    emit(m.b)
    steps[#steps + 1] = {
      result = s, a = m.a, b = m.b,
      chance = m.chance, cond = m.cond,
      expCycles = math.ceil(100 / math.max(m.chance, 0.01)),
    }
  end
  emit(target)
  return steps
end

-- Human-readable plan lines (for logs, chat, or the dashboard)
function planner.describe(steps)
  local lines = {}
  local total = 0
  for i, s in ipairs(steps) do
    total = total + s.expCycles
    lines[#lines + 1] = ("%d. %s + %s -> %s  (%.0f%%, ~%d cycles)")
      :format(i, s.a, s.b, s.result, s.chance, s.expCycles)
    if s.cond and s.cond ~= "" then
      lines[#lines + 1] = ("   NOTE: %s"):format(s.cond)
    end
  end
  lines[#lines + 1] = ("Total: %d steps, ~%d cycles expected"):format(#steps, total)
  return lines
end

return planner
