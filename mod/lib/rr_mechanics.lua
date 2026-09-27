-- Radical Red v4.1 overworld gameplay callbacks.
--
-- These routines are native Thumb functions in the ROM hack.  The host does
-- not execute ARM code, so this module supplies behavior-equivalent Lua
-- callbacks while continuing to read RR's pools and level-cap tables from the
-- player's validated ROM.

local Mechanics = {}

local ADDR = {
  SET_TO_LEVEL_CAP = 0x090772D1,
  CHECK_SHINY = 0x09077AD1,
  CHECK_ATTACK = 0x09077B09,
  CHECK_GENDER_CHANGE = 0x09077B59,
  CHANGE_GENDER = 0x09077C45,
  CHECK_SPEED = 0x09077D4D,
  CHECK_DEFENSE = 0x09077D9D,
  CHECK_SP_ATTACK = 0x09077DED,
  CHECK_NO_FAIRY = 0x09077E3D,
  CHECK_STARTERS_ONLY = 0x09077F75,
  HEAL_CHOSEN_MON = 0x09077FD1,
  CHECK_ONE_USABLE_MON = 0x09078085,
  GIVE_RANDOM_EGG = 0x0907C9E1,
  GIVE_DIFFERENT_RANDOM_EGG = 0x0907CA2D,
  BUILD_RANDOM_STARTERS = 0x0907CC55,
  BUILD_CATEGORY_STARTERS = 0x0907CCDD,
  BUFFER_LEVEL_CAP = 0x090950A5,
  CHECK_DEOXYS = 0x090B5CDD,
  CHANGE_DEOXYS_FORM = 0x090B5EF9,
  SWAP_ABILITY = 0x090B5F8D,
  CHECK_ABILITY_SWAP = 0x090B6005,
  CHECK_PARTY_DEOXYS = 0x090BB1A9,
}

local ROM = {
  EGG_POOL = 0x11636D0,
  RANDOM_STARTERS = 0x1165E1A,
  LEVEL_CAPS = 0x135013C,
}

local CATEGORY_POOLS = {
  [0] = { 0x1163246, 68 },
  [1] = { 0x11633AA, 47 },
  [2] = { 0x11632CE, 60 },
  [3] = { 0x11631F6, 40 },
  [4] = { 0x1163106, 42 },
  [5] = { 0x11634B0, 41 },
  [6] = { 0x1162FC4, 46 },
  [7] = { 0x1163020, 41 },
  [8] = { 0x116315A, 40 },
  [10] = { 0x116360C, 38 },
  [11] = { 0x116356C, 80 },
  [12] = { 0x1163502, 53 },
  [13] = { 0x1163346, 50 },
  [14] = { 0x1163408, 50 },
  [15] = { 0x1163072, 30 },
  [16] = { 0x116346C, 34 },
  [17] = { 0x11630AE, 44 },
  [23] = { 0x11631AA, 38 },
}

-- GetCurrentLevelCap counts these story milestones in this exact order.  The
-- order matters only for parity with the ROM; every set flag advances one row.
local CAP_PROGRESS_FLAGS = {
  0x991, 0x827, 0x982, 0x981, 0x826, 0x998, 0x825, 0x824,
  0x053, 0x955, 0x038, 0x823, 0x822, 0x821, 0x201, 0x820,
}

local FALLBACK_CAPS = {
  { 15, 22, 27, 34, 44, 47, 56, 57, 59, 68, 73, 76, 79, 80, 81, 82, 85, 100 },
  { 16, 23, 28, 36, 44, 47, 56, 57, 59, 68, 73, 76, 79, 80, 81, 82, 85, 100 },
}

local GENDER_CHANGE_SPECIES = {
  [346] = true, [392] = true, [393] = true, [465] = true,
  [468] = true, [603] = true, [707] = true, [708] = true,
  [736] = true, [785] = true, [846] = true, [974] = true,
}

local GENDER_CHANGE_NAMES = {
  SNORUNT = true, RALTS = true, KIRLIA = true, SALANDIT = true,
  BURMY = true, COMBEE = true, ESPURR = true, BASCULIN = true,
  LECHONK = true,
}

local STARTER_RANGES = {
  { 1, 9 }, { 152, 160 }, { 277, 285 }, { 441, 449 },
  { 548, 556 }, { 758, 766 }, { 922, 930 }, { 939, 947 },
  { 1102, 1110 }, { 1299, 1301 },
}

local DEOXYS_FORMS = { [410] = true, [1040] = true, [1041] = true, [1042] = true }

local function mergeDefaults(overrides)
  local deps = {}
  for key, value in pairs(overrides or {}) do deps[key] = value end
  local modules = {
    Natives = "src.core.game3.scripting.natives",
    Flags = "src.core.game3.scripting.flags",
    Pokemon = "src.core.game3.pokemon",
    Party = "src.core.game3.party",
    Storage = "src.core.game3.storage",
    SummaryData = "src.core.game3.summary_data",
    Rng = "src.core.game3.rng",
  }
  for key, moduleName in pairs(modules) do
    if deps[key] == nil then deps[key] = require(moduleName) end
  end
  return deps
end

local function storeOf()
  local ok, Space = pcall(require, "src.core.game3.scripting.space")
  if not ok then Space = package.loaded["src.core.game3.scripting.space"] end
  return Space and Space.store or nil
end

local function sessionOf(deps)
  if deps.getSession then return deps.getSession() end
  local ok, Runtime = pcall(require, "src.core.game3.runtime")
  if not ok then Runtime = package.loaded["src.core.game3.runtime"] end
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
  setVar(deps, ctx, 0x800D, value)
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

local function selectedMon(deps, ctx)
  local session = sessionOf(deps)
  if not session then return nil end
  if getVar(deps, ctx, 0x8003) == 1 then
    local storage = deps.Storage.ensure(session)
    return deps.Storage.getBoxMon(storage,
      getVar(deps, ctx, 0x8000) + 1, getVar(deps, ctx, 0x8001) + 1)
  end
  local slot = getVar(deps, ctx, 0x8004)
  if slot < 0 or slot >= 6 then return nil end
  return session.party and session.party[slot + 1] or nil
end

local function speciesOf(mon)
  return tonumber(mon and (mon.species or mon.speciesId)) or 0
end

local function isEgg(deps, mon)
  if not mon then return false end
  if deps.Pokemon.isEgg then return deps.Pokemon.isEgg(mon) end
  return mon.isEgg == true
end

local function alivePartyMons(deps)
  local session = sessionOf(deps)
  local out = {}
  for _, mon in ipairs((session and session.party) or {}) do
    if speciesOf(mon) ~= 0 and not isEgg(deps, mon) then out[#out + 1] = mon end
  end
  return out
end

local function u16(bytes, offset)
  local lo, hi = bytes:byte(offset + 1, offset + 2)
  return (lo or 0) + (hi or 0) * 0x100
end

local function readU16Pool(rom, offset, count)
  assert(rom and rom._read, "Radical Red mechanics require the validated ROM")
  local bytes = rom:_read(offset, count * 2)
  local pool = {}
  for i = 0, count - 1 do pool[#pool + 1] = u16(bytes, i * 2) end
  return pool
end

local function randomIndex(deps, count)
  if count <= 0 then return 1 end
  if deps.randomIndex then return (deps.randomIndex(count) % count) + 1 end
  if deps.Rng and deps.Rng.mod then return deps.Rng.mod(count) + 1 end
  if deps.Rng and deps.Rng.Random then return (deps.Rng.Random() % count) + 1 end
  return math.random(1, count)
end

local function chooseUnique(deps, pool, count)
  local copy = {}
  for i, value in ipairs(pool) do copy[i] = value end
  local out = {}
  for _ = 1, math.min(count, #copy) do
    local index = randomIndex(deps, #copy)
    out[#out + 1] = copy[index]
    copy[index] = copy[#copy]
    copy[#copy] = nil
  end
  return out
end

local function getFlag(deps, ctx, id)
  return deps.Flags.getFlag(storeOf(), ctx, id) == true
end

local function levelCapTables(rom)
  if not (rom and rom._read) then return FALLBACK_CAPS end
  local ok, bytes = pcall(rom._read, rom, ROM.LEVEL_CAPS, 36)
  if not ok or type(bytes) ~= "string" or #bytes ~= 36 then return FALLBACK_CAPS end
  local tables = { {}, {} }
  for mode = 1, 2 do
    for i = 1, 18 do tables[mode][i] = bytes:byte((mode - 1) * 18 + i) end
  end
  return tables
end

local function currentLevelCap(deps, rom, ctx)
  local index = 0
  if getFlag(deps, ctx, 0x82C) then
    index = 17
  else
    for _, flag in ipairs(CAP_PROGRESS_FLAGS) do
      if getFlag(deps, ctx, flag) then index = index + 1 end
    end
  end
  if index > 17 then index = 17 end
  local mode = getFlag(deps, ctx, 0x1034) and 2 or 1
  local cap = levelCapTables(rom)[mode][index + 1]
  if getFlag(deps, ctx, 0x1033) then cap = math.min(100, cap + 3) end
  return cap
end

local function setMonLevel(deps, mon, level)
  level = math.max(1, math.min(100, math.floor(tonumber(level) or 1)))
  mon.level = level
  local growth = tonumber(mon.growthRate)
  if growth == nil and deps.Pokemon.growthRate then growth = deps.Pokemon.growthRate(speciesOf(mon)) end
  mon.growthRate = tonumber(growth) or 0
  mon.exp = deps.SummaryData.expForLevel(mon.growthRate, level)
  if deps.Pokemon.applyStats then deps.Pokemon.applyStats(mon) end
end

local function isStarter(species)
  for _, range in ipairs(STARTER_RANGES) do
    if species >= range[1] and species <= range[2] then return true end
  end
  return false
end

local function genderTarget(deps, mon)
  local current = mon.gender
  if current ~= "M" and current ~= "F" and deps.Pokemon.gender then
    current = deps.Pokemon.gender(speciesOf(mon), mon.personality)
  end
  return current == "M" and "F" or "M"
end

local function canChangeGender(deps, mon)
  local species = speciesOf(mon)
  if GENDER_CHANGE_SPECIES[species] then return true end
  -- Converted saves and third-party save importers can mark a species as
  -- National-numbered before the RR internal id is restored.  The cartridge
  -- callback compares internal ids, but resolving the live ROM name gives the
  -- same answer without rejecting valid Combee/Burmy forms in those saves.
  local name = mon and mon.name
  local normalized = type(name) == "string"
    and name:upper():gsub("[^A-Z]", "") or ""
  if GENDER_CHANGE_NAMES[normalized] then return true end
  if deps.Pokemon.name and species > 0 then
    local ok, resolved = pcall(deps.Pokemon.name, species)
    if ok and type(resolved) == "string" then name = resolved end
  end
  name = type(name) == "string" and name:upper():gsub("[^A-Z]", "") or ""
  return GENDER_CHANGE_NAMES[name] == true
end

local function findGenderPersonality(deps, mon, target)
  local old = math.floor(tonumber(mon.personality) or 0) % 4294967296
  local nature, parity = old % 25, old % 2
  local shiny = deps.Pokemon.isShiny and deps.Pokemon.isShiny(mon) or false
  if not shiny then
    for n = 1, 131072 do
      local candidate = (old + n * 50) % 4294967296
      if deps.Pokemon.gender(speciesOf(mon), candidate) == target
          and not deps.Pokemon.isShiny({
            personality = candidate,
            otId = mon.otId or mon.trainerId,
            otSecretId = mon.otSecretId,
          }) then
        return candidate
      end
    end
    return old
  end

  local function xor16(a, b)
    local result, place = 0, 1
    a, b = math.floor(a or 0) % 65536, math.floor(b or 0) % 65536
    for _ = 1, 16 do
      local aa, bb = a % 2, b % 2
      if aa ~= bb then result = result + place end
      a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
    end
    return result
  end
  local trainerXor = xor16(mon.otId or mon.trainerId or 0, mon.otSecretId or 0)
  for low = parity, 65535, 2 do
    if deps.Pokemon.gender(speciesOf(mon), low) == target then
      for shinyValue = 0, 7 do
        local high = xor16(trainerXor, xor16(low, shinyValue))
        local candidate = low + high * 65536
        if candidate % 25 == nature then return candidate end
      end
    end
  end
  return old
end

local function changeSpecies(deps, mon, species)
  local oldMax, oldHp = tonumber(mon.maxHp) or 0, tonumber(mon.hp) or 0
  mon.species, mon.speciesId = species, species
  if deps.Pokemon.name then mon.name = deps.Pokemon.name(species) end
  if deps.Pokemon.abilityId then
    local ability = deps.Pokemon.abilityId(species, mon.personality)
    mon.ability, mon.abilityId = ability, ability
  end
  if deps.Pokemon.gender then mon.gender = deps.Pokemon.gender(species, mon.personality) end
  if deps.Pokemon.applyStats then deps.Pokemon.applyStats(mon) end
  if oldMax > 0 and oldHp > 0 then
    mon.hp = math.max(1, math.floor((tonumber(mon.maxHp) or 1) * oldHp / oldMax))
  end
end

local function buildHandlers(deps, rom)
  local H = {}

  H[ADDR.GIVE_RANDOM_EGG] = function(ctx, adapters)
    local pool = readU16Pool(rom, ROM.EGG_POOL, 12)
    local species = pool[randomIndex(deps, #pool)]
    setVar(deps, ctx, 0x514A, species)
    local session = sessionOf(deps)
    if adapters and adapters.giveEggToPlayer then adapters.giveEggToPlayer(species)
    elseif session then deps.Party.giveEggToPlayer(session, species) end
    return false
  end

  H[ADDR.GIVE_DIFFERENT_RANDOM_EGG] = function(ctx, adapters)
    local pool = readU16Pool(rom, ROM.EGG_POOL, 12)
    local previous = getVar(deps, ctx, 0x514A)
    local choices = {}
    for _, species in ipairs(pool) do
      if species ~= previous then choices[#choices + 1] = species end
    end
    local species = choices[randomIndex(deps, #choices)]
    setVar(deps, ctx, 0x514A, species)
    local session = sessionOf(deps)
    if adapters and adapters.giveEggToPlayer then adapters.giveEggToPlayer(species)
    elseif session then deps.Party.giveEggToPlayer(session, species) end
    return false
  end

  H[ADDR.BUILD_RANDOM_STARTERS] = function(ctx)
    local pool = readU16Pool(rom, ROM.RANDOM_STARTERS, 330)
    for i, species in ipairs(chooseUnique(deps, pool, 6)) do
      setVar(deps, ctx, 0x5141 + i, species)
    end
    return false
  end

  H[ADDR.BUILD_CATEGORY_STARTERS] = function(ctx)
    local descriptor = CATEGORY_POOLS[getVar(deps, ctx, 0x5140)]
    if descriptor then
      local pool = readU16Pool(rom, descriptor[1], descriptor[2])
      for i, species in ipairs(chooseUnique(deps, pool, 6)) do
        setVar(deps, ctx, 0x5141 + i, species)
      end
    end
    return false
  end

  H[ADDR.SET_TO_LEVEL_CAP] = function(ctx)
    local mon = selectedMon(deps, ctx)
    local cap = currentLevelCap(deps, rom, ctx)
    local changed = mon and (tonumber(mon.level) or 1) < cap
    if changed then setMonLevel(deps, mon, cap) end
    setResult(deps, ctx, changed and 1 or 0)
    return false
  end

  H[ADDR.BUFFER_LEVEL_CAP] = function(ctx, adapters)
    setString(ctx, adapters, 1, currentLevelCap(deps, rom, ctx))
    return false
  end

  H[ADDR.CHECK_SHINY] = function(ctx)
    local mon = selectedMon(deps, ctx)
    setResult(deps, ctx, mon and deps.Pokemon.isShiny(mon) and 1 or 0)
    return false
  end

  local function statCheck(key)
    return function(ctx)
      local mon = selectedMon(deps, ctx)
      local stats = mon and deps.Pokemon.stats(speciesOf(mon)) or nil
      setResult(deps, ctx, stats and (tonumber(stats[key]) or 0) > 124 and 1 or 0)
      return false
    end
  end
  H[ADDR.CHECK_ATTACK] = statCheck("atk")
  H[ADDR.CHECK_SPEED] = statCheck("spe")
  H[ADDR.CHECK_DEFENSE] = statCheck("def")
  H[ADDR.CHECK_SP_ATTACK] = statCheck("spa")

  H[ADDR.CHECK_GENDER_CHANGE] = function(ctx, adapters)
    local mon = selectedMon(deps, ctx)
    local eligible = mon and canChangeGender(deps, mon)
    setResult(deps, ctx, eligible and 1 or 0)
    if eligible then setString(ctx, adapters, 1, genderTarget(deps, mon) == "F" and "Female" or "Male") end
    return false
  end

  H[ADDR.CHANGE_GENDER] = function(ctx)
    local mon = selectedMon(deps, ctx)
    if mon and canChangeGender(deps, mon) then
      local target = genderTarget(deps, mon)
      mon.personality = findGenderPersonality(deps, mon, target)
      mon.nature = mon.personality % 25
      mon.gender = target
      if deps.Pokemon.abilityId then
        local ability = deps.Pokemon.abilityId(speciesOf(mon), mon.personality)
        mon.ability, mon.abilityId = ability, ability
      end
      if deps.Pokemon.applyStats then deps.Pokemon.applyStats(mon) end
    end
    return false
  end

  H[ADDR.CHECK_NO_FAIRY] = function(ctx)
    local valid = true
    local megaExceptions = { [359] = 0x235, [376] = 0x237, [584] = 0x242 }
    for _, mon in ipairs(alivePartyMons(deps)) do
      local species = speciesOf(mon)
      local types = deps.Pokemon.types(species)
      local held = tonumber(mon.heldItem or mon.item) or 0
      if types[1] == 23 or types[2] == 23 or megaExceptions[species] == held then
        valid = false
        break
      end
    end
    setResult(deps, ctx, valid and 1 or 0)
    return false
  end

  H[ADDR.CHECK_STARTERS_ONLY] = function(ctx)
    local valid = true
    for _, mon in ipairs(alivePartyMons(deps)) do
      if not isStarter(speciesOf(mon)) then valid = false break end
    end
    setResult(deps, ctx, valid and 1 or 0)
    return false
  end

  H[ADDR.HEAL_CHOSEN_MON] = function(ctx)
    deps.Storage.fullHealMon(selectedMon(deps, ctx))
    return false
  end

  H[ADDR.CHECK_ONE_USABLE_MON] = function(ctx)
    local count = 0
    for _, mon in ipairs(alivePartyMons(deps)) do
      if (tonumber(mon.hp) or 0) ~= 0 then count = count + 1 end
    end
    setResult(deps, ctx, count == 1 and 1 or 0)
    return false
  end

  H[ADDR.CHECK_DEOXYS] = function(ctx)
    setResult(deps, ctx, DEOXYS_FORMS[speciesOf(selectedMon(deps, ctx))] and 1 or 0)
    return false
  end

  H[ADDR.CHANGE_DEOXYS_FORM] = function(ctx)
    local mon = selectedMon(deps, ctx)
    local target = getVar(deps, ctx, 0x5142)
    if not mon or not DEOXYS_FORMS[speciesOf(mon)] or not DEOXYS_FORMS[target] then
      setResult(deps, ctx, 1)
    elseif speciesOf(mon) == target then
      setResult(deps, ctx, 2)
    else
      changeSpecies(deps, mon, target)
      setResult(deps, ctx, 0)
    end
    return false
  end

  H[ADDR.CHECK_PARTY_DEOXYS] = function(ctx)
    local result = 0
    for _, mon in ipairs(alivePartyMons(deps)) do
      if DEOXYS_FORMS[speciesOf(mon)] then result = 2 break end
    end
    setResult(deps, ctx, result)
    return false
  end

  H[ADDR.CHECK_ABILITY_SWAP] = function(ctx, adapters)
    local mon = selectedMon(deps, ctx)
    local pair = mon and deps.Pokemon.abilities(speciesOf(mon)) or { 0, 0 }
    local current = tonumber(mon and (mon.abilityId or mon.ability)) or 0
    local target = pair[1] == current and pair[2] or pair[1]
    local valid = mon and pair[1] ~= 0 and pair[2] ~= 0 and target ~= current
    setResult(deps, ctx, valid and 1 or 0)
    if valid then
      setString(ctx, adapters, 1, mon.nickname ~= "" and mon.nickname or mon.name)
      setString(ctx, adapters, 2, deps.Pokemon.abilityName(target))
      ctx.rrAbilitySwapTarget = target
    end
    return false
  end

  H[ADDR.SWAP_ABILITY] = function(ctx)
    local mon = selectedMon(deps, ctx)
    if mon then
      local pair = deps.Pokemon.abilities(speciesOf(mon))
      local current = tonumber(mon.abilityId or mon.ability) or 0
      local target = pair[1] == current and pair[2] or pair[1]
      if target and target ~= 0 and target ~= current then
        mon.ability, mon.abilityId = target, target
        mon.abilitySlot = target == pair[2] and 2 or 1
        -- Keep the PID nature while making the ordinary ability lookup agree.
        local wantedParity = target == pair[2] and 1 or 0
        local pid = math.floor(tonumber(mon.personality) or 0)
        if pid % 2 ~= wantedParity then pid = (pid + 25) % 4294967296 end
        mon.personality = pid
      end
    end
    return false
  end

  return H
end

function Mechanics.install(mod, rom, overrides)
  local deps = mergeDefaults(overrides)
  local handlers = buildHandlers(deps, rom)
  local count = 0
  for address, handler in pairs(handlers) do
    deps.Natives.ALLOW["native:" .. address] = handler
    count = count + 1
  end
  Mechanics._deps = deps
  Mechanics._handlers = handlers
  Mechanics._rom = rom
  if mod and mod.log and mod.log.info then
    mod.log:info(("Radical Red mechanics layer: %d ROM-native callbacks"):format(count))
  end
  return {
    nativeCallbacks = count,
    levelCaps = true,
    starterPools = true,
    eggPools = true,
    partyValidators = true,
    formChanges = true,
    abilityChanges = true,
  }
end

Mechanics.ADDR = ADDR
Mechanics.CATEGORY_POOLS = CATEGORY_POOLS
Mechanics.currentLevelCap = currentLevelCap

return Mechanics
