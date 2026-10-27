local t = require("t")
local H = require("harness")
local data = require("data")
local util = require("util")
local ui_validator = require("ui_validator")

t.case("wild encounters are tracked per zone with names and types read from the core", function()
  local mock, tr, core = H.boot()
  core.encounter(21); core.encounter(22); core.encounter(21)
  H.settle(mock)
  local d = tr.data
  t.eq(data.area(d, 5).wild.s21f0.n, 2)
  t.eq(data.area(d, 5).wild.s22f0.n, 1)
  local list = H.find(mock, "panel", "p_wild")
  t.eq(#list.rows, 2)
  t.eq(list.rows[1].title, "Demomon 21")
  local types = core.types_of(21)
  t.eq(list.rows[1].sub, "Demotype " .. types[1] .. " / Demotype " .. types[2])
  t.eq(list.rows[1].meta, "seen 2x")
  t.eq(H.find(mock, "panel", "p_area").title, "Demoplace 100")
end)

t.case("nothing is stored but ids: no names, no types", function()
  local mock, tr, core = H.boot()
  core.encounter(21)
  core.start_battle("trainer", { 30 })
  H.settle(mock)
  H.settle(mock)
  local text = util.ser(H.stored(mock))
  t.ok(not text:find("Demo", 1, true), "names stay out of the store")
  t.ok(H.stored(mock).areas.z5.wild.s21f0)
end)

t.case("encounters are counted once (by seq) and in the zone they happened in", function()
  local mock, tr, core = H.boot()
  core.encounter(21)
  H.settle(mock, 3)
  t.eq(data.area(tr.data, 5).wild.s21f0.n, 1)
  core.zone = 7
  core.encounter(21, { shiny = true })
  core.encounter(25, { zone = 9 }) -- an old entry from another zone keeps its own zone
  H.settle(mock)
  t.eq(data.area(tr.data, 7).wild.s21f0.n, 1)
  t.eq(data.area(tr.data, 7).wild.s21f0.shiny, true)
  t.eq(data.area(tr.data, 9).wild.s25f0.n, 1)
  t.eq(data.area(tr.data, 5).wild.s21f0.n, 1)
end)

t.case("the core's encounter event polls at once", function()
  local mock, tr, core = H.boot()
  core.encounter(21)
  mock.fire_event("uzume.soullink-core", "encounter", { species = 21 })
  t.eq(data.area(tr.data, 5).wild.s21f0.n, 1)
  mock.fire_event("someone.else", "encounter", {})
end)

t.case("current area first; visiting marks areas", function()
  local mock, tr, core = H.boot()
  H.settle(mock)
  t.ok(data.area(tr.data, 5).visited)
  t.eq(H.find(mock, "panel", "p_area").title, "Demoplace 100")
  core.zone = 7
  H.settle(mock)
  t.eq(H.find(mock, "panel", "p_area").title, "Demoplace 101")
  t.ok(data.area(tr.data, 7).visited)
  t.ok(data.area(tr.data, 5).visited)
end)

t.case("trainer species are seen once per battle, only active foes", function()
  local mock, tr, core = H.boot()
  core.start_battle("trainer", { 30 })
  H.settle(mock, 2)
  t.eq(data.area(tr.data, 5).trainers.s30f0.n, 1)
  core.battle.foes[#core.battle.foes + 1] = { species = 31, form = 0, level = 6, hp = 9, max_hp = 9 }
  H.settle(mock, 2)
  t.eq(data.area(tr.data, 5).trainers.s31f0.n, 1)
  t.eq(data.area(tr.data, 5).trainers.s30f0.n, 1)
  core.end_battle()
  H.settle(mock)
  core.start_battle("trainer", { 30 })
  H.settle(mock, 2)
  t.eq(data.area(tr.data, 5).trainers.s30f0.n, 2)
  t.eq(next(data.area(tr.data, 5).wild), nil, "trainer Pokemon are not wild encounters")
  local rows = H.find(mock, "panel", "p_trainers").rows
  t.eq(#rows, 2)
end)

t.case("catch: the team gains the species after the wild battle", function()
  local mock, tr, core = H.boot()
  core.team = { { species = 1, form = 0 } }
  core.encounter(21)
  core.start_battle("wild", { 21 })
  H.settle(mock, 6) -- the census before the battle runs while it goes on
  core.team = { { species = 1, form = 0 }, { species = 21, form = 0 } }
  core.end_battle()
  H.settle(mock, 6)
  t.eq(data.area(tr.data, 5).wild.s21f0.caught, true)
  t.eq(H.find(mock, "panel", "p_wild").rows[1].meta, "caught")
end)

t.case("catch into a box when the team is full; the late arrival is caught by a later pass", function()
  local mock, tr, core = H.boot()
  core.team = { { species = 1, form = 0 } }
  core.boxes = { [2] = { { species = 3, form = 0 } } }
  core.encounter(21)
  core.start_battle("wild", { 21 })
  H.settle(mock, 6)
  core.end_battle()
  H.settle(mock, 2) -- first pass: nothing yet
  t.eq(data.area(tr.data, 5).wild.s21f0.caught, false)
  core.boxes[2][2] = { species = 21, form = 0 }
  mock.tick(40, 2, 400) -- the 4 s and 12 s passes
  t.eq(data.area(tr.data, 5).wild.s21f0.caught, true)
end)

t.case("no catch: fled, defeated or a different species gained", function()
  local mock, tr, core = H.boot()
  core.team = { { species = 1, form = 0 } }
  core.encounter(21)
  core.start_battle("wild", { 21 })
  H.settle(mock, 6)
  core.team = { { species = 1, form = 0 }, { species = 22, form = 0 } }
  core.end_battle()
  mock.tick(80, 2, 400)
  t.eq(data.area(tr.data, 5).wild.s21f0.caught, false)
  t.ok(not tr.catch:active(), "the check ends after the last pass")
end)

t.case("catch: no guess when the census before the battle failed", function()
  local mock, tr, core = H.boot()
  local team_api = core.api.team
  core.api.team = function() return nil, "not_ready" end
  core.encounter(21)
  core.start_battle("wild", { 21 })
  H.settle(mock, 2)
  core.api.team = team_api
  core.team = { { species = 21, form = 0 } }
  core.end_battle()
  mock.tick(120, 2, 400)
  t.eq(data.area(tr.data, 5).wild.s21f0.caught, false)
  t.ok(not tr.catch:active())
end)

t.case("catch: a census that finishes after the battle still compares with the team at its start", function()
  local mock, tr, core = H.boot()
  core.box_total = 31
  core.encounter(21)
  core.start_battle("wild", { 21 })
  H.settle(mock, 1) -- 10 ticks: only part of the 31 boxes is read
  core.team = { { species = 21, form = 0 } }
  core.end_battle()
  mock.tick(120, 2, 400)
  t.eq(data.area(tr.data, 5).wild.s21f0.caught, true)
end)

t.case("catch with a core that has no boxes: team only", function()
  local mock, tr, core = H.boot()
  core.boxes_supported = false
  core.encounter(21)
  core.start_battle("wild", { 21 })
  H.settle(mock, 3)
  core.team = { { species = 21, form = 0 } }
  core.end_battle()
  H.settle(mock, 4)
  t.eq(data.area(tr.data, 5).wild.s21f0.caught, true)
end)

t.case("eggs do not count as owned", function()
  local mock, tr, core = H.boot()
  core.encounter(21)
  core.start_battle("wild", { 21 })
  H.settle(mock, 6)
  core.team = { { species = 21, form = 0, egg = true } }
  core.end_battle()
  mock.tick(80, 2, 400)
  t.eq(data.area(tr.data, 5).wild.s21f0.caught, false)
end)

t.case("notes are saved at once and survive a restart", function()
  local mock, tr = H.boot()
  H.settle(mock)
  local ta = H.find(mock, "panel", "p_notes")
  t.eq(ta.action, "note:5")
  mock.action("note:5", "use surf here")
  t.eq(H.stored(mock).areas.z5.notes, "use surf here")
  local mock2 = H.boot({ store = { [H.KEY] = H.stored(mock) } })
  H.settle(mock2)
  t.eq(H.find(mock2, "panel", "p_notes").value, "use surf here")
  mock.action("note:5", "")
  t.eq(H.stored(mock).areas.z5.notes, "")
  mock.action("note:abc", "x") -- not a zone: ignored
end)

t.case("typing a note does not redraw under the cursor", function()
  local mock, tr, core = H.boot()
  H.settle(mock)
  mock.action("note:5", "typing")
  local sets = mock.ui.sets.panel
  core.encounter(21)
  mock.tick(11, 2, 33) -- poll finds the encounter; the redraw waits for the quiet time
  t.eq(mock.ui.sets.panel, sets)
  mock.tick(5, 2, 1000)
  t.ok(mock.ui.sets.panel > sets)
end)

t.case("screen: all areas, filters, selection", function()
  local mock, tr, core = H.boot()
  core.encounter(21)
  H.settle(mock, 2)
  mock.action("note:5", "hi")
  core.zone = 7
  H.settle(mock)
  local tbl = H.find(mock, "screen", "areas")
  t.eq(#tbl.rows, 4, "three encounter areas with four zones, in game order")
  t.eq(tbl.rows[1].cells, { "Demoplace 100 (zone 5)", "1", "0", "0", "yes" })
  t.eq(tbl.rows[2].cells[1], "Demoplace 100 (zone 6)", "same name twice: the zone id tells them apart")
  t.eq(tbl.rows[3].cells[1], "Demoplace 101")
  t.eq(tbl.rows[1].value, 5)
  mock.action("filter:unvisited")
  tbl = H.find(mock, "screen", "areas")
  t.eq(#tbl.rows, 2)
  t.eq(tbl.rows[1].value, 6)
  mock.action("filter:visited")
  t.eq(#H.find(mock, "screen", "areas").rows, 2)
  mock.action("filter:notes")
  tbl = H.find(mock, "screen", "areas")
  t.eq(#tbl.rows, 1)
  t.eq(tbl.rows[1].value, 5)
  t.eq(H.find(mock, "screen", "f_notes").selected, true)
  t.eq(H.find(mock, "screen", "f_all").selected, false)
  mock.action("filter:bogus")
  t.eq(tr.filter, "notes")
  mock.action("filter:all")
  mock.action("pick", 5)
  t.eq(H.find(mock, "screen", "s_area").title, "Demoplace 100 (zone 5)" == nil and "" or "Demoplace 100")
  t.eq(H.find(mock, "screen", "s_notes").action, "note:5")
  mock.action("open")
  t.eq(mock.ui.opened, { "screen" })
end)

t.case("zones with data outside the core's areas are listed too", function()
  local mock, tr, core = H.boot()
  core.zone = 44
  core.encounter(21)
  H.settle(mock, 2)
  local tbl = H.find(mock, "screen", "areas")
  t.eq(#tbl.rows, 5)
  t.eq(tbl.rows[5].value, 44)
  t.eq(tbl.rows[5].cells[1], "Demoplace 44")
end)

t.case("the table is capped at 500 rows", function()
  local mock = H.boot({ setup = function(core)
    local zones = {}
    for z = 1, 600 do zones[z] = 1000 + z end
    core.areas_data = { { id = 1, name = "Big", zones = zones } }
  end })
  H.settle(mock)
  t.eq(#H.find(mock, "screen", "areas").rows, 500)
end)

t.case("seen types overview counts species per type", function()
  local mock, tr, core = H.boot()
  core.encounter(21); core.encounter(22)
  core.start_battle("trainer", { 21, 23 })
  H.settle(mock, 3)
  local counts = {}
  for _, s in ipairs({ 21, 22, 23 }) do
    local seen = {}
    for _, id in ipairs(core.types_of(s)) do
      if not seen[id] then seen[id] = true; counts[id] = (counts[id] or 0) + 1 end
    end
  end
  local section = H.find(mock, "panel", "p_types")
  local chips = ui_validator.all(section, "chip")
  local total = 0
  for _ in pairs(counts) do total = total + 1 end
  t.eq(#chips, total)
  for _, chip in ipairs(chips) do
    local name, n = chip.text:match("^(Demotype %d+) (%d+)$")
    local id = tonumber(name:match("%d+"))
    t.eq(tonumber(n), counts[id], chip.text)
  end
end)

t.case("only what was seen is shown: unvisited areas stay empty, no spoilers", function()
  local mock, tr, core = H.boot()
  H.settle(mock, 2)
  local text = util.ser(mock.ui.trees)
  t.ok(not text:find("Demomon", 1, true), "no species appear before one was seen")
  t.eq(#H.find(mock, "panel", "p_types").children, 1, "only the empty note")
  t.eq(core.calls.encounters ~= nil, true)
end)

t.case("names and types appear once the game text is ready", function()
  local mock, tr, core = H.boot({ setup = function(c) c.names_ready = false end })
  core.encounter(21)
  H.settle(mock, 2)
  t.eq(H.find(mock, "panel", "p_wild").rows[1].title, "Species 21")
  t.eq(H.find(mock, "panel", "p_wild").rows[1].sub, nil)
  t.eq(H.find(mock, "panel", "p_area").title, "Zone 5")
  core.names_ready = true
  mock.tick(40, 2, 400)
  t.eq(H.find(mock, "panel", "p_area").title, "Demoplace 100")
  t.eq(H.find(mock, "panel", "p_wild").rows[1].title, "Demomon 21")
  t.ok(H.find(mock, "panel", "p_wild").rows[1].sub)
end)

t.case("zone label falls back to the zone id", function()
  local mock, tr, core = H.boot({ setup = function(c) c.names_ready = false end })
  H.settle(mock)
  -- the location answer carried no name either
  core.api.location = function() return { zone = 77, source = "memory" } end
  H.settle(mock)
  t.eq(H.find(mock, "panel", "p_area").title, "Zone 77")
end)

t.case("core not ready or missing: nothing breaks, nothing is recorded", function()
  local mock, tr, core = H.boot()
  core.ready = false
  H.settle(mock, 3)
  t.eq(tr.cur_zone, nil)
  t.eq(mock.ui.trees.panel.children[1].type, "empty")
  local mock2, tr2 = H.boot({ core = false })
  H.settle(mock2, 3)
  t.eq(next(tr2.data.areas), nil)
  local warns = 0
  for _, l in ipairs(mock2.logs) do if l.level == "warn" then warns = warns + 1 end end
  t.eq(warns, 1, "one warning only")
end)

t.case("data is kept per game", function()
  local mock, tr, core = H.boot()
  core.encounter(21)
  H.settle(mock, 2)
  t.eq(H.stored(mock).areas.z5.wild.s21f0.n, 1)
  t.eq(require("tracker").store_key({ game = { code = "000400000011C500" } }), "tracker.game-000400000011c500")
  t.eq(require("tracker").store_key({ game = {} }), nil)
end)

t.case("in a run the key includes the run id; randomized runs work the same", function()
  local run = { id = "7f3a9c10-aaaa-bbbb-cccc-1234567890ab", status = "active", randomizer = { mode = "each", preset_id = "p", tool_version = "1", allow_own = true } }
  local mock, tr, core = H.boot({ run = { current = run } })
  core.encounter(21)
  H.settle(mock, 3)
  local key = "tracker.run-7f3a9c10-aaaa-bbbb-cccc-1234567890ab"
  t.eq(tr.key, key)
  t.ok(#key <= 64)
  t.ok(mock.store.data[key])
  t.eq(mock.store.data[H.KEY], nil)
  -- the same game outside a run uses its own data
  local plain = H.boot()
  t.eq(plain.store.data[key], nil)
  -- a second run does not see the first run's data
  local other = H.boot({ run = { current = { id = "other-run", status = "active" } } })
  t.eq(other.store.data[key], nil)
end)

t.case("run view without a game still shows the run's data", function()
  local run = { id = "r1", status = "active", view = true }
  local key = "tracker.run-r1"
  local seed = data.new()
  data.record_wild(seed, 5, 21, 0); data.set_note(seed, 5, "from the game")
  local mock, tr = H.boot({ game = {}, core = false, run = { current = run }, store = { [key] = seed } })
  t.eq(tr.key, key)
  local tbl = H.find(mock, "screen", "areas")
  t.eq(tbl.rows[1].cells[1], "Zone 5")
  t.eq(tbl.rows[1].cells[5], "yes")
end)

t.case("no game and no run: empty state, nothing stored", function()
  local mock, tr = H.boot({ game = {}, core = false })
  t.eq(tr.key, nil)
  t.eq(mock.ui.trees.screen.type, "empty")
  mock.action("note:5", "x")
  H.settle(mock, 2)
  t.eq(mock.store.puts, 0)
end)

t.case("store conflict: both sides are merged, nothing is lost", function()
  local mock, tr, core = H.boot()
  core.encounter(21)
  H.settle(mock, 2) -- saved with revision 1
  local remote = data.new()
  data.record_wild(remote, 6, 22, 0); data.set_note(remote, 6, "other pc")
  mock.store_remote_write(H.KEY, remote)
  core.encounter(23)
  H.settle(mock, 2) -- stale write -> merge -> write again
  local saved = H.stored(mock)
  t.ok(saved.areas.z5.wild.s21f0 and saved.areas.z5.wild.s23f0)
  t.ok(saved.areas.z6.wild.s22f0)
  t.eq(saved.areas.z6.notes, "other pc")
  t.eq(#mock.fb.store.conflicts(H.KEY), 0, "resolved by the second write")
end)

t.case("store.changed merges the other PC's data in", function()
  local mock, tr, core = H.boot()
  core.encounter(21)
  H.settle(mock, 2)
  local remote = data.sanitize(util.copy(H.stored(mock)))
  data.record_wild(remote, 9, 25, 0)
  mock.store_remote_write(H.KEY, remote)
  mock.fire_event("app", "store.changed", H.KEY)
  t.ok(data.area(tr.data, 9).wild.s25f0)
  t.ok(data.area(tr.data, 5).wild.s21f0)
  H.settle(mock, 2)
  t.ok(H.stored(mock).areas.z9)
  mock.fire_event("app", "store.changed", "other.key")
end)

t.case("without the store permission the tracker still works in memory", function()
  local mock, tr, core = H.boot({ store = false })
  core.encounter(21)
  H.settle(mock, 3)
  t.eq(data.area(tr.data, 5).wild.s21f0.n, 1)
end)

t.case("german translation follows the game language", function()
  local mock, tr, core = H.boot({ language = "de" })
  H.settle(mock)
  t.eq(H.find(mock, "panel", "p_all").label, "Alle Gebiete")
end)
