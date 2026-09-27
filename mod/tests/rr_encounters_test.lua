local loader = loadfile("mods/radical_red_experience/lib/rr_encounters.lua")
  or loadfile("lib/rr_encounters.lua")
local RR = assert(loader)()

assert(RR.periodForHour(3) == "night")
assert(RR.periodForHour(4) == "day")
assert(RR.periodForHour(16) == "day")
assert(RR.periodForHour(17) == "night")
assert(RR.periodForHour(23) == "night")

local function area(species)
  return {
    rate = 20,
    slots = { { species = species, minLevel = 3, maxLevel = 5 } },
  }
end

local entry = {
  land = area(0), -- Base CFRU placeholder: must never become a battle.
  water = area(7),
  rocks = area(0),
  fishing = area(8),
  rrDay = { land = area(25) },
  rrNight = { land = area(19) },
}

local Encounters = {
  _tables = { TEST = entry },
  _pendingWild = nil,
}
function Encounters.ensureLoaded() return true end
function Encounters.tableFor(mapId) return Encounters._tables[mapId] end
function Encounters.rollLand(mapId)
  local slot = Encounters._tables[mapId].land.slots[1]
  return { species = slot.species, level = slot.minLevel }
end
function Encounters.rollWater(mapId)
  local slot = Encounters._tables[mapId].water.slots[1]
  return { species = slot.species, level = slot.minLevel }
end
function Encounters.rollRocks(mapId)
  local table = Encounters._tables[mapId].rocks
  if not table then return nil end
  local slot = table.slots[1]
  return { species = slot.species, level = slot.minLevel }
end
function Encounters.rollFishing(mapId)
  local slot = Encounters._tables[mapId].fishing.slots[1]
  return { species = slot.species, level = slot.minLevel }
end
function Encounters.onStep()
  return { species = 0, level = 1 }
end
function Encounters.hasFishingMons(mapId)
  return Encounters._tables[mapId].fishing ~= nil
end
function Encounters.setWildBattle(species, level, item)
  Encounters._pendingWild = { species = species, level = level, item = item }
end
function Encounters.takePendingWild()
  local result = Encounters._pendingWild
  Encounters._pendingWild = nil
  return result
end

package.loaded["src.core.game3.encounters"] = Encounters
RR._testHour = 12
local report = RR.install({
  SPECIES_COUNT = 1376,
  RR_WILD_DAY_HEADER_COUNT = 83,
  RR_WILD_NIGHT_HEADER_COUNT = 83,
})
assert(report.speciesZeroGuard == true and report.activePeriod == "day")
assert(Encounters.tableFor("TEST").land.slots[1].species == 25)
assert(Encounters.rollLand("TEST").species == 25)
assert(Encounters.rollWater("TEST").species == 7,
  "missing time-specific methods must fall back to the base header")
assert(Encounters.rollRocks("TEST") == nil,
  "species-zero base placeholders must be disabled")
assert(Encounters.onStep("TEST") == nil,
  "the final encounter guard must reject species zero")

RR._testHour = 18
assert(Encounters.tableFor("TEST").land.slots[1].species == 19)
assert(report.activePeriod == "night")

Encounters.setWildBattle(0, 1)
assert(Encounters.takePendingWild() == nil)
Encounters.setWildBattle(25, 5)
local pending = assert(Encounters.takePendingWild())
assert(pending.species == 25 and pending.level == 5)

print("PASS rr_encounters_test: RR day/night tables and species-zero guard verified")
