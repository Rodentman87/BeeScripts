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
-- Optional roles are only taken when the evidence is real: below
-- this they stay unset and fall back to the processing chest, which
-- is always a safe answer. Without the bar a spare barrel on some
-- side would be promoted to "the drone cabinet" on nothing at all.
local MIN_OPTIONAL = 8

local function scoreSide(info, cur)
  local kind = sides.kindOf(info)
  local s = {}
  s.apiarySide = (kind == "apiary" and 10 or 0)
               + (info.queens > 0 and 5 or 0)
               + ((info.size == 9 or info.size == 12) and 2 or 0)
  s.scannerSide = (kind == "machine" and 8 or 0)
                + ((not kind and info.size <= 8) and 3 or 0)
  -- Cabinets: a filing cabinet holds ONE item ID, so one with
  -- princesses and no drones (or the reverse) is as clear a signal
  -- as any block name. The name makes it a cabinet (a huge chest-
  -- kind inventory counts too, for a driver that names nothing);
  -- the contents say which cabinet. An EMPTY cabinet cannot be told
  -- apart, stays unset, and is set on the wiring screen. The dump is
  -- the chest with things in it that are not bees at all.
  local bees = info.princesses + info.drones
  local cab  = sides.isCabinet(info) or (kind == "chest" and info.size >= 100)
  local big  = cab and 5 or 0
  local junk = (info.items > 0 and bees == 0) and 1 or 0
  local chest = (kind == "chest" and 8 or 0) + (info.size >= 27 and 2 or 0)
  -- A cabinet is never one of the plain chests: not the processing
  -- chest (a one-item-ID box cannot hold both bees), not the sorting
  -- chest (a library, not a bin), not the dump (combs come in many
  -- kinds). Pushed well under the chest scores so a real chest on
  -- any other side wins those roles outright.
  local notChest = cab and 6 or 0
  s.chestSide     = chest + (info.princesses > 0 and 5 or 0) - notChest
  s.sortChestSide = chest + (info.princesses == 0 and 2 or 0)
                  - junk * 6 - notChest
  s.princessSide = big + ((info.princesses > 0 and info.drones == 0) and 6 or 0)
  s.droneSide    = big + ((info.drones > 0 and info.princesses == 0) and 6 or 0)
  s.dumpSide     = (kind == "chest" and 3 or 0) + junk * 6 - notChest
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

  local optional = {}
  for _, role in ipairs(sides.ROLES) do optional[role.key] = role.optional end

  local assign, conf, roleOf, usedRole = {}, {}, {}, {}
  for _, c in ipairs(cand) do
    if not roleOf[c.side] and not usedRole[c.key]
       and not (optional[c.key] and c.score < MIN_OPTIONAL) then
      assign[c.key], roleOf[c.side], usedRole[c.key] = c.side, c.key, true
      conf[c.key] = (c.score >= 8 and "sure") or (c.score >= 4 and "likely") or "guess"
    end
  end
  -- An optional role nothing argued for is left explicitly unset, not
  -- absent: sides.apply reads false as "clear it" and the wiring
  -- screen can step it back on from there.
  for _, role in ipairs(sides.ROLES) do
    if role.optional and assign[role.key] == nil then assign[role.key] = false end
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
    if sides.isSet(assign[r.key]) then
      bits[#bits + 1] = r.key:gsub("Side$", "") .. "=" .. sides.sideName(assign[r.key])
    end
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
  -- Only the required roles have to be pinned down. An optional one
  -- left unset is an answer, not a shrug: it means "use the
  -- processing chest", which is what the classic build does anyway.
  for _, role in ipairs(sides.ROLES) do
    if not role.optional and
       (not assign or not sides.isSet(assign[role.key])
        or conf[role.key] == "guess") then
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
-- Write an assignment into beeconfig.lua. beeconf does the careful
-- part (patch the value, keep the comments, compile before writing,
-- leave a .bak); this decides WHAT to write. A role that was never
-- set and still is not stays out of the file altogether; one being
-- retired is written as `false`, which every reader treats as "no
-- such side" -- otherwise it would simply come back on next boot.
--------------------------------------------------------------------
function D.save(assign)
  local now, changes, order = sides.current(), {}, {}
  for _, role in ipairs(sides.ROLES) do
    local side = assign[role.key]
    if sides.isSet(side) then
      changes[role.key] = {side = side}
      order[#order + 1] = role.key
    elseif role.optional and side == false and sides.isSet(now[role.key]) then
      changes[role.key] = false
      order[#order + 1] = role.key
    end
  end
  local ok, pathOrWhy = require("beeconf").write(changes,
                                                 "set by beebreeder sides")
  if not ok then return false, pathOrWhy end
  sides.apply(assign)
  return true, pathOrWhy
end

return D
