-- Counting owned Pokemon per species/form (team and boxes) to see whether a wild encounter was caught.
-- A census is a job that reads the team at once and then one box per step, so the core is never asked for
-- many boxes in one tick. Without box support the census covers the team only.
local data = require("data")

local M = {}
M.__index = M

local function add(counts, rec)
  if type(rec) == "table" and math.type(rec.species) == "integer" and rec.species >= 1 and rec.egg ~= true then
    local key = data.species_key(rec.species, math.type(rec.form) == "integer" and rec.form or 0)
    counts[key] = (counts[key] or 0) + 1
  end
end

local function add_list(counts, list)
  if type(list) ~= "table" then return end
  for _, rec in pairs(list) do add(counts, rec) end
end

function M.new(core)
  return setmetatable({ core = core, counts = {}, next_box = 1, boxes = nil, started = false, boxed = false }, M)
end

--- One step. Returns true when the census is complete.
function M:step()
  if not self.started then
    self.started = true
    local team = self.core:team()
    if not team then
      self.failed = true
      return true
    end
    add_list(self.counts, team)
    self.boxes = self.core:box_count()
    self.boxed = self.boxes ~= nil
    return not self.boxes or self.boxes < 1
  end
  local list = self.core:box(self.next_box)
  if list then add_list(self.counts, list) end
  self.next_box = self.next_box + 1
  return self.next_box > self.boxes
end

--- Catch detection around one wild battle: a census before it starts and one or more after it ended.
local Catch = {}
Catch.__index = Catch
M.Catch = Catch

local PASSES = { 0, 4000, 12000 } -- ms after the battle ended; the game adds a caught creature late

function Catch.new(core)
  return setmetatable({ core = core, job = nil, cur = nil }, Catch)
end

--- foes: list of { zone, species, form }.
function Catch:battle_started(foes)
  self.cur = { foes = foes, before = nil, ended = false, pass = 1 }
  self.job = { census = M.new(self.core), purpose = "before" }
end

function Catch:battle_ended(now)
  local cur = self.cur
  if not cur then return end
  cur.ended = true
  cur.at = now
end

--- One step; returns a list of { zone, species, form } that were caught.
function Catch:tick(now)
  local out = {}
  local cur = self.cur
  if self.job then
    if self.job.census:step() then
      local job = self.job
      self.job = nil
      if not cur then return out end
      if job.purpose == "before" then
        if not job.census.failed then cur.before = job.census.counts end
      else
        local remaining = {}
        for _, f in ipairs(cur.foes) do
          local key = data.species_key(f.species, f.form)
          if (job.census.counts[key] or 0) > (cur.before[key] or 0) then
            out[#out + 1] = f
          else
            remaining[#remaining + 1] = f
          end
        end
        cur.foes = remaining
        cur.pass = cur.pass + 1
        if #remaining == 0 or cur.pass > #PASSES then self.cur = nil end
      end
    end
  elseif cur and cur.ended then
    if not cur.before then
      self.cur = nil -- the census before the battle never finished: no way to tell, so no guess
    elseif now >= cur.at + PASSES[cur.pass] then
      self.job = { census = M.new(self.core), purpose = "after" }
    end
  end
  return out
end

--- True while a battle is being watched for a catch.
function Catch:active() return self.cur ~= nil end

return M
