-- Radical Red v4.1 wild-encounter extraction and runtime selection.
--
-- RR does not use FireRed's gWildMonHeaders as its primary encounter table.
-- Its CFRU resolver selects a relocated day table from 04:00 through 16:59
-- and a relocated night table from 17:00 through 03:59, then falls back to
-- gWildMonHeaders only when a selected map/method is absent.  Some of those
-- fallback headers deliberately contain SPECIES_NONE placeholders, so they
-- must never be handed to Game3's battle constructor.

local RR_Encounters = {}

RR_Encounters.FORMAT_VERSION = 2

local METHODS = { "land", "water", "rocks", "fishing" }
local COUNTS = { land = 12, water = 5, rocks = 5, fishing = 10 }

local function gbaOff(ptr)
  ptr = tonumber(ptr)
  if ptr and ptr >= 0x08000000 and ptr < 0x0A000000 then
    return ptr - 0x08000000
  end
  return nil
end

local function readInfo(rom, infoOff, slotCount)
  if not infoOff then return nil end
  local rate = rom:get(infoOff)
  local monsOff = gbaOff(rom:u32(infoOff + 4))
  if not monsOff then return nil end
  local slots = {}
  for index = 0, slotCount - 1 do
    local offset = monsOff + index * 4
    slots[#slots + 1] = {
      minLevel = rom:get(offset),
      maxLevel = rom:get(offset + 1),
      species = rom:u16(offset + 2),
    }
  end
  return { rate = rate, slots = slots }
end

local function parseHeaders(rom, offset, version, label)
  assert(type(offset) == "number", "missing RR " .. tostring(label) .. " header offset")
  local headerSize = version.wild_mon_header_size or 20
  local expected = version[label .. "_wild_header_count"]
  local entries = {}
  for index = 0, 511 do
    local header = offset + index * headerSize
    local mapGroup, mapNum = rom:get(header), rom:get(header + 1)
    if mapGroup == 0xFF and mapNum == 0xFF then
      if expected then
        assert(#entries == expected,
          ("RR %s encounter header count changed: expected %d, got %d")
            :format(label, expected, #entries))
      end
      return entries
    end
    local entry = { mapGroup = mapGroup, mapNum = mapNum }
    for pointerIndex, method in ipairs(METHODS) do
      local pointer = rom:u32(header + pointerIndex * 4)
      entry[method] = readInfo(rom, gbaOff(pointer), COUNTS[method])
    end
    entries[#entries + 1] = entry
  end
  error("unterminated RR " .. tostring(label) .. " encounter headers")
end

local function validSlot(slot, speciesCount)
  if type(slot) ~= "table" then return false end
  local species = tonumber(slot.species or slot[1]) or 0
  local minLevel = tonumber(slot.minLevel or slot.level or slot[2]) or 0
  local maxLevel = tonumber(slot.maxLevel or slot.level or slot[2]) or minLevel
  return species >= 1 and species < speciesCount
    and minLevel >= 1 and minLevel <= 100
    and maxLevel >= 1 and maxLevel <= 100
end

local function validateArea(area, speciesCount, description, audit)
  if type(area) ~= "table" then return nil end
  assert(type(area.slots) == "table" and #area.slots > 0,
    description .. " has no encounter slots")
  local valid = 0
  for _, slot in ipairs(area.slots) do
    if validSlot(slot, speciesCount) then valid = valid + 1 end
  end
  if valid == #area.slots then return area end
  assert(valid == 0,
    description .. " mixes valid monsters with invalid/species-zero slots")
  audit.placeholderAreas = audit.placeholderAreas + 1
  audit.placeholderSlots = audit.placeholderSlots + #area.slots
  -- An all-invalid table is CFRU's representation of "no encounters" for
  -- this method.  Removing it preserves that meaning and prevents species 0.
  return nil
end

local function sanitizeEntries(entries, speciesCount, label)
  local audit = { placeholderAreas = 0, placeholderSlots = 0 }
  for _, entry in ipairs(entries) do
    local mapKey = ("%d:%d"):format(entry.mapGroup, entry.mapNum)
    for _, method in ipairs(METHODS) do
      entry[method] = validateArea(entry[method], speciesCount,
        ("RR %s %s %s"):format(label, mapKey, method), audit)
    end
  end
  return audit
end

local function indexEntries(entries)
  local indexed = {}
  for _, entry in ipairs(entries) do
    indexed[("%d:%d"):format(entry.mapGroup, entry.mapNum)] = entry
  end
  return indexed
end

local function packedEntry(entry)
  if not entry then return nil end
  return {
    land = entry.land,
    water = entry.water,
    rocks = entry.rocks,
    fishing = entry.fishing,
  }
end

local function buildTables(baseEntries, dayEntries, nightEntries, Versions)
  local dayByKey, nightByKey = indexEntries(dayEntries), indexEntries(nightEntries)
  local baseByKey = indexEntries(baseEntries)
  for key in pairs(dayByKey) do
    assert(baseByKey[key], "RR day encounter map is absent from the fallback table: " .. key)
    assert(nightByKey[key], "RR day encounter map is absent from the night table: " .. key)
  end
  for key in pairs(nightByKey) do
    assert(dayByKey[key], "RR night encounter map is absent from the day table: " .. key)
  end
  local tables = {}
  for _, entry in ipairs(baseEntries) do
    local key = ("%d:%d"):format(entry.mapGroup, entry.mapNum)
    local packed = {
      mapGroup = entry.mapGroup,
      mapNum = entry.mapNum,
      land = entry.land,
      water = entry.water,
      rocks = entry.rocks,
      fishing = entry.fishing,
      rrDay = packedEntry(dayByKey[key]),
      rrNight = packedEntry(nightByKey[key]),
    }
    -- Match the stock extractor: the last Altering Cave header wins.
    tables[key] = packed
    local alias = Versions.frMapFor(entry.mapGroup, entry.mapNum)
    if alias then
      tables[alias] = packed
      if alias:sub(1, 3) == "FR_" then
        local noFr = alias:sub(4)
        tables[noFr] = packed
        local routeNum = noFr:match("^ROUTE_(%d+)$")
        if routeNum then
          tables["ROUTE" .. routeNum] = packed
          tables["FR_ROUTE" .. routeNum] = packed
        end
      elseif alias:sub(1, 6) == "SEVII_" then
        tables[alias:sub(7)] = packed
      end
    end
  end
  return tables
end

local function serializeArea(lines, indent, name, area)
  if not area then return end
  lines[#lines + 1] = indent .. name .. " = {"
  lines[#lines + 1] = indent .. ("  rate = %d,"):format(area.rate or 0)
  lines[#lines + 1] = indent .. "  slots = {"
  for _, slot in ipairs(area.slots) do
    lines[#lines + 1] = indent
      .. ("    { species = %d, minLevel = %d, maxLevel = %d },")
        :format(slot.species, slot.minLevel, slot.maxLevel)
  end
  lines[#lines + 1] = indent .. "  },"
  lines[#lines + 1] = indent .. "},"
end

local function serializeMethods(lines, indent, entry)
  for _, method in ipairs(METHODS) do
    serializeArea(lines, indent, method, entry and entry[method])
  end
end

local function serializeEntry(lines, key, entry)
  lines[#lines + 1] = ("T[%q] = {"):format(key)
  lines[#lines + 1] = ("    mapGroup = %d,"):format(entry.mapGroup)
  lines[#lines + 1] = ("    mapNum = %d,"):format(entry.mapNum)
  serializeMethods(lines, "    ", entry)
  if entry.rrDay then
    lines[#lines + 1] = "    rrDay = {"
    serializeMethods(lines, "      ", entry.rrDay)
    lines[#lines + 1] = "    },"
  end
  if entry.rrNight then
    lines[#lines + 1] = "    rrNight = {"
    serializeMethods(lines, "      ", entry.rrNight)
    lines[#lines + 1] = "    },"
  end
  lines[#lines + 1] = "}"
end

local function encodeLua(tables, counts, audit)
  local lines = {
    "-- Auto-extracted from Radical Red's base/day/night wild tables.",
    ("-- format_version=%d base=%d day=%d night=%d placeholders_removed=%d/%d")
      :format(RR_Encounters.FORMAT_VERSION, counts.base, counts.day, counts.night,
        audit.placeholderAreas, audit.placeholderSlots),
    "local T = {}",
  }
  local canonical, aliases = {}, {}
  for key in pairs(tables) do
    if key:match("^%d+:%d+$") then canonical[#canonical + 1] = key
    else aliases[#aliases + 1] = key end
  end
  table.sort(canonical)
  table.sort(aliases)
  for _, key in ipairs(canonical) do serializeEntry(lines, key, tables[key]) end
  for _, key in ipairs(aliases) do
    local entry = tables[key]
    local numeric = ("%d:%d"):format(entry.mapGroup, entry.mapNum)
    lines[#lines + 1] = ("T[%q] = T[%q]"):format(key, numeric)
  end
  lines[#lines + 1] = "return T"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

local function usableCensus(tables)
  local maps, slots = 0, 0
  for key, entry in pairs(tables) do
    if key:match("^%d+:%d+$") then
      maps = maps + 1
      for _, bucket in ipairs({ entry, entry.rrDay, entry.rrNight }) do
        for _, method in ipairs(METHODS) do
          local area = bucket and bucket[method]
          if area then slots = slots + #area.slots end
        end
      end
    end
  end
  return maps, slots
end

function RR_Encounters.writeExtract(rom, cache, root, version, Profile)
  assert(rom and cache and version and Profile,
    "RR encounter extraction needs ROM, cache, version, and profile")
  root = root or ("data/" .. "generated/gba")
  local base = parseHeaders(rom, assert(version.wild_mon_headers), version, "base")
  local day = parseHeaders(rom, assert(version.rr_wild_day_headers), version, "day")
  local night = parseHeaders(rom, assert(version.rr_wild_night_headers), version, "night")
  local baseAudit = sanitizeEntries(base, Profile.SPECIES_COUNT, "base")
  local dayAudit = sanitizeEntries(day, Profile.SPECIES_COUNT, "day")
  local nightAudit = sanitizeEntries(night, Profile.SPECIES_COUNT, "night")
  local audit = {
    placeholderAreas = baseAudit.placeholderAreas + dayAudit.placeholderAreas
      + nightAudit.placeholderAreas,
    placeholderSlots = baseAudit.placeholderSlots + dayAudit.placeholderSlots
      + nightAudit.placeholderSlots,
  }
  assert(audit.placeholderAreas == 18 and audit.placeholderSlots == 177,
    ("RR encounter placeholder census changed: got %d areas/%d slots")
      :format(audit.placeholderAreas, audit.placeholderSlots))
  local Versions = require("src.import.gba.versions")
  local tables = buildTables(base, day, night, Versions)
  local mapCount, usableSlots = usableCensus(tables)
  assert(mapCount == 134 and usableSlots == 4866,
    ("RR encounter census changed: got %d maps/%d usable slots")
      :format(mapCount, usableSlots))
  local blob = encodeLua(tables,
    { base = #base, day = #day, night = #night }, audit)
  local ok, err = cache:write(root .. "/encounters.lua", blob)
  assert(ok ~= false and ok ~= nil,
    "could not write RR encounters: " .. tostring(err))
  return {
    format = RR_Encounters.FORMAT_VERSION,
    baseHeaders = #base,
    dayHeaders = #day,
    nightHeaders = #night,
    placeholderAreasRemoved = audit.placeholderAreas,
    placeholderSlotsRemoved = audit.placeholderSlots,
    maps = mapCount,
    usableSlots = usableSlots,
  }
end

function RR_Encounters.periodForHour(hour)
  hour = math.floor(tonumber(hour) or 0) % 24
  -- Exact RR v4.1 resolver: evening (17:00-19:59) shares the night table.
  return (hour >= 17 or hour < 4) and "night" or "day"
end

local function currentHour()
  if RR_Encounters._testHour ~= nil then return RR_Encounters._testHour end
  local now = os.date("*t")
  return (type(now) == "table" and tonumber(now.hour)) or 0
end

local function safeArea(area, speciesCount)
  if type(area) ~= "table" then return nil end
  local slots = area.slots or area.mons or area
  if type(slots) ~= "table" or #slots == 0 then return nil end
  for _, slot in ipairs(slots) do
    if not validSlot(slot, speciesCount) then return nil end
  end
  return area
end

function RR_Encounters.resolveArea(entry, method, hour, speciesCount)
  if type(entry) ~= "table" then return nil end
  speciesCount = tonumber(speciesCount) or 1376
  local base = entry.__rrBase or entry
  local period = RR_Encounters.periodForHour(hour)
  local variant = period == "night" and entry.rrNight or entry.rrDay
  -- CFRU falls back method-by-method to gWildMonHeaders.
  return safeArea((variant and variant[method]) or base[method], speciesCount)
end

local function safeEncounter(encounter, speciesCount)
  if type(encounter) ~= "table" then return encounter end
  local species = tonumber(encounter.species) or tonumber(encounter.speciesId)
  local level = tonumber(encounter.level) or 0
  if species and species >= 1 and species < speciesCount
      and level >= 1 and level <= 100 then
    return encounter
  end
  return nil
end

function RR_Encounters.install(Profile)
  local Encounters = require("src.core.game3.encounters")
  if Encounters.__radicalRedTimeTables then
    return Encounters.__radicalRedTimeTables.report
  end

  local state = {
    period = nil,
    tables = nil,
    warned = false,
    report = {
      dayHeaders = Profile.RR_WILD_DAY_HEADER_COUNT,
      nightHeaders = Profile.RR_WILD_NIGHT_HEADER_COUNT,
      speciesZeroGuard = true,
    },
  }
  Encounters.__radicalRedTimeTables = state

  local function activate()
    Encounters.ensureLoaded()
    local tables = Encounters._tables
    local hour = currentHour()
    local period = RR_Encounters.periodForHour(hour)
    if state.tables == tables and state.period == period then return end
    state.tables, state.period = tables, period
    local seen, active = {}, 0
    for _, entry in pairs(tables or {}) do
      if type(entry) == "table" and not seen[entry] then
        seen[entry] = true
        if not entry.__rrBase then
          entry.__rrBase = {}
          for _, method in ipairs(METHODS) do
            entry.__rrBase[method] = entry[method]
          end
        end
        for _, method in ipairs(METHODS) do
          entry[method] = RR_Encounters.resolveArea(
            entry, method, hour, Profile.SPECIES_COUNT)
        end
        active = active + 1
      end
    end
    state.report.activePeriod = period
    state.report.tablesAudited = active
  end

  local function warnInvalid(source)
    if state.warned then return end
    state.warned = true
    print("[radical-red] blocked invalid/species-zero wild encounter from "
      .. tostring(source))
  end

  local function wrapEncounterResult(name)
    local original = assert(Encounters[name], "missing encounter method " .. name)
    Encounters[name] = function(...)
      activate()
      local result = original(...)
      local safe = safeEncounter(result, Profile.SPECIES_COUNT)
      if result ~= nil and safe == nil then warnInvalid(name) end
      return safe
    end
  end

  for _, name in ipairs({ "rollLand", "rollWater", "rollRocks", "rollFishing", "onStep" }) do
    wrapEncounterResult(name)
  end

  for _, name in ipairs({ "tableFor", "hasFishingMons" }) do
    local original = assert(Encounters[name], "missing encounter method " .. name)
    Encounters[name] = function(...)
      activate()
      return original(...)
    end
  end

  local originalSet = assert(Encounters.setWildBattle)
  Encounters.setWildBattle = function(species, level, item)
    local candidate = safeEncounter({ species = species, level = level, item = item },
      Profile.SPECIES_COUNT)
    if not candidate then
      warnInvalid("setWildBattle")
      return nil
    end
    return originalSet(tonumber(candidate.species) or tonumber(candidate.speciesId),
      tonumber(candidate.level), candidate.item)
  end

  local originalTake = assert(Encounters.takePendingWild)
  Encounters.takePendingWild = function(...)
    local result = originalTake(...)
    local safe = safeEncounter(result, Profile.SPECIES_COUNT)
    if result ~= nil and safe == nil then warnInvalid("takePendingWild") end
    return safe
  end

  activate()
  return state.report
end

return RR_Encounters
