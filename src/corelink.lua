-- Reads the Pokemon core interface (`pokemon.core` of uzume.soullink-core) through uz.call.
-- Every call is protected; failures and "not ready" answers come back as nil and are never cached,
-- so names and types appear as soon as the game text is loaded. All ids are the game's; names are read
-- at runtime and kept in memory only.
local M = {}
M.__index = M

local INTERFACE = "pokemon.core"

function M.new(uz)
  return setmetatable({ uz = uz, names = {}, types = {}, zone_names = {}, universe = nil, warned = false }, M)
end

--- Calls a function of the interface. Returns value, or nil, reason.
function M:call(fn, ...)
  local ok, v, why = pcall(self.uz.call, INTERFACE, fn, ...)
  if not ok then
    if not self.warned then
      self.warned = true
      self.uz.log.warn("pokemon.core call failed: " .. tostring(v))
    end
    return nil, "unavailable"
  end
  if v == nil then return nil, why or "unavailable" end
  return v
end

function M:location() 
  local loc = self:call("location")
  if type(loc) == "table" and math.type(loc.zone) == "integer" then return loc end
  return nil
end

function M:encounters()
  local list = self:call("encounters")
  return type(list) == "table" and list or nil
end

function M:battle()
  local b = self:call("battle")
  return type(b) == "table" and b or nil
end

function M:team()
  local t = self:call("team")
  return type(t) == "table" and t or nil
end

function M:box_count()
  local n = self:call("box_count")
  return math.type(n) == "integer" and n or nil
end

function M:box(n)
  local b = self:call("box", n)
  return type(b) == "table" and b or nil
end

--- A name from the game text, or nil while it is not available.
function M:name(kind, id)
  local key = kind .. ":" .. tostring(id)
  local cached = self.names[key]
  if cached then return cached end
  local v = self:call("name", kind, id)
  if type(v) == "string" and v ~= "" then
    self.names[key] = v
    return v
  end
  return nil
end

--- Type ids of a species/form as a list of one or two ids, or nil while unknown.
function M:species_types(species, form)
  local key = species .. ":" .. (form or 0)
  local cached = self.types[key]
  if cached then return cached end
  local info = self:call("species_info", species, form or 0)
  if type(info) == "table" and type(info.types) == "table" and math.type(info.types[1]) == "integer" then
    local t = { info.types[1] }
    if math.type(info.types[2]) == "integer" and info.types[2] ~= info.types[1] then t[2] = info.types[2] end
    self.types[key] = t
    return t
  end
  return nil
end

--- Area (location) universe in game order: list of { zone, name } for every zone with wild encounters.
function M:zone_list()
  if self.universe then return self.universe end
  local areas = self:call("areas")
  if type(areas) ~= "table" or #areas == 0 then return nil end
  local out, seen = {}, {}
  for _, a in ipairs(areas) do
    for _, z in ipairs(a.zones or {}) do
      if math.type(z) == "integer" and not seen[z] then
        seen[z] = true
        out[#out + 1] = { zone = z, name = type(a.name) == "string" and a.name or nil }
        if type(a.name) == "string" then self.zone_names[z] = a.name end
      end
    end
  end
  self.universe = out
  return out
end

--- Name of a zone (its location name), or nil while unknown.
function M:zone_name(zone)
  local cached = self.zone_names[zone]
  if cached then return cached end
  local info = self:call("zone_info", zone)
  if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
    self.zone_names[zone] = info.name
    return info.name
  end
  return nil
end

--- Remembers a name the core reported with an event or a location read.
function M:remember_zone(zone, name)
  if type(name) == "string" and name ~= "" then self.zone_names[zone] = name end
end

return M
