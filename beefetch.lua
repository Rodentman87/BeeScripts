-- beefetch.lua  ->  install to /lib/beefetch.lua
-- The updater's engine: fetch every file in the manifest to a staging
-- path, compare it byte for byte with the installed copy, and only
-- then write. That is what lets the update screen say what actually
-- CHANGED -- wget on its own overwrites blindly, and a silent failure
-- then looks exactly like a successful no-op.
--
-- A failed fetch never touches the installed file. That is the whole
-- point of staging: a flaky connection can leave you with an older
-- BeeScripts, never with half of one.

local shell      = require("shell")
local filesystem = require("filesystem")
local computer   = require("computer")

local fetch = {}

-- /tmp is a tmpfs on OpenOS, but do not bet the update on it existing
fetch.STAGE = filesystem.exists("/tmp") and "/tmp/beeup/" or "/home/.beeup/"

local function sizeOf(path)
  if not filesystem.exists(path) then return nil end
  local ok, n = pcall(filesystem.size, path)
  return ok and n or nil
end
fetch.sizeOf = sizeOf

function fetch.kb(n)
  if not n then return "?" end
  return ("%.1fk"):format(n / 1024)
end

local function ensureDir(path)
  if path and path ~= "" and not filesystem.exists(path) then
    filesystem.makeDirectory(path)
  end
end

-- Staging holds ONE file, not a release: /tmp is a small tmpfs and a
-- manifest's worth of scripts fills it, after which wget starts
-- failing on files that were never the problem. So every path out of
-- a fetch drops its staging copy (that is what `done` is for), and
-- the walk sweeps the directory first in case a run was interrupted.
local function drop(path)
  if path and filesystem.exists(path) then pcall(filesystem.remove, path) end
end

local function done(tmp, status, detail)
  drop(tmp)
  return status, detail
end

function fetch.clear()
  local ok, iter = pcall(filesystem.list, fetch.STAGE)
  if ok and iter then for name in iter do drop(fetch.STAGE .. name) end end
end

-- Byte for byte, sizes first: two files of different lengths cannot
-- be the same, and that check alone settles almost every file.
local function identical(a, b)
  local sa, sb = sizeOf(a), sizeOf(b)
  if not sa or not sb or sa ~= sb then return false end
  local fa = io.open(a, "rb")
  if not fa then return false end
  local fb = io.open(b, "rb")
  if not fb then fa:close() return false end
  local same = true
  while true do
    local ba, bb = fa:read(2048), fb:read(2048)
    if ba ~= bb then same = false break end
    if ba == nil then break end
  end
  fa:close()
  fb:close()
  return same
end

--------------------------------------------------------------------
-- One entry per line:  <source>  <install path>  [keep]
-- A malformed line is reported and skipped rather than quietly
-- dropped -- a typo in the manifest should not silently stop a module
-- from ever updating again.
--------------------------------------------------------------------
function fetch.parse(path, onBad)
  local f = io.open(path, "r")
  if not f then return nil end
  local list = {}
  for line in f:lines() do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and line:sub(1, 1) ~= "#" then
      local src, dst, flag = line:match("^(%S+)%s+(%S+)%s*(%S*)")
      if src and dst and dst:sub(1, 1) == "/" then
        list[#list + 1] = {src = src, dst = dst, keep = (flag == "keep")}
      elseif onBad then
        onBad(line)
      end
    end
  end
  f:close()
  return list
end

-- The manifest comes from the repo; a copy of the last good one is
-- kept so a flaky connection leaves you able to update rather than
-- stranded with no list at all.
function fetch.manifest(base, name, cache, onBad)
  local tmp = fetch.STAGE .. "manifest.txt"
  ensureDir(fetch.STAGE)
  -- A stale copy from an earlier run would masquerade as a fresh one
  drop(tmp)
  if shell.execute("wget -fq " .. base .. name .. " " .. tmp) then
    local list = fetch.parse(tmp, onBad)
    if list and #list > 0 then
      pcall(filesystem.copy, tmp, cache)
      return list, "from the repo"
    end
  end
  local old = fetch.parse(cache, onBad)
  if old and #old > 0 then return old, "from the last good copy" end
  return nil
end

--------------------------------------------------------------------
-- Fetch and install one entry. Returns status, detail:
--   changed / new / unchanged / kept / failed
--------------------------------------------------------------------
function fetch.one(base, e)
  if e.keep and filesystem.exists(e.dst) then return "kept", "kept" end
  ensureDir(fetch.STAGE)
  local tmp = fetch.STAGE .. e.src:gsub("[/\\]", "_")
  drop(tmp)
  local ok = shell.execute("wget -fq " .. base .. e.src .. " " .. tmp)
  local got = sizeOf(tmp)
  if not ok or not got or got == 0 then
    return done(tmp, "failed", "wget failed -- old copy kept")
  end
  local before = sizeOf(e.dst)
  if before and identical(tmp, e.dst) then
    return done(tmp, "unchanged", fetch.kb(got))
  end
  ensureDir(filesystem.path(e.dst))
  if filesystem.exists(e.dst) then pcall(filesystem.remove, e.dst) end
  local copied = pcall(filesystem.copy, tmp, e.dst)
  if not copied or (sizeOf(e.dst) or 0) == 0 then
    return done(tmp, "failed", "could not write " .. e.dst)
  end
  if before then
    return done(tmp, "changed", fetch.kb(before) .. " -> " .. fetch.kb(got))
  end
  return done(tmp, "new", "new " .. fetch.kb(got))
end

-- Walk the manifest. report(event, ...) gets "start" (n), "file"
-- (i, src, status, detail) and "done" (summary). `only` is a set of
-- sources to retry; nil means all of them.
function fetch.all(base, list, report, only)
  local sum = {changed = 0, new = 0, unchanged = 0, kept = 0, failed = 0,
               libChanged = false, failedList = {}, total = #list}
  local t0 = computer.uptime()
  fetch.clear()       -- whatever an interrupted run left in staging
  report("start", #list)
  for i, e in ipairs(list) do
    if only and not only[e.src] then
      report("file", i, e.src, "skipped")
    else
      local st, detail = fetch.one(base, e)
      sum[st] = (sum[st] or 0) + 1
      if st == "failed" then sum.failedList[#sum.failedList + 1] = e end
      if (st == "changed" or st == "new") and e.dst:sub(1, 4) == "/lib" then
        sum.libChanged = true
      end
      report("file", i, e.src, st, detail)
    end
  end
  sum.secs = computer.uptime() - t0
  report("done", sum)
  return sum
end

-- Boot straight into the home screen: one line in /home/.shrc, added
-- only when it is not there already, file created when it is missing.
-- Returns true + path when it wrote, false + why when it did not.
function fetch.shrc(line)
  local path = "/home/.shrc"
  local f = io.open(path, "r")
  if f then
    local body = f:read("*a") or ""
    f:close()
    for l in body:gmatch("[^\n]+") do
      if l:gsub("%s", "") == line then return false, "already there" end
    end
  end
  local out = io.open(path, "a")
  if not out then return false, "cannot write " .. path end
  out:write(line .. "\n")
  out:close()
  return true, path
end

return fetch
