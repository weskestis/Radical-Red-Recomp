-- Reader for the Dynamic Pokemon Expansion tables in Radical Red v4.1.
-- It operates exclusively on the user's required import; no ROM bytes are
-- bundled with this mod.

local RR = {
  IMPORT_ID = "radical_red_v4_1",
  SOURCE_VERSION = "v4.1",
  ROM_SIZE = 33554432,
  EXPECTED_MD5 = "8529f3a45d32bce4da637976fcf269d4",
  SPECIES_COUNT = 1376,
  FIRERED_INTERNAL_SPECIES = 411,
  FIRERED_PATCHABLE_SPECIES = 386,
  NAME_STRIDE = 11,
  BASE_STATS_STRIDE = 28,
  BATTLE_MOVE_STRIDE = 12,
  MOVE_COUNT = 1004,
  -- Compatibility alias retained for callers; this is the complete registry.
  FIRERED_MOVE_COUNT = 1004,
  TYPE_COUNT = 24,
  -- CFRU stores the modern type chart as a dense 24x24 matrix. Unlike the
  -- vanilla three-byte list this table has no public pointer slot, so the
  -- exact-v4.1 import contract pins and verifies its ROM offset.
  TYPE_CHART_OFFSET = 0x1146CE2,
  VERSION_SENTINEL_OFFSET = 0x10F6D55,
}

RR.POINTER_SLOTS = {
  battleMoves = 0x0001CC,
  speciesNames = 0x000144,
  baseStats = 0x0001BC,
  eggMoves = 0x045C50,
  tmhmLearnsets = 0x043C68,
  tutorLearnsets = 0x120C30,
  frontPics = 0x000128,
  backPics = 0x00012C,
  palettes = 0x000130,
  shinyPalettes = 0x000134,
  evolutions = 0x042F6C,
  pokedexEntries = 0x088E34,
  speciesToNationalDex = 0x04323C,
  icons = 0x000138,
  iconPaletteIndices = 0x00013C,
  levelUpLearnsets = 0x03EA7C,
}

RR.MOVE_SPLIT_NAMES = {
  [0] = "physical",
  [1] = "special",
  [2] = "status",
}

RR.TYPE_NAMES = {
  [0] = "NORMAL", [1] = "FIGHTING", [2] = "FLYING", [3] = "POISON",
  [4] = "GROUND", [5] = "ROCK", [6] = "BUG", [7] = "GHOST",
  [8] = "STEEL", [9] = "MYSTERY", [10] = "FIRE", [11] = "WATER",
  [12] = "GRASS", [13] = "ELECTRIC", [14] = "PSYCHIC", [15] = "ICE",
  [16] = "DRAGON", [17] = "DARK", [19] = "ROOSTLESS", [20] = "BLANK",
  [23] = "FAIRY",
}

RR.GROWTH_NAMES = {
  [0] = "MEDIUM_FAST", [1] = "ERRATIC", [2] = "FLUCTUATING",
  [3] = "MEDIUM_SLOW", [4] = "FAST", [5] = "SLOW",
}

local CHARMAP = {
  [0x00] = " ", [0x06] = "É", [0x1B] = "é", [0x2D] = "&", [0x2E] = "+",
  [0x35] = "=", [0x36] = ";", [0x5B] = "%", [0x5C] = "(", [0x5D] = ")",
  [0x85] = "<", [0x86] = ">", [0xA1] = "0", [0xA2] = "1", [0xA3] = "2",
  [0xA4] = "3", [0xA5] = "4", [0xA6] = "5", [0xA7] = "6", [0xA8] = "7",
  [0xA9] = "8", [0xAA] = "9", [0xAB] = "!", [0xAC] = "?", [0xAD] = ".",
  [0xAE] = "-", [0xAF] = "·", [0xB0] = "…", [0xB1] = "“", [0xB2] = "”",
  [0xB3] = "‘", [0xB4] = "'", [0xB5] = "♂", [0xB6] = "♀", [0xB7] = "¥",
  [0xB8] = ",", [0xB9] = "×", [0xBA] = "/", [0xEF] = "▶", [0xF0] = ":",
}
for i = 0, 25 do
  CHARMAP[0xBB + i] = string.char(string.byte("A") + i)
  CHARMAP[0xD5 + i] = string.char(string.byte("a") + i)
end

local function byteAt(s, offset)
  local value = s:byte(offset + 1)
  assert(value, "truncated Radical Red table")
  return value
end

local function u16(s, offset)
  return byteAt(s, offset) + byteAt(s, offset + 1) * 0x100
end

local function u32(s, offset)
  return byteAt(s, offset) + byteAt(s, offset + 1) * 0x100
    + byteAt(s, offset + 2) * 0x10000 + byteAt(s, offset + 3) * 0x1000000
end

local function decodeName(record)
  local out = {}
  for i = 1, #record do
    local b = record:byte(i)
    if b == 0xFF then break end
    out[#out + 1] = CHARMAP[b] or ("{%02X}"):format(b)
  end
  return table.concat(out)
end

local function isNameRecord(record)
  local terminator = record:find(string.char(0xFF), 1, true)
  if not terminator or terminator == 1 then return false end
  for i = terminator + 1, #record do
    if record:byte(i) ~= 0xFF then return false end
  end
  return true
end

local Rom = {}
Rom.__index = Rom

function Rom:_read(offset, length)
  local bytes = assert(self.imports:read(self.importId, offset, length))
  assert(#bytes == length,
    ("short read at 0x%X: expected %d bytes, received %d")
      :format(offset, length, #bytes))
  return bytes
end

function Rom:pointerAt(slot)
  local raw = u32(self:_read(slot, 4), 0)
  assert(raw >= 0x08000000 and raw < 0x0A000000,
    ("invalid GBA pointer 0x%08X at slot 0x%X"):format(raw, slot))
  local offset = raw - 0x08000000
  assert(offset >= 0 and offset < RR.ROM_SIZE,
    ("pointer at slot 0x%X resolves outside the ROM"):format(slot))
  return offset, raw
end

function Rom:_loadSpeciesTables()
  if self.names and self.baseStats then return end
  self.namesOffset = self:pointerAt(RR.POINTER_SLOTS.speciesNames)
  self.baseStatsOffset = self:pointerAt(RR.POINTER_SLOTS.baseStats)
  self.names = self:_read(self.namesOffset,
    (RR.SPECIES_COUNT + 1) * RR.NAME_STRIDE)
  self.baseStats = self:_read(self.baseStatsOffset,
    RR.SPECIES_COUNT * RR.BASE_STATS_STRIDE)
end

function Rom:_loadBattleMoves()
  if self.battleMoves then return end
  self.battleMovesOffset = self:pointerAt(RR.POINTER_SLOTS.battleMoves)
  self.battleMoves = self:_read(self.battleMovesOffset,
    RR.FIRERED_MOVE_COUNT * RR.BATTLE_MOVE_STRIDE)
end

function Rom:moveCount()
  return RR.MOVE_COUNT
end

function Rom:move(index)
  assert(index >= 0 and index < RR.FIRERED_MOVE_COUNT, "move index out of range")
  self:_loadBattleMoves()
  local first = index * RR.BATTLE_MOVE_STRIDE + 1
  local row = self.battleMoves:sub(first, first + RR.BATTLE_MOVE_STRIDE - 1)
  local priority = byteAt(row, 7)
  if priority >= 0x80 then priority = priority - 0x100 end
  local splitId = byteAt(row, 10)
  local category = RR.MOVE_SPLIT_NAMES[splitId]
  assert(category, ("unsupported Radical Red move split %d at move %d")
    :format(splitId, index))
  return {
    index = index,
    effect = byteAt(row, 0),
    power = byteAt(row, 1),
    type = byteAt(row, 2),
    accuracy = byteAt(row, 3),
    pp = byteAt(row, 4),
    secondaryChance = byteAt(row, 5),
    target = byteAt(row, 6),
    priority = priority,
    flags = byteAt(row, 8),
    zMovePower = byteAt(row, 9),
    splitId = splitId,
    category = category,
    zMoveEffect = byteAt(row, 11),
  }
end

function Rom:_loadTypeChart()
  if self.typeChart then return end
  self.typeChart = self:_read(RR.TYPE_CHART_OFFSET,
    RR.TYPE_COUNT * RR.TYPE_COUNT)
end

-- CFRU's dense chart uses 0 for an unspecified/neutral matchup and 1 for an
-- immunity. gen1recomp uses the original tenths convention (0/5/10/20), so
-- normalize at the private-ROM boundary.
function Rom:typeMultiplier(attackType, defenseType)
  assert(attackType >= 0 and attackType < RR.TYPE_COUNT,
    "attacking type index out of range")
  assert(defenseType >= 0 and defenseType < RR.TYPE_COUNT,
    "defending type index out of range")
  self:_loadTypeChart()
  local raw = byteAt(self.typeChart, attackType * RR.TYPE_COUNT + defenseType)
  if raw == 0 then return 10 end
  if raw == 1 then return 0 end
  assert(raw == 5 or raw == 10 or raw == 20,
    ("unsupported Radical Red type multiplier %d for %d>%d")
      :format(raw, attackType, defenseType))
  return raw
end

function Rom:typeChartRows()
  local rows = {}
  for attackType = 0, RR.TYPE_COUNT - 1 do
    local row = {}
    for defenseType = 0, RR.TYPE_COUNT - 1 do
      row[defenseType] = self:typeMultiplier(attackType, defenseType)
    end
    rows[attackType] = row
  end
  return rows
end

function Rom:name(index)
  assert(index >= 0 and index <= RR.SPECIES_COUNT, "species index out of range")
  self:_loadSpeciesTables()
  local first = index * RR.NAME_STRIDE + 1
  return decodeName(self.names:sub(first, first + RR.NAME_STRIDE - 1))
end

function Rom:detectSpeciesCount()
  self:_loadSpeciesTables()
  for index = 0, RR.SPECIES_COUNT do
    local first = index * RR.NAME_STRIDE + 1
    local record = self.names:sub(first, first + RR.NAME_STRIDE - 1)
    if not isNameRecord(record) then return index end
  end
  return RR.SPECIES_COUNT + 1
end

function Rom:species(index)
  assert(index >= 0 and index < RR.SPECIES_COUNT, "species index out of range")
  self:_loadSpeciesTables()
  local first = index * RR.BASE_STATS_STRIDE + 1
  local row = self.baseStats:sub(first, first + RR.BASE_STATS_STRIDE - 1)
  local type1, type2 = byteAt(row, 6), byteAt(row, 7)
  local growth = byteAt(row, 19)
  local populated = true
  for offset = 0, 5 do
    if byteAt(row, offset) == 0 then populated = false end
  end
  return {
    index = index,
    name = self:name(index),
    baseStats = {
      hp = byteAt(row, 0), attack = byteAt(row, 1),
      defense = byteAt(row, 2), speed = byteAt(row, 3),
      specialAttack = byteAt(row, 4), specialDefense = byteAt(row, 5),
    },
    typeIds = { type1, type2 },
    types = { RR.TYPE_NAMES[type1] or tostring(type1),
              RR.TYPE_NAMES[type2] or tostring(type2) },
    catchRate = byteAt(row, 8),
    baseExp = byteAt(row, 9),
    evYield = u16(row, 10),
    itemCommon = u16(row, 12),
    itemRare = u16(row, 14),
    genderRatio = byteAt(row, 16),
    eggCycles = byteAt(row, 17),
    friendship = byteAt(row, 18),
    growthRateId = growth,
    growthRate = RR.GROWTH_NAMES[growth] or tostring(growth),
    eggGroups = { byteAt(row, 20), byteAt(row, 21) },
    ability1 = byteAt(row, 22),
    ability2 = byteAt(row, 23),
    safariFleeRate = byteAt(row, 24),
    bodyColorFlags = byteAt(row, 25),
    hiddenAbility = byteAt(row, 26),
    populated = populated,
  }
end

function Rom:verify()
  local header = self:_read(0xA0, 0x20)
  local title = header:sub(1, 12):gsub("%z+$", "")
  local gameCode = header:sub(13, 16)
  local revision = header:byte(29)
  assert(title == "POKEMON FIRE", "required import is not a FireRed-family ROM")
  assert(gameCode == "BPRE", "required import has unexpected game code " .. gameCode)
  assert(revision == 0, "required import has unsupported ROM revision")
  assert(decodeName(self:_read(RR.VERSION_SENTINEL_OFFSET, 24))
      == "Radical Red Version v4.1",
    "embedded version sentinel does not identify Radical Red v4.1")

  local detected = self:detectSpeciesCount()
  assert(detected == RR.SPECIES_COUNT,
    ("unexpected Dynamic Pokemon Expansion species count: expected %d, found %d")
      :format(RR.SPECIES_COUNT, detected))
  assert(self:name(1) == "Bulbasaur", "species-table sentinel Bulbasaur not found")
  assert(self:name(RR.SPECIES_COUNT - 1) == "Chillet",
    "species-table terminal sentinel Chillet not found")

  local bulbasaur = self:species(1)
  assert(bulbasaur.baseStats.hp == 45 and bulbasaur.baseStats.specialAttack == 65,
    "base-stats sentinel does not match Radical Red v4.1")
  assert(bulbasaur.typeIds[1] == 12 and bulbasaur.typeIds[2] == 3,
    "type sentinel does not match Radical Red v4.1")

  local pound = self:move(1)
  local swordsDance = self:move(14)
  local ember = self:move(52)
  local bite = self:move(44)
  local shadowBall = self:move(247)
  assert(self.battleMovesOffset == 0x11521D0,
    "battle-move pointer does not match Radical Red v4.1")
  assert(pound.category == "physical" and swordsDance.category == "status"
      and ember.category == "special" and bite.category == "physical"
      and shadowBall.category == "special",
    "move-split sentinels do not match Radical Red v4.1")
  assert(self:typeMultiplier(0, 7) == 0
      and self:typeMultiplier(16, 23) == 0
      and self:typeMultiplier(23, 16) == 20
      and self:typeMultiplier(17, 8) == 10,
    "modern type-chart sentinels do not match Radical Red v4.1")

  local categoryCounts = { physical = 0, special = 0, status = 0 }
  for index = 0, RR.FIRERED_MOVE_COUNT - 1 do
    local category = self:move(index).category
    categoryCounts[category] = categoryCounts[category] + 1
  end
  assert(categoryCounts.physical == 435 and categoryCounts.special == 305
      and categoryCounts.status == 264,
    "move-category counts do not match Radical Red v4.1")

  local pointers = {}
  for name, slot in pairs(RR.POINTER_SLOTS) do
    pointers[name] = self:pointerAt(slot)
  end
  return {
    title = title,
    gameCode = gameCode,
    revision = revision,
    size = self.info.size,
    md5 = self.info.md5,
    speciesCount = detected,
    firstSpecies = self:name(1),
    lastSpecies = self:name(RR.SPECIES_COUNT - 1),
    embeddedVersion = "Radical Red Version v4.1",
    moveCount = RR.FIRERED_MOVE_COUNT,
    moveCategories = categoryCounts,
    typeCount = RR.TYPE_COUNT,
    typeChartOffset = RR.TYPE_CHART_OFFSET,
    pointers = pointers,
  }
end

function RR.open(imports, importId)
  importId = importId or RR.IMPORT_ID
  local info = assert(imports:info(importId),
    "Radical Red v4.1 required import is unavailable")
  assert(info.size == RR.ROM_SIZE,
    ("Radical Red import must be %d bytes; received %s")
      :format(RR.ROM_SIZE, tostring(info.size)))
  if info.md5 then
    assert(info.md5:lower() == RR.EXPECTED_MD5,
      "Radical Red import MD5 does not match v4.1")
  end
  return setmetatable({
    imports = imports,
    importId = importId,
    info = info,
  }, Rom)
end

return RR
