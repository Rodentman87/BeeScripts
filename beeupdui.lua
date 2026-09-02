-- beeupdui.lua  ->  install to /lib/beeupdui.lua
-- The update screen: every file in the manifest with what actually
-- happened to it, a progress bar, the totals, and whether a /lib
-- module changed -- which means the module cache is stale and a
-- reboot is the difference between the new code running and not.
--
-- beeupdate works without this file (it may not be installed yet on
-- a first run) and falls back to printing the same lines.

local core   = require("beeui")
local config = require("beeconfig")
local frame  = require("beeframe")
local C, g = core.C, core.g

local updui = {}

local MARK = {changed = {"check", "good"}, unchanged = {"same", "dim2"},
              new = {"plus", "warn"}, kept = {"kept", "dim"},
              failed = {"fail", "bad"}, skipped = {"mid", "dim2"}}

local W, H, total, done = 160, 50, 0, 0
local COLS, ROWS = 3, 16
local log, logTop = {}, 28
local base = ""

local function colorOf(name) return C[name] or C.text end

local function addLog(text, color)
  log[#log + 1] = {text = text, color = color}
  local room = H - 3 - logTop
  while #log > room do table.remove(log, 1) end
  for i = 1, room do
    core.line(logTop + i - 1, log[i] and log[i].text or "",
              log[i] and log[i].color or C.text, W - 4, 2)
  end
end

local function bar()
  local w = W - 20
  local n = total > 0 and math.floor(w * done / total + 0.5) or 0
  core.fillRect(2, 4, n, 1, C.good)
  core.fillRect(2 + n, 4, w - n, 1, C.barEmpty)
  core.text(w + 4, 4, ("%d/%d"):format(done, total), C.good)
end

--------------------------------------------------------------------
function updui.begin(url, n, source)
  base = url
  core.begin()
  W, H = core.size()
  total, done, log = n, 0, {}
  logTop = math.min(28, H - 22)
  frame.header(g("update") .. " Update", {})
  core.text(2, 2, core.clip(url, W - 30), C.dim)
  core.text(W - 26, 2, ("%s %s  %d files"):format(g("check"),
            source or "repo", n), C.good)
  core.panel(1, logTop - 1, W, H - 3 - logTop + 2, "Log")
  bar()
end

-- One file's outcome, into its column and into the log
function updui.file(i, name, st, detail)
  done = i
  local mark = MARK[st] or MARK.skipped
  local col = math.floor((i - 1) / ROWS) % COLS
  local row = 6 + (i - 1) % ROWS
  local x = 3 + col * math.floor((W - 6) / COLS)
  if row < logTop - 2 then
    core.text(x, row, g(mark[1]), colorOf(mark[2]))
    core.text(x + 2, row, core.clip(name, 15),
              st == "unchanged" and C.dim or C.text)
    core.text(x + 18, row, core.clip(detail or "", 18),
              st == "unchanged" and C.dim2 or colorOf(mark[2]))
  end
  if st ~= "unchanged" and st ~= "skipped" then
    addLog(("%s %s %s"):format(name, g(mark[1]), detail or ""), colorOf(mark[2]))
  end
  bar()
end

function updui.done(sum)
  local row = logTop - 5
  core.text(3, row, ("%s %d changed    %s %d new    %s %d unchanged    %s %d kept    %s %d failed")
            :format(g("check"), sum.changed, g("plus"), sum.new, g("same"),
                    sum.unchanged, g("kept"), sum.kept, g("fail"), sum.failed),
            C.text)
  core.line(row + 2, sum.libChanged
            and (g("warn") .. " /lib changed -- reboot to load it")
            or (g("check") .. " nothing in /lib changed -- no reboot needed"),
            sum.libChanged and C.warn or C.good)
  if sum.failed > 0 then
    core.text(60, row + 2, ("%s %d failed -- installed copies untouched")
              :format(g("fail"), sum.failed), C.bad)
  end
  addLog(("%d files %s %ds"):format(sum.total, g("mid"),
         math.floor(sum.secs or 0)), C.text)
end

-- The callback beeupdate hands to beefetch
function updui.report(event, a, b, c, d)
  if event == "file" then
    updui.file(a, b, c, d)
  elseif event == "done" then
    updui.done(a)
  end
end

--------------------------------------------------------------------
-- Wait for the user. Returns "reboot", "retry" or "home".
--------------------------------------------------------------------
function updui.wait(sum)
  local state
  frame.bar(H, {
    {id = "reboot", label = "[ " .. g("rescan") .. " REBOOT ]",
     bg = sum.libChanged and C.good or C.barEmpty,
     fg = sum.libChanged and C.headerFg or C.text,
     onPress = function() state = "reboot" end},
    {id = "retry", label = "[ " .. g("retry") .. " RETRY FAILED ]",
     bg = sum.failed > 0 and C.warn or C.barEmpty,
     fg = sum.failed > 0 and C.headerFg or C.dim,
     onPress = function() if sum.failed > 0 then state = "retry" end end},
    {id = "home", label = "[ " .. g("left") .. " HOME ]",
     onPress = function() state = "home" end},
  })
  frame.hint("home")
  core.setKeyHandler(function(_, code)
    if code == core.keys.q then state = "home" end
  end)
  while not state do core.pump(config.animDelay or 0.5) end
  core.setKeyHandler(nil)
  return state
end

function updui.finish() core.finish() end

return updui
