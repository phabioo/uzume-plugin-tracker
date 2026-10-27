-- Entry module of the Randomizer Tracker plugin.
local Tracker = require("tracker")

fb.log.info(fb.i18n.t("loaded", { version = (fb.plugin and fb.plugin.version) or "?" }))
Tracker.new(fb):start()
