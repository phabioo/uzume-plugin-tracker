local t = require("t")
local uz_mock = require("uz_mock")
local J = require("json")

local LUA = (arg and arg[-1]) or "lua5.4"

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("a"); f:close()
  return s
end

t.case("bundle --check passes", function()
  local ok = os.execute(LUA .. " tools/bundle.lua --check > /dev/null 2>&1")
  t.ok(ok == true, "plugin/main.lua is stale; run tools/bundle.lua")
end)

t.case("plugin/main.lua runs in a sandbox without require/load/io/os", function()
  local mock = uz_mock.new({ game = { system = "3ds", code = "000400000011C400", title = "Demo" } })
  mock.set_provider("pokemon.core", require("fake_core").new().api)
  local env = { uz = mock.uz }
  for _, n in ipairs({ "assert", "error", "getmetatable", "ipairs", "next", "pairs", "pcall", "select",
    "setmetatable", "tonumber", "tostring", "type", "xpcall", "rawequal", "rawget", "rawlen", "rawset",
    "string", "table", "math", "utf8", "coroutine" }) do
    env[n] = _G[n]
  end
  env.print = function(...) mock.uz.log.info(...) end
  env._VERSION = _VERSION
  for _, n in ipairs({ "require", "load", "loadstring", "dofile", "loadfile", "io", "os", "package", "debug" }) do
    t.eq(env[n], nil)
  end
  local chunk = assert(load(read("plugin/main.lua"), "=plugin/main.lua", "t", env))
  chunk()
  t.ok(mock.ui.trees.panel and mock.ui.trees.screen, "both surfaces drawn")
  mock.tick(30, 2, 300)
  t.ok(mock.store.data["tracker.game-000400000011c400"], "location visit stored")
  for _, l in ipairs(mock.logs) do t.ok(l.level ~= "error", l.text) end
end)

local function manifest() return J.decode(read("plugin/manifest.json")) end

t.case("manifest fields", function()
  local m = manifest()
  t.eq(m.id, "uzume.tracker")
  t.eq(m.name, "Randomizer Tracker")
  t.eq(m.api, 1)
  t.eq(m.type, "script")
  t.eq(m.requires, { ["uzume.soullink-core"] = ">=0.4.0" })
  t.eq(m.games, { { system = "3ds", codes = { "000400000011C400", "000400000011C500" } } })
  t.ok(m.version:match("^%d+%.%d+%.%d+$"))
  local perms = {}
  for _, p in ipairs(m.permissions) do perms[p] = true end
  t.ok(perms.store and perms.ui and perms["run.state"])
  t.ok(not perms["memory.read"] and not perms["memory.write"] and not perms["rom.read"], "reads the game through pokemon.core only")
  t.ok(m.ui.panel and m.ui.screen)
  t.eq(m.provides, nil)
end)

local function keys_of(path)
  local out = {}
  for k in pairs(uz_mock.read_json_flat(read(path))) do out[k] = true end
  return out
end

t.case("i18n: German has exactly the English keys", function()
  local en, de = keys_of("plugin/i18n/en.json"), keys_of("plugin/i18n/de.json")
  for k in pairs(en) do t.ok(de[k], "missing in de: " .. k) end
  for k in pairs(de) do t.ok(en[k], "extra in de: " .. k) end
end)

t.case("i18n: every key used in the sources exists, and every key is used", function()
  local en = keys_of("plugin/i18n/en.json")
  local p = assert(io.popen("ls src"))
  local used = {}
  local dynamic = { "filter." }
  for name in p:lines() do
    if name:match("%.lua$") then
      local src = read("src/" .. name)
      for key in src:gmatch('T%("([%w_.]+)"') do used[key] = true end
      for key in src:gmatch('uz%.i18n%.t%("([%w_.]+)"') do used[key] = true end
    end
  end
  p:close()
  for key in pairs(used) do
    if key:sub(-1) ~= "." then t.ok(en[key], "undefined i18n key: " .. key) end -- "x.y." + id is dynamic
  end
  for key in pairs(en) do
    local dyn = false
    for _, prefix in ipairs(dynamic) do if key:sub(1, #prefix) == prefix then dyn = true end end
    t.ok(used[key] or dyn, "unused i18n key: " .. key)
  end
  for _, f in ipairs(require("views").FILTERS) do t.ok(en["filter." .. f], f) end
end)

t.case("i18n placeholders match between languages", function()
  local en = uz_mock.read_json_flat(read("plugin/i18n/en.json"))
  local de = uz_mock.read_json_flat(read("plugin/i18n/de.json"))
  for k, v in pairs(en) do
    local a, b = {}, {}
    for ph in v:gmatch("{([%w_]+)}") do a[#a + 1] = ph end
    for ph in de[k]:gmatch("{([%w_]+)}") do b[#b + 1] = ph end
    table.sort(a); table.sort(b)
    t.eq(b, a, k)
  end
end)

t.case("old apps with only the global fb still start the bundled plugin", function()
  local mock = uz_mock.new({ game = { system = "3ds", code = "000400000011C400", title = "Demo" } })
  mock.set_provider("pokemon.core", require("fake_core").new().api)
  local env = { fb = mock.uz }
  for _, n in ipairs({ "assert", "error", "getmetatable", "ipairs", "next", "pairs", "pcall", "select",
    "setmetatable", "tonumber", "tostring", "type", "xpcall", "rawequal", "rawget", "rawlen", "rawset",
    "string", "table", "math", "utf8", "coroutine" }) do
    env[n] = _G[n]
  end
  env._VERSION = _VERSION
  t.eq(env.uz, nil)
  local chunk = assert(load(read("plugin/main.lua"), "=plugin/main.lua", "t", env))
  chunk()
  t.ok(mock.ui.trees.panel and mock.ui.trees.screen, "surfaces drawn through the fb fallback")
end)
