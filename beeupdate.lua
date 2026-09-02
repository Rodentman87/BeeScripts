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
-- Every file is fetched to a staging path and compared with the
-- installed copy before anything is written (beefetch does that), so
-- the report says what actually changed rather than what was
-- overwritten -- and a failed fetch leaves the old file alone.
--
-- Setup: set BASE to your repo's raw-content URL, trailing slash
-- included, and make sure beefiles.txt sits next to the scripts.

local BASE = "https://raw.githubusercontent.com/Rodentman87/BeeScripts/refs/heads/main/"

local MANIFEST  = "beefiles.txt"
local LAST_LIST = "/home/beefiles.txt"  -- last good copy, kept as a fallback
local BOOT_LINE = "beehome"

local args = {...}
local dryRun = (args[1] == "list")

local fetch = require("beefetch")

-- The screen is optional in both directions: it may not be installed
-- yet on a first run, and there may be no GPU at all. Either way the
-- printed report says the same things.
local hasUi, ui = pcall(require, "beeupdui")
if hasUi then
  local ok, core = pcall(require, "beeui")
  hasUi = ok and core.hasGpu and core.isWide()
end

local function badLine(line) print("  skipping unreadable line: " .. line) end

local list, source = fetch.manifest(BASE, MANIFEST, LAST_LIST, badLine)
if not list then
  print("Could not read " .. MANIFEST .. " from " .. BASE)
  print("Check the Internet Card, the URL above, and that the file")
  print("exists in the repo. Nothing was changed.")
  return
end

if dryRun then
  print(("%d files listed (%s)"):format(#list, source))
  for _, e in ipairs(list) do
    print(("  %-16s -> %s%s"):format(e.src, e.dst, e.keep and "  (keep)" or ""))
  end
  print("List only -- nothing was changed.")
  return
end

--------------------------------------------------------------------
-- Reporting: the screen when there is one, plain lines when not.
--------------------------------------------------------------------
local WORD = {changed = "changed", unchanged = "same", new = "NEW",
              kept = "kept", failed = "FAILED", skipped = "skipped"}

local function printReport(event, a, b, c, d)
  if event == "start" then
    print(("%d files listed (%s)"):format(a, source))
  elseif event == "file" and c ~= "skipped" then
    print(("  %-18s %-8s %s"):format(b, WORD[c] or c, d or ""))
  elseif event == "done" then
    print(("Done: %d changed, %d new, %d unchanged, %d kept, %d failed.")
          :format(a.changed, a.new, a.unchanged, a.kept, a.failed))
    if a.failed > 0 then print("Re-run beeupdate to retry the failures.") end
    print(a.libChanged and "A /lib file changed -- reboot to load it."
          or "Nothing in /lib changed -- no reboot needed.")
  end
end

local report = printReport
if hasUi then
  ui.begin(BASE, #list, source)
  report = ui.report
end

local sum = fetch.all(BASE, list, report)

-- Boot into the home screen. Done after the install so the line only
-- appears once beehome is actually on disk, and only once ever.
local added, why = fetch.shrc(BOOT_LINE)
local bootNote = added and ("added `" .. BOOT_LINE .. "` to /home/.shrc")
                 or ("/home/.shrc: " .. tostring(why))

--------------------------------------------------------------------
if not hasUi then
  print(bootNote)
  return
end

while true do
  local choice = ui.wait(sum)
  if choice == "retry" and sum.failed > 0 then
    local only = {}
    for _, e in ipairs(sum.failedList) do only[e.src] = true end
    ui.begin(BASE, #list, source)
    local again = fetch.all(BASE, list, ui.report, only)
    -- A retry only knows about the files it retried, but a /lib
    -- module that changed on the first pass still means reboot.
    again.libChanged = again.libChanged or sum.libChanged
    sum = again
  elseif choice == "reboot" then
    ui.finish()
    print(bootNote)
    require("computer").shutdown(true)
    return
  else
    ui.finish()
    print(bootNote)
    if sum.libChanged then
      print("A /lib file changed -- reboot before running anything.")
    end
    return
  end
end
