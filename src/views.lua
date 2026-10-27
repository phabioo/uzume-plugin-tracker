-- Declarative UI trees (panel, screen) from a view model. Pure functions, no fb access.
local M = {}

local function text(props)
  props.type = "text"
  return props
end

local function species_title(e, T)
  if e.form and e.form > 0 then return T("species.form", { name = e.name, form = e.form }) end
  return e.name
end

local function species_rows(entries, T, wild)
  local rows = {}
  for _, e in ipairs(entries) do
    local meta
    if wild then
      meta = e.caught and T("row.caught") or T("row.seen", { n = e.n })
    else
      meta = T("row.seen", { n = e.n })
    end
    local row = { id = e.key, title = species_title(e, T), meta = meta, tone = (wild and e.caught) and "ok" or "neutral" }
    if e.types and e.types ~= "" then row.sub = e.types end
    rows[#rows + 1] = row
  end
  return rows
end

--- Section for one area: wild species, trainer species and the notes field.
function M.area_section(a, T, id_prefix)
  local kids = {}
  if a.visited then
    kids[#kids + 1] = { type = "badge", text = T("area.visited"), tone = "ok" }
  else
    kids[#kids + 1] = { type = "badge", text = T("area.not_visited"), tone = "neutral" }
  end
  if #a.wild > 0 then
    kids[#kids + 1] = text({ text = T("area.wild"), style = "eyebrow" })
    kids[#kids + 1] = { type = "list", id = id_prefix .. "wild", rows = species_rows(a.wild, T, true) }
  else
    kids[#kids + 1] = text({ text = T("area.no_wild"), style = "meta" })
  end
  if #a.trainers > 0 then
    kids[#kids + 1] = text({ text = T("area.trainers"), style = "eyebrow" })
    kids[#kids + 1] = { type = "list", id = id_prefix .. "trainers", rows = species_rows(a.trainers, T, false) }
  end
  kids[#kids + 1] = text({ text = T("area.notes"), style = "eyebrow" })
  kids[#kids + 1] = { type = "textarea", id = id_prefix .. "notes", action = "note:" .. a.zone, value = a.notes,
    lines = 4, placeholder = T("area.notes.placeholder") }
  return { type = "section", id = id_prefix .. "area", title = a.name, children = kids }
end

local function types_section(vm, T, id)
  local kids
  if #vm.types == 0 then
    kids = { text({ text = T("types.none"), style = "meta" }) }
  else
    local chips = {}
    for _, ty in ipairs(vm.types) do
      chips[#chips + 1] = { type = "chip", text = T("types.chip", { name = ty.name, n = ty.n }) }
    end
    kids = { { type = "grid", gap = 8, columns = 2, children = chips } }
    if vm.types_pending > 0 then
      kids[#kids + 1] = text({ text = T("types.pending", { n = vm.types_pending }), style = "meta" })
    end
  end
  return { type = "section", id = id, title = T("types.title"), children = kids }
end

function M.panel(vm, T)
  if not vm.ready then
    return { type = "empty", title = T("empty.no_game.title"), text = T("empty.no_game.text") }
  end
  local kids = {}
  if vm.cur then
    kids[#kids + 1] = M.area_section(vm.cur, T, "p_")
  else
    kids[#kids + 1] = { type = "empty", title = T("empty.waiting.title"), text = T("empty.waiting.text") }
  end
  kids[#kids + 1] = types_section(vm, T, "p_types")
  kids[#kids + 1] = { type = "button", id = "p_all", label = T("btn.all_areas"), action = "open", variant = "secondary" }
  return { type = "column", gap = 12, children = kids }
end

local FILTERS = { "all", "unvisited", "visited", "notes" }
M.FILTERS = FILTERS

function M.screen(vm, T)
  if not vm.ready then
    return { type = "empty", title = T("empty.no_game.title"), text = T("empty.no_game.text") }
  end
  local chips = {}
  for _, f in ipairs(FILTERS) do
    chips[#chips + 1] = { type = "chip", id = "f_" .. f, text = T("filter." .. f), action = "filter:" .. f, selected = vm.filter == f }
  end
  local rows = {}
  for _, r in ipairs(vm.rows) do
    rows[#rows + 1] = { cells = { r.name, tostring(r.seen), tostring(r.caught), tostring(r.trainers), r.notes and T("col.yes") or "" },
      action = "pick", value = r.zone }
  end
  local kids = {
    { type = "row", gap = 8, align = "center", children = chips },
  }
  if #rows == 0 then
    kids[#kids + 1] = { type = "empty", title = T("empty.no_rows.title"), text = T("empty.no_rows.text") }
  else
    kids[#kids + 1] = { type = "table", id = "areas",
      columns = { T("col.area"), T("col.seen"), T("col.caught"), T("col.trainers"), T("col.notes") }, rows = rows }
    if vm.truncated then
      kids[#kids + 1] = text({ text = T("rows.truncated", { n = #rows }), style = "meta" })
    end
  end
  if vm.selected then kids[#kids + 1] = M.area_section(vm.selected, T, "s_") end
  kids[#kids + 1] = types_section(vm, T, "s_types")
  return { type = "column", gap = 16, children = kids }
end

return M
