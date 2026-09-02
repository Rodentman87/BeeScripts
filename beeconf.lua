-- beeconf.lua  ->  install to /lib/beeconf.lua
-- Writing settings back into beeconfig.lua. That file is the user's:
-- the updater never overwrites it, it is full of comments worth
-- keeping, and it has to stay loadable or nothing boots. So only the
-- VALUE on a matching line is patched, the result is compiled before
-- anything is written, and the old file becomes a .bak.
--
-- Keys the file has never heard of (a setting added by an update)
-- are appended near the others rather than lost.

local conf = {}

local CANDIDATES = {"/lib/beeconfig.lua", "/home/lib/beeconfig.lua",
                    "/usr/lib/beeconfig.lua"}

function conf.path()
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

-- How a value is spelled in the file. A side is written as
-- `sides.north` when the config declares `local sides =` (as the
-- shipped one does) and as a bare number when it does not. `false`
-- is a value like any other: that is how an optional side is retired
-- so it stays retired across a reboot.
function conf.render(value, named)
  local t = type(value)
  if t == "number" or t == "boolean" then return tostring(value) end
  if t == "string" then return ("%q"):format(value) end
  if t == "table" and type(value.side) == "number" then
    if named then
      return "sides." .. (require("beesides").sideName(value.side))
    end
    return tostring(value.side)
  end
  return nil
end

local namedMemo = nil

local function usesNamedSides()
  if namedMemo ~= nil then return namedMemo end
  namedMemo = true
  local path = conf.path()
  local f = path and io.open(path, "r")
  if f then
    namedMemo = f:read("*a"):find("local%s+sides%s*=") ~= nil
    f:close()
  end
  return namedMemo
end

-- The lines conf.write would put in the file, for a preview. Returns
-- a list of "  key = value," strings in the given key order.
function conf.lines(changes, order)
  local named = usesNamedSides()
  local out = {}
  for _, key in ipairs(order or {}) do
    local rendered = changes[key] ~= nil and conf.render(changes[key], named)
    if rendered then
      out[#out + 1] = ("  %s = %s,"):format(key, rendered)
    end
  end
  return out
end

--------------------------------------------------------------------
-- changes = {key = value}. Values are numbers, booleans, strings or
-- {side = n}. Returns ok, pathOrError. On success the live `config`
-- table is updated too, so the running program sees the new values
-- without a reboot.
--------------------------------------------------------------------
function conf.write(changes, comment)
  local path, err = conf.path()
  if not path then return false, err end
  local f = io.open(path, "r")
  if not f then return false, "cannot read " .. path end
  local lines = {}
  for line in f:lines() do lines[#lines + 1] = line end
  f:close()
  local original = table.concat(lines, "\n") .. "\n"
  local named = original:find("local%s+sides%s*=") ~= nil

  local want = {}
  for key, value in pairs(changes) do
    local rendered = conf.render(value, named)
    if rendered then want[key] = rendered end
  end

  -- Patch in place. The value may be a number, true/false, a quoted
  -- string or sides.something, and whatever follows it (the comma and
  -- the comment that explains the setting) is kept exactly as it was.
  local lastHit = nil
  for i, line in ipairs(lines) do
    for key, name in pairs(want) do
      local head, tail = line:match(
        "^(%s*" .. key .. "%s*=%s*)\"[^\"]*\"(%s*,.*)$")
      if not head then
        head, tail = line:match("^(%s*" .. key .. "%s*=%s*)[%w_%.]+(.*)$")
      end
      if head then
        lines[i] = head .. name .. tail
        want[key] = nil
        lastHit = i
      end
    end
  end

  -- A config predating a setting has no line to patch: add one, next
  -- to the last thing we did touch so it lands among its relatives.
  local added = {}
  for key, name in pairs(want) do
    added[#added + 1] = ("  %s = %s,  -- %s"):format(key, name,
                        comment or "added by beebreeder")
  end
  table.sort(added)
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

  -- config is shared through package.loaded, so putting the values in
  -- it is all it takes for the running screens to see them.
  local live = require("beeconfig")
  for key, value in pairs(changes) do
    if type(value) == "table" and type(value.side) == "number" then
      live[key] = value.side
    else
      live[key] = value
    end
  end
  namedMemo = named
  return true, path
end

return conf
