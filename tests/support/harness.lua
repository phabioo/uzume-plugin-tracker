-- Boots the tracker sources against the fake uz and the fake pokemon.core.
local uz_mock = require("uz_mock")
local fake_core = require("fake_core")

local H = {}
H.GAME = { system = "3ds", code = "000400000011C400", title = "Demo Game" }
H.KEY = "tracker.game-000400000011c400"

--- opts as uz_mock.new, plus opts.core = false for a missing interface, opts.setup(core) before the start.
function H.boot(opts)
  opts = opts or {}
  opts.game = opts.game or H.GAME
  local core = fake_core.new()
  if opts.setup then opts.setup(core) end
  local mock = uz_mock.new(opts)
  if opts.core ~= false then mock.set_provider("pokemon.core", core.api) end
  local tracker = require("tracker").new(mock.uz)
  tracker:start()
  return mock, tracker, core
end

--- Lets `n` poll cycles pass (10 ticks each, 300 ms per tick so debounces and timers run out).
function H.settle(mock, n)
  mock.tick((n or 1) * 10, 2, 300)
end

--- The block with an id in a slot's tree.
function H.find(mock, slot, id)
  return require("ui_validator").find(mock.ui.trees[slot], id)
end

function H.stored(mock) return mock.store.data[H.KEY] end

return H
