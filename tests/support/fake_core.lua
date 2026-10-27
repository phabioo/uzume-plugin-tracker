-- Fake `pokemon.core` provider with synthetic ids and names ("Demomon 21", "Demotype 3", "Demoplace 5").
-- Mutate the fields (zone, battle, team, boxes, ...) between ticks to script a play session.
local F = {}

function F.new()
  local c = {
    ready = true,        -- false: every call answers nil, "not_ready"
    names_ready = true,  -- false: names, types and areas are not available yet
    zone = 5,
    areas_data = {
      { id = 100, name = "Demoplace 100", zones = { 5, 6 } },
      { id = 101, name = "Demoplace 101", zones = { 7 } },
      { id = 102, name = "Demoplace 100", zones = { 9 } }, -- same name as the first: the tracker adds the zone id
    },
    enc = {},
    battle = { active = false },
    team = {},
    boxes = {},
    box_total = 3,
    boxes_supported = true,
    calls = {},
  }

  local function not_ready() return nil, "not_ready" end
  local function counted(name, fn)
    return function(...)
      c.calls[name] = (c.calls[name] or 0) + 1
      if not c.ready then return not_ready() end
      return fn(...)
    end
  end

  --- Types of a synthetic species: two type ids derived from the species id (equal for some species).
  function c.types_of(species)
    local a, b = species % 5 + 1, (species * 3) % 5 + 1
    return { a, b }
  end

  --- The location name of a zone: the name of its area, else "Demoplace <zone>".
  function c.zone_name(zone)
    for _, a in ipairs(c.areas_data) do
      for _, z in ipairs(a.zones) do if z == zone then return a.name end end
    end
    return "Demoplace " .. zone
  end

  c.api = {
    info = counted("info", function() return { supported = true, features = {} } end),
    location = counted("location", function()
      return { zone = c.zone, location = 1000 + c.zone, name = c.names_ready and c.zone_name(c.zone) or nil, source = "memory" }
    end),
    zone_info = counted("zone_info", function(zone)
      if not c.names_ready then return not_ready() end
      return { zone = zone, location = 1000 + zone, name = c.zone_name(zone) }
    end),
    areas = counted("areas", function()
      if not c.names_ready then return not_ready() end
      return c.areas_data
    end),
    encounters = counted("encounters", function() return c.enc end),
    battle = counted("battle", function() return c.battle end),
    team = counted("team", function() return c.team end),
    box_count = counted("box_count", function()
      if not c.boxes_supported then return nil, "unsupported" end
      return c.box_total
    end),
    box = counted("box", function(n)
      if not c.boxes_supported then return nil, "unsupported" end
      return c.boxes[n] or {}
    end),
    name = counted("name", function(kind, id)
      if not c.names_ready then return not_ready() end
      if kind == "species" then return "Demomon " .. id end
      if kind == "type" then return "Demotype " .. id end
      return "Demo" .. kind .. " " .. id
    end),
    species_info = counted("species_info", function(species)
      if not c.names_ready then return not_ready() end
      return { types = c.types_of(species), growth = 0 }
    end),
  }

  --- Appends a wild encounter like the core's `encounters()` list does; returns the entry.
  function c.encounter(species, opts)
    opts = opts or {}
    local e = { seq = #c.enc + 1, species = species, form = opts.form or 0, level = 5, shiny = opts.shiny or false,
                horde = false, zone = opts.zone or c.zone, location = 1000 + (opts.zone or c.zone), frame = 1 }
    c.enc[#c.enc + 1] = e
    return e
  end

  function c.start_battle(kind, species_list)
    local foes = {}
    for _, s in ipairs(species_list) do foes[#foes + 1] = { species = s, form = 0, level = 5, hp = 10, max_hp = 10 } end
    c.battle = { active = true, kind = kind, horde = false, foes = foes, own = {} }
  end

  function c.end_battle() c.battle = { active = false } end

  return c
end

return F
