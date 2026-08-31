-- beeupdate.lua  ->  install to /home/beeupdate.lua
-- One-command updater: pulls the latest bee scripts from your repo.
-- Requires an Internet Card.
--
-- The file list lives in the REPO, not in here: beefiles.txt names
-- every source and where it installs. Adding a module means adding
-- a line there -- this script never needs re-deploying for it.
-- (It does list itself, so bug fixes to the updater still arrive.)
--
--   beeupdate         fetch beefiles.txt, then install everything
--   beeupdate list    show what would happen, change nothing
--
-- Setup: set BASE to your repo's raw-content URL, trailing slash
-- included, and make sure beefiles.txt sits next to the scripts.

local shell      = require("shell")
local filesystem = require("filesystem")

local BASE = "https://raw.githubusercontent.com/Rodentman87/BeeScripts/refs/heads/main/"

local MANIFEST  = "beefiles.txt"
local TMP_LIST  = "/tmp/beefiles.txt"
local LAST_LIST = "/home/beefiles.txt"  -- last good copy, kept as a fallback

local args = {...}
local dryRun = (args[1] == "list")

local function fetch(src, dst, force)
  local flag = force and "-f " or ""
  return shell.execute("wget " .. flag .. BASE .. src .. " " .. dst)
end

-- One entry per line:  <source>  <install path>  [keep]
-- Anything blank or starting with # is a comment. A malformed line
-- is reported and skipped rather than quietly dropped -- a typo in
-- the manifest should not silently stop a module from updating.
local function parse(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local list = {}
  for line in f:lines() do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and line:sub(1, 1) ~= "#" then
      local src, dst, flag = line:match("^(%S+)%s+(%S+)%s*(%S*)")
      if src and dst and dst:sub(1, 1) == "/" then
        list[#list + 1] = {src = src, dst = dst, keep = (flag == "keep")}
      else
        print("  skipping unreadable line: " .. line)
      end
    end
  end
  f:close()
  return list
end

-- The manifest itself comes from the repo. A cached copy of the last
-- good one is kept so a flaky connection leaves you able to update
-- rather than stranded with no list at all.
local function manifest()
  print("fetching " .. MANIFEST)
  if fetch(MANIFEST, TMP_LIST, true) then
    local list = parse(TMP_LIST)
    if list and #list > 0 then
      pcall(filesystem.copy, TMP_LIST, LAST_LIST)
      return list, "from the repo"
    end
    print("  " .. MANIFEST .. " downloaded but has no usable entries")
  end
  local cached = parse(LAST_LIST)
  if cached and #cached > 0 then return cached, "from the last good copy" end
  return nil
end

local list, source = manifest()
if not list then
  print("Could not read " .. MANIFEST .. " from " .. BASE)
  print("Check the Internet Card, the URL above, and that the file")
  print("exists in the repo. Nothing was changed.")
  return
end
print(("%d files listed (%s)"):format(#list, source))

local updated, kept, failed = 0, 0, 0
for _, e in ipairs(list) do
  if e.keep and filesystem.exists(e.dst) then
    print("keeping " .. e.dst)
    kept = kept + 1
  elseif dryRun then
    print(("would fetch %-16s -> %s"):format(e.src, e.dst))
  else
    local dir = filesystem.path(e.dst)
    if dir and not filesystem.exists(dir) then
      filesystem.makeDirectory(dir)
    end
    print("fetching " .. e.src)
    if fetch(e.src, e.dst, true) then
      updated = updated + 1
    else
      print("  FAILED: " .. e.src)
      failed = failed + 1
    end
  end
end

if dryRun then
  print("List only -- nothing was changed.")
  return
end
print(("Done: %d updated, %d kept, %d failed."):format(updated, kept, failed))
if failed > 0 then
  print("Re-run beeupdate to retry the failures.")
end
print("Reboot (or clear package.loaded) to pick up new libs.")
