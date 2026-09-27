-- Radical Red v4.1 randomizer runtime.
--
-- The setup choices themselves are owned by the extracted cartridge script.
-- This module supplies the native CFRU behavior that the Lua host cannot run:
-- deterministic species, ability, and learnset mappings seeded by the
-- player's full trainer id.  Every candidate pool below is read from the
-- validated v4.1 ROM; no replacement list is bundled with the mod.

local Randomizer = {}

local FLAG = {
  SPECIES = 0x940,
  SPECIES_SCALED = 0x93A,
  ABILITY = 0x942,
  LEARNSET = 0x941,
  TEMP_DISABLE = 0x930,
  SPECIES_DISABLE = 0x104E,
  ABILITY_DISABLE_1 = 0x1042,
  ABILITY_DISABLE_2 = 0x104B,
  HARDCORE = 0x1034,
  RESTRICTED = 0x103C,
}

-- ROM addresses are the literal pools used by RR 4.1's TryRandomizeSpecies,
-- TryRandomizeAbility, and RandomizeMove.  rr_rom reads file offsets.
local ROM = {
  SPECIES_POOLS = {
    none = 0x1165E18,
    badge2 = 0x11659A4,
    badge4 = 0x1165292,
    midpoint = 0x1164B52,
    badge6 = 0x11643AA,
    full = 0x1163B98,
  },
  ABILITY_DEFAULT = 0x1162ED6,
  ABILITY_RESTRICTED = 0x1162E06,
  MOVE_DEFAULT = 0x11627B8,
  MOVE_RESTRICTED = 0x116221A,
}

-- Radical Red deliberately supplies several rival records for the same
-- encounter.  Its map script selects the record that matches the player's
-- chosen starter/region; applying the host trainer hook afterwards used to
-- erase that choice by randomizing the selected party a second time.
--
-- Classes 81 and 89 contain only the branching Kanto-rival records in v4.1.
-- Brendan and May share the generic Pokemon Trainer class, so their exact
-- trainer ids are listed.  The two Champion trios are the final rival's
-- starter-dependent parties and must remain paired with that branch too.
local FIXED_RIVAL_CLASSES = {
  [81] = true,
  [89] = true,
}

local FIXED_RIVAL_IDS = {
  [26] = true,  -- Brendan, postgame
  [44] = true,  -- Brendan, S.S. Anne
  [50] = true,  -- Brendan, Fuchsia
  [55] = true,  -- Brendan, Route 23
  [57] = true,  -- Brendan, late game
  [61] = true,  -- May
  [438] = true, [439] = true, [440] = true, -- Champion branches
  [739] = true, [740] = true, [741] = true, -- rematch branches
}

local function isFixedRival(trainerClass, trainerId)
  trainerClass = math.floor(tonumber(trainerClass) or -1)
  trainerId = math.floor(tonumber(trainerId) or -1)
  return FIXED_RIVAL_CLASSES[trainerClass] == true
    or FIXED_RIVAL_IDS[trainerId] == true
end

local U32 = 4294967296

local function u16(bytes, offset)
  local lo, hi = bytes:byte(offset + 1, offset + 2)
  return (lo or 0) + (hi or 0) * 0x100
end

local function readU16Pool(rom, offset)
  local countBytes = assert(rom:_read(offset, 2))
  local count = u16(countBytes, 0)
  assert(count > 0 and count < 4096,
    ("invalid Radical Red randomizer pool count at 0x%X"):format(offset))
  local bytes = assert(rom:_read(offset + 2, count * 2))
  local out = {}
  for i = 0, count - 1 do out[i + 1] = u16(bytes, i * 2) end
  return out
end

local function readU8Pool(rom, offset)
  local count = assert(rom:_read(offset, 1)):byte(1)
  assert(count and count > 0,
    ("invalid Radical Red randomizer pool count at 0x%X"):format(offset))
  local bytes = assert(rom:_read(offset + 1, count))
  local out = {}
  for i = 1, count do out[i] = bytes:byte(i) end
  return out
end

local function loadPools(rom)
  local pools = { species = {} }
  for key, offset in pairs(ROM.SPECIES_POOLS) do
    pools.species[key] = readU16Pool(rom, offset)
  end
  pools.abilityDefault = readU8Pool(rom, ROM.ABILITY_DEFAULT)
  pools.abilityRestricted = readU8Pool(rom, ROM.ABILITY_RESTRICTED)
  pools.moveDefault = readU16Pool(rom, ROM.MOVE_DEFAULT)
  pools.moveRestricted = readU16Pool(rom, ROM.MOVE_RESTRICTED)
  return pools
end

local function liveSpace()
  local ok, Space = pcall(require, "src.core.game3.scripting.space")
  if ok and Space then return Space end
  return package.loaded["src.core.game3.scripting.space"]
end

local function liveSession()
  local ok, Runtime = pcall(require, "src.core.game3.runtime")
  if ok and Runtime and Runtime.getSession then return Runtime.getSession() end
  Runtime = package.loaded["src.core.game3.runtime"]
  return Runtime and Runtime.getSession and Runtime.getSession() or nil
end

local function flagOn(id)
  local Space = liveSpace()
  if not (Space and Space.store) then return false end
  local Flags = require("src.core.game3.scripting.flags")
  return Flags.getFlag(Space.store, Space.vm and Space.vm.ctx, id) == true
end

-- T1_READ_32(gSaveBlock2->playerTrainerId) is the public id in the low word
-- and secret id in the high word.  Game3 stores those words separately.
local function trainerId32(session)
  session = session or liveSession()
  local public = math.floor(tonumber(session and
    (session.trainerId or session.id or session.playerId)) or 0) % 0x10000
  local secret = math.floor(tonumber(session and session.secretId) or 0) % 0x10000
  local id = public + secret * 0x10000
  return id == 0 and 1 or id
end

local function mulU32(a, b)
  local ok, Rng = pcall(require, "src.core.game3.rng")
  if ok and Rng and Rng.mulU32 then return Rng.mulU32(a, b) end
  a = math.floor(tonumber(a) or 0) % U32
  b = math.floor(tonumber(b) or 0) % U32
  local aLo, aHi = a % 65536, math.floor(a / 65536)
  local bLo, bHi = b % 65536, math.floor(b / 65536)
  return (aLo * bLo + ((aLo * bHi + aHi * bLo) % 65536) * 65536) % U32
end

local function bxor(a, b)
  local ok, bit = pcall(require, "bit")
  if ok and bit and bit.bxor then return bit.bxor(a, b) % U32 end
  local result, place = 0, 1
  a, b = math.floor(a or 0), math.floor(b or 0)
  while a > 0 or b > 0 do
    local aa, bb = a % 2, b % 2
    if aa ~= bb then result = result + place end
    a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
  end
  return result
end

local function randomizersEnabled()
  return not flagOn(FLAG.TEMP_DISABLE)
end

local function speciesMode()
  if not randomizersEnabled() or flagOn(FLAG.SPECIES_DISABLE) then return nil end
  -- The cartridge tests scaled mode before the ordinary species flag.
  if flagOn(FLAG.SPECIES_SCALED) then return "scaled" end
  if flagOn(FLAG.SPECIES) then return "normal" end
  return nil
end

local function scaledPool(pools)
  -- Exact progression order from v4.1 TryRandomizeSpecies.
  if flagOn(0x827) then return pools.species.full end
  if flagOn(0x825) then return pools.species.badge6 end
  if flagOn(0x053) then return pools.species.midpoint end
  if flagOn(0x823) then return pools.species.badge4 end
  if flagOn(0x821) then return pools.species.badge2 end
  return pools.species.none
end

local function speciesPool(pools)
  local mode = speciesMode()
  if mode == "normal" then return pools.species.full, mode end
  if mode == "scaled" then return scaledPool(pools), mode end
  return nil, nil
end

local function randomizeSpecies(pools, species, session)
  species = math.floor(tonumber(species) or 0)
  local pool = speciesPool(pools)
  -- RR accepts species 1..1375 here. Zero, Egg, and invalid ids pass through.
  if not pool or species < 1 or species >= 1376 then return species end
  local index = mulU32(trainerId32(session), species) % #pool
  return pool[index + 1] or species
end

local function restrictedRules()
  return flagOn(FLAG.HARDCORE) or flagOn(FLAG.RESTRICTED)
end

local function randomizeAbility(pools, ability, species, session)
  ability = math.floor(tonumber(ability) or 0)
  species = math.floor(tonumber(species) or 0)
  if ability == 0 or not randomizersEnabled() or not flagOn(FLAG.ABILITY)
      or flagOn(FLAG.ABILITY_DISABLE_1) or flagOn(FLAG.ABILITY_DISABLE_2) then
    return ability
  end
  local pool = restrictedRules() and pools.abilityRestricted
    or pools.abilityDefault
  local id = trainerId32(session)
  local startAt = (id % 0x10000) % #pool
  local xorVal = math.floor(id / 0x10000) % 0xFF
  local index = ability + species + startAt
  if index >= #pool then index = index - #pool + 2 end
  index = bxor(index, xorVal) % #pool
  return pool[index + 1] or ability
end

local function randomizeMove(pools, move, species, session)
  move = math.floor(tonumber(move) or 0)
  species = math.floor(tonumber(species) or 0)
  if move == 0 or move == 165 or not randomizersEnabled()
      or not flagOn(FLAG.LEARNSET) then return move end
  local pool = restrictedRules() and pools.moveRestricted or pools.moveDefault
  local product = mulU32(move, species)
  product = mulU32(product, trainerId32(session))
  return pool[(product % #pool) + 1] or move
end

local function shallow(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = item end
  return out
end

local function patchPokemon(pools)
  local Pokemon = require("src.core.game3.pokemon")
  if Pokemon.__radicalRedRandomizer then return end
  Pokemon.__radicalRedRandomizer = true

  local originalLearnset = assert(Pokemon.learnset)
  Pokemon.learnset = function(species)
    local rows = originalLearnset(species)
    if not (randomizersEnabled() and flagOn(FLAG.LEARNSET)) then return rows end
    local speciesId = type(species) == "table" and Pokemon.speciesOf(species)
      or (type(species) == "string" and
        (Pokemon.speciesFromName(species) or tonumber(species)))
      or tonumber(species)
    if not speciesId then return rows end
    local out = {}
    for i, row in ipairs(rows or {}) do
      local level = tonumber(row[1] or row.level) or 0
      local move = tonumber(row[2] or row.move) or 0
      local mapped = randomizeMove(pools, move, speciesId)
      out[i] = { level, mapped, level = level, move = mapped }
    end
    return out
  end

  local originalAbilityId = assert(Pokemon.abilityId)
  Pokemon.abilityId = function(species, personality, abilityNum)
    local original = originalAbilityId(species, personality, abilityNum)
    local speciesId = type(species) == "table" and Pokemon.speciesOf(species)
      or (type(species) == "string" and
        (Pokemon.speciesFromName(species) or tonumber(species)))
      or tonumber(species)
    return randomizeAbility(pools, original, speciesId or 0)
  end
end

local function patchParty(pools, mod)
  local Party = require("src.core.game3.party")
  if Party.__radicalRedRandomizer then return end
  Party.__radicalRedRandomizer = true
  local originalGiveMon = assert(Party.giveMon)
  Party.giveMon = function(session, species, level, nickname, opts)
    if not (mod and mod.__rrPreserveRegionalStarter) then
      species = randomizeSpecies(pools, species, session)
    end
    return originalGiveMon(session, species, level, nickname, opts)
  end
end

local function patchWildBattles(pools)
  local Bridge = require("src.core.game3.battle_bridge")
  if Bridge.__radicalRedRandomizer then return end
  Bridge.__radicalRedRandomizer = true
  local originalStartWild = assert(Bridge.startWild)
  Bridge.startWild = function(mod, game, encounter, opts)
    if type(encounter) == "table" then
      local Pokemon = require("src.core.game3.pokemon")
      local copy = shallow(encounter)
      local original = tonumber(copy.species or copy.speciesId)
      if not original and copy.species ~= nil then
        original = Pokemon.speciesFromName(copy.species)
      end
      local mapped = randomizeSpecies(pools, original)
      if mapped and mapped > 0 and mapped ~= original then
        copy.species, copy.speciesId = mapped, mapped
        copy.name, copy.nickname = nil, nil
        copy.moves, copy.pp, copy.maxPp = nil, nil, nil
      end
      if flagOn(FLAG.ABILITY) then
        copy.ability, copy.abilityId = nil, nil
      end
      encounter = copy
    end
    return originalStartWild(mod, game, encounter, opts)
  end
end

local function installTrainerHook(mod, pools)
  mod.hooks:wrap("trainer.party", function(next, trainerClass, trainerId, party)
    if type(party) ~= "table" then
      return next(trainerClass, trainerId, party)
    end
    -- The cartridge has already selected the rival party for the active
    -- starter/region branch. Preserve its species, explicit moves, items, and
    -- abilities even when one or more randomizer modes are enabled.
    if isFixedRival(trainerClass, trainerId) then
      return next(trainerClass, trainerId, party)
    end
    local mode = speciesMode()
    local learnsetMode = randomizersEnabled() and flagOn(FLAG.LEARNSET)
    local abilityMode = randomizersEnabled() and flagOn(FLAG.ABILITY)
    if not (mode or learnsetMode or abilityMode) then
      return next(trainerClass, trainerId, party)
    end

    local Pokemon = require("src.core.game3.pokemon")
    local G3 = require("src.mods.Gen3Compat")
    local out = {}
    for i, mon in ipairs(party) do
      local row = shallow(mon)
      local original = tonumber(row.speciesId)
        or G3.speciesId(row.species) or tonumber(row.species)
      local mapped = mode and randomizeSpecies(pools, original) or original
      if mapped and mapped > 0 then
        row.species = G3.speciesName(mapped) or Pokemon.keyName(mapped) or mapped
        row.speciesId = mapped
      end
      if mode or learnsetMode then
        local moves = Pokemon.movesAtLevel(mapped or original, row.level or 5)
        row.moves, row.moveIds = {}, {}
        for j, move in ipairs(moves or {}) do
          row.moves[j] = G3.moveName(move) or move
          row.moveIds[j] = move
        end
        row.pp, row.maxPp = nil, nil
      end
      if abilityMode then row.ability, row.abilityId = nil, nil end
      out[i] = row
    end
    return next(trainerClass, trainerId, out)
  end, 900)
end

function Randomizer.install(mod, rom)
  assert(mod and mod.hooks, "Radical Red randomizer requires mod hooks")
  assert(rom and rom._read, "Radical Red randomizer requires the validated ROM")
  local pools = loadPools(rom)
  patchPokemon(pools)
  patchParty(pools, mod)
  patchWildBattles(pools)
  installTrainerHook(mod, pools)
  Randomizer._pools = pools
  return {
    cartridgeSetup = true,
    species = true,
    scaledSpecies = true,
    abilities = true,
    learnsets = true,
    regionalStarterPreserved = true,
    fixedRivals = true,
    fixedRivalClasses = 2,
    fixedRivalIds = 12,
    speciesPool = #pools.species.full,
    scaledPool = #pools.species.none,
    abilityPool = #pools.abilityDefault,
    movePool = #pools.moveDefault,
  }
end

Randomizer.FLAG = FLAG
Randomizer.ROM = ROM
Randomizer.loadPools = loadPools
Randomizer.trainerId32 = trainerId32
Randomizer.randomizeSpecies = randomizeSpecies
Randomizer.randomizeAbility = randomizeAbility
Randomizer.randomizeMove = randomizeMove
Randomizer.isFixedRival = isFixedRival
Randomizer.FIXED_RIVAL_CLASSES = FIXED_RIVAL_CLASSES
Randomizer.FIXED_RIVAL_IDS = FIXED_RIVAL_IDS

return Randomizer
