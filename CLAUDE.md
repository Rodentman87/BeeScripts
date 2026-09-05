# BeeScripts — GTNH Bee Breeding Automation

OpenComputers Lua programs that automate Forestry bee breeding in
GregTech: New Horizons (Minecraft 1.7.10). They run on an in-game
computer; this repo is the source of truth, deployed in-game via
`beeupdate` (wget from raw.githubusercontent.com, BASE url set in
beeupdate.lua, file list read from `beefiles.txt` in the repo).

## Environment & constraints — read before writing code

- **Target is OpenOS (Lua 5.2/5.3-ish) inside Minecraft.** Only OpenOS
  APIs exist: `component`, `event`, `term`, `computer`, `keyboard`,
  `sides`, `serialization`, `filesystem`, `robot` (robot only). No
  LuaRocks, no io beyond basics, no coroutine-heavy patterns needed.
- **The sandbox drops some standard globals** — `collectgarbage` is
  nil here, and calling it is a runtime error, not a no-op. Guard
  anything outside the list above (`if collectgarbage then ... end`)
  rather than assuming stock Lua. Memory is reclaimed by dropping
  references; there is no way to force a collection.
- **Nothing here can be executed outside the game.** There is no test
  harness. Validate with `perl tools/check.pl` (block-balance + line
  counts + manifest drift over all .lua files; `python3 tools/check.py`
  is the same check where Python exists) and careful review. When
  logic is intricate (e.g. the planner, the stock gate), port it to
  Python and test the port, or desk-check it against a worked example
  — that is how beeplanner.lua and beebank.lua were validated.
- **Keep every file under ~200 lines.** Historical reason was in-game
  paste corruption; it remains good discipline and some flows still
  paste (the robot).
- **Module caching:** OpenOS caches `require`d modules per shell
  session. After changing any /lib file in-game, `reboot` (or clear
  `package.loaded`). Many "bugs" have been stale caches.
- **Deployment layout lives in `beefiles.txt`**, not in code:
  `<source> <install path> [keep]`, one per line. beeupdate fetches
  that manifest first and installs whatever it names, so **adding a
  module means adding a line there** — nothing else. Entry points go
  to `/home` (beehome, beebreeder, beeprobe, beeplan, beeupdate),
  libraries to `/lib` (first on package.path). `beeupdate` lists
  itself, so it self-updates, and stays LAST in the manifest.
  `beebot.lua` is deliberately absent: it is installed by hand on the
  ROBOT's filesystem, not the PC's. A full checker run fails on
  manifest drift.
- **beeconfig.lua is user-edited and never overwritten** by the
  updater (the `keep` flag: fetched only if missing). New config keys
  must have in-code defaults (`config.key or default`) because
  deployed configs won't have them.

## Hardware this code assumes

Tier 3 case, T1 CPU, T3 GPU + a 2x3 wall of T3 screens (160x50, 256
colors, touch), a Transposer touching: processing chest, Apiary, GT Scanner (analyzes
bees), sorting chest (hybrid sweep destination). An Adapter touches
the apiary exposing `tile_for_apiculture_0_name` (getBeeBreedingData,
listAllSpecies). Computronics Chat Box for notifications. Network
card + a robot ("beebot": inventory + inventory controller upgrades,
network card, pickaxe) parked facing the block under the apiary for
foundation swapping. Sides are configured in beeconfig.lua.

**Storage has two shapes and the code supports both.** Classic: one
processing chest (`chestSide`) plus an optional sorting chest.
Split: two Extra Utilities filing cabinets — one item ID each, so one
holds every princess and the other every drone (`princessSide`,
`droneSide`, ~540 slots) — plus a dump chest for combs (`dumpSide`).
All three are optional and each falls back to `chestSide`, so an
untouched classic config behaves bit-for-bit as it always did. Six
sides is the budget: apiary, scanner and the storage roles have to
share them, which is why `dumpSide` may sit on `chestSide` and why
the sorting chest is retired once cabinets are in use. Cabinets
**re-sort on every insert or removal**, so a slot number from a scan
is fiction after the first transfer on that side: re-find, never
reuse a slot list.

UI code must degrade: colors quantize on T2 (16-color) and mono T1;
all layout derives from `gpu.getResolution()`; headless falls back to
`print`. Two dashboard layouts exist and `beedash` picks one by
width: `beecompact` (80x25) and `beewide` (120+ columns, built for
160x50). The BeeHome screens (home, breed, settings, update) are
160x50 only and say so rather than folding badly: on anything
narrower `beehome` prints a library summary and hands over to the
CLI, and `beebreeder` with no args falls back to `beesetup`. On depth 8 the fixed 240-color cube has NO greys, so
`beetheme` puts greys in palette slots 0-7 and exact accent colors
(gold tile, glint, the current step's species) in 8-15; lower tiers
keep their stock palette. Every non-ASCII glyph goes through
`beetheme.g(name)` so a font gap is one config line away from fixed
(`beeprobe glyphs` shows them all). Widths are measured with
`unicode.len`, never `#`, because box drawing is multi-byte.

## Module map

Boot flow: `beehome` (the screen the computer boots into) → the
library, restocks, and launchers for everything else.
Engine flow: `beebreeder` (entry/args/setup launch) → `beerun` (loop:
scan → analyze → evaluate → cross) → `beestep` (per-cycle brains:
replan, announce, route pane, foundation upkeep, stagnation
watchdog) with `beegate` choosing each cycle's pair.

- `beeconfig` — user settings (sides, delays, goals, floors, robot,
  shimmer, hive climate, home screen). `beeconf` — reads, patches,
  compile-checks and writes any scalar key back into beeconfig,
  keeping the comments and a .bak; `beedetect.save` is one caller
  and the settings screen is the other.
- `beegenes` — pure genetics logic, no hardware: genome reading,
  scoring, isWinner/countTarget (purity-aware), pickPair (greedy,
  fertility-aware), pickCross (recipe → convert → greedy tiers).
- `beestock` — pure bookkeeping for the stock floors: tally by active
  species, low/ok/surplus, is-this-pair-safe, restock plans.
  `beebank` — pure: the ladder that replaces an unsafe cross with one
  that banks or converts instead. `beegate` — the engine's side of
  both: pick the pair, run the ladder, log/chat the note once, and
  decide what "done" means for a restock run.
- `beeyard` — the apiary and the scanner (insert, wait, recover,
  empty the output slots); screen-ignorant, reports via callbacks;
  `yard.sleep` is injected (ui.sleep) so waits are input-aware.
  `beestore` — the bee library behind it: which side keeps what
  (`sides()`), the lazy `getAllStacks` scan with a slot-loop
  fallback, and the hybrid sweep. beeyard re-exports it all.
  `beeexport` — the other direction: EXPORT breeds a species one over
  its floors with purity forced on for that run, moves a pure
  princess and a pure drone to the dump chest (for a bee house), and
  restocks the line when the princess who left was the last one.
- `beeattach` — what is attached to each transposer side (size,
  block name, bee counts). `beesides` — the roles, validate/apply of
  a role→side assignment, `isCabinet` (by block name:
  `tile.extrautils:filing`); re-exports beeattach. `beedetect` —
  scores sides against roles, decides when it is sure enough to act,
  and writes the result through beeconf. `beewire` — the wiring
  screen and its headless report. Apiary and scanner are named by
  their block; chests are told apart by contents (princesses mark
  the processing chest). A cabinet is a chest to validation but never
  a plain-chest role: its contents say princess or drone cabinet, an
  EMPTY cabinet cannot be told and is left for the wiring screen, and
  a cabinet sitting in a chest role or with no role fails validation
  so startup re-detects. Optional roles need real evidence or they
  stay unset. Everything short of "sure" asks.
- `beeplanner` — AND-graph cost search over the mutation cache; cost
  = expected cycles (100/chance); memoized, cycle-guarded.
- `beedata` — extraction/caching of the mutation registry (one-time
  RAM-heavy call) to /home/beedata/mutations.dat: one mutation per
  line, `parentA|parentB|result|chance|conditions`. Exports
  `apiculture()`/`ensureDir()`/`field()` for beespecies and beeyard.
- `beespecies` — same idea for `listAllSpecies`, caching each
  species' preferred climate to /home/beedata/species.dat as
  `name|temperature|humidity`. Values are stored exactly as the
  registry spells them; beeclimate does the interpreting, so a pack
  that says HELLISH and one that says Hellish both work.
- `beeclimate` — climate model: scales, tolerance alleles, genome
  tolerance reading, hive climate (detected or configured),
  suitability verdicts, partner ranking, planner surcharge.
  `beeadvice` — the wording of a mismatch (one-liner, tolerance
  prescription, how to fix it); pure string work, no requires.
- `beedump` — `beebreeder dump`: one bee's raw genome to a file plus
  a field summary. The fastest way to check this pack's driver field
  names, especially the tolerance alleles.
- `beeprobe` / `beeplan` — CLI tools: registry probing/building and
  offline route planning.
- `beeui` — core UI toolkit: colors, primitives (`core.segs`
  multi-color row renderer with an x-origin, `core.panel` titled
  box), unicode-aware `core.len/sub/clip`, `core.g` glyphs. Buttons
  and the event pump live in `beeinput` (keys + touch; Q = halt
  unless a key handler is set) and are re-exported. `beetheme` —
  glyph table with ASCII fallbacks and the depth-8 palette plan.
- `beesegs` — species-colored segment system + shared wall-clock
  shimmer (traveling 2-char purple window over glint species;
  `segs.tick()` is idempotent per time step). Segments may carry
  `bg`/`bgSpecies`; rows are keyed by origin so two panes share a row.
- `beedash` — facade: forwards every call to the layout that fits
  the screen, no-op for methods a layout lacks. `beecompact` — the
  80x25 dashboard. `beewide` — the 160x50 frame (header icon strip,
  status, control bar with pause / chat / pure / goal / log paging)
  delegating to `beeroute` (route pane), `beecross` (Punnett pane),
  `beehive` (queen, bee on a learned progress bar, ETA), `beepanes`
  (bank bars, lineage strip, chest stock, climate row), `beelog`
  (scrollback). `beesetup` — touch setup screens (search picker,
  settings). `beepreview` — plan preview pane on the settings screen.
- `beetree` — pure: plan steps → node tree (`build`: owned species
  are leaves, repeats become `↑` refs) → indented segment rows
  (`rows`, `fit`, `summary`). `beepedigree` — tidy layout of that
  tree as one dot per species (gold tile = exists, inverted pulsing
  = working) and its painter. `beepunnett` — pure: 2x2 allele square
  for a pair with the mutations each cell can trigger, plus odds.
- **BeeHome screens** (160x50 only; narrower screens get a printed
  summary and the CLI). `beeframe` — the chrome all four share:
  header + icon strip, divider, group rules, control bar, Q hint.
  `beehome` — the entry point: autoheal, boot, main loop.
  `beehomeact` — everything it does (scan, repaint, run, restock,
  sub-screens); buttons only ever name what they want, and the loop
  acts between ticks. `beehomeui` — the panes. `beepop` — pure: the
  library as rows, totals and an Attention list. `beestatus` — the
  part only hardware knows (cache ages, side fill, apiary state,
  wiring, climate). `beeswarm` — the meadow, drawn from the last
  scan and never from the transposer. `beerecent` — the event ring.
- `beecfgui` + `beeedit` + `beefields` — the settings screen: one
  table of typed fields, a working copy edited until SAVE, changed
  values in gold, and the exact lines beeconf will write.
- `beebreedui` + `beecands` + `beebrief` + `beepick` — the breed
  screen. `beepick` is pure (one-step and two-step candidates,
  seasons, distance); `beecands` draws the three lists; `beebrief`
  draws the Preview (tree, restock prefix, recipe, conditions,
  total, pedigree).
- `beefetch` + `beeupdui` — the updater: fetch to staging, compare
  byte for byte, install only what changed, report through a
  callback that is either the screen or `print`.
- `beecolors` — GENERATED: 466 species → {color, glint}, extracted
  from mod source files (Forestry/ExtraBees/MagicBees/GT5U bee
  definition enums) by a Python parser; unknown species get a stable
  hashed color. To regenerate, re-run a parser over those Java files
  (see git history / ask the user for them). Duplicate names across
  mods: GregTech wins (emitted last).
- `beechat` — chat box notifications; no-ops without the box; never
  throws. `beefound` + `beebot` — foundation automation: PC parses
  "Requires X as a foundation" from step conditions, broadcasts on
  port 4477; robot swaps the block by inventory label match.

## Load-bearing semantics (violate at your peril)

- Everything keys on species **display names** (registry, scanner,
  palette all agree on them).
- "**Exists**" (some bee actively expresses a species) vs
  "**finished**" (purity-checked princess + drone bank) are different
  milestones. The planner runs on exists — that's what enables
  replanning-every-cycle, self-healing, and lucky skips. Success and
  drone counting run on finished (isWinner respects requirePure).
  Never display exists-vocabulary where users read finished (the
  Done list deliberately excludes the overall target).
- The planner replans from live chest state every cycle; state that
  must persist across replans (doneSteps, stagnation counters) lives
  in beestep module-locals with an explicit reset().
- **A queen carries the PRINCESS's genome** (the drone contributes
  only to the offspring). So whether the hive ticks at all is decided
  by the princess alone: pick a princess this climate can house, or
  she freezes in the apiary and `yard.waitForCycle` waits forever.
  That is why climate.rank scores princesses on "works here" and
  drones purely on "donates tolerance".
- A species' preferred climate is fixed by its species allele and is
  NOT breedable; **tolerance** is the heritable part. Every "make it
  work at Normal/Normal" path therefore ends in either a tolerance
  allele or an alveary block. Warnings must never imply otherwise.
- Climate data is best-effort: unknown species, unparseable values
  and unreadable tolerance alleles all resolve to "no opinion", and
  everything downstream stays silent rather than warning wrongly.
  With no species cache, climate.rank is constant and pair ordering
  is bit-for-bit what it was before climate existed.
- Princesses are the scarce resource. pickCross's convert tier exists
  to steer the princess line toward recipe parents rather than
  greedy-crossing it away; fertility-1 economies spend fuel drones,
  not banked target drones.
- **Stock floors apply to EVERY species present**, not only the ones
  in the current plan: `princessFloor` (1) princesses and
  `droneFloor` (4) drones each. Anything above a floor is "surplus",
  and surplus is the only thing a cross is allowed to spend — that
  replaces the old idea of a fuel species, so there is no fuel key
  and no needs set. A princess is never consumed, only transformed,
  so a line is lost only when the LAST princess of a species goes
  under a foreign drone; a drone is consumed outright. That is why
  the gate's two triggers are "this drone was holding the floor" and
  "this is her last princess and the drone is foreign".
- **The gate runs after the planner and after pair selection, never
  inside them.** The planner still works on "exists", which is what
  makes replanning every cycle, self-healing and lucky skips work;
  the gate only ever swaps the pair that was about to be bred.
- config is mutated at runtime and `run.start` writes its drone goal
  through to `config.droneGoal` on purpose (every screen reads it
  live) — a caller that wants its old value back saves it first, as
  beehomeact does around every run.
- config is mutated at runtime (chat toggle button, setup screen
  choices) — modules read it live, don't snapshot values.

## In-game workflow

The computer **boots into `beehome`** (beeupdate appends that line to
/home/.shrc once). From there: BREED opens the breed screen (or
beesetup on a narrow one) and runs it, EXPORT is that same screen
ending with a pure pair in the dump chest, RESTOCK LOW walks every
species under its floor, AUTO-TEND does that by itself whenever the
apiary is idle, SETTINGS edits beeconfig in place, WIRING opens the
wiring screen, UPDATE runs beeupdate, SHELL and Q drop out.

The CLI is unchanged. `beeprobe` (format sample) → `beeprobe build`
(mutation + species climate caches) → `beebreeder` (no args = the
picker with a plan preview; or `beebreeder <Species>`; `dump` writes
one bee's raw data; `direct` skips the planner; `sides` opens the
wiring screen). Every `beebreeder` and `beehome` start checks the
transposer sides against the world first and heals a moved build;
`beeprobe sides [save]` is the headless view of the same.
`beeplan <Species>` plans without running. `beeupdate` pulls this
repo, comparing each file with the installed copy before writing so
the report says what actually changed. Q or the HALT button stops
gracefully; startup recovers mid-cycle queens automatically.

## Known gaps / ideas parked

- Planner doesn't model princess-side availability (pickCross's
  convert tier compensates); could cost conversions in the search.
- Setup screen "other gene targets" (fertility, speed, etc. beyond
  species) — designed for, not built; genes.score is the extension
  point.
- Climate: the planner's surcharge is per-species and flat; it could
  instead cost the alveary blocks a route would need. Tolerance is
  never a *goal*, only a tiebreak — a real "breed Both 3 into this
  line" mode would need genes.score to carry non-species targets.
- Climate detection depends on the apiculture tile exposing
  getTemperature/getHumidity, which is a guess — `beeprobe climate`
  sweeps every climate-ish method and shows raw returns. If the
  driver has none, beeconfig is the whole source of truth (fine for
  an alveary, where you set the climate yourself). A method that
  answers with a NUMBER is currently dropped: mapping an enum
  ordinal needs to know its base, and guessing wrong would warn
  wrongly. Map it for real once a real return value is in hand.
- Wide dashboard follow-ups: species inspector popup (touch a name
  for its climate and the mutations that make it — the Population
  table is where it earns its place), sounds. The glyph set still
  needs a real-font check via `beeprobe glyphs`, and the new icons
  have never been seen in a real font at all.
- Chat box could listen (chat_message events) for remote commands.
- Nothing about a filing cabinet has been verified in game: what the
  transposer reports for its size and block name, whether it accepts
  an unanalyzed bee, and whether `getAllStacks` exists on this OC
  build. All three are coded defensively (unknown name and size,
  dump-side fallback on a refused insert, slot-loop fallback), but
  the first run should check them — see the end of PLAN-beehome.md.
- The home screen has no 80x25 layout: narrow and headless setups
  get a printed summary and the CLI. A folded-down version is
  possible; the panes are already geometry-driven.
- `beestatus` compares `filesystem.lastModified` (real-world ms) with
  `os.time()`, which means different things on different OpenOS
  builds. Where they disagree the cache age reads "?" rather than
  something wrong; a build-specific clock would fix it properly.
- The stock gate is per-cycle and greedy. It cannot see that two
  species are about to go low at once, and the restock preview costs
  each species independently.
