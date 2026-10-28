-- Entry module of the Randomizer Tracker plugin.
local Tracker = require("tracker")

uz.log.info(uz.i18n.t("loaded", { version = (uz.plugin and uz.plugin.version) or "?" }))
Tracker.new(uz):start()
