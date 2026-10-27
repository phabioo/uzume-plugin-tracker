-- Wires the seen-data to Uzume: polls pokemon.core, stores per run or game, builds the views.
local census = require("census")
local corelink = require("corelink")
local data = require("data")
local util = require("util")
local views = require("views")

local Tracker = {}
Tracker.__index = Tracker

local CORE_ID = "uzume.soullink-core"
local POLL_TICKS = 10        -- poll the core about 3 times per second at 30 ticks per second
local SAVE_DELAY_MS = 2000   -- changes are written at most this often
local RENDER_MS = 500        -- views are rebuilt at most this often
local RETRY_NAMES_MS = 5000  -- rebuild views while names or types are still missing
local TYPING_QUIET_MS = 3000 -- no redraw right after the person typed a note
local MAX_ROWS = 500

--- Store key: "tracker.run-<run id>" in a run, else "tracker.game-<game code>"; nil without either.
function Tracker.store_key(fb)
  local function clean(s, max)
    return (tostring(s):lower():gsub("[^a-z0-9_.-]", "_")):sub(1, max)
  end
  if fb.run and fb.run.current then
    local ok, cur = pcall(fb.run.current)
    if ok and type(cur) == "table" and cur.id ~= nil and tostring(cur.id) ~= "" then
      return "tracker.run-" .. clean(cur.id, 36)
    end
  end
  local code = fb.game and fb.game.code
  if type(code) == "string" and code ~= "" then return "tracker.game-" .. clean(code, 40) end
  return nil
end

function Tracker.new(fb)
  local self = setmetatable({}, Tracker)
  self.fb = fb
  self.T = function(key, vars) return fb.i18n.t(key, vars) end
  self.core = corelink.new(fb)
  self.catch = census.Catch.new(self.core)
  self.ticks = 0
  self.rev = 0
  self.last_seq = 0
  self.filter = "all"
  self.shown = {}
  self.last_save, self.last_render, self.quiet_until, self.last_retry = 0, 0, 0, 0
  return self
end

-- Storage -------------------------------------------------------------------------------------------------

function Tracker:load()
  self.data, self.rev = data.new(), 0
  if not self.key or not self.fb.store then return end
  local ok, v, rev = pcall(self.fb.store.get, self.key)
  if not ok then
    self.fb.log.warn("store.get failed: " .. tostring(v))
    return
  end
  self.rev = rev or 0
  self.data = data.sanitize(v) or data.new()
end

function Tracker:notify(title, body)
  pcall(self.fb.ui.notify, { tone = "warning", title = title, text = body })
end

--- Writes the data. On a stale write the stored version is merged with ours (nothing is lost) and written again.
function Tracker:save()
  self.dirty = false
  self.last_save = self.fb.clock()
  if not self.key or not self.fb.store then return end
  for attempt = 1, 2 do
    local ok, res, why = pcall(self.fb.store.put, self.key, self.data, self.rev)
    if not ok then
      self.fb.log.warn("store.put failed: " .. tostring(res))
      self.dirty = true
      return
    elseif res == true then
      self.rev = why
      return
    elseif why == "conflict" and attempt == 1 then
      local gok, remote, rev = pcall(self.fb.store.get, self.key)
      if not gok then
        self.dirty = true
        return
      end
      self.data = data.merge(remote, self.data)
      self.rev = rev or 0
      self.view_dirty = true
    else
      self.fb.log.warn("store.put refused: " .. tostring(why))
      self.dirty = true
      self:notify(self.T("store.failed.title"), self.T("store.failed.text"))
      return
    end
  end
end

--- The stored version changed elsewhere: merge it into ours.
function Tracker:on_store_changed()
  if not self.key or not self.fb.store then return end
  local ok, remote, rev = pcall(self.fb.store.get, self.key)
  if not ok or remote == nil then return end
  self.data = data.merge(remote, self.data)
  self.rev = rev or self.rev
  self.dirty, self.view_dirty = true, true
end

-- Lifecycle -----------------------------------------------------------------------------------------------

function Tracker:start()
  local fb = self.fb
  self.key = Tracker.store_key(fb)
  self:load()
  fb.on_tick(function() self:tick() end)
  fb.ui.on_action(function(a, v) self:action(a, v) end)
  for _, name in ipairs({ "encounter", "location.changed", "battle.started", "battle.ended" }) do
    fb.events.on(CORE_ID, name, function() self:poll() end)
  end
  fb.events.on("app", "store.changed", function(k)
    if k == self.key then self:on_store_changed() end
  end)
  fb.events.on("app", "store.conflict", function(k)
    if k == self.key then self.dirty = true end
  end)
  self.view_dirty = true
  self:render_all()
end

-- Polling the core ----------------------------------------------------------------------------------------

function Tracker:mark(changed)
  if changed then
    self.dirty, self.view_dirty = true, true
  end
end

function Tracker:poll_location()
  local loc = self.core:location()
  if not loc then return end
  self.core:remember_zone(loc.zone, loc.name)
  if loc.zone ~= self.cur_zone then
    self.cur_zone = loc.zone
    self.view_dirty = true
    if data.visit(self.data, loc.zone) then self.dirty = true end
  end
end

function Tracker:poll_encounters()
  local list = self.core:encounters()
  if not list then return end
  for _, e in ipairs(list) do
    if math.type(e.seq) == "integer" and e.seq > self.last_seq then
      self.last_seq = e.seq
      local zone = math.type(e.zone) == "integer" and e.zone or self.cur_zone
      if zone and math.type(e.species) == "integer" then
        self:mark(data.record_wild(self.data, zone, e.species, e.form, e.shiny == true))
      end
    end
  end
end

function Tracker:poll_battle()
  local b = self.core:battle()
  local active = b and b.active == true
  local now = self.fb.clock()
  if active and not self.battle then
    self.battle = { kind = b.kind, seen = {} }
    if b.kind == "wild" and self.cur_zone then
      local foes = {}
      for _, f in ipairs(b.foes or {}) do
        if math.type(f.species) == "integer" and f.species >= 1 then
          foes[#foes + 1] = { zone = self.cur_zone, species = f.species, form = math.type(f.form) == "integer" and f.form or 0 }
        end
      end
      self.catch:battle_started(foes)
    end
  end
  if active and self.battle.kind == "trainer" and self.cur_zone then
    for _, f in ipairs(b.foes or {}) do
      if math.type(f.species) == "integer" and f.species >= 1 then
        local key = data.species_key(f.species, f.form)
        if not self.battle.seen[key] then
          self.battle.seen[key] = true
          self:mark(data.record_trainer(self.data, self.cur_zone, f.species, f.form))
        end
      end
    end
  end
  if not active and self.battle then
    if self.battle.kind == "wild" then self.catch:battle_ended(now) end
    self.battle = nil
  end
end

function Tracker:poll()
  self:poll_location()
  self:poll_encounters()
  self:poll_battle()
end

function Tracker:tick()
  self.ticks = self.ticks + 1
  local now = self.fb.clock()
  if self.ticks % POLL_TICKS == 0 then self:poll() end
  if self.catch:active() then
    for _, f in ipairs(self.catch:tick(now)) do
      self:mark(data.mark_caught(self.data, f.zone, f.species, f.form))
    end
  end
  if self.dirty and now - self.last_save >= SAVE_DELAY_MS then self:save() end
  if self.unresolved and now - self.last_retry >= RETRY_NAMES_MS then
    self.last_retry = now
    self.view_dirty = true
  end
  if self.view_dirty and now >= self.quiet_until and now - self.last_render >= RENDER_MS then
    self:render_all()
  end
end

-- View model ----------------------------------------------------------------------------------------------

function Tracker:zone_label(zone)
  local name = self.core:zone_name(zone)
  if name then return name end
  self.unresolved = true
  return self.T("area.zone", { zone = zone })
end

function Tracker:entry_view(key, e)
  local v = { key = key, species = e.species, form = e.form, n = e.n, caught = e.caught, shiny = e.shiny }
  v.name = self.core:name("species", e.species)
  if not v.name then
    self.unresolved = true
    v.name = self.T("species.unknown", { id = e.species })
  end
  local types = self.core:species_types(e.species, e.form)
  if types then
    local names = {}
    for _, id in ipairs(types) do
      local n = self.core:name("type", id)
      if not n then self.unresolved = true; n = self.T("types.unknown", { id = id }) end
      names[#names + 1] = n
    end
    v.types = table.concat(names, " / ")
  end
  return v
end

local function sorted_entries(self, map)
  local list = {}
  for key, e in pairs(map) do list[#list + 1] = self:entry_view(key, e) end
  table.sort(list, function(a, b)
    if a.species ~= b.species then return a.species < b.species end
    return a.form < b.form
  end)
  return list
end

function Tracker:area_view(zone)
  local a = data.area(self.data, zone, false) or { visited = false, notes = "", wild = {}, trainers = {} }
  return { zone = zone, name = self:zone_label(zone), visited = a.visited, notes = a.notes,
    wild = sorted_entries(self, a.wild), trainers = sorted_entries(self, a.trainers) }
end

--- Seen types overview over the whole scope: type name and number of seen species with it.
function Tracker:types_view()
  local counts, pending = {}, 0
  for _, s in pairs(data.seen_species(self.data)) do
    local types = self.core:species_types(s.species, s.form)
    if types then
      for _, id in ipairs(types) do counts[id] = (counts[id] or 0) + 1 end
    else
      pending = pending + 1
    end
  end
  local list = {}
  for id, n in pairs(counts) do
    local name = self.core:name("type", id)
    if not name then self.unresolved = true; name = self.T("types.unknown", { id = id }) end
    list[#list + 1] = { id = id, name = name, n = n }
  end
  table.sort(list, function(a, b)
    if a.n ~= b.n then return a.n > b.n end
    return a.id < b.id
  end)
  if pending > 0 then self.unresolved = true end
  return list, pending
end

--- Rows of the all-areas table: the core's encounter areas in game order, then other areas with data.
function Tracker:rows_view()
  local zones, seen = {}, {}
  for _, z in ipairs(self.core:zone_list() or {}) do
    if not seen[z.zone] then seen[z.zone] = true; zones[#zones + 1] = z.zone end
  end
  local extra = {}
  for _, a in pairs(self.data.areas) do
    if not seen[a.zone] and data.has_data(a) then extra[#extra + 1] = a.zone end
  end
  table.sort(extra)
  for _, z in ipairs(extra) do zones[#zones + 1] = z end

  local rows, names = {}, {}
  for _, zone in ipairs(zones) do
    local a = data.area(self.data, zone, false)
    local visited = a ~= nil and a.visited
    local has_notes = a ~= nil and a.notes ~= ""
    local f = self.filter
    if f == "all" or (f == "unvisited" and not visited) or (f == "visited" and visited) or (f == "notes" and has_notes) then
      local seen_n, caught_n, trainers_n = 0, 0, 0
      if a then seen_n, caught_n, trainers_n = data.counts(a) end
      local name = self:zone_label(zone)
      names[name] = (names[name] or 0) + 1
      rows[#rows + 1] = { zone = zone, name = name, seen = seen_n, caught = caught_n, trainers = trainers_n, notes = has_notes }
    end
  end
  for _, r in ipairs(rows) do
    if names[r.name] > 1 then r.name = self.T("area.zone_suffix", { name = r.name, zone = r.zone }) end
  end
  local truncated = #rows > MAX_ROWS
  while #rows > MAX_ROWS do rows[#rows] = nil end
  return rows, truncated
end

function Tracker:vm(with_rows)
  self.unresolved = false
  local vm = { ready = self.key ~= nil, filter = self.filter, rows = {}, types = {}, types_pending = 0 }
  if not vm.ready then return vm end
  if self.cur_zone then vm.cur = self:area_view(self.cur_zone) end
  vm.types, vm.types_pending = self:types_view()
  if with_rows then
    vm.rows, vm.truncated = self:rows_view()
    local sel = self.selected_zone or self.cur_zone
    if sel then vm.selected = self:area_view(sel) end
  end
  return vm
end

-- Rendering -----------------------------------------------------------------------------------------------

function Tracker:set_if_changed(slot, tree)
  local key = util.ser(tree)
  if self.shown[slot] == key then return end
  self.shown[slot] = key
  self.fb.ui.set(slot, tree)
end

function Tracker:render_all()
  self.view_dirty = false
  self.last_render = self.fb.clock()
  self:set_if_changed("panel", views.panel(self:vm(false), self.T))
  self:set_if_changed("screen", views.screen(self:vm(true), self.T))
end

-- Actions -------------------------------------------------------------------------------------------------

local H = {}

function H.open(self)
  if self.fb.ui.open then self.fb.ui.open("screen") end
end

function H.pick(self, v)
  if math.type(v) == "integer" then
    self.selected_zone = v
    self.view_dirty = true
  end
end

function Tracker:action(action, value)
  if not self.key then return end
  local h = H[action]
  if h then
    h(self, value)
    self:render_all()
    return
  end
  local filter = tostring(action):match("^filter:(%a+)$")
  if filter then
    for _, f in ipairs(views.FILTERS) do
      if f == filter then
        self.filter = f
        self:render_all()
      end
    end
    return
  end
  local zone = tostring(action):match("^note:(%d+)$")
  if zone then
    if data.set_note(self.data, tonumber(zone), value) then
      self:save()
      self.quiet_until = self.fb.clock() + TYPING_QUIET_MS
      self.view_dirty = true
    end
  end
end

return Tracker
