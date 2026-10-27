-- What the player has seen, per area. Pure data logic, keyed by ids only (no names are stored).
--
-- data = { v = 1, areas = { ["z<zone>"] = area } }
-- area = { zone, visited, notes, wild = { ["s<species>f<form>"] = entry }, trainers = { same keys = entry } }
-- entry = { species, form, n = times seen, caught = bool (wild only), shiny = bool (wild only) }
local util = require("util")

local M = {}
M.MAX_AREAS = 1000
M.MAX_SPECIES = 200
M.MAX_NOTE = 2000

local function is_int(v) return math.type(v) == "integer" end

function M.new() return { v = 1, areas = {} } end

function M.area_key(zone) return "z" .. zone end
function M.species_key(species, form) return "s" .. species .. "f" .. (form or 0) end

--- The area of a zone; created when `create` is true (nil when the area limit is reached).
function M.area(data, zone, create)
  local key = M.area_key(zone)
  local a = data.areas[key]
  if a or not create then return a end
  local count = 0
  for _ in pairs(data.areas) do count = count + 1 end
  if count >= M.MAX_AREAS then return nil end
  a = { zone = zone, visited = false, notes = "", wild = {}, trainers = {} }
  data.areas[key] = a
  return a
end

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

--- Marks an area as visited. Returns true when that changed something.
function M.visit(data, zone)
  local a = M.area(data, zone, true)
  if not a or a.visited then return false end
  a.visited = true
  return true
end

local function record(data, zone, kind, species, form, shiny)
  if not is_int(zone) or not is_int(species) or species < 1 then return false end
  form = is_int(form) and form >= 0 and form or 0
  local a = M.area(data, zone, true)
  if not a then return false end
  a.visited = true
  local key = M.species_key(species, form)
  local e = a[kind][key]
  if not e then
    if count(a[kind]) >= M.MAX_SPECIES then return false end
    e = { species = species, form = form, n = 0 }
    if kind == "wild" then e.caught, e.shiny = false, false end
    a[kind][key] = e
  end
  e.n = e.n + 1
  if kind == "wild" and shiny then e.shiny = true end
  return true
end

--- A wild encounter of a species in a zone. Returns true when recorded.
function M.record_wild(data, zone, species, form, shiny)
  return record(data, zone, "wild", species, form, shiny)
end

--- A species seen on a trainer's side in a zone (once per battle).
function M.record_trainer(data, zone, species, form)
  return record(data, zone, "trainers", species, form)
end

--- Marks a wild species of an area as caught. Returns true when that changed something.
function M.mark_caught(data, zone, species, form)
  local a = M.area(data, zone, false)
  local e = a and a.wild[M.species_key(species, form)]
  if not e or e.caught then return false end
  e.caught = true
  return true
end

--- Free-text note of an area (cleared notes of unknown areas are not created).
function M.set_note(data, zone, text)
  text = tostring(text or "")
  if #text > M.MAX_NOTE then
    local cut = utf8.offset(text, M.MAX_NOTE + 1) or (M.MAX_NOTE + 1)
    text = text:sub(1, math.min(cut - 1, M.MAX_NOTE))
  end
  local a = M.area(data, zone, text ~= "")
  if not a then return false end
  a.notes = text
  return true
end

--- Number of seen wild species, caught ones and trainer species of an area.
function M.counts(area)
  local seen, caught = 0, 0
  for _, e in pairs(area.wild) do
    seen = seen + 1
    if e.caught then caught = caught + 1 end
  end
  return seen, caught, count(area.trainers)
end

--- Every species seen anywhere (wild or on a trainer), as key -> { species, form }.
function M.seen_species(data)
  local out = {}
  for _, a in pairs(data.areas) do
    for _, kind in ipairs({ "wild", "trainers" }) do
      for key, e in pairs(a[kind]) do out[key] = { species = e.species, form = e.form } end
    end
  end
  return out
end

--- Validates stored data; returns a clean copy or nil when it is not tracker data.
function M.sanitize(v)
  if type(v) ~= "table" or v.v ~= 1 or type(v.areas) ~= "table" then return nil end
  local data = M.new()
  local n = 0
  for _, a in pairs(v.areas) do
    if type(a) == "table" and is_int(a.zone) and a.zone >= 0 and n < M.MAX_AREAS then
      local area = M.area(data, a.zone, true)
      n = n + 1
      area.visited = a.visited == true
      area.notes = type(a.notes) == "string" and a.notes:sub(1, M.MAX_NOTE) or ""
      for _, kind in ipairs({ "wild", "trainers" }) do
        if type(a[kind]) == "table" then
          for _, e in pairs(a[kind]) do
            if type(e) == "table" and is_int(e.species) and e.species >= 1 then
              local form = is_int(e.form) and e.form >= 0 and e.form or 0
              local clean = { species = e.species, form = form, n = is_int(e.n) and e.n >= 1 and e.n or 1 }
              if kind == "wild" then clean.caught, clean.shiny = e.caught == true, e.shiny == true end
              if count(area[kind]) < M.MAX_SPECIES then area[kind][M.species_key(e.species, form)] = clean end
            end
          end
        end
      end
    end
  end
  return data
end

--- True when the area has anything the player recorded.
function M.has_data(area)
  return area.visited or area.notes ~= "" or next(area.wild) ~= nil or next(area.trainers) ~= nil
end


local function merge_notes(a, b)
  if a == b or b == "" then return a end
  if a == "" then return b end
  if a:find(b, 1, true) then return a end
  if b:find(a, 1, true) then return b end
  local joined = a .. "\n---\n" .. b
  if #joined > M.MAX_NOTE then joined = joined:sub(1, M.MAX_NOTE) end
  return joined
end

--- Merges two data sets without losing anything either side recorded (union of areas and species, larger
--- counts, caught/visited/shiny if either says so, both notes when they differ). Returns a new data table.
function M.merge(a, b)
  local out = M.sanitize(a) or M.new()
  local other = M.sanitize(b) or M.new()
  for _, oa in pairs(other.areas) do
    local area = M.area(out, oa.zone, true)
    if area then
      area.visited = area.visited or oa.visited
      area.notes = merge_notes(area.notes, oa.notes)
      for _, kind in ipairs({ "wild", "trainers" }) do
        for key, e in pairs(oa[kind]) do
          local mine = area[kind][key]
          if not mine then
            if count(area[kind]) < M.MAX_SPECIES then area[kind][key] = util.copy(e) end
          else
            mine.n = math.max(mine.n, e.n)
            if kind == "wild" then
              mine.caught = mine.caught or e.caught
              mine.shiny = mine.shiny or e.shiny
            end
          end
        end
      end
    end
  end
  return out
end

M.copy = util.copy

return M
