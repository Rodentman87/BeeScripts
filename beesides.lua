-- beesides.lua  ->  install to /lib/beesides.lua
-- Auto-discovery of which transposer side each inventory is on, so
-- the build can be rearranged without hand-editing beeconfig.
--
-- The transposer answers, per side: is there an inventory, how big,
-- what block is it (getInventoryName -- best effort, not every
-- driver answers) and what is in it. That names the apiary and the
-- scanner outright. Chests and cabinets are all the same kind of
-- block, so contents tell them apart: the processing chest holds
-- PRINCESSES, a cabinet holds one item ID and so is all princesses
-- or all drones, the dump has no bees at all. Anything still
-- ambiguous is left for beewire to ask about -- guessing wrong puts
-- bees in the wrong box.

local config = require("beeconfig")
local attach = require("beeattach")

local S = {}

-- The looking half lives in beeattach; callers keep the old names.
S.NAMES        = attach.NAMES
S.probe        = attach.probe
S.describeSide = attach.describeSide

-- Optional roles may be left unset (`false` in an assignment): they
-- fall back to the processing chest, which is the classic one-chest
-- build. Only the first three are ever required.
S.ROLES = {
  {key = "chestSide",     label = "Processing chest", kind = "chest"},
  {key = "apiarySide",    label = "Apiary / alveary", kind = "apiary"},
  {key = "scannerSide",   label = "GT scanner",       kind = "machine"},
  {key = "princessSide",  label = "Princess cabinet", kind = "chest", optional = true, cabinet = true},
  {key = "droneSide",     label = "Drone cabinet",    kind = "chest", optional = true, cabinet = true},
  {key = "dumpSide",      label = "Dump chest",       kind = "chest", optional = true},
  {key = "sortChestSide", label = "Sorting chest",    kind = "chest", optional = true},
}

-- An assignment holds a side number, or anything else for "unset"
function S.isSet(side) return type(side) == "number" end

local APIARY  = {"apicult", "apiary", "alveary", "beehouse", "bee.house"}
local CABINET = {"filing", "cabinet"}   -- tile.extrautils:filing
local CHEST   = {"chest", "crate", "barrel", "drawer", "storage",
                 "container", "filing", "cabinet"}
local MACHINE = {"scanner", "machine", "gt.block"}

local function kw(s, list)
  for _, k in ipairs(list) do
    if s:find(k, 1, true) then return true end
  end
  return false
end

-- What a side looks like, or nil for "no opinion" (no name from the
-- driver, or a name we don't recognize). nil must never warn.
local function kindOf(info)
  local block = tostring(info and info.block or ""):lower()
  if block == "" then return nil end
  if kw(block, APIARY)  then return "apiary"  end
  if kw(block, CHEST)   then return "chest"   end
  if kw(block, MACHINE) then return "machine" end
  return nil
end
S.kindOf = kindOf

-- A filing cabinet is a chest to validation (kind "chest") but a
-- library to detection: one item ID, hundreds of stacks. The name
-- decides, not the size -- what the transposer reports for its size
-- is the driver's business and has been seen well under 100.
function S.isCabinet(info)
  local block = tostring(info and info.block or ""):lower()
  return block ~= "" and kw(block, CABINET)
end

function S.sideName(side)
  return S.NAMES[side] or ("side " .. tostring(side))
end

function S.current()
  local a = {}
  for _, role in ipairs(S.ROLES) do
    local side = config[role.key]
    a[role.key] = S.isSet(side) and side or false
  end
  return a
end

--------------------------------------------------------------------
-- Is an assignment usable? Structure first (something there, no two
-- roles on one side), then the block name where we have one -- that
-- is what catches a chest and an apiary having been swapped.
--------------------------------------------------------------------
function S.validate(probe, assign)
  local problems, seen = {}, {}
  for _, role in ipairs(S.ROLES) do
    local side = assign[role.key]
    local info = S.isSet(side) and probe[side] or nil
    -- An unset optional role just uses the processing chest, which is
    -- not a fault and must not read as one. Sharing chestSide's side
    -- is that same fallback spelled out, so it is allowed too.
    if S.isSet(side) or not role.optional then
      if not info or not info.size then
        problems[#problems + 1] = ("%s: nothing on the %s side")
                                  :format(role.label, S.sideName(side))
      elseif seen[side] and not (role.optional and side == assign.chestSide) then
        problems[#problems + 1] = ("%s: shares the %s side with %s")
                                  :format(role.label, S.sideName(side), seen[side])
      else
        seen[side] = seen[side] or role.label
        local kind = kindOf(info)
        if kind and kind ~= role.kind then
          problems[#problems + 1] = ("%s: the %s side is %s")
                                    :format(role.label, S.sideName(side), info.block)
        elseif S.isCabinet(info) and not role.cabinet then
          -- A cabinet passes as a chest by kind, but a one-item-ID
          -- box can be neither the processing chest nor a bin.
          problems[#problems + 1] = ("%s: the %s side is a filing cabinet")
                                    :format(role.label, S.sideName(side))
        end
      end
    end
  end
  -- A cabinet nobody is using is a mistake in the making: the bees
  -- it was placed for would go to the processing chest instead.
  for side = 0, 5 do
    if probe[side] and probe[side].size and S.isCabinet(probe[side])
       and not seen[side] then
      problems[#problems + 1] = ("Filing cabinet on the %s side has no role")
                                :format(S.sideName(side))
    end
  end
  -- Two swaps no block name can see, because both sides hold the same
  -- block. `want` is the side the princesses belong in and `other`
  -- the one that only ever sees drones; both halves of the evidence
  -- are required, because a stray princess in the sorting chest on
  -- its own is the user's business, not a fault.
  local function swapped(want, other, why)
    local x, y = probe[assign[want]], probe[assign[other]]
    if x and y and x.size and y.size and assign[want] ~= assign[other]
       and y.princesses > 0 and x.princesses == 0 then
      problems[#problems + 1] = why
    end
  end
  swapped("chestSide", "sortChestSide",
          "Chests look swapped: the princesses are in the sorting chest")
  swapped("princessSide", "droneSide",
          "Cabinets look swapped: the princesses are in the drone cabinet")
  return #problems == 0, problems
end

-- Take an assignment for this run. config is shared by every module
-- (package.loaded), so this is all it takes -- no reboot. An optional
-- role explicitly set to false is CLEARED, not left as it was: that
-- is how the wiring screen retires a sorting chest.
function S.apply(assign)
  for _, role in ipairs(S.ROLES) do
    local side = assign[role.key]
    if S.isSet(side) then
      config[role.key] = side
    elseif role.optional and side == false then
      config[role.key] = nil
    end
  end
end

return S
