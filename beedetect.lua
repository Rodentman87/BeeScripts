-- beedetect.lua  ->  install to /lib/beedetect.lua
-- Which transposer side is which, written back into beeconfig.
-- beesides looks; this one decides. A wrong guess sends princesses
-- to the sorting chest, so anything short of "sure" asks the user.

local sides  = require("beesides")

local D = {}

--------------------------------------------------------------------
-- Scoring. Every occupied side is scored for every role and the
-- best global pairing wins. Block names count most, contents break
-- the chest/chest tie, and a role keeps the side it already has on
-- a tie, so a working config never churns.
--------------------------------------------------------------------
local function scoreSide(info, cur)
  local kind = sides.kindOf(info)
  local s = {}
  s.apiarySide = (kind == "apiary" and 10 or 0)
               + (info.queens > 0 and 5 or 0)
               + ((info.size == 9 or info.size == 12) and 2 or 0)
  s.scannerSide = (kind == "machine" and 8 or 0)
                + ((not kind and info.size <= 8) and 3 or 0)
  local chest = (kind == "chest" and 8 or 0) + (info.size >= 27 and 2 or 0)
  s.chestSide     = chest + (info.princesses > 0 and 5 or 0)
  s.sortChestSide = chest + (info.princesses == 0 and 2 or 0)
  for key in pairs(s) do
    s[key] = s[key] + 0.1                      -- an occupied side beats none
    if cur[key] == info.side then s[key] = s[key] + 1 end
  end
  return s
end

-- Returns assign (role key -> side) and conf (role key -> "sure" |
-- "likely" | "guess"). "guess" means: ask the user.
function D.detect(probe)
  local err
  if not probe then probe, err = sides.probe() end
  if not probe then return nil, err end
  local cur = sides.current()
  local score, cand = {}, {}
  for side = 0, 5 do
    local info = probe[side]
    if info and info.size then
      score[side] = scoreSide(info, cur)
      for key, v in pairs(score[side]) do
        cand[#cand + 1] = {side = side, key = key, score = v}
      end
    end
  end
  table.sort(cand, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    if a.side  ~= b.side  then return a.side < b.side end
    return a.key < b.key
  end)

  local assign, conf, roleOf, usedRole = {}, {}, {}, {}
  for _, c in ipairs(cand) do
    if not roleOf[c.side] and not usedRole[c.key] then
      assign[c.key], roleOf[c.side], usedRole[c.key] = c.side, c.key, true
      conf[c.key] = (c.score >= 8 and "sure") or (c.score >= 4 and "likely") or "guess"
    end
  end

  -- Winning by less than 2 over a side that is not firmly spoken
  -- for elsewhere is a coin flip, not an answer.
  for _, role in ipairs(sides.ROLES) do
    local key, mine = role.key, assign[role.key]
    if mine then
      local rival = -1
      for side = 0, 5 do
        if score[side] and side ~= mine then
          local got = roleOf[side]
          local slack = got and (score[side][got] - score[side][key]) or 0
          if slack <= 1 and score[side][key] > rival then rival = score[side][key] end
        end
      end
      if score[mine][key] - rival < 2 then conf[key] = "guess" end
    end
  end
  return assign, conf
end

function D.describe(assign)
  local bits = {}
  for _, r in ipairs(sides.ROLES) do
    bits[#bits + 1] = r.key:gsub("Side$", "") .. "=" .. sides.sideName(assign[r.key])
  end
  return table.concat(bits, " ")
end

--------------------------------------------------------------------
-- Startup self-heal. Returns status, message, probe, assign, conf:
--   "ok"          config already matches the world
--   "fixed"       detection was unambiguous; applied for this run
--   "unresolved"  caller should ask the user (beewire)
--------------------------------------------------------------------
function D.autoheal()
  local probe, err = sides.probe()
  if not probe then return "unresolved", err end
  if sides.validate(probe, sides.current()) then return "ok", nil, probe end

  local assign, conf = D.detect(probe)
  local sure = assign ~= nil
  for _, role in ipairs(sides.ROLES) do
    if not assign or not assign[role.key] or conf[role.key] == "guess" then
      sure = false
    end
  end
  if not sure or not sides.validate(probe, assign) then
    return "unresolved", "cannot tell which side is which", probe, assign, conf
  end
  sides.apply(assign)
  return "fixed", D.describe(assign), probe, assign, conf
end

--------------------------------------------------------------------
-- Write an assignment into beeconfig.lua. Only the value on each
-- <role>Side line changes, so comments and other settings survive --
-- this file is the user's, the updater never touches it. The result
-- is compiled before it is written; the old file becomes a .bak.
--------------------------------------------------------------------
local CANDIDATES = {"/lib/beeconfig.lua", "/home/lib/beeconfig.lua", "/usr/lib/beeconfig.lua"}

local function configPath()
  local fs = require("filesystem")
  local ok, found = pcall(package.searchpath, "beeconfig", package.path)
  if ok and found and fs.exists(found) then return found end
  for _, p in ipairs(CANDIDATES) do
    if fs.exists(p) then return p end
  end
  return nil, "cannot find beeconfig.lua on package.path"
end

local function writeAll(path, body)
  local f, err = io.open(path, "w")
  if not f then return false, tostring(err) end
  f:write(body)
  f:close()
  return true
end

function D.save(assign)
  local path, err = configPath()
  if not path then return false, err end
  local f = io.open(path, "r")
  if not f then return false, "cannot read " .. path end
  local lines, want = {}, {}
  for line in f:lines() do lines[#lines + 1] = line end
  f:close()
  local original = table.concat(lines, "\n") .. "\n"
  -- sides.north when that module is in scope (as in the shipped
  -- config), a plain number when it is not.
  local named = original:find("local%s+sides%s*=") ~= nil
  for _, role in ipairs(sides.ROLES) do
    local side = assign[role.key]
    if side then
      want[role.key] = named and ("sides." .. sides.sideName(side)) or tostring(side)
    end
  end

  local lastHit = nil
  for i, line in ipairs(lines) do
    for key, name in pairs(want) do
      local head, tail = line:match("^(%s*" .. key .. "%s*=%s*)[%w_%.]+(.*)$")
      if head then
        lines[i] = head .. name .. tail
        want[key] = nil
        lastHit = i
      end
    end
  end

  -- A config predating a setting has no line to patch: add one.
  local added = {}
  for _, role in ipairs(sides.ROLES) do
    if want[role.key] then
      added[#added + 1] = ("  %s = %s,  -- added by beebreeder sides")
                          :format(role.key, want[role.key])
    end
  end
  if #added > 0 then
    local at = lastHit or math.max(#lines - 1, 0)
    for k = #added, 1, -1 do table.insert(lines, at + 1, added[k]) end
  end

  local body = table.concat(lines, "\n") .. "\n"
  if not load(body, "beeconfig") then
    return false, "refused to write: the patched beeconfig would not compile"
  end
  writeAll(path .. ".bak", original)
  local ok, werr = writeAll(path, body)
  if not ok then return false, werr end
  sides.apply(assign)
  return true, path
end

return D
