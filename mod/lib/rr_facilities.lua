-- Radical Red v4.1 Battle Simulator / Battle Facility runtime.
--
-- The facility trainer records, names, dialogue, and Pokemon spreads remain in
-- the player's validated ROM.  This module translates the ROM's native Thumb
-- entry points into host-side Lua and patches only the live runtime tables.

local Facilities = {}

Facilities.SPECIAL = {
  GENERATE_TRAINER = 0x052,
  LOAD_INTRO = 0x053,
}

Facilities.ADDR = {
  SIMULATOR_SETUP = 0x0906E935,
  SIMULATOR_TRAINER = 0x09077A19,
  FIXED_PARTY = 0x090790C9,
  RENTAL_PARTY_A = 0x09079289,
  RENTAL_PARTY_B = 0x09079301,
  ROLL_THREE = 0x0907CE21,
  SIMULATOR_COMPARE = 0x090C18A1,
  SIMULATOR_TARGET = 0x090C1935,
  SIMULATOR_ADD_SCORE = 0x090C19B5,
  SIMULATOR_BONUS = 0x090C19E9,
}

Facilities.ROM = {
  TOWER_TRAINERS = 0x114AB3C,
  TOWER_TRAINER_COUNT = 0x114A5BE,
  SPECIAL_TRAINERS = 0x114A8CC,
  SPECIAL_TRAINER_COUNT = 0x114A5BC,
  FRONTIER_BRAINS = 0x114A72C,
  FEMALE_NAME_COUNT = 0x1151ABC,
  MALE_NAME_COUNT = 0x1151ABE,
  FEMALE_NAMES = 0x1151AC0,
  MALE_NAMES = 0x1151C50,
  RENTAL_POINTER_TABLE = 0x1124D00,
  FIXED_PARTY_SIX = 0x112C860,
  FIXED_PARTY_SEVEN = 0x112C908,
  SIMULATOR_TRAINERS = 0x134E858,
  LITTLE_SPREADS = 0x1136C0C,
  MIDDLE_SPREADS = 0x1138B00,
  LEGENDARY_SPREADS = 0x1139F58,
  REGULAR_SPREADS = 0x113B0D8,
}

local TRAINER = {
  BRAIN = 0x397,
  SPECIAL = 0x398,
  REGULAR = 0x399,
}

local VAR = {
  PARTY_SIZE = 0x5015,
  LEVEL = 0x5016,
  BATTLE_TYPE = 0x5017,
  TIER = 0x5018,
  TRAINER_NAME_1 = 0x5019,
  TRAINER_NAME_2 = 0x501A,
  TRAINER_ID = 0x501C,
  SIMULATOR_VALUE = 0x5000,
  SIMULATOR_PARTY_A = 0x5118,
  SIMULATOR_PARTY_B = 0x5119,
  SIMULATOR_MODE = 0x5127,
  FIXED_PARTY_KIND = 0x512B,
  SIMULATOR_WINS = 0x5134,
  SIMULATOR_TARGET = 0x5135,
  SIMULATOR_ALT_WINS = 0x5136,
  SIMULATOR_POINTS = 0x513F,
  RESULT = 0x800D,
  TEXT_COLOR = 0x8012,
  TEXT_COLOR_BACKUP = 0x8013,
}

local FLAG = {
  HARDCORE = 0x1034,
  SIMULATOR_SHORT = 0x1065,
  SIMULATOR_ALT = 0x1066,
}

local TOWER_TRAINER_SIZE = 20
local SPECIAL_TRAINER_SIZE = 52
local SPREAD_SIZE = 28
local STAT_KEYS = { "hp", "atk", "def", "spe", "spa", "spd" }
local GENERIC_POOL = {
  regular = { Facilities.ROM.REGULAR_SPREADS, 1679 },
  legendary = { Facilities.ROM.LEGENDARY_SPREADS, 160 },
  middle = { Facilities.ROM.MIDDLE_SPREADS, 186 },
  little = { Facilities.ROM.LITTLE_SPREADS, 283 },
}

local state = {
  generated = {},
  selected = {},
  transientText = {},
}
Facilities._state = state

local function mergeDefaults(overrides)
  local deps = {}
  for key, value in pairs(overrides or {}) do deps[key] = value end
  local modules = {
    Natives = "src.core.game3.scripting.natives",
    Flags = "src.core.game3.scripting.flags",
    Pokemon = "src.core.game3.pokemon",
    Rng = "src.core.game3.rng",
    SummaryData = "src.core.game3.summary_data",
    Tower = "src.core.game3.trainer_tower",
    Trainers = "src.core.game3.scripting.trainers",
    TextIR = "src.core.game3.scripting.text_ir",
    RomText = "src.core.game3.rom_text",
  }
  for key, moduleName in pairs(modules) do
    if deps[key] == nil then deps[key] = require(moduleName) end
  end
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

local function getFlag(deps, ctx, id)
  return deps.Flags.getFlag(storeOf(), ctx, id) == true
end

local function setResult(deps, ctx, value)
  setVar(deps, ctx, VAR.RESULT, value)
  return value
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
  assert(rom and rom._read, "Radical Red facilities require the validated ROM")
  local bytes = rom:_read(offset, length)
  assert(type(bytes) == "string" and #bytes == length,
    ("short Radical Red facility read at 0x%X"):format(offset))
  return bytes
end

local function pointerOffset(pointer)
  pointer = tonumber(pointer) or 0
  if pointer < 0x08000000 or pointer >= 0x0A000000 then return nil end
  return pointer - 0x08000000
end

local function random16(deps)
  if deps.random16 then return math.floor(deps.random16()) % 0x10000 end
  if deps.Rng and deps.Rng.Random then return deps.Rng.Random() end
  return math.random(0, 0xFFFF)
end

local function random32(deps)
  if deps.random32 then return math.floor(deps.random32()) % 4294967296 end
  if deps.Rng and deps.Rng.Random32 then return deps.Rng.Random32() end
  return random16(deps) + random16(deps) * 0x10000
end

local function randomMod(deps, count)
  count = math.floor(tonumber(count) or 0)
  if count <= 0 then return 0 end
  return random16(deps) % count
end

local function readTextBytes(rom, pointer)
  local offset = pointerOffset(pointer)
  if not offset then return string.char(0xFF) end
  local bytes = read(rom, offset, 768)
  local eos = bytes:find(string.char(0xFF), 1, true)
  if eos then return bytes:sub(1, eos) end
  return bytes .. string.char(0xFF)
end

local function plainText(deps, bytes)
  if deps.TextIR and deps.TextIR.decode and deps.TextIR.toPlain then
    return deps.TextIR.toPlain(deps.TextIR.decode(bytes), {})
  end
  local out = {}
  for i = 1, #bytes do
    local b = bytes:byte(i)
    if b == 0xFF then break end
    if b == 0 then out[#out + 1] = " "
    elseif b >= 0xA1 and b <= 0xAA then out[#out + 1] = tostring(b - 0xA1)
    elseif b >= 0xBB and b <= 0xD4 then out[#out + 1] = string.char(65 + b - 0xBB)
    elseif b >= 0xD5 and b <= 0xEE then out[#out + 1] = string.char(97 + b - 0xD5)
    elseif b == 0xFE or b == 0xFA or b == 0xFB then out[#out + 1] = "\n"
    elseif b == 0xAD then out[#out + 1] = "."
    elseif b == 0xAE then out[#out + 1] = "-"
    elseif b == 0xB8 then out[#out + 1] = ","
    elseif b == 0xAB then out[#out + 1] = "!"
    elseif b == 0xAC then out[#out + 1] = "?"
    elseif b == 0xB4 then out[#out + 1] = "'"
    end
  end
  return table.concat(out)
end

local function textAt(deps, rom, pointer)
  if not pointerOffset(pointer) then return "" end
  return plainText(deps, readTextBytes(rom, pointer))
end

local function installTransientText(deps, rom, pointer)
  local key = ("rr:facility:%08x"):format(tonumber(pointer) or 0)
  local bytes = readTextBytes(rom, pointer)
  local ir = deps.TextIR and deps.TextIR.decode and deps.TextIR.decode(bytes) or bytes
  deps.RomText.overrides[key] = ir
  state.transientText[key] = true
  return key, ir
end

local function regularTrainerCount(rom)
  return u16(read(rom, Facilities.ROM.TOWER_TRAINER_COUNT, 2), 0)
end

local function specialTrainerCount(rom)
  return u16(read(rom, Facilities.ROM.SPECIAL_TRAINER_COUNT, 2), 0)
end

local function regularName(deps, rom, gender, index)
  local countOffset = gender == 0 and Facilities.ROM.MALE_NAME_COUNT
    or Facilities.ROM.FEMALE_NAME_COUNT
  local tableOffset = gender == 0 and Facilities.ROM.MALE_NAMES
    or Facilities.ROM.FEMALE_NAMES
  local count = u16(read(rom, countOffset, 2), 0)
  if count <= 0 then return "TRAINER" end
  index = math.floor(tonumber(index) or 0) % count
  local pointer = u32(read(rom, tableOffset + index * 4, 4), 0)
  local name = textAt(deps, rom, pointer)
  return name ~= "" and name or "TRAINER"
end

local function parseRegularTrainer(deps, rom, index, battler, ctx)
  local count = regularTrainerCount(rom)
  if count <= 0 then return nil end
  index = math.floor(tonumber(index) or 0) % count
  local row = read(rom, Facilities.ROM.TOWER_TRAINERS + index * TOWER_TRAINER_SIZE,
    TOWER_TRAINER_SIZE)
  local gender = byteAt(row, 4)
  local nameVar = battler == 0 and VAR.TRAINER_NAME_1 or VAR.TRAINER_NAME_2
  return {
    kind = 0, index = index, owNum = u16(row, 0), class = byteAt(row, 2),
    pic = byteAt(row, 3), gender = gender,
    name = regularName(deps, rom, gender, getVar(deps, ctx, nameVar)),
    pre = u32(row, 8), playerWin = u32(row, 12), playerLose = u32(row, 16),
  }
end

local function parseSpecialTrainer(deps, rom, kind, index)
  local base = kind == 2 and Facilities.ROM.FRONTIER_BRAINS
    or Facilities.ROM.SPECIAL_TRAINERS
  if kind == 1 then
    local count = specialTrainerCount(rom)
    if count <= 0 then return nil end
    index = math.floor(tonumber(index) or 0) % count
  else
    index = math.max(0, math.floor(tonumber(index) or 0))
  end
  local row = read(rom, base + index * SPECIAL_TRAINER_SIZE, SPECIAL_TRAINER_SIZE)
  local namePointer = u32(row, 8)
  if not pointerOffset(namePointer) then return nil end
  return {
    kind = kind, index = index, owNum = u16(row, 0), class = byteAt(row, 2),
    pic = byteAt(row, 3), gender = byteAt(row, 4), monotype = byteAt(row, 5) ~= 0,
    name = textAt(deps, rom, namePointer), namePointer = namePointer,
    pre = u32(row, 12), playerWin = u32(row, 16), playerLose = u32(row, 20),
    pools = {
      regular = { u32(row, 24), u16(row, 40) },
      middle = { u32(row, 28), u16(row, 42) },
      little = { u32(row, 32), u16(row, 44) },
      legendary = { u32(row, 36), u16(row, 46) },
    },
    song = u16(row, 48),
  }
end

local function trainerRecord(deps, rom, kind, index, battler, ctx)
  if kind == 0 then return parseRegularTrainer(deps, rom, index, battler, ctx) end
  return parseSpecialTrainer(deps, rom, kind, index)
end

local function spreadAt(rom, pointerOrOffset, index, isOffset)
  local offset = isOffset and pointerOrOffset or pointerOffset(pointerOrOffset)
  if not offset then return nil end
  local row = read(rom, offset + index * SPREAD_SIZE, SPREAD_SIZE)
  local packedIv = u32(row, 4)
  local ivs = {}
  for i, key in ipairs(STAT_KEYS) do
    ivs[key] = math.floor(packedIv / (2 ^ ((i - 1) * 5))) % 32
  end
  local moves = {}
  for i = 0, 3 do
    local move = u16(row, 16 + i * 2)
    if move ~= 0 then moves[#moves + 1] = move end
  end
  local flags = byteAt(row, 25)
  return {
    species = u16(row, 0), nature = byteAt(row, 2), ball = byteAt(row, 3),
    ivs = ivs,
    evs = {
      hp = byteAt(row, 8), atk = byteAt(row, 9), def = byteAt(row, 10),
      spe = byteAt(row, 11), spa = byteAt(row, 12), spd = byteAt(row, 13),
    },
    item = u16(row, 14), moves = moves, specificTeamType = byteAt(row, 24),
    shiny = flags % 2 == 1,
    forSingles = math.floor(flags / 2) % 2 == 1,
    forDoubles = math.floor(flags / 4) % 2 == 1,
    modifyMovesDoubles = math.floor(flags / 8) % 2 == 1,
    ability = math.floor(flags / 16) % 4,
    gigantamax = math.floor(flags / 64) % 2 == 1,
    level = byteAt(row, 26),
  }
end

local function abilityIds(rom, species)
  local base
  if rom.pointerAt then
    local ok, offset = pcall(rom.pointerAt, rom, 0x1BC)
    if ok then base = offset end
  end
  if not base then base = pointerOffset(u32(read(rom, 0x1BC, 4), 0)) end
  if not base then return 0, 0, 0 end
  local row = read(rom, base + species * 28, 28)
  return byteAt(row, 22), byteAt(row, 23), byteAt(row, 26)
end

local function personalityForSpread(deps, spread)
  local base = random32(deps)
  local nature = spread.nature % 25
  local personality = base - (base % 50) + nature
  local wantedParity
  if spread.ability == 1 then wantedParity = 0
  elseif spread.ability == 2 then wantedParity = 1 end
  if wantedParity ~= nil and personality % 2 ~= wantedParity then personality = personality + 25 end
  if personality >= 4294967296 then personality = personality - 50 end
  return personality
end

local function makeMon(deps, rom, spread, level, owner)
  if not spread or spread.species == 0 then return nil end
  level = math.max(1, math.min(100, math.floor(tonumber(level) or 50)))
  local personality = personalityForSpread(deps, spread)
  local a1, a2, hidden = abilityIds(rom, spread.species)
  local ability, hiddenAbility
  if spread.ability == 0 then
    ability, hiddenAbility = hidden ~= 0 and hidden or a1, true
  elseif spread.ability == 2 then
    ability = a2 ~= 0 and a2 or a1
  else
    ability = a1
  end
  local moves, pp, maxPp = {}, {}, {}
  for _, move in ipairs(spread.moves or {}) do
    moves[#moves + 1] = move
    local value = deps.Pokemon.movePp and deps.Pokemon.movePp(move) or 5
    pp[#pp + 1], maxPp[#maxPp + 1] = value, value
  end
  local growthRate = deps.Pokemon.growthRate and deps.Pokemon.growthRate(spread.species) or 0
  local exp = deps.SummaryData and deps.SummaryData.expForLevel
    and deps.SummaryData.expForLevel(growthRate, level) or level * level * level
  local name = deps.Pokemon.name and deps.Pokemon.name(spread.species)
    or ("SPECIES " .. spread.species)
  local mon = {
    species = spread.species, speciesId = spread.species,
    speciesNumbering = deps.Pokemon.NUMBERING_INTERNAL,
    name = name, nickname = "", level = level, metLevel = level,
    growthRate = growthRate, exp = exp, status = nil,
    personality = personality, nature = spread.nature,
    ivs = spread.ivs, evs = spread.evs,
    ability = ability, abilityId = ability, hiddenAbility = hiddenAbility or nil,
    moves = moves, pp = pp, maxPp = maxPp,
    item = spread.item ~= 0 and spread.item or nil,
    heldItem = spread.item ~= 0 and spread.item or nil,
    pokeball = spread.ball ~= 0 and spread.ball or 4,
    gender = deps.Pokemon.gender and deps.Pokemon.gender(spread.species, personality) or "U",
    friendship = 255, happiness = 255, obedient = true,
    isShiny = spread.shiny or nil, shiny = spread.shiny or nil,
    gigantamax = spread.gigantamax or nil,
    rrFacility = true,
  }
  if owner then
    mon.ot, mon.otName = owner.name, owner.name
    mon.otId = owner.otId or random32(deps)
    mon.otGender = owner.gender
  end
  if deps.Pokemon.applyStats then deps.Pokemon.applyStats(mon) end
  mon.hp = tonumber(mon.maxHp) or mon.hp or 1
  return mon
end

local function poolKindForTier(tier, battleType)
  if tier == 1 or tier == 3 or tier == 8 then return "legendary" end
  if tier == 4 or tier == 9 then return "little" end
  if tier == 5 or tier == 10 then
    if battleType == 0 or battleType == 4 then return "middle" end
    return "regular"
  end
  return "regular"
end

local function trainerPool(record, kind)
  local pool = record and record.pools and record.pools[kind]
  if pool and pointerOffset(pool[1]) and pool[2] > 0 then return pool[1], pool[2], false end
  local generic = GENERIC_POOL[kind] or GENERIC_POOL.regular
  return generic[1], generic[2], true
end

local function spreadAllowed(spread, singles)
  if not spread or spread.species == 0 then return false end
  if singles then return spread.forSingles end
  return spread.forDoubles
end

local function buildParty(deps, rom, record, ctx, trainerId)
  local count = math.max(1, math.min(6, getVar(deps, ctx, VAR.PARTY_SIZE)))
  local level = getVar(deps, ctx, VAR.LEVEL)
  if level <= 0 then level = 50 end
  local battleType = getVar(deps, ctx, VAR.BATTLE_TYPE)
  local singles = battleType == 0 or battleType == 4
  local kind = poolKindForTier(getVar(deps, ctx, VAR.TIER), battleType)
  local pointer, size, isOffset
  if trainerId == TRAINER.REGULAR then
    local generic = GENERIC_POOL[kind] or GENERIC_POOL.regular
    pointer, size, isOffset = generic[1], generic[2], true
  else
    pointer, size, isOffset = trainerPool(record, kind)
  end
  local owner = { name = record.name, gender = record.gender, otId = random32(deps) }
  local party, speciesSeen, itemSeen = {}, {}, {}
  local attempts = 0
  while #party < count and attempts < math.max(256, size * 3) do
    attempts = attempts + 1
    local spread = spreadAt(rom, pointer, randomMod(deps, size), isOffset)
    local item = spread and spread.item or 0
    if spreadAllowed(spread, singles) and not speciesSeen[spread.species]
        and (item == 0 or not itemSeen[item]) then
      local mon = makeMon(deps, rom, spread, level, owner)
      if mon then
        party[#party + 1] = mon
        speciesSeen[spread.species] = true
        if item ~= 0 then itemSeen[item] = true end
      end
    end
  end
  -- Curated pools should satisfy the uniqueness rules.  If a tiny custom
  -- pool cannot, fill remaining slots without duplicating a species.
  if #party < count then
    for index = 0, size - 1 do
      local spread = spreadAt(rom, pointer, index, isOffset)
      if spreadAllowed(spread, singles) and not speciesSeen[spread.species] then
        local mon = makeMon(deps, rom, spread, level, owner)
        if mon then
          party[#party + 1] = mon
          speciesSeen[spread.species] = true
          if #party >= count then break end
        end
      end
    end
  end
  return party
end

local function className(deps, class)
  local pack = deps.Trainers.pack and deps.Trainers.pack()
  return pack and pack.classNames and pack.classNames[class] or ("CLASS " .. tostring(class))
end

local function definitionFor(deps, rom, trainerId, ctx)
  trainerId = tonumber(trainerId)
  local kind = trainerId == TRAINER.REGULAR and 0
    or trainerId == TRAINER.SPECIAL and 1
    or trainerId == TRAINER.BRAIN and 2 or nil
  if kind == nil then return nil end
  local index = getVar(deps, ctx, VAR.TRAINER_ID)
  local partySize = getVar(deps, ctx, VAR.PARTY_SIZE)
  local level = getVar(deps, ctx, VAR.LEVEL)
  local battleType = getVar(deps, ctx, VAR.BATTLE_TYPE)
  local tier = getVar(deps, ctx, VAR.TIER)
  local nameIndex = getVar(deps, ctx, VAR.TRAINER_NAME_1)
  local signature = table.concat({ index, partySize, level, battleType, tier, nameIndex }, ":")
  local selected = state.selected[trainerId]
  if selected and selected.signature == signature then return selected.definition end
  local record = trainerRecord(deps, rom, kind, index, 0, ctx)
  if not record then return nil end
  local party = buildParty(deps, rom, record, ctx, trainerId)
  if #party == 0 then return nil end
  local dialogs = {
    intro = textAt(deps, rom, record.pre),
    defeat = textAt(deps, rom, record.playerWin),
    victory = textAt(deps, rom, record.playerLose),
  }
  local definition = {
    id = trainerId, class = record.class, className = className(deps, record.class),
    pic = record.pic, name = record.name, gender = record.gender,
    encounterMusic = 0, doubleBattle = battleType ~= 0 and battleType ~= 4,
    partySize = #party, partyFlags = 3, lastLevel = party[#party].level,
    aiFlags = 7, ai = { checkBadMove = true, checkViability = true, tryToFaint = true },
    items = { 0, 0, 0, 0 }, party = party, dialogs = dialogs,
    rrFacility = true, record = record,
  }
  state.selected[trainerId] = { signature = signature, definition = definition }
  return definition
end

local function foeFromDefinition(definition)
  local lead = definition and definition.party and definition.party[1]
  if not lead then return nil end
  return {
    species = lead.species, level = lead.level, ivs = lead.ivs, evs = lead.evs,
    item = lead.item, heldItem = lead.heldItem, moves = lead.moves,
    personality = lead.personality, ability = lead.ability, abilityId = lead.abilityId,
    trainerId = definition.id, aiFlags = definition.aiFlags, ai = definition.ai,
    items = definition.items, party = definition.party,
    trainerName = definition.name, trainerClass = definition.class,
    trainerClassName = definition.className, trainerPic = definition.pic,
    gender = definition.gender, encounterMusic = definition.encounterMusic,
    doubleBattle = definition.doubleBattle, rrFacility = true,
  }
end

local function installTrainerPatch(deps, rom)
  local Trainers = deps.Trainers
  if not Trainers or Trainers._rrFacilityOriginals then return false end
  local originals = {
    get = Trainers.get, foeFromId = Trainers.foeFromId,
    info = Trainers.info, dialogs = Trainers.dialogs,
    getEncounterMusic = Trainers.getEncounterMusic,
  }
  Trainers._rrFacilityOriginals = originals
  local function currentCtx()
    local Space = package.loaded["src.core.game3.scripting.space"]
    return Space and Space.vm and Space.vm.ctx or Facilities._lastCtx
  end
  Trainers.get = function(id)
    local def = definitionFor(deps, rom, id, currentCtx())
    if def then return def end
    return originals.get(id)
  end
  Trainers.foeFromId = function(id)
    local def = definitionFor(deps, rom, id, currentCtx())
    if def then return foeFromDefinition(def) end
    return originals.foeFromId(id)
  end
  Trainers.info = function(id, opts)
    local def = definitionFor(deps, rom, id, currentCtx())
    if not def then return originals.info(id, opts) end
    return {
      class = def.class, className = def.className, name = def.name, pic = def.pic,
      gender = def.gender, encounterMusic = def.encounterMusic,
      doubleBattle = def.doubleBattle, partySize = def.partySize,
      lastLevel = def.lastLevel, aiFlags = def.aiFlags, ai = def.ai,
      items = def.items, party = def.party, dialogs = def.dialogs,
    }
  end
  Trainers.dialogs = function(id)
    local def = definitionFor(deps, rom, id, currentCtx())
    if def then return def.dialogs end
    return originals.dialogs(id)
  end
  Trainers.getEncounterMusic = function(id)
    local def = definitionFor(deps, rom, id, currentCtx())
    if def then return 285 end
    return originals.getEncounterMusic(id)
  end
  return true
end

local function saveRentalBackup(deps, session)
  if not session then return end
  if not session.rrFacilityFreshBackup then deps.Tower.savePlayerParty(session) end
  session.rrFacilityFreshBackup = nil
  session.rrFacilityPartyBackup = true
end

local function restoreRentalParty(deps)
  local session = sessionOf(deps)
  if not (session and session.rrFacilityPartyBackup) then return false end
  deps.Tower.loadPlayerParty(session)
  session.rrFacilityPartyBackup = nil
  session.rrFacilityFreshBackup = nil
  return true
end

local function replaceParty(deps, rom, offset, ctx)
  if not offset then return false end
  local session = sessionOf(deps)
  if not session then return false end
  saveRentalBackup(deps, session)
  local party = {}
  for index = 0, 5 do
    local spread = spreadAt(rom, offset, index, true)
    local level = spread and spread.level or 0
    if level <= 0 then level = getVar(deps, ctx, VAR.LEVEL) end
    if level <= 0 then level = 50 end
    local mon = makeMon(deps, rom, spread, level, {
      name = session.name or session.playerName or "RED",
      gender = session.gender or session.playerGender,
      otId = session.trainerId or session.playerId,
    })
    if mon then party[#party + 1] = mon end
  end
  if #party == 0 then return false end
  session.party = party
  return true
end

local function buildHandlers(deps, rom)
  local H = {}

  H.specialGenerate = function(ctx, adapters)
    Facilities._lastCtx = ctx
    local battler = math.max(0, math.min(2, getVar(deps, ctx, 0x8000)))
    local kind = math.max(0, math.min(2, getVar(deps, ctx, 0x8001)))
    local index
    if kind == 0 then
      index = randomMod(deps, regularTrainerCount(rom))
    elseif kind == 1 then
      local count = specialTrainerCount(rom)
      repeat
        index = randomMod(deps, count)
        local row = parseSpecialTrainer(deps, rom, 1, index)
        if getVar(deps, ctx, VAR.TIER) ~= 6 or (row and row.monotype) then break end
      until false
    else
      index = getVar(deps, ctx, 0x8002)
    end
    setVar(deps, ctx, VAR.TRAINER_ID + battler, index)
    if kind == 0 then
      local probe = parseRegularTrainer(deps, rom, index, battler, ctx)
      local countOffset = probe and probe.gender == 0 and Facilities.ROM.MALE_NAME_COUNT
        or Facilities.ROM.FEMALE_NAME_COUNT
      local nameCount = u16(read(rom, countOffset, 2), 0)
      local nameVar = battler == 0 and VAR.TRAINER_NAME_1 or VAR.TRAINER_NAME_2
      setVar(deps, ctx, nameVar, randomMod(deps, nameCount))
    end
    local record = trainerRecord(deps, rom, kind, index, battler, ctx)
    if record then setString(ctx, adapters, 1, record.name) end
    local trainerId = kind == 0 and TRAINER.REGULAR or kind == 1 and TRAINER.SPECIAL or TRAINER.BRAIN
    state.selected[trainerId] = nil
    return false, record and record.owNum or 0
  end

  H.specialIntro = function(ctx)
    Facilities._lastCtx = ctx
    local battler = math.max(0, math.min(2, getVar(deps, ctx, 0x8000)))
    local kind = math.max(0, math.min(2, getVar(deps, ctx, 0x8001)))
    local index = getVar(deps, ctx, VAR.TRAINER_ID + battler)
    local record = trainerRecord(deps, rom, kind, index, battler, ctx)
    if not record then return false end
    local key = installTransientText(deps, rom, record.pre)
    ctx.data = ctx.data or {}
    ctx.data[0] = key
    setVar(deps, ctx, VAR.TEXT_COLOR_BACKUP, getVar(deps, ctx, VAR.TEXT_COLOR))
    setVar(deps, ctx, VAR.TEXT_COLOR, record.gender == 0 and 0 or 1)
    return false
  end

  H[Facilities.ADDR.FIXED_PARTY] = function(ctx)
    Facilities._lastCtx = ctx
    local kind = getVar(deps, ctx, VAR.FIXED_PARTY_KIND)
    local offset = kind == 7 and Facilities.ROM.FIXED_PARTY_SEVEN
      or kind == 6 and Facilities.ROM.FIXED_PARTY_SIX or nil
    replaceParty(deps, rom, offset, ctx)
    return false
  end

  H[Facilities.ADDR.RENTAL_PARTY_A] = function(ctx)
    Facilities._lastCtx = ctx
    local mode = getVar(deps, ctx, VAR.SIMULATOR_MODE)
    local pointer = u32(read(rom, Facilities.ROM.RENTAL_POINTER_TABLE + mode * 60 + 156, 4), 0)
    replaceParty(deps, rom, pointerOffset(pointer), ctx)
    return false
  end

  H[Facilities.ADDR.RENTAL_PARTY_B] = function(ctx)
    Facilities._lastCtx = ctx
    local mode = getVar(deps, ctx, VAR.SIMULATOR_MODE)
    local pointer = u32(read(rom, Facilities.ROM.RENTAL_POINTER_TABLE + mode * 60 + 36, 4), 0)
    replaceParty(deps, rom, pointerOffset(pointer), ctx)
    return false
  end

  H[Facilities.ADDR.ROLL_THREE] = function(ctx)
    local values, used = {}, {}
    while #values < 3 do
      local value = randomMod(deps, 10)
      if not used[value] then used[value] = true; values[#values + 1] = value end
    end
    setVar(deps, ctx, 0x5140, values[1])
    setVar(deps, ctx, 0x5142, values[2])
    setVar(deps, ctx, 0x5143, values[3])
    return false
  end

  H[Facilities.ADDR.SIMULATOR_COMPARE] = function(ctx)
    local left = getFlag(deps, ctx, FLAG.SIMULATOR_ALT)
      and getVar(deps, ctx, VAR.SIMULATOR_ALT_WINS)
      or getVar(deps, ctx, VAR.SIMULATOR_WINS)
    local result = left < getVar(deps, ctx, VAR.SIMULATOR_TARGET) and 1 or 0
    setResult(deps, ctx, result)
    return false, result
  end

  H[Facilities.ADDR.SIMULATOR_TARGET] = function(ctx)
    local target = getFlag(deps, ctx, FLAG.SIMULATOR_SHORT) and 8 or 6
    local result = getVar(deps, ctx, VAR.SIMULATOR_TARGET) >= target and 1 or 0
    setResult(deps, ctx, result)
    return false, result
  end

  H[Facilities.ADDR.SIMULATOR_ADD_SCORE] = function(ctx)
    setVar(deps, ctx, VAR.SIMULATOR_POINTS,
      getVar(deps, ctx, VAR.SIMULATOR_POINTS) + getVar(deps, ctx, VAR.SIMULATOR_TARGET))
    return false
  end

  H[Facilities.ADDR.SIMULATOR_BONUS] = function(ctx)
    setVar(deps, ctx, VAR.SIMULATOR_POINTS, getVar(deps, ctx, VAR.SIMULATOR_POINTS) + 5)
    return false
  end

  H[Facilities.ADDR.SIMULATOR_TRAINER] = function(ctx)
    local firstCount = 27
    local base = getFlag(deps, ctx, FLAG.SIMULATOR_ALT) and 0 or firstCount
    local count = getFlag(deps, ctx, FLAG.SIMULATOR_ALT) and firstCount or 24
    local index = base + randomMod(deps, count)
    local trainerId = u32(read(rom, Facilities.ROM.SIMULATOR_TRAINERS + index * 4, 4), 0)
    if base == 0 and trainerId == 77 then
      if randomMod(deps, 2) == 0 then trainerId = 78 end
    elseif base == 0 and (trainerId == 435 or trainerId == 438) then
      local roll = randomMod(deps, 3)
      if roll == 0 then trainerId = 184 elseif roll == 1 then trainerId = 440 end
    elseif base == 0 and trainerId == 432 then
      local roll = randomMod(deps, 3)
      if roll == 0 then trainerId = 218 elseif roll == 1 then trainerId = 437 end
    end
    setResult(deps, ctx, trainerId)
    return false, trainerId
  end

  H[Facilities.ADDR.SIMULATOR_SETUP] = function(ctx)
    -- This callback chooses the party variant for the already selected RR
    -- trainer.  Preserve script-provided variants and initialize empty slots
    -- deterministically so the host never reads an uninitialized FireRed row.
    local trainerId = getVar(deps, ctx, VAR.RESULT)
    setVar(deps, ctx, VAR.SIMULATOR_VALUE, trainerId)
    if getVar(deps, ctx, VAR.SIMULATOR_PARTY_A) == 0 then
      setVar(deps, ctx, VAR.SIMULATOR_PARTY_A,
        1 + ((trainerId + (getFlag(deps, ctx, FLAG.HARDCORE) and 1 or 0)) % 3))
    end
    if getVar(deps, ctx, VAR.SIMULATOR_PARTY_B) == 0 then
      setVar(deps, ctx, VAR.SIMULATOR_PARTY_B, 1 + (trainerId % 3))
    end
    return false
  end

  return H
end

local function installPartyLifecycle(deps, mod)
  local saveKey, loadKey = "special:39", "special:40"
  if not deps.Natives._rrFacilityPartyLifecycle then
    local save = deps.Natives.ALLOW[saveKey]
    local loadParty = deps.Natives.ALLOW[loadKey]
    if save then
      deps.Natives.ALLOW[saveKey] = function(ctx, adapters)
        local a, b = save(ctx, adapters)
        local session = sessionOf(deps)
        if session then session.rrFacilityFreshBackup = true end
        return a, b
      end
    end
    if loadParty then
      deps.Natives.ALLOW[loadKey] = function(ctx, adapters)
        local a, b = loadParty(ctx, adapters)
        local session = sessionOf(deps)
        if session then
          session.rrFacilityPartyBackup = nil
          session.rrFacilityFreshBackup = nil
        end
        return a, b
      end
    end
    deps.Natives._rrFacilityPartyLifecycle = true
  end
  if mod and mod.events and mod.events.on then
    mod.events:on("battle.ended", function() restoreRentalParty(deps) end)
    mod.events:on("script.ended", function() restoreRentalParty(deps) end)
  end
end

local function installDynamicTrainerHook(deps, mod)
  if not (mod and mod.hooks and mod.hooks.wrap) then return false end
  mod.hooks:wrap("script.command", function(next, ctx, op, row)
    if (op == "trainerbattle" or op == "dotrainerbattle") and type(row) == "table" then
      local trainer = tonumber(row.trainer or row[1])
      local isVariable = trainer and ((trainer >= 0x4000 and trainer <= 0x40FF)
        or (trainer >= 0x8000 and trainer <= 0x8014))
      if isVariable then
        local resolved = getVar(deps, ctx, trainer)
        local copy = {}
        for key, value in pairs(row) do copy[key] = value end
        copy.trainer, copy[1] = resolved, resolved
        return next(ctx, op, copy)
      end
    end
    return next(ctx, op, row)
  end)
  return true
end

function Facilities.install(mod, rom, overrides)
  local deps = mergeDefaults(overrides)
  local handlers = buildHandlers(deps, rom)
  deps.Natives.ALLOW["special:" .. Facilities.SPECIAL.GENERATE_TRAINER] = handlers.specialGenerate
  deps.Natives.ALLOW["special:" .. Facilities.SPECIAL.LOAD_INTRO] = handlers.specialIntro
  local nativeCount = 0
  for address, handler in pairs(handlers) do
    if type(address) == "number" then
      deps.Natives.ALLOW["native:" .. address] = handler
      nativeCount = nativeCount + 1
    end
  end
  installPartyLifecycle(deps, mod)
  local trainers = installTrainerPatch(deps, rom)
  local dynamicIds = installDynamicTrainerHook(deps, mod)
  Facilities._deps = deps
  Facilities._handlers = handlers
  Facilities._rom = rom
  if mod and mod.log and mod.log.info then
    mod.log:info(("Radical Red facilities: 2 specials, %d callbacks, ROM trainers %s")
      :format(nativeCount, trainers and "active" or "already active"))
  end
  return {
    specialCallbacks = 2,
    nativeCallbacks = nativeCount,
    romTrainerTables = true,
    romSpreadTables = true,
    rentalParties = true,
    partyRestore = true,
    dynamicTrainerIds = dynamicIds,
  }
end

Facilities.TRAINER = TRAINER
Facilities.VAR = VAR
Facilities.FLAG = FLAG
Facilities._spreadAt = spreadAt
Facilities._trainerRecord = trainerRecord
Facilities._restoreRentalParty = restoreRentalParty

return Facilities
