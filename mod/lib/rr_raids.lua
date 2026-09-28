-- Radical Red v4.1 raid-den runtime.
--
-- Raid encounters, partners, spreads, and rewards are read from the player's
-- validated ROM.  Nothing from those tables is shipped in the mod.  The
-- original hack implements the eight entry points below as GBA specials;
-- gen1recomp cannot execute their Thumb code, so this module supplies the
-- equivalent host-side state transitions and battle setup.

local Raids = {}

Raids.ADDR = {
  DETERMINE_STARS = 0x0908F21D,
}

Raids.SPECIAL = {
  AVAILABLE = 0x115,
  INTRO = 0x116,
  CREATE_MON = 0x117,
  START_BATTLE = 0x118,
  SET_DONE = 0x119,
  CLEAR_DONE = 0x11A,
  ALL_DONE = 0x11B,
  REWARD = 0x11C,
}

local ROM = {
  RAID_TABLE = 0x1134C34,
  RAID_PARTNER_COUNT = 0x1134176,
  RAID_PARTNERS = 0x1134178,
  FRONTIER_LEGENDARY_SPREADS = 0x1139F58,
  FRONTIER_SPREADS = 0x113B0D8,
  ITEMS_BY_TYPE = 0x115740C,
  EVOLUTION_TABLE = 0x17CD9B0,
}

local MAPSEC_DYNAMIC = 0x57
local KANTO_MAPSEC_COUNT = 109
local RAID_STAR_COUNT = 7
local RAID_DATA_SIZE = 8
local RAID_RECORD_SIZE = 30
local RAID_PARTNER_SIZE = 60
local FRONTIER_SPREAD_SIZE = 28
local FRONTIER_SPREAD_COUNT = 1679
local FRONTIER_LEGENDARY_SPREAD_COUNT = 160
local EVOLUTIONS_PER_SPECIES = 16
local EVOLUTION_ENTRY_SIZE = 8
local MAX_RAID_DROPS = 12
local FIRST_RAID_BATTLE_FLAG = 0x1800

local FLAG = {
  TAG_BATTLE = 0x908,
  DYNAMAX_BATTLE = 0x918,
  RAID_BATTLE = 0x919,
  RAID_NO_FORCE_END = 0x91A,
  BATTLE_FACILITY = 0x930,
  GAME_CLEAR = 0x82C,
}

local VAR = {
  TEMP_0 = 0x4000,
  RAID_NUMBER_OFFSET = 0x5137,
  PARTNER = 0x5011,
  PARTNER_BACKSPRITE = 0x5012,
  FACILITY_PARTNER_ID = 0x501E,
  FACILITY_LEVEL = 0x5016,
  RESULT = 0x800D,
  LAST_TALKED = 0x800F,
}

local RAID_MULTI_TRAINER_ID = 0x3FE
local MENU_LIST_ID = 0x7E
local DROP_RATES = { 100, 80, 80, 50, 50, 30, 30, 25, 25, 5, 4, 1 }
local FACILITY_DROPS_4 = {
  69, 63, 153, 168, 19, 0x24E, 0, 111, 0, 200, 0x268, 0x269,
}
local FACILITY_DROPS_56 = {
  69, 63, 153, 168, 0x21B, 0x24E, 111, 71, 200, 0x58, 0x268, 0x269,
}
local STAR_RANGES = {
  [1] = { 15, 20 }, [2] = { 25, 30 }, [3] = { 35, 40 },
  [4] = { 50, 55 }, [5] = { 60, 65 }, [6] = { 75, 90 },
}
local STAR_BY_BADGES = {
  [0] = { 0, 0 }, [1] = { 1, 1 }, [2] = { 1, 2 },
  [3] = { 2, 2 }, [4] = { 2, 3 }, [5] = { 3, 3 },
  [6] = { 3, 4 }, [7] = { 4, 4 }, [8] = { 4, 5 },
  [9] = { 5, 6 },
}
local EGG_MOVE_CHANCE = { [1] = 0, [2] = 10, [3] = 30, [4] = 50, [5] = 70, [6] = 70 }
local STAT_KEYS = { "hp", "atk", "def", "spe", "spa", "spd" }
local BADGE_FLAGS = { 0x820, 0x821, 0x822, 0x823, 0x824, 0x825, 0x826, 0x827 }

-- RR 4.1's move registry includes the Gen IX additions before its generated
-- Z-/Max-move block, so these values intentionally differ from the older CFRU
-- header checked into the public source tree.  They are fixed by the exact ROM
-- hash required by the manifest and were verified against gMoveNames and
-- gBattleMoves in that image.
local MOVE = {
  STRUGGLE = 0x0A5,
  TRANSFORM = 0x090,
  MAX_GUARD = 901,
  FIRST_Z = 848,
  LAST_Z = 900,
}

local MAX_MOVE_BY_TYPE = {
  [0] = { 902, 903 },  -- Normal / Max Strike
  [1] = { 904, 905 },  -- Fighting / Max Knuckle
  [2] = { 906, 907 },  -- Flying / Max Airstream
  [3] = { 908, 909 },  -- Poison / Max Ooze
  [4] = { 910, 911 },  -- Ground / Max Quake
  [5] = { 912, 913 },  -- Rock / Max Rockfall
  [6] = { 914, 915 },  -- Bug / Max Flutterby
  [7] = { 916, 917 },  -- Ghost / Max Phantasm
  [8] = { 918, 919 },  -- Steel / Max Steelspike
  [10] = { 920, 921 }, -- Fire / Max Flare
  [11] = { 922, 923 }, -- Water / Max Geyser
  [12] = { 924, 925 }, -- Grass / Max Overgrowth
  [13] = { 926, 927 }, -- Electric / Max Lightning
  [14] = { 928, 929 }, -- Psychic / Max Mindstorm
  [15] = { 930, 931 }, -- Ice / Max Hailstorm
  [16] = { 932, 933 }, -- Dragon / Max Wyrmwind
  [17] = { 934, 935 }, -- Dark / Max Darkness
  [23] = { 936, 937 }, -- Fairy / Max Starfall
}

local RAID_BANNED_MOVES = {
  [0x1C2] = true, -- Bug Bite
  [0x157] = true, -- Covet
  [0x0AE] = true, -- Curse
  [0x0C2] = true, -- Destiny Bond
  [0x099] = true, -- Explosion
  [0x1DA] = true, -- Incinerate
  [0x11A] = true, -- Knock Off
  [0x0C3] = true, -- Perish Song
  [0x1C3] = true, -- Pluck
  [0x078] = true, -- Self-Destruct
  [0x0A2] = true, -- Super Fang
}

local RAID_BOSS_BANNED_MOVES = {
  [0x106] = true, -- Memento
  [0x1D6] = true, -- Healing Wish
  [0x1D7] = true, -- Lunar Dance
  [0x1EF] = true, -- Final Gambit
  [0x295] = true, -- Mind Blown
  [0x2C8] = true, -- Steel Beam
  [0x0DC] = true, -- Pain Split
  [0x11B] = true, -- Endeavor
  [0x108] = true, -- Focus Punch
  [0x260] = true, -- Shell Trap
  [0x245] = true, -- Beak Blast
  [0x0B6] = true, -- Protect
  [0x0C5] = true, -- Detect
  [0x27D] = true, -- Quick Guard
  [0x27E] = true, -- Wide Guard
  [0x20F] = true, -- King's Shield
  [0x237] = true, -- Spiky Shield
  [0x244] = true, -- Baneful Bunker
  [0x27C] = true, -- Mat Block
  [0x2C4] = true, -- Obstruct
}

local state = {
  current = nil,
  foe = nil,
  selectedPartner = nil,
  mapHasRaid = nil,
  stars = nil,
  stable = nil,
}
Raids._state = state

local function mergeDefaults(overrides)
  local deps = {}
  for key, value in pairs(overrides or {}) do deps[key] = value end
  local modules = {
    Natives = "src.core.game3.scripting.natives",
    Flags = "src.core.game3.scripting.flags",
    Pokemon = "src.core.game3.pokemon",
    Party = "src.core.game3.party",
    Bag = "src.core.game3.bag",
    ItemsData = "src.core.game3.items_data",
    Rng = "src.core.game3.rng",
  }
  for key, moduleName in pairs(modules) do
    if deps[key] == nil then deps[key] = require(moduleName) end
  end
  if deps.bit == nil then deps.bit = require("bit") end
  return deps
end

local function storeOf()
  local Space = package.loaded["src.core.game3.scripting.space"]
  return Space and Space.store or nil
end

local function sessionOf(deps)
  if deps.getSession then return deps.getSession() end
  local Runtime = package.loaded["src.core.game3.runtime"]
  return Runtime and Runtime.getSession and Runtime.getSession() or nil
end

local function getVar(deps, ctx, id)
  return tonumber(deps.Flags.getVar(storeOf(), ctx, id)) or 0
end

local function setVar(deps, ctx, id, value)
  value = math.floor(tonumber(value) or 0) % 0x10000
  deps.Flags.setVar(storeOf(), ctx, id, value)
  if ctx and type(ctx.setVar) == "function" then ctx:setVar(id, value) end
end

local function setResult(deps, ctx, value)
  setVar(deps, ctx, VAR.RESULT, value)
  return value
end

local function getFlag(deps, ctx, id)
  return deps.Flags.getFlag(storeOf(), ctx, id) == true
end

local function setFlag(deps, ctx, id, on)
  deps.Flags.setFlag(storeOf(), ctx, id, on ~= false)
end

local function setString(ctx, adapters, index, value)
  value = tostring(value or "")
  if ctx then
    ctx.stringVars = ctx.stringVars or {}
    ctx.stringVars[index] = value
  end
  if adapters and adapters.setStringVar then adapters.setStringVar(index, value) end
end

local function byteAt(bytes, offset)
  return bytes:byte(offset + 1) or 0
end

local function u16(bytes, offset)
  return byteAt(bytes, offset) + byteAt(bytes, offset + 1) * 0x100
end

local function u32(bytes, offset)
  return u16(bytes, offset) + u16(bytes, offset + 2) * 0x10000
end

local function read(rom, offset, length)
  assert(rom and rom._read, "Radical Red raids require the validated ROM")
  local bytes = rom:_read(offset, length)
  assert(type(bytes) == "string" and #bytes == length,
    ("short Radical Red raid read at 0x%X"):format(offset))
  return bytes
end

local function pointerOffset(pointer)
  pointer = tonumber(pointer) or 0
  if pointer < 0x08000000 or pointer >= 0x0A000000 then return nil end
  return pointer - 0x08000000
end

local function bxor32(deps, a, b)
  local value = deps.bit.bxor(math.floor(a or 0), math.floor(b or 0))
  if value < 0 then value = value + 4294967296 end
  return value
end

local function random16(deps)
  if deps.random16 then return math.floor(deps.random16()) % 0x10000 end
  return deps.Rng.Random and deps.Rng.Random() or math.random(0, 0xFFFF)
end

local function random32(deps)
  if deps.random32 then return math.floor(deps.random32()) % 4294967296 end
  if deps.Rng.Random32 then return deps.Rng.Random32() end
  return random16(deps) + random16(deps) * 0x10000
end

local function randomMod(deps, count, wide)
  count = math.floor(tonumber(count) or 0)
  if count <= 0 then return 0 end
  return ((wide and random32(deps) or random16(deps)) % count)
end

local function decodeText(bytes)
  local out = {}
  for i = 1, #bytes do
    local b = bytes:byte(i)
    if b == 0xFF then break end
    if b == 0 then
      out[#out + 1] = " "
    elseif b >= 0xA1 and b <= 0xAA then
      out[#out + 1] = tostring(b - 0xA1)
    elseif b >= 0xBB and b <= 0xD4 then
      out[#out + 1] = string.char(string.byte("A") + b - 0xBB)
    elseif b >= 0xD5 and b <= 0xEE then
      out[#out + 1] = string.char(string.byte("a") + b - 0xD5)
    elseif b == 0xAE then
      out[#out + 1] = "-"
    elseif b == 0xB8 then
      out[#out + 1] = ","
    elseif b == 0xAD then
      out[#out + 1] = "."
    elseif b == 0xAC then
      out[#out + 1] = "?"
    elseif b == 0xAB then
      out[#out + 1] = "!"
    elseif b == 0xB4 then
      out[#out + 1] = "'"
    else
      out[#out + 1] = " "
    end
  end
  return table.concat(out):gsub("%s+$", "")
end

local function readTextPointer(rom, pointer, maxLength)
  local offset = pointerOffset(pointer)
  if not offset then return "" end
  return decodeText(read(rom, offset, maxLength or 24))
end

local function currentMapIndex(deps)
  if deps.currentMapIndex then return deps.currentMapIndex() end
  local session = sessionOf(deps)
  local section = session and deps.Pokemon.currentMapSec and deps.Pokemon.currentMapSec(session)
  section = tonumber(section)
  if not section then return nil end
  local index = section - MAPSEC_DYNAMIC
  if index < 0 or index >= KANTO_MAPSEC_COUNT then return nil end
  return index
end

local function mapPair(mapId)
  if type(mapId) ~= "string" then return nil, nil end
  local ok, Catalog = pcall(require, "src.import.gba.map_catalog")
  local key = ok and Catalog and Catalog.slotKeyFor and Catalog.slotKeyFor(mapId)
  if not key then return nil, nil end
  local group, num = key:match("^(%d+)_(%d+)$")
  return tonumber(group), tonumber(num)
end

local function nonzeroByte(value, fallback)
  value = math.floor(tonumber(value) or 0) % 0x100
  return value == 0 and fallback or value
end

-- dynamax.c:GetRaidRandomNumber.  RR intentionally uses a stable number so a
-- den keeps the same contents for the current hour.
local function raidRandomNumber(deps, ctx)
  if deps.raidRandomNumber then return deps.raidRandomNumber(ctx) % 4294967296 end
  local session = sessionOf(deps) or {}
  local now = (deps.now and deps.now()) or os.date("*t")
  local dayOfWeek = nonzeroByte(now.wday, 8)
  local hour = nonzeroByte(now.hour, 24)
  local day = nonzeroByte(now.day, 32)
  local month = nonzeroByte(now.month, 13)
  local dw = session.dynamicWarp or {}
  local group = tonumber(dw.mapGroup or dw.group)
  local num = tonumber(dw.mapNum or dw.num)
  if group == nil or num == nil then
    group, num = mapPair(dw.map or session.map)
  end
  group = nonzeroByte(group, 0xFF)
  num = nonzeroByte(num, 0xFF)
  local warp = nonzeroByte(dw.warpId, 0xFF)
  local x, y = tonumber(dw.x) or 0, tonumber(dw.y) or 0
  local pos = x + y
  if pos == 0 then pos = 0xFFFF end
  local offset = getVar(deps, ctx, VAR.RAID_NUMBER_OFFSET)
  local trainer = tonumber(session.trainerId or session.id or session.playerId) or 0
  local secret = tonumber(session.secretId or session.otSecretId) or 0
  if trainer < 0x10000 then trainer = trainer + (secret % 0x10000) * 0x10000 end
  local left = hour * (day + month) * group * (num + warp + pos)
  local inner = bxor32(deps, hour * (day + month), dayOfWeek)
  return bxor32(deps, (left + inner + offset) % 4294967296, trainer)
end

local function countBadges(deps, ctx)
  if getFlag(deps, ctx, FLAG.BATTLE_FACILITY) or getFlag(deps, ctx, FLAG.GAME_CLEAR) then
    return 9
  end
  local count = 0
  for _, flag in ipairs(BADGE_FLAGS) do
    if getFlag(deps, ctx, flag) then count = count + 1 end
  end
  return count
end

local function determineStars(deps, ctx, stable)
  local row = STAR_BY_BADGES[countBadges(deps, ctx)] or STAR_BY_BADGES[0]
  if row[1] == row[2] then return row[1] end
  return row[1] + (stable % (row[2] - row[1] + 1))
end

local function descriptor(rom, mapIndex, stars)
  if not mapIndex or mapIndex < 0 or mapIndex >= KANTO_MAPSEC_COUNT then return nil end
  if not stars or stars < 0 or stars >= RAID_STAR_COUNT then return nil end
  local slot = mapIndex * RAID_STAR_COUNT + stars
  local bytes = read(rom, ROM.RAID_TABLE + slot * RAID_DATA_SIZE, RAID_DATA_SIZE)
  local pointer, amount = u32(bytes, 0), u16(bytes, 4)
  local offset = pointerOffset(pointer)
  if not offset or amount <= 0 then return nil end
  return { pointer = pointer, offset = offset, amount = amount }
end

local function raidRecord(rom, desc, index)
  if not desc or index < 0 or index >= desc.amount then return nil end
  local bytes = read(rom, desc.offset + index * RAID_RECORD_SIZE, RAID_RECORD_SIZE)
  local drops = {}
  for i = 0, MAX_RAID_DROPS - 1 do drops[i + 1] = u16(bytes, 6 + i * 2) end
  return {
    species = u16(bytes, 0), item = u16(bytes, 2), ability = byteAt(bytes, 4),
    drops = drops, recordIndex = index,
  }
end

local function levelForStars(stars, stable)
  local range = STAR_RANGES[stars]
  if not range then return 1 end
  if range[1] == range[2] then return range[1] end
  return range[1] + (stable % (range[2] - range[1]))
end

local spreadAt

local function evolutionTarget(rom, species, method, item, moves)
  species = math.floor(tonumber(species) or 0)
  if species <= 0 then return nil end
  local moveSet = {}
  for _, move in ipairs(moves or {}) do moveSet[tonumber(move) or -1] = true end
  local base = ROM.EVOLUTION_TABLE
    + species * EVOLUTIONS_PER_SPECIES * EVOLUTION_ENTRY_SIZE
  local bytes = read(rom, base,
    EVOLUTIONS_PER_SPECIES * EVOLUTION_ENTRY_SIZE)
  for index = 0, EVOLUTIONS_PER_SPECIES - 1 do
    local offset = index * EVOLUTION_ENTRY_SIZE
    local evoMethod = u16(bytes, offset)
    local param = u16(bytes, offset + 2)
    local target = u16(bytes, offset + 4)
    local variant = u16(bytes, offset + 6)
    if evoMethod == method and param ~= 0 and target ~= 0 then
      if method == 0xFD then return target end
      if (variant == 0 or variant == 3) and param == (tonumber(item) or 0) then
        return target
      end
      if variant == 2 and moveSet[param] then return target end
    end
  end
  return nil
end

local function facilitySpread(rom, stable)
  local legendary = stable % 100 >= 90
  local offset = legendary and ROM.FRONTIER_LEGENDARY_SPREADS or ROM.FRONTIER_SPREADS
  local count = legendary and FRONTIER_LEGENDARY_SPREAD_COUNT or FRONTIER_SPREAD_COUNT
  return spreadAt(rom, 0x08000000 + offset, stable % count), legendary
end

local function determineRaid(deps, rom, ctx)
  local mapIndex = currentMapIndex(deps)
  local stable = raidRandomNumber(deps, ctx)
  local stars = determineStars(deps, ctx, stable)
  state.stable, state.stars = stable, stars
  if getFlag(deps, ctx, FLAG.BATTLE_FACILITY) then
    local spread, legendary = facilitySpread(rom, stable)
    if not spread or spread.species == 0 then return nil end
    local species = evolutionTarget(rom, spread.species, 0xFE,
      spread.item, spread.moves)
    local gigantamax = false
    if not species then
      species = evolutionTarget(rom, spread.species, 0xFD)
      gigantamax = species ~= nil
    end
    species = species or spread.species
    local level = getVar(deps, ctx, VAR.FACILITY_LEVEL)
    if level <= 0 then level = 50 end
    local drops = stars <= 4 and FACILITY_DROPS_4 or FACILITY_DROPS_56
    local recordDrops = {}
    for i, item in ipairs(drops) do recordDrops[i] = item end
    local record = {
      species = spread.species, item = spread.item, ability = spread.ability,
      drops = recordDrops, recordIndex = stable % (legendary
        and FRONTIER_LEGENDARY_SPREAD_COUNT or FRONTIER_SPREAD_COUNT),
    }
    local data = {
      mapIndex = mapIndex, stable = stable, stars = stars, level = level,
      record = record, spread = spread, species = species,
      baseSpecies = spread.species, facility = true, legendaryPool = legendary,
      gigantamax = gigantamax, recommendedLevel = level,
    }
    state.current = data
    return data
  end
  if mapIndex == nil then return nil end
  local desc = descriptor(rom, mapIndex, stars)
  if not desc then return nil end
  local record = raidRecord(rom, desc, stable % desc.amount)
  if not record or record.species == 0 then return nil end
  local species = record.species
  local gigantamax = false
  if stars >= 6 and (stable % 100 >= 95 or stable % 100 < 20) then
    local form = evolutionTarget(rom, species, 0xFD)
    if form then species, gigantamax = form, true end
  end
  local data = {
    mapIndex = mapIndex, stable = stable, stars = stars, level = levelForStars(stars, stable),
    descriptor = desc, record = record, species = species,
    baseSpecies = record.species, gigantamax = gigantamax,
    recommendedLevel = (STAR_RANGES[stars] and STAR_RANGES[stars][2] + 5) or 1,
  }
  state.current = data
  return data
end

local function partnerCount(rom)
  return byteAt(read(rom, ROM.RAID_PARTNER_COUNT, 1), 0)
end

local function partnerAt(rom, index)
  local bytes = read(rom, ROM.RAID_PARTNERS + index * RAID_PARTNER_SIZE, RAID_PARTNER_SIZE)
  local pointers, sizes = {}, {}
  for star = 0, RAID_STAR_COUNT - 1 do
    pointers[star] = u32(bytes, 16 + star * 4)
    sizes[star] = u16(bytes, 44 + star * 2)
  end
  local name = readTextPointer(rom, u32(bytes, 12), 24)
  return {
    id = index, owNum = u16(bytes, 0), trainerClass = byteAt(bytes, 2),
    backSpriteId = byteAt(bytes, 3), gender = byteAt(bytes, 4),
    otId = u32(bytes, 8), name = name ~= "" and name or ("PARTNER " .. (index + 1)),
    spreadPointers = pointers, spreadSizes = sizes,
  }
end

spreadAt = function(rom, pointer, index)
  local offset = pointerOffset(pointer)
  if not offset then return nil end
  local bytes = read(rom, offset + index * FRONTIER_SPREAD_SIZE, FRONTIER_SPREAD_SIZE)
  local packedIv = u32(bytes, 4)
  local ivs = {}
  for i, key in ipairs(STAT_KEYS) do
    ivs[key] = math.floor(packedIv / (2 ^ ((i - 1) * 5))) % 32
  end
  local moves = {}
  for i = 0, 3 do moves[i + 1] = u16(bytes, 16 + i * 2) end
  local flags = byteAt(bytes, 25)
  return {
    species = u16(bytes, 0), nature = byteAt(bytes, 2), ball = byteAt(bytes, 3),
    ivs = ivs,
    evs = {
      hp = byteAt(bytes, 8), atk = byteAt(bytes, 9), def = byteAt(bytes, 10),
      spe = byteAt(bytes, 11), spa = byteAt(bytes, 12), spd = byteAt(bytes, 13),
    },
    item = u16(bytes, 14), moves = moves, specificTeamType = byteAt(bytes, 24),
    shiny = flags % 2 == 1, ability = math.floor(flags / 16) % 4,
    gigantamax = math.floor(flags / 64) % 2 == 1,
    level = byteAt(bytes, 26),
  }
end

local function selectPartners(deps, rom, raid)
  local count = partnerCount(rom)
  local checked, selected, marked = {}, {}, 0
  local value = raid.stable
  local i = 1
  while #selected < 3 and marked < count and i < 0x10000 do
    if value == 0 then value = 0xFFFFFFFF end
    value = bxor32(deps, value, i)
    local index = value % count
    if checked[index] == nil then
      local partner = partnerAt(rom, index)
      marked = marked + 1
      if pointerOffset(partner.spreadPointers[raid.stars])
          and (partner.spreadSizes[raid.stars] or 0) > 0 then
        checked[index] = true
        selected[#selected + 1] = partner
      else
        checked[index] = false
      end
    end
    i = i + 1
  end
  if #selected < 3 then
    for index = 0, count - 1 do
      if checked[index] == nil then
        local partner = partnerAt(rom, index)
        if pointerOffset(partner.spreadPointers[raid.stars])
            and (partner.spreadSizes[raid.stars] or 0) > 0 then
          selected[#selected + 1] = partner
          if #selected >= 3 then break end
        end
      end
    end
  end
  for _, partner in ipairs(selected) do
    partner.team = {}
    for slot = 0, math.min(2, (partner.spreadSizes[raid.stars] or 0) - 1) do
      local spread = spreadAt(rom, partner.spreadPointers[raid.stars], slot)
      partner.team[#partner.team + 1] = spread
    end
  end
  return selected
end

local function speciesName(deps, species)
  local ok, name = pcall(deps.Pokemon.name, species)
  return ok and name or ("SPECIES " .. tostring(species))
end

local function abilityIds(rom, species)
  local base
  if rom.pointerAt then
    local ok, offset = pcall(rom.pointerAt, rom, 0x1BC)
    if ok then base = offset end
  end
  if not base then
    local pointer = u32(read(rom, 0x1BC, 4), 0)
    base = pointerOffset(pointer)
  end
  if not base then return 0, 0, 0 end
  local row = read(rom, base + species * 28, 28)
  return byteAt(row, 22), byteAt(row, 23), byteAt(row, 26)
end

local function chooseAbility(deps, rom, species, abilityRule, personality)
  local a1, a2, hidden = abilityIds(rom, species)
  if abilityRule == 0 then return hidden ~= 0 and hidden or a1, true end
  if abilityRule == 1 then return a1, false end
  if abilityRule == 2 then return a2 ~= 0 and a2 or a1, false end
  if abilityRule == 4 and randomMod(deps, 2) == 1 and hidden ~= 0 then return hidden, true end
  if a2 ~= 0 and personality % 2 == 1 then return a2, false end
  return a1, false
end

local function uniquePerfectIvs(deps, ivs, count)
  local chosen, done = {}, 0
  while done < math.min(6, count) do
    local index = randomMod(deps, 6) + 1
    if not chosen[index] then
      chosen[index] = true
      ivs[STAT_KEYS[index]] = 31
      done = done + 1
    end
  end
end

local function appendMove(deps, mon, move)
  if not move or move == 0 then return end
  for _, known in ipairs(mon.moves) do if known == move then return end end
  if #mon.moves >= 4 then
    table.remove(mon.moves, 1)
    table.remove(mon.pp, 1)
    table.remove(mon.maxPp, 1)
  end
  local pp = deps.Pokemon.movePp and deps.Pokemon.movePp(move) or 5
  mon.moves[#mon.moves + 1] = move
  mon.pp[#mon.pp + 1] = pp
  mon.maxPp[#mon.maxPp + 1] = pp
end

local function makeRaidMon(deps, rom, raid)
  local species, level = raid.species, raid.level
  if raid.facility and raid.spread then
    local spread = raid.spread
    local personality = random32(deps)
    personality = personality - (personality % 50) + (spread.nature % 25)
    local wantedParity
    if spread.ability == 1 then wantedParity = 0
    elseif spread.ability == 2 then wantedParity = 1 end
    if wantedParity ~= nil and personality % 2 ~= wantedParity then
      personality = personality + 25
    end
    if personality >= 4294967296 then personality = personality - 50 end
    local ability, hidden = chooseAbility(deps, rom, species,
      spread.ability, personality)
    local ivs, evs, moves, pp, maxPp = {}, {}, {}, {}, {}
    for _, key in ipairs(STAT_KEYS) do
      ivs[key] = tonumber(spread.ivs and spread.ivs[key]) or 0
      evs[key] = tonumber(spread.evs and spread.evs[key]) or 0
    end
    for _, move in ipairs(spread.moves or {}) do
      if move ~= 0 then
        moves[#moves + 1] = move
        local value = deps.Pokemon.movePp and deps.Pokemon.movePp(move) or 5
        pp[#pp + 1], maxPp[#maxPp + 1] = value, value
      end
    end
    local mon = {
      species = species, speciesId = species,
      name = speciesName(deps, species), nickname = "",
      level = level, metLevel = level, personality = personality,
      nature = spread.nature, ivs = ivs, evs = evs,
      ability = ability, abilityId = ability, hiddenAbility = hidden or nil,
      item = spread.item ~= 0 and spread.item or nil,
      heldItem = spread.item ~= 0 and spread.item or nil,
      moves = moves, pp = pp, maxPp = maxPp,
      pokeball = spread.ball ~= 0 and spread.ball or 4,
      gender = deps.Pokemon.gender and deps.Pokemon.gender(species, personality) or "U",
      friendship = 255, happiness = 255,
      isShiny = spread.shiny or nil, shiny = spread.shiny or nil,
      gigantamax = raid.gigantamax or spread.gigantamax or nil,
      rrRaid = true, rrFacility = true, raidStars = raid.stars,
    }
    deps.Pokemon.applyStats(mon)
    mon.raidBaseMaxHp = tonumber(mon.maxHp) or 1
    if species ~= 303 then mon.maxHp = mon.raidBaseMaxHp * 4 end
    mon.hp = mon.maxHp
    return mon
  end
  local personality = random32(deps)
  local ivs = {
    hp = randomMod(deps, 32), atk = randomMod(deps, 32), def = randomMod(deps, 32),
    spe = randomMod(deps, 32), spa = randomMod(deps, 32), spd = randomMod(deps, 32),
  }
  uniquePerfectIvs(deps, ivs, raid.stars)
  local ability, hidden = chooseAbility(deps, rom, species, raid.record.ability, personality)
  if raid.record.ability == 1 then personality = personality - (personality % 2) end
  if raid.record.ability == 2 then personality = personality - (personality % 2) + 1 end
  local moves, pp, maxPp = deps.Pokemon.movesAtLevel(species, level)
  moves, pp, maxPp = moves or {}, pp or {}, maxPp or {}
  local mon = {
    species = species, speciesId = species, name = speciesName(deps, species), nickname = "",
    level = level, personality = personality,
    nature = deps.Pokemon.natureId and deps.Pokemon.natureId(personality) or personality % 25,
    ivs = ivs, evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 },
    ability = ability, abilityId = ability, hiddenAbility = hidden or nil,
    item = raid.record.item ~= 0 and raid.record.item or nil,
    moves = moves, pp = pp, maxPp = maxPp,
    gender = deps.Pokemon.gender and deps.Pokemon.gender(species, personality) or "U",
    rrRaid = true, raidStars = raid.stars, gigantamax = raid.gigantamax or nil,
  }
  local eggMoves = deps.Pokemon.eggMoves and deps.Pokemon.eggMoves(species) or nil
  local chance = EGG_MOVE_CHANCE[raid.stars] or 0
  for _ = 1, 4 do
    if eggMoves and #eggMoves > 0 and randomMod(deps, 100) < chance then
      local move = eggMoves[randomMod(deps, #eggMoves) + 1]
      local duplicate = false
      for _, known in ipairs(mon.moves) do if known == move then duplicate = true break end end
      if duplicate then move = eggMoves[randomMod(deps, #eggMoves) + 1] end
      appendMove(deps, mon, move)
    end
  end
  deps.Pokemon.applyStats(mon)
  mon.raidBaseMaxHp = tonumber(mon.maxHp) or 1
  -- v4.1 GetRaidBattleHPBoost is always four; Shedinja is the sole exception.
  if species ~= 303 then mon.maxHp = mon.raidBaseMaxHp * 4 end
  mon.hp = mon.maxHp
  return mon
end

local function personalityForSpread(deps, spread, partner)
  local wantedParity = spread.ability > 0 and math.min(1, spread.ability - 1) or nil
  local tid, sid = partner.otId % 0x10000, math.floor(partner.otId / 0x10000) % 0x10000
  for _ = 1, 131072 do
    local pid = random32(deps)
    if wantedParity ~= nil then pid = pid - (pid % 2) + wantedParity end
    if spread.shiny then
      local low = pid % 0x10000
      local shiny = randomMod(deps, 8)
      local high = bxor32(deps, bxor32(deps, bxor32(deps, shiny, sid), tid), low) % 0x10000
      pid = low + high * 0x10000
    end
    if pid % 25 == spread.nature then return pid end
  end
  return spread.nature
end

local function randomRaidLevel(deps, stars)
  local range = STAR_RANGES[stars] or { 1, 2 }
  return range[1] + randomMod(deps, math.max(1, range[2] - range[1]))
end

local function makePartnerMon(deps, rom, raid, partner, spread)
  local personality = personalityForSpread(deps, spread, partner)
  local a1, a2, hidden = abilityIds(rom, spread.species)
  local ability, isHidden
  if spread.ability == 0 then
    ability, isHidden = hidden ~= 0 and hidden or a1, true
  elseif spread.ability == 2 then
    ability = a2 ~= 0 and a2 or a1
  else
    ability = a1
  end
  local pp, maxPp = {}, {}
  for i, move in ipairs(spread.moves) do
    local value = deps.Pokemon.movePp and deps.Pokemon.movePp(move) or 5
    pp[i], maxPp[i] = value, value
  end
  local mon = {
    species = spread.species, speciesId = spread.species,
    name = speciesName(deps, spread.species), nickname = "",
    level = randomRaidLevel(deps, raid.stars), personality = personality,
    nature = spread.nature, ivs = spread.ivs, evs = spread.evs,
    ability = ability, abilityId = ability, hiddenAbility = isHidden or nil,
    item = spread.item ~= 0 and spread.item or nil,
    moves = spread.moves, pp = pp, maxPp = maxPp,
    gender = deps.Pokemon.gender and deps.Pokemon.gender(spread.species, personality) or "U",
    ot = partner.name, otName = partner.name, otId = partner.otId,
    friendship = 255, happiness = 255, pokeball = 4,
    rrRaidPartner = true, gigantamax = spread.gigantamax or nil,
  }
  deps.Pokemon.applyStats(mon)
  mon.hp = mon.maxHp
  return mon
end

local function buildPartnerParty(deps, rom, raid, partner)
  local party = {}
  for _, spread in ipairs(partner and partner.team or {}) do
    party[#party + 1] = makePartnerMon(deps, rom, raid, partner, spread)
  end
  return party
end

local function shieldRatio(level)
  if level < 20 then return 1 end
  if level <= 40 then return 2 end
  if level <= 70 then return 3 end
  return 4
end

local function raidRuleLevel(raid, battler)
  if raid and raid.facility then return 100 end
  return tonumber(battler and battler.mon and battler.mon.level) or 1
end

local function koStatIncrease(raid, battler)
  local level = raidRuleLevel(raid, battler)
  if level < 20 then return 0 end
  if level <= 40 then return 1 end
  if level <= 70 then return 2 end
  return 3
end

local function repeatedAttackChance(raid, battler)
  local level = raidRuleLevel(raid, battler)
  if level < 20 then return 0 end
  if level <= 40 then return 30 end
  if level <= 70 then return 50 end
  return 70
end

local function statNullificationChance(raid, battler)
  if (tonumber(battler and battler.isFirstTurn) or 0) > 0 then return 0 end
  local level = raidRuleLevel(raid, battler)
  if level < 20 then return 0 end
  if level <= 40 then return 20 end
  if level <= 70 then return 35 end
  return 50
end

local function shieldCount(deps, species, noForceEnd)
  local stats = deps.Pokemon.stats and deps.Pokemon.stats(species) or {}
  local total = 0
  for _, key in ipairs({ "hp", "atk", "def", "spe", "spa", "spd" }) do
    total = total + (tonumber(stats and stats[key]) or 0)
  end
  if total <= 349 then return 1 end
  if total <= 494 then return 2 end
  if total <= 568 then return 3 end
  if noForceEnd and total >= 600 then return 5 end
  return 4
end

local function maxMovePower(basePower, moveType)
  basePower = math.max(1, math.floor(tonumber(basePower) or 1))
  local reduced = moveType == 1 or moveType == 3
  if reduced then
    if basePower <= 40 then return 70 end
    if basePower <= 50 then return 75 end
    if basePower <= 60 then return 80 end
    if basePower <= 70 then return 85 end
    if basePower <= 100 then return 90 end
    if basePower <= 140 then return 95 end
    return 100
  end
  if basePower <= 40 then return 90 end
  if basePower <= 50 then return 100 end
  if basePower <= 60 then return 110 end
  if basePower <= 70 then return 120 end
  if basePower <= 100 then return 130 end
  if basePower <= 140 then return 140 end
  return 150
end

local function maxMoveFor(move)
  if not move or move.category == "status" or (tonumber(move.power) or 0) <= 0 then
    return MOVE.MAX_GUARD
  end
  local pair = MAX_MOVE_BY_TYPE[tonumber(move.type)] or MAX_MOVE_BY_TYPE[0]
  return pair[move.category == "special" and 2 or 1]
end

local function bossUsesRegularMove(st, raid, battler, moveId, move)
  if not move or move.category == "status" or moveId == MOVE.STRUGGLE then return true end
  if battler and (battler.expMustRecharge or battler.recharge
      or battler.expLockedMove or battler.twoTurnMove
      or (tonumber(battler.expRampageTurns) or 0) > 0
      or (tonumber(battler.expUproarTurns) or 0) > 0) then
    return true
  end
  local randomTurn = math.floor(tonumber(st and st.randomTurnNumber) or 0)
  if (tonumber(raid and raid.stars) or 0) < 4 then return randomTurn % 4 == 0 end
  return randomTurn % 100 >= 90
end

local function isZMove(moveId)
  moveId = tonumber(moveId) or -1
  return moveId >= MOVE.FIRST_Z and moveId <= MOVE.LAST_Z
end

local function shieldBreaksFor(raidMove)
  if not raidMove then return 1 end
  if raidMove.isZ then return 3 end
  if raidMove.isMax or raidMove.effect == 38 or raidMove.effect == 186 then return 2 end
  return 1
end

local function nextShieldCutoff(hp, maxHp, ratio)
  local previous = 0
  for i = 1, ratio do
    local cutoff = math.floor(maxHp * i / ratio)
    if i == ratio then cutoff = maxHp end
    if hp > previous and hp <= cutoff then return previous end
    previous = cutoff
  end
  return 0
end

local function decorateRaidAdapter(deps, adapter, battleState)
  if not adapter or adapter._rrRaidDecorated then return adapter end
  adapter._rrRaidDecorated = true
  local raid = battleState.raid
  local originalLoss = adapter.applyHpLoss
  local originalFaint = adapter.emitFaint
  local originalAbilityOf = adapter.abilityOf

  local function chance(self, percent)
    percent = math.floor(tonumber(percent) or 0)
    if percent <= 0 then return false end
    if percent >= 100 then return true end
    return self:roll(0, 99) < percent
  end

  adapter.abilityOf = function(self, battler)
    -- CFRU temporarily disables abilities that a Mold Breaker-style action
    -- ignores after a raid nullification.  The host has no equivalent mask;
    -- suppressing non-boss abilities for this one action preserves the
    -- observable protection/immunity behavior and is cleared by the resolver.
    if raid and raid.nullifiedStats and battler ~= battleState.enemy then return nil end
    return originalAbilityOf(self, battler)
  end

  adapter.applyHpLoss = function(self, battler, amount, opts)
    if battler ~= battleState.enemy or not raid or not opts or not opts.hit then
      return originalLoss(self, battler, amount, opts)
    end
    local before = tonumber(battler.mon and battler.mon.hp) or 0
    local maxHp = math.max(1, tonumber(battler.mon and battler.mon.maxHp) or 1)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if raid.shieldsUp then
      amount = math.floor(amount / math.max(1, math.floor(before / 8)))
      if amount <= 0 and before > 0 then amount = 1 end
      if amount >= before then amount = math.max(0, before - 1) end
      local lost = originalLoss(self, battler, amount, opts)
      local move = raid.currentMove
      local serial = move and move.serial
      if lost > 0 and (serial == nil or raid.lastShieldBreakSerial ~= serial) then
        raid.lastShieldBreakSerial = serial
        raid.shieldsDestroyed = (raid.shieldsDestroyed or 0) + shieldBreaksFor(move)
        if raid.shieldsDestroyed >= (raid.shieldCount or 1) then
          raid.shieldsUp = false
          if self.say then self:say("The mysterious barrier was broken!") end
          local residual = math.max(1, math.floor(maxHp / 6))
          if raid.shieldsDestroyed > (raid.shieldCount or 1) then
            residual = math.max(1, math.floor(residual * 3 / 2))
          end
          originalLoss(self, battler, residual, { hit = false })
        end
      end
      return lost
    end

    local ratio = shieldRatio(tonumber(battler.mon.level) or 1)
    local cutoff = nextShieldCutoff(before, maxHp, ratio)
    if cutoff > 0 and before - amount < cutoff then amount = before - cutoff end
    local lost = originalLoss(self, battler, amount, opts)
    local after = tonumber(battler.mon.hp) or 0
    if cutoff > 0 and before > cutoff and after > 0
        and after <= cutoff + math.floor(maxHp / 16) then
      raid.shieldsUp = true
      raid.shieldsDestroyed = 0
      raid.lastShieldBreakSerial = nil
      raid.shieldCount = shieldCount(deps, battler.species, raid.noForceEnd)
      if self.say then self:say("A mysterious barrier appeared!") end
    end
    return lost
  end

  adapter.emitFaint = function(self, battler)
    local result = originalFaint(self, battler)
    -- emitFaint is normally called after the engine has already written HP=0,
    -- so current HP cannot be used to decide whether this is the first faint.
    if battler and battler.side == "player" and raid
        and not battler._rrRaidFaintCounted then
      battler._rrRaidFaintCounted = true
      raid.faints = (raid.faints or 0) + 1
      raid.stormLevel = raid.faints

      local boss = battleState.enemy
      if boss and not self:isFainted(boss)
          and (not raid.currentMove or raid.currentMove.baseId ~= MOVE.STRUGGLE)
          and chance(self, repeatedAttackChance(raid, boss)) then
        raid.attackAgain = true
      end

      if boss and not self:isFainted(boss) and chance(self, 50) then
        local increase = koStatIncrease(raid, boss)
        if increase > 0 then
          local key = chance(self, 50) and "spAtk" or "attack"
          local changed = self:changeStages(boss, { [key] = increase })
          if changed[key] and changed[key].delta ~= 0 and self.say then
            self:say("The raid Pokémon became stronger after the knockout!")
          end
        end
      end

      if raid.faints >= 4 and not raid.noForceEnd then
        battleState.over, battleState.result = true, "lose"
        battleState.endReason = "raid_four_faints"
      end
    end
    return result
  end
  return adapter
end

local function copyRecord(value)
  local out = {}
  for key, item in pairs(value or {}) do out[key] = item end
  return out
end

local function effectiveMoveId(user, moveId, opts)
  opts = opts or {}
  if not opts.called and user then
    if user.expLockedMove and not opts.pursuitSwitch then return user.expLockedMove end
    if user.expEncoreMove and (tonumber(user.expEncoreTurns) or 0) > 0 then
      return user.expEncoreMove
    end
  end
  return moveId
end

local function blockedMoveResult(State, Engine, user, target, moveId, slot,
    adapter, st, out, message)
  out = out or {}
  user = State.occupant(st, user)
  target = State.occupant(st, target)
  local mark = adapter.eventMark and adapter:eventMark() or 0
  if user and user.mon and slot and user.mon.pp then
    user.mon.pp[slot] = math.max(0, (tonumber(user.mon.pp[slot]) or 0) - 1)
  end
  if user then
    user.expMovedThisTurn = true
    user.lastMoveId, user.lastMove = moveId, moveId
  end
  if adapter.pushEvent then
    adapter:pushEvent({
      kind = "move", moveId = moveId,
      attacker = user and user.side, target = target and target.side,
      attackerId = user and State.idOf(user),
      targetId = target and State.idOf(target), turn = 0,
    })
    adapter:pushEvent({ kind = "msg", text = message, id = "RR_RAID_PREVENTS" })
  end
  out[#out + 1] = message
  local events = adapter.eventsSince and adapter:eventsSince(mark) or {}
  out.events = events
  out._anim = {
    moveId = moveId, user = user, target = target,
    hits = {}, heals = {}, faints = {}, missed = true,
    cancelled = true, statusOnly = true, events = events,
    msgs = { message },
  }
  if Engine.afterAction then Engine.afterAction(st, adapter) end
  return out
end

local function nullifyRaidStats(State, adapter, st, raid, boss)
  if not boss or statNullificationChance(raid, boss) <= 0 then return false end
  if adapter:roll(0, 99) >= statNullificationChance(raid, boss) then return false end
  for _, battler in ipairs(State.present(st)) do
    if battler ~= boss and not adapter:isFainted(battler) then
      for _, key in ipairs({
        "attack", "defense", "spAtk", "spDef", "speed", "accuracy", "evasion",
      }) do
        battler.stages[key] = 0
      end
      battler.expLightningRodRedirected = nil
    end
  end
  adapter:clearStatus(boss)
  raid.nullifiedStats = true
  return true
end

local function applyMaxMoveEffect(State, adapter, st, boss, baseMove)
  local moveType = tonumber(baseMove and baseMove.type) or 0
  local function change(list, changes)
    for _, battler in ipairs(list) do
      if battler and not adapter:isFainted(battler) then adapter:changeStages(battler, changes) end
    end
  end
  local allies, foes = State.allies(st, boss), State.foes(st, boss)
  local message
  if moveType == 0 then
    change(foes, { speed = -1 }); message = "Max Strike lowered the opposing side's Speed!"
  elseif moveType == 1 then
    change(allies, { attack = 1 }); message = "Max Knuckle raised the raid Pokémon's Attack!"
  elseif moveType == 2 then
    change(allies, { speed = 1 }); message = "Max Airstream raised the raid Pokémon's Speed!"
  elseif moveType == 3 then
    change(allies, { spAtk = 1 }); message = "Max Ooze raised the raid Pokémon's Sp. Atk!"
  elseif moveType == 4 then
    change(allies, { spDef = 1 }); message = "Max Quake raised the raid Pokémon's Sp. Def!"
  elseif moveType == 5 then
    adapter:setWeather("SAND", 5); message = "Max Rockfall whipped up a sandstorm!"
  elseif moveType == 6 then
    change(foes, { spAtk = -1 }); message = "Max Flutterby lowered the opposing side's Sp. Atk!"
  elseif moveType == 7 then
    change(foes, { defense = -1 }); message = "Max Phantasm lowered the opposing side's Defense!"
  elseif moveType == 8 then
    change(allies, { defense = 1 }); message = "Max Steelspike raised the raid Pokémon's Defense!"
  elseif moveType == 10 then
    adapter:setWeather("SUN", 5); message = "Max Flare intensified the sunlight!"
  elseif moveType == 11 then
    adapter:setWeather("RAIN", 5); message = "Max Geyser made it rain!"
  elseif moveType == 12 then
    st.rrTerrain, st.rrTerrainTurns = "GRASSY", 5
    message = "Max Overgrowth covered the field in grass!"
  elseif moveType == 13 then
    st.rrTerrain, st.rrTerrainTurns = "ELECTRIC", 5
    message = "Max Lightning electrified the field!"
  elseif moveType == 14 then
    st.rrTerrain, st.rrTerrainTurns = "PSYCHIC", 5
    message = "Max Mindstorm warped the field!"
  elseif moveType == 15 then
    adapter:setWeather("HAIL", 5); message = "Max Hailstorm started hail!"
  elseif moveType == 16 then
    change(foes, { attack = -1 }); message = "Max Wyrmwind lowered the opposing side's Attack!"
  elseif moveType == 17 then
    change(foes, { spDef = -1 }); message = "Max Darkness lowered the opposing side's Sp. Def!"
  elseif moveType == 23 then
    st.rrTerrain, st.rrTerrainTurns = "MISTY", 5
    message = "Max Starfall shrouded the field in mist!"
  end
  return message
end

local function attachResolvedMessage(adapter, result, message, first)
  if not message or message == "" or type(result) ~= "table" then return end
  local event = { kind = "msg", text = message, id = "RR_RAID_RULE" }
  if adapter.pushEvent then adapter:pushEvent(event) end
  if first then table.insert(result, 1, message) else result[#result + 1] = message end
  result.events = result.events or {}
  if first then table.insert(result.events, 1, event) else result.events[#result.events + 1] = event end
  if result._anim then
    result._anim.events = result._anim.events or {}
    result._anim.msgs = result._anim.msgs or {}
    if first then
      table.insert(result._anim.events, 1, event)
      table.insert(result._anim.msgs, 1, message)
    else
      result._anim.events[#result._anim.events + 1] = event
      result._anim.msgs[#result._anim.msgs + 1] = message
    end
  end
end

local function usableRepeatMoves(Moves, boss)
  local rows = {}
  for slot, moveId in ipairs((boss and boss.mon and boss.mon.moves) or {}) do
    local pp = tonumber(boss.mon.pp and boss.mon.pp[slot]) or 0
    local ok, move = pcall(Moves.get, moveId)
    if pp > 0 and ok and move and tonumber(moveId) ~= 0 then
      local numeric = tonumber(move.numId) or tonumber(moveId) or -1
      local bannedStatus = move.category == "status"
        and (RAID_BANNED_MOVES[numeric] or RAID_BOSS_BANNED_MOVES[numeric])
      if not bannedStatus then rows[#rows + 1] = { move = moveId, slot = slot } end
    end
  end
  return rows
end

local function scheduleRepeatedAttack(State, Moves, Battle, adapter, st, raid)
  if not raid.attackAgain then return false end
  raid.attackAgain = false
  if st.over or (tonumber(raid.repeatedAttacks) or 0) >= 2 then return false end
  local boss = st.enemy
  if not boss or adapter:isFainted(boss) then return false end
  local targets = {}
  for _, id in ipairs(State.positionsOnSide("player")) do
    if State.isAlive(st, id) then targets[#targets + 1] = id end
  end
  local choices = usableRepeatMoves(Moves, boss)
  if #targets == 0 or #choices == 0 or type(Battle._actions) ~= "table" then return false end
  local choice = choices[adapter:roll(1, #choices)]
  local target = targets[adapter:roll(1, #targets)]
  raid.repeatedAttacks = (raid.repeatedAttacks or 0) + 1
  table.insert(Battle._actions, Battle._actionI, {
    battler = State.idOf(boss), user = boss, kind = "move",
    move = choice.move, slot = choice.slot, target = target,
    _rrRaidRepeat = true,
  })
  return true
end

local function installBattleHooks(deps)
  if deps.skipBattleHooks then return false end
  local okA, Adapter = pcall(require, "src.core.game3.battle.adapter")
  local okB, Battle = pcall(require, "src.core.game3.battle")
  local okS, State = pcall(require, "src.core.game3.battle.state")
  local okE, Engine = pcall(require, "src.core.game3.battle.engine")
  local okM, Moves = pcall(require, "src.core.game3.battle.moves")
  if not (okA and okB and okS and okE and okM) then return false end

  Raids._activeDeps = deps
  if not Adapter._rrRaidOriginalNew then
    Adapter._rrRaidOriginalNew = Adapter.new
    Adapter.new = function(st, sayFn)
      local adapter = Adapter._rrRaidOriginalNew(st, sayFn)
      if st and st.raid then decorateRaidAdapter(Raids._activeDeps, adapter, st) end
      return adapter
    end
  end

  if not Moves._rrRaidOriginalGet then
    Moves._rrRaidOriginalGet = Moves.get
    Moves.get = function(moveId)
      local context = Raids._maxMoveContext
      local numeric = tonumber(moveId)
      if context and numeric == context.maxId then
        local maxRow = copyRecord(Moves._rrRaidOriginalGet(moveId))
        local base = context.baseMove
        maxRow.numId = context.maxId
        maxRow.power = context.power
        maxRow.type = base.type
        maxRow.category = base.category
        maxRow.accuracy = 100
        maxRow.effect = 17 -- EFFECT_ALWAYS_HIT; Max Moves bypass accuracy.
        maxRow.secondaryChance = 0
        maxRow.target = 0
        maxRow.flags = 2 -- Protect-affected; the resolver applies 25% through it.
        return maxRow
      end
      return Moves._rrRaidOriginalGet(moveId)
    end
  end

  if not Engine._rrRaidOriginalPlanTurnActions then
    Engine._rrRaidOriginalPlanTurnActions = Engine.planTurnActions
    Engine.planTurnActions = function(st, adapter, chosen)
      if st and st.raid then
        st.raid.repeatedAttacks = 0
        st.raid.attackAgain = false
        st.raid.actionTurn = st.turn
      end
      return Engine._rrRaidOriginalPlanTurnActions(st, adapter, chosen)
    end
  end

  if not Engine._rrRaidOriginalResolveMove then
    Engine._rrRaidOriginalResolveMove = Engine.resolveMove
    Engine.resolveMove = function(user, target, moveId, slot, adapter, st, out, opts)
      local raid = st and st.raid
      if not raid then
        return Engine._rrRaidOriginalResolveMove(
          user, target, moveId, slot, adapter, st, out, opts)
      end

      local topLevel = not (opts and opts.called)
      local battler = State.occupant(st, user)
      local targetBattler = State.occupant(st, target)
      local resolvedId = effectiveMoveId(battler, moveId, opts)
      local okMove, baseMove = pcall(Moves.get, resolvedId)
      if not okMove or not baseMove then
        return Engine._rrRaidOriginalResolveMove(
          user, target, moveId, slot, adapter, st, out, opts)
      end
      local baseId = tonumber(baseMove.numId) or tonumber(resolvedId) or -1
      local boss = st.enemy
      local isBoss = battler ~= nil and battler == boss
      local regular = true
      local nullified = false
      if topLevel and isBoss then
        nullified = nullifyRaidStats(State, adapter, st, raid, boss)
      end

      local bossBanned = RAID_BANNED_MOVES[baseId]
        or RAID_BOSS_BANNED_MOVES[baseId]
      local blocked = false
      local blockedMessage = "The raid battle prevented that move!"
      if topLevel then
        if isBoss and bossBanned and baseMove.category == "status" then
          blocked = true
        elseif not isBoss and RAID_BANNED_MOVES[baseId] and not isZMove(baseId) then
          blocked = true
        elseif not isBoss and baseId == MOVE.TRANSFORM and targetBattler == boss
            and raid.shieldsUp then
          blocked = true
        elseif not isBoss and targetBattler == boss and raid.shieldsUp
            and baseMove.category == "status" then
          blocked = true
          blockedMessage = "The mysterious barrier protected the raid Pokémon!"
        end
      end
      if blocked then
        local result = blockedMoveResult(State, Engine, user, target, moveId,
          slot, adapter, st, out, blockedMessage)
        if nullified then
          attachResolvedMessage(adapter, result,
            "The raid Pokémon nullified stat changes and abilities!", true)
        end
        raid.nullifiedStats = false
        return result
      end

      local useMoveId = moveId
      local isMax = false
      if topLevel and isBoss and baseMove.category ~= "status"
          and baseId ~= MOVE.STRUGGLE then
        regular = bossUsesRegularMove(st, raid, boss, baseId, baseMove)
        if bossBanned or not regular then
          isMax = true
          useMoveId = maxMoveFor(baseMove)
        end
      end

      local previousMove = raid.currentMove
      if topLevel then
        raid.moveSerial = (raid.moveSerial or 0) + 1
        raid.currentMove = {
          serial = raid.moveSerial, baseId = baseId,
          effect = tonumber(baseMove.effect) or 0,
          isMax = isMax, isZ = isZMove(baseId),
        }
      end

      local previousMax = Raids._maxMoveContext
      local protected
      if isMax then
        local power = maxMovePower(baseMove.power, tonumber(baseMove.type) or 0)
        if targetBattler and targetBattler.expProtected then
          protected = targetBattler
          targetBattler.expProtected = nil
          power = math.max(1, math.floor(power / 4))
        end
        Raids._maxMoveContext = {
          maxId = useMoveId, baseMove = baseMove, power = power,
        }
      end

      local packed = { pcall(Engine._rrRaidOriginalResolveMove,
        user, target, useMoveId, slot, adapter, st, out, opts) }
      Raids._maxMoveContext = previousMax
      if protected then protected.expProtected = true end
      if not packed[1] then
        raid.nullifiedStats = false
        raid.currentMove = previousMove
        error(packed[2], 0)
      end

      local result = packed[2]
      if topLevel and nullified then
        attachResolvedMessage(adapter, result,
          "The raid Pokémon nullified stat changes and abilities!", true)
      end
      local anim = type(result) == "table" and result._anim or nil
      local completed = not (anim and anim.cancelled)
      if topLevel and isBoss and isMax and completed
          and not (anim and anim.missed) and not st.over then
        local message = applyMaxMoveEffect(State, adapter, st, boss, baseMove)
        attachResolvedMessage(adapter, result, message, false)
        boss.choicedMove = nil
      end
      if topLevel and isBoss and completed and not st.over and adapter:isFainted(boss) == false
          and (baseMove.category == "status" or regular)
          and adapter:roll(0, 99) < repeatedAttackChance(raid, boss) then
        raid.attackAgain = true
      end
      if topLevel then scheduleRepeatedAttack(State, Moves, Battle, adapter, st, raid) end
      raid.nullifiedStats = false
      raid.currentMove = previousMove
      return unpack(packed, 2)
    end
  end

  if not Engine._rrRaidOriginalCheckEnd then
    Engine._rrRaidOriginalCheckEnd = Engine.checkEnd
    Engine.checkEnd = function(st, adapter)
      if st and st.raid and not st.over and not st.raid.noForceEnd
          and (tonumber(st.turn) or 0) >= 10
          and st.enemy and st.enemy.mon and (tonumber(st.enemy.mon.hp) or 0) > 0 then
        st.over, st.result, st.endReason = true, "lose", "raid_ten_turns"
        return "lose"
      end
      return Engine._rrRaidOriginalCheckEnd(st, adapter)
    end
  end

  if not Battle._rrRaidOriginalStart then
    Battle._rrRaidOriginalStart = Battle.start
    Battle.start = function(opts)
      local foe = opts and opts.foe
      if not (type(foe) == "table" and foe.rrRaid) then
        return Battle._rrRaidOriginalStart(opts)
      end
      local adjusted = {}
      for key, value in pairs(opts) do adjusted[key] = value end
      local party = adjusted.playerParty or {}
      local baseCount = #party
      for _, mon in ipairs(foe.partnerParty or {}) do party[#party + 1] = mon end
      adjusted.playerParty = party
      adjusted.double = #(foe.partnerParty or {}) > 0
      -- The stock entry deliberately disables wild doubles.  Let it construct
      -- doubles, while the State wrapper preserves wild/catching semantics.
      adjusted.wild = false
      local originalNew = State.new
      State.new = function(stateOpts)
        local copy = {}
        for key, value in pairs(stateOpts or {}) do copy[key] = value end
        copy.wild = true
        copy.double = adjusted.double
        copy.partnerIndex = adjusted.double and (baseCount + 1) or nil
        local st = originalNew(copy)
        st.raid = foe.raidState or { stars = foe.raidStars }
        st.kind, st.wild = "wild", true
        return st
      end
      local ok, first, second = pcall(Battle._rrRaidOriginalStart, adjusted)
      State.new = originalNew
      if not ok then error(first, 0) end
      return first, second
    end
  end
  return true
end

local function copyMon(mon)
  local out = {}
  for key, value in pairs(mon or {}) do
    if type(value) == "table" then
      local inner = {}
      for k, v in pairs(value) do inner[k] = v end
      out[key] = inner
    else
      out[key] = value
    end
  end
  return out
end

local function raidCatchRoll(deps, itemId, battler, battleState, session)
  local ok, Catching = pcall(require, "src.core.game3.battle.catching")
  if not ok or not Catching then return false, 0 end
  local numeric = deps.ItemsData.toNumericId(itemId) or tonumber(itemId) or 4
  if numeric == 1 then return true, 4 end
  local odds = math.min(255, Catching.catchOdds(itemId, battler, battleState, session) * 4)
  if odds >= 255 then return true, 4 end
  local threshold = math.floor(1048560 / math.sqrt(math.sqrt(16711680 / odds)))
  local shakes = 0
  for _ = 1, 4 do
    if random16(deps) < threshold then shakes = shakes + 1 else break end
  end
  return shakes == 4, shakes
end

local function storeRaidCatch(deps, itemId, battleState, session, raid)
  local Catching = require("src.core.game3.battle.catching")
  local source = battleState and battleState.enemy and battleState.enemy.mon or state.foe
  local mon = copyMon(source)
  mon.maxHp = tonumber(mon.raidBaseMaxHp) or mon.maxHp
  mon.hp = math.max(1, math.min(tonumber(mon.hp) or 1, tonumber(mon.maxHp) or 1))
  mon.rrRaid, mon.raidStars, mon.raidBaseMaxHp = nil, nil, nil
  local types = deps.Pokemon.types and deps.Pokemon.types(mon.species) or { 0, 0 }
  local battler = {
    mon = mon, species = mon.species, type1 = types[1],
    type2 = types[2] ~= types[1] and types[2] or nil,
  }
  return Catching.storeCaught(session, battler, itemId, { raid = raid })
end

local function postRaidCapture(deps, adapters, raid, finish)
  if deps.postRaidCapture then return deps.postRaidCapture(adapters, raid, finish) end
  if deps.skipCaptureUi then finish(); return end
  local session = sessionOf(deps)
  local okMenu, BagMenu = pcall(require, "src.ui.game3.bag_menu")
  local Battle = package.loaded["src.core.game3.battle"]
  local battleState = Battle and Battle.getState and Battle.getState() or nil
  if not (session and session.bag and okMenu and BagMenu and BagMenu.show) then finish(); return end

  local settled = false
  local function settle(message)
    if settled then return end
    settled = true
    local function complete()
      if adapters and adapters.closeMessage then adapters.closeMessage() end
      finish()
    end
    if message and adapters and adapters.openMessageAsync then
      adapters.openMessageAsync(message, complete)
    else
      complete()
    end
  end
  local function openBag()
    BagMenu.show(session.bag, {
      session = session, battle = true, pocket = "POKE_BALLS",
      onBattleUse = function(itemId)
        if not itemId then settle(); return end
        if not deps.Bag.remove(session.bag, itemId, 1) then settle(); return end
        local battler = battleState and battleState.enemy
        if not battler then
          local mon = state.foe
          local types = deps.Pokemon.types and deps.Pokemon.types(mon.species) or { 0, 0 }
          battler = { mon = mon, species = mon.species, type1 = types[1], type2 = types[2] }
        end
        local caught, shakes = raidCatchRoll(deps, itemId, battler, battleState, session)
        if caught then
          local stored = storeRaidCatch(deps, itemId, battleState, session, raid)
          if stored and stored.success then
            settle(speciesName(deps, raid.species) .. " was caught!")
          else
            settle("There is no room for the raid Pokémon.")
          end
        else
          settle(("The ball shook %d time%s, but the raid Pokémon escaped!")
            :format(shakes, shakes == 1 and "" or "s"))
        end
      end,
      onClose = function() settle() end,
    })
  end
  local prompt = "The raid Pokémon is weak!\nChoose a Poké Ball, or press B to let it go."
  if adapters and adapters.openMessageAsync then adapters.openMessageAsync(prompt, openBag) else openBag() end
end

local function rewardAmount(deps, rom, item)
  local pocket = deps.ItemsData.pocketOf(item)
  if pocket == "POKE_BALLS" or (deps.ItemsData.isBerry and deps.ItemsData.isBerry(item))
  then
    return randomMod(deps, 5) + 1
  end
  local ok, bytes = pcall(read, rom, ROM.ITEMS_BY_TYPE + item * 2, 2)
  local itemType = ok and u16(bytes, 0) or -1
  if itemType == 1 or itemType == 2 then return randomMod(deps, 5) + 1 end
  if itemType == 3 or itemType == 4 then
    return randomMod(deps, 3) + 1
  end
  if itemType == 5 then return randomMod(deps, 21) + 10 end
  if itemType == 22 then return randomMod(deps, 10) + 1 end
  return 1
end

local function modifyFacilityDrop(deps, item)
  if item == 63 then
    item = item + randomMod(deps, 6)
    if item >= 68 then item = 70 end
  elseif item == 153 then
    item = item + randomMod(deps, 6)
  elseif item == 168 then
    item = item + randomMod(deps, 7)
  end
  return item
end

local function wishingPieceId(deps)
  if state.wishingPieceId ~= nil then
    return state.wishingPieceId ~= false and state.wishingPieceId or nil
  end
  local id
  if deps.ItemsData and deps.ItemsData.toNumericId then
    local ok, value = pcall(deps.ItemsData.toNumericId, "WISHING_PIECE")
    if ok then id = tonumber(value) end
  end
  if not id and deps.ItemsData and deps.ItemsData.ensureLoaded then
    local ok, items = pcall(deps.ItemsData.ensureLoaded)
    if ok and type(items) == "table" then
      for itemId, row in pairs(items) do
        local name = type(row) == "table" and tostring(row.name or "") or ""
        name = name:gsub("é", "e"):gsub("É", "E")
          :upper():gsub("[^A-Z0-9]", "")
        if name == "WISHINGPIECE" then
          id = tonumber(itemId)
          break
        end
      end
    end
  end
  state.wishingPieceId = id or false
  return id
end

local function hasWishingPiece(deps)
  local session = sessionOf(deps)
  local id = wishingPieceId(deps)
  return id ~= nil and session and session.bag
    and deps.Bag and deps.Bag.has
    and deps.Bag.has(session.bag, id, 1) == true
end

local function reactivateDenWithWishingPiece(deps, ctx, mapIndex)
  if mapIndex == nil or not getFlag(deps, ctx, FIRST_RAID_BATTLE_FLAG + mapIndex) then
    return true, false
  end
  local session = sessionOf(deps)
  local id = wishingPieceId(deps)
  if not (id and session and session.bag and deps.Bag
      and deps.Bag.has and deps.Bag.remove
      and deps.Bag.has(session.bag, id, 1)) then
    return false, false
  end
  if not deps.Bag.remove(session.bag, id, 1) then return false, false end

  -- RR's stable den RNG includes this save variable specifically so a
  -- Wishing Piece advances the den to the next deterministic encounter instead
  -- of immediately recreating the raid that was just cleared.
  setVar(deps, ctx, VAR.RAID_NUMBER_OFFSET,
    (getVar(deps, ctx, VAR.RAID_NUMBER_OFFSET) + 1) % 0x10000)
  setFlag(deps, ctx, FIRST_RAID_BATTLE_FLAG + mapIndex, false)
  state.current, state.foe, state.selectedPartner = nil, nil, nil
  state.stars, state.stable = nil, nil
  return true, true
end

local function mapHasAnyRaid(rom, mapIndex)
  state.mapHasRaid = state.mapHasRaid or {}
  if state.mapHasRaid[mapIndex] ~= nil then return state.mapHasRaid[mapIndex] end
  local yes = false
  for stars = 0, RAID_STAR_COUNT - 1 do
    if descriptor(rom, mapIndex, stars) then yes = true break end
  end
  state.mapHasRaid[mapIndex] = yes
  return yes
end

local function choosePartner(deps, rom, ctx, adapters, raid)
  local partners = selectPartners(deps, rom, raid)
  if #partners == 0 then setResult(deps, ctx, 0); return false end
  local labels = {}
  for i, partner in ipairs(partners) do
    local lead = partner.team[1] and speciesName(deps, partner.team[1].species) or "---"
    labels[i] = partner.name .. ": " .. lead
  end
  local function select(index)
    index = tonumber(index)
    if index == nil or index == 0x7F or not partners[index + 1] then
      state.selectedPartner = nil
      setResult(deps, ctx, 0)
      return
    end
    local partner = partners[index + 1]
    state.selectedPartner = partner
    raid.partner = partner
    setFlag(deps, ctx, FLAG.TAG_BATTLE, true)
    setVar(deps, ctx, VAR.PARTNER, RAID_MULTI_TRAINER_ID)
    setVar(deps, ctx, VAR.FACILITY_PARTNER_ID, partner.id)
    setVar(deps, ctx, VAR.PARTNER_BACKSPRITE, partner.backSpriteId)
    setString(ctx, adapters, 1, partner.name)
    setString(ctx, adapters, 2, speciesName(deps, raid.species))
    setString(ctx, adapters, 7, partner.name)
    setString(ctx, adapters, 8, speciesName(deps, raid.species))
    setResult(deps, ctx, 1)
  end
  if not (adapters and adapters.multichoice) then select(0); return false end

  local okM, Multichoice = pcall(require, "src.core.game3.scripting.multichoice")
  if okM and Multichoice then
    Multichoice.LISTS[MENU_LIST_ID] = { labels = labels, count = #labels }
  end
  local okF, Fade = pcall(require, "src.ui.game3.fade")
  if okF and Fade and Fade.clear then Fade.clear() end
  local summary = string.rep("★", raid.stars) .. " " .. speciesName(deps, raid.species)
    .. "\nRecommended Lv. " .. tostring(raid.recommendedLevel) .. "\nChoose a partner."
  return deps.Natives.yieldHost(ctx, adapters, function(done)
    local function menu()
      adapters.multichoice({ op = "multichoice", listId = MENU_LIST_ID, count = #labels }, function(index)
        select(index)
        if adapters.closeMessage then adapters.closeMessage() end
        done()
      end)
    end
    if adapters.openMessageStay then adapters.openMessageStay(summary, menu) else menu() end
  end)
end

local function buildHandlers(deps, rom)
  local H = {}

  H[Raids.SPECIAL.AVAILABLE] = function(ctx)
    local mapIndex = currentMapIndex(deps)
    local done = mapIndex ~= nil and getFlag(deps, ctx, FIRST_RAID_BATTLE_FLAG + mapIndex)
    local facility = getFlag(deps, ctx, FLAG.BATTLE_FACILITY)
    local raid = not done and determineRaid(deps, rom, ctx) or nil
    -- A cleared den is still interactable when the player owns a Wishing
    -- Piece. The actual item spend is deferred to INTRO so merely probing the
    -- den's availability cannot consume inventory.
    local available = facility or (not done and raid ~= nil)
      or (done and hasWishingPiece(deps))
    setResult(deps, ctx, available and 1 or 0)
    return false, available and 1 or 0
  end

  H[Raids.SPECIAL.INTRO] = function(ctx, adapters)
    setResult(deps, ctx, 0)
    local mapIndex = currentMapIndex(deps)
    if not getFlag(deps, ctx, FLAG.BATTLE_FACILITY) then
      local ok = reactivateDenWithWishingPiece(deps, ctx, mapIndex)
      if not ok then return false end
    end
    local raid = determineRaid(deps, rom, ctx)
    if not raid then return false end
    return choosePartner(deps, rom, ctx, adapters, raid)
  end

  H[Raids.SPECIAL.CREATE_MON] = function(ctx)
    local raid = state.current or determineRaid(deps, rom, ctx)
    if not raid then setResult(deps, ctx, 0); return false end
    local foe = makeRaidMon(deps, rom, raid)
    local partner = state.selectedPartner or raid.partner
    foe.partnerParty = buildPartnerParty(deps, rom, raid, partner)
    foe.raidState = {
      stars = raid.stars, mapIndex = raid.mapIndex, species = raid.species,
      facility = raid.facility and true or false,
      noForceEnd = getFlag(deps, ctx, FLAG.RAID_NO_FORCE_END),
      shieldsUp = false, shieldsDestroyed = 0, faints = 0,
      repeatedAttacks = 0, attackAgain = false,
    }
    state.foe = foe
    setResult(deps, ctx, 1)
    return false, foe
  end

  H[Raids.SPECIAL.START_BATTLE] = function(ctx, adapters)
    local raid = state.current or determineRaid(deps, rom, ctx)
    if not raid then setResult(deps, ctx, 0); return false end
    if not state.foe then H[Raids.SPECIAL.CREATE_MON](ctx) end
    local foe = state.foe
    if not (foe and adapters and adapters.startWildBattle) then
      setResult(deps, ctx, 0)
      return false
    end
    local session = sessionOf(deps)
    if getFlag(deps, ctx, FLAG.BATTLE_FACILITY) and session and deps.Party.healAll then
      deps.Party.healAll(session.party)
    end
    setFlag(deps, ctx, FLAG.RAID_BATTLE, true)
    return deps.Natives.yieldHost(ctx, adapters, function(done)
      adapters.startWildBattle(foe, function(result)
        local code = deps.Natives.outcome_to_code and deps.Natives.outcome_to_code(result) or 1
        if ctx then ctx.lastBattleOutcome = code end
        local function finish()
          setFlag(deps, ctx, FLAG.RAID_BATTLE, false)
          setFlag(deps, ctx, FLAG.DYNAMAX_BATTLE, false)
          setFlag(deps, ctx, FLAG.TAG_BATTLE, false)
          setResult(deps, ctx, code)
          done()
        end
        if code == ((deps.Natives.B_OUTCOME and deps.Natives.B_OUTCOME.WON) or 1) then
          postRaidCapture(deps, adapters, raid, finish)
        else
          finish()
        end
      end, { wildScripted = true, legendary = true, aiFlags = 7 })
    end)
  end

  H[Raids.SPECIAL.SET_DONE] = function(ctx)
    local mapIndex = currentMapIndex(deps)
    if mapIndex ~= nil then setFlag(deps, ctx, FIRST_RAID_BATTLE_FLAG + mapIndex, true) end
    return false
  end

  H[Raids.SPECIAL.CLEAR_DONE] = function(ctx)
    if getVar(deps, ctx, 0x8000) == 1 then
      for i = 0, KANTO_MAPSEC_COUNT - 1 do setFlag(deps, ctx, FIRST_RAID_BATTLE_FLAG + i, false) end
    else
      local mapIndex = currentMapIndex(deps)
      if mapIndex ~= nil then setFlag(deps, ctx, FIRST_RAID_BATTLE_FLAG + mapIndex, false) end
    end
    state.current, state.foe, state.selectedPartner = nil, nil, nil
    state.stars, state.stable = nil, nil
    return false
  end

  H[Raids.SPECIAL.ALL_DONE] = function(ctx)
    local allDone = true
    for i = 0, KANTO_MAPSEC_COUNT - 1 do
      if mapHasAnyRaid(rom, i) and not getFlag(deps, ctx, FIRST_RAID_BATTLE_FLAG + i) then
        allDone = false
        break
      end
    end
    setResult(deps, ctx, allDone and 1 or 0)
    return false, allDone and 1 or 0
  end

  H[Raids.SPECIAL.REWARD] = function(ctx)
    local raid = state.current or determineRaid(deps, rom, ctx)
    setResult(deps, ctx, 0)
    if not raid then setResult(deps, ctx, 1); return false, 1 end
    local cursor = getVar(deps, ctx, VAR.TEMP_0)
    while cursor < MAX_RAID_DROPS do
      local index = cursor + 1
      local item = raid.record.drops[index] or 0
      cursor = cursor + 1
      setVar(deps, ctx, VAR.TEMP_0, cursor)
      if item ~= 0 and randomMod(deps, 100, not raid.facility) < DROP_RATES[index] then
        if raid.facility then item = modifyFacilityDrop(deps, item) end
        setVar(deps, ctx, VAR.LAST_TALKED, 0xFD)
        setVar(deps, ctx, 0x8000, item)
        setVar(deps, ctx, 0x8001, rewardAmount(deps, rom, item))
        return false, item
      end
    end
    setResult(deps, ctx, 1)
    return false, 1
  end

  return H
end

function Raids.install(mod, rom, overrides)
  local deps = mergeDefaults(overrides)
  local handlers = buildHandlers(deps, rom)
  local installed = 0
  for id, handler in pairs(handlers) do
    deps.Natives.ALLOW["special:" .. id] = handler
    installed = installed + 1
  end
  deps.Natives.ALLOW["native:" .. Raids.ADDR.DETERMINE_STARS] = function(ctx)
    state.current, state.foe, state.selectedPartner = nil, nil, nil
    state.stable = raidRandomNumber(deps, ctx)
    state.stars = determineStars(deps, ctx, state.stable)
    return false, state.stars
  end
  local battleHooks = installBattleHooks(deps)
  if mod and mod.log and mod.log.info then
    mod.log:info(("Radical Red raids: %d specials, battle hooks %s")
      :format(installed, battleHooks and "active" or "unavailable"))
  end
  return {
    specialCallbacks = installed,
    nativeCallbacks = 1,
    battleHooks = battleHooks,
    romBacked = true,
    wishingPieceRespawn = true,
    mapSections = KANTO_MAPSEC_COUNT,
  }
end

Raids.ROM = ROM
Raids.FLAG = FLAG
Raids.VAR = VAR
Raids._descriptor = descriptor
Raids._raidRecord = raidRecord
Raids._partnerAt = partnerAt
Raids._spreadAt = spreadAt
Raids._decorateRaidAdapter = decorateRaidAdapter
Raids._combat = {
  koStatIncrease = koStatIncrease,
  repeatedAttackChance = repeatedAttackChance,
  statNullificationChance = statNullificationChance,
  shieldCount = shieldCount,
  shieldBreaksFor = shieldBreaksFor,
  maxMovePower = maxMovePower,
  maxMoveFor = maxMoveFor,
  bossUsesRegularMove = bossUsesRegularMove,
}

return Raids
