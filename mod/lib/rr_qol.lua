-- Radical Red v4.1 quality-of-life flags whose effects normally live in
-- CFRU's ARM code.  The ROM scripts still own the flags; this module only
-- supplies the matching host behavior after those scripts set them.

local Qol = {}

Qol.FLAG = {
  RUNNING_SHOES = 0x082F,
  DEX_NAV = 0x091E,
  SO2_TOXIC = 0x103F,
  WOYAOPP = 0x1040,
  DEX_ALL = 0x1056,
  TEAM_PREVIEW = 0x1083,
  EZ_CATCH = 0x109D,
}

local METHODS = {
  { key = "land", label = "WALK", area = "land" },
  { key = "rocks", label = "ROCK", area = "land" },
  { key = "water", label = "SURF", area = "water" },
  { key = "fishing", label = "FISH", area = "water" },
}

local RODS = {
  { last = 2, item = 262, label = "OLD ROD" },
  { last = 5, item = 263, label = "GOOD ROD" },
  { last = 10, item = 264, label = "SUPER ROD" },
}

local DEXNAV_SAVE_ROOT = "radical_red_experience"
local DEXNAV_SCHEMA = 1
local IV_KEYS = { "hp", "atk", "def", "spe", "spa", "spd" }

local function mergeDefaults(overrides)
  local deps = {}
  for key, value in pairs(overrides or {}) do deps[key] = value end
  local modules = {
    Flags = "src.core.game3.scripting.flags",
    Encounters = "src.core.game3.encounters",
    Pokemon = "src.core.game3.pokemon",
    Dex = "src.core.game3.dex",
  }
  for key, moduleName in pairs(modules) do
    if deps[key] == nil then deps[key] = require(moduleName) end
  end
  local optional = {
    Rng = "src.core.game3.rng",
    Bag = "src.core.game3.bag",
    ItemsData = "src.core.game3.items_data",
    Types = "src.core.game3.battle.types",
  }
  for key, moduleName in pairs(optional) do
    if deps[key] == nil then
      local ok, module = pcall(require, moduleName)
      if ok then deps[key] = module end
    end
  end
  return deps
end

local function storeOf(deps)
  if deps.getStore then return deps.getStore() end
  -- Mods run with a capability-scoped package table.  Resolve the live engine
  -- module through require so we do not read the sandbox's stale shadow copy.
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

local function flagOn(deps, id)
  local store = storeOf(deps)
  return store ~= nil and deps.Flags.getFlag(store, nil, id) == true
end

local function playSelect()
  pcall(function() require("src.core.game3.audio").playSe(5) end)
end

function Qol.ensureRunningShoes(deps)
  deps = deps or Qol._deps
  if not deps then return false end
  local store = storeOf(deps)
  if not store then return false end
  if deps.Flags.getFlag(store, nil, Qol.FLAG.RUNNING_SHOES) ~= true then
    deps.Flags.setFlag(store, nil, Qol.FLAG.RUNNING_SHOES, true)
  end
  return true
end

function Qol.dexAllEnabled(deps)
  return flagOn(deps or Qol._deps, Qol.FLAG.DEX_ALL)
end

function Qol.teamPreviewEnabled(deps)
  return flagOn(deps or Qol._deps, Qol.FLAG.TEAM_PREVIEW)
end

function Qol.ezCatchEnabled(deps)
  return flagOn(deps or Qol._deps, Qol.FLAG.EZ_CATCH)
end

local function speciesOf(mon)
  return tonumber(mon and (mon.species or mon.speciesId or mon.id))
end

local function dexNavState(session)
  if type(session) ~= "table" then
    return { schema = DEXNAV_SCHEMA, searchLevels = {}, chain = 0 }
  end
  if type(session.modData) ~= "table" then session.modData = {} end
  local root = session.modData[DEXNAV_SAVE_ROOT]
  if type(root) ~= "table" then
    root = {}
    session.modData[DEXNAV_SAVE_ROOT] = root
  end
  local state = root.dexNav
  if type(state) ~= "table" then
    state = {}
    root.dexNav = state
  end
  state.schema = DEXNAV_SCHEMA
  if type(state.searchLevels) ~= "table" then state.searchLevels = {} end
  state.chain = math.max(0, math.min(100, math.floor(tonumber(state.chain) or 0)))
  return state
end

function Qol.ensureDexNavState(session)
  return dexNavState(session)
end

local function searchKey(deps, species)
  local key = tonumber(species)
  if deps and deps.Pokemon and type(deps.Pokemon.national) == "function" then
    local ok, national = pcall(deps.Pokemon.national, key)
    if ok and tonumber(national) then key = tonumber(national) end
  end
  return tostring(math.floor(key or 0))
end

local function searchLevel(deps, state, species)
  local key = searchKey(deps, species)
  return math.max(0, math.min(255,
    math.floor(tonumber(state.searchLevels[key]
      or state.searchLevels[tonumber(key)]) or 0)))
end

local function setSearchLevel(deps, state, species, value)
  local key = searchKey(deps, species)
  state.searchLevels[key] = math.max(0, math.min(255,
    math.floor(tonumber(value) or 0)))
  state.searchLevels[tonumber(key)] = nil
  return state.searchLevels[key]
end

local function resetChain(state)
  state.chain = 0
  state.chainMap = nil
  state.pendingSpecies = nil
end

local function syncChainMap(state, session)
  local map = session and session.map
  if state.chain > 0 and state.chainMap and map and state.chainMap ~= map then
    resetChain(state)
  end
end

local function rodForSlot(index)
  for _, rod in ipairs(RODS) do
    if index <= rod.last then return rod.item, rod.label end
  end
  return RODS[#RODS].item, RODS[#RODS].label
end

local function caught(deps, session, species)
  local dex = (session and session.dex) or {}
  return deps.Dex.isCaught and deps.Dex.isCaught(dex, species) == true
    or (dex.caught and dex.caught[species] == true)
    or (dex.owned and dex.owned[species] == true)
end

local function safePokemonName(deps, species, fallback)
  local ok, name = pcall(deps.Pokemon.name, species)
  return ok and name or (fallback or "?????")
end

local function hiddenAbility(deps, species)
  if deps.Pokemon.abilities then pcall(deps.Pokemon.abilities, species) end
  local row = deps.Pokemon._abilities and deps.Pokemon._abilities[species]
  return tonumber(row and (row.hidden or row[3])) or 0
end

local function itemNames(deps, species)
  local meta = deps.Pokemon.speciesMeta and deps.Pokemon.speciesMeta(species)
  if not meta then return {} end
  local out, seen = {}, {}
  for _, id in ipairs({ tonumber(meta.itemCommon) or 0, tonumber(meta.itemRare) or 0 }) do
    if id > 0 and not seen[id] then
      seen[id] = true
      local name = tostring(id)
      if deps.ItemsData and deps.ItemsData.displayName then
        local ok, display = pcall(deps.ItemsData.displayName, id)
        if ok and display then name = display end
      end
      out[#out + 1] = name
    end
  end
  return out
end

local function buildDexRows(deps, session)
  local entry = session and deps.Encounters.tableFor(session.map)
  local order, bySpecies = {}, {}
  for _, method in ipairs(METHODS) do
    local area = entry and entry[method.key]
    for slotIndex, slot in ipairs((area and (area.slots or area.mons)) or {}) do
      local species = tonumber(slot.species or slot.speciesId or slot[1])
      if species and species > 0 then
        local key = method.area .. ":" .. tostring(species)
        local row = bySpecies[key]
        if not row then
          row = {
            species = species,
            area = method.area,
            minLevel = tonumber(slot.minLevel or slot.level or slot[2]) or 1,
            maxLevel = tonumber(slot.maxLevel or slot.level or slot[2]) or 1,
            methods = {}, methodSet = {}, scanSlots = {},
          }
          bySpecies[key] = row
          order[#order + 1] = row
        end
        local methodLabel, requiredItem = method.label, nil
        if method.key == "fishing" then
          requiredItem, methodLabel = rodForSlot(slotIndex)
        end
        row.scanSlots[#row.scanSlots + 1] = {
          method = method.key,
          label = methodLabel,
          requiredItem = requiredItem,
          minLevel = tonumber(slot.minLevel or slot.level or slot[2]) or 1,
          maxLevel = tonumber(slot.maxLevel or slot.level or slot[2]) or 1,
        }
        row.minLevel = math.min(row.minLevel,
          tonumber(slot.minLevel or slot.level or slot[2]) or row.minLevel)
        row.maxLevel = math.max(row.maxLevel,
          tonumber(slot.maxLevel or slot.level or slot[2]) or row.maxLevel)
        if not row.methodSet[methodLabel] then
          row.methodSet[methodLabel] = true
          row.methods[#row.methods + 1] = methodLabel
        end
      end
    end
  end
  local all = Qol.dexAllEnabled(deps)
  local dex = (session and session.dex) or {}
  local state = dexNavState(session)
  syncChainMap(state, session)
  for _, row in ipairs(order) do
    row.revealed = all or deps.Dex.isSeen(dex, row.species) == true
    row.caught = caught(deps, session, row.species)
    row.searchLevel = searchLevel(deps, state, row.species)
    if row.revealed then
      row.name = safePokemonName(deps, row.species)
      local types = deps.Pokemon.types and deps.Pokemon.types(row.species) or { 0, 0 }
      row.types = { tonumber(types[1]) or 0, tonumber(types[2]) or tonumber(types[1]) or 0 }
      if row.caught then
        row.hiddenAbility = hiddenAbility(deps, row.species)
        if row.hiddenAbility > 0 and deps.Pokemon.abilityName then
          local ok, name = pcall(deps.Pokemon.abilityName, row.hiddenAbility)
          row.hiddenAbilityName = ok and name or "-------"
        end
        row.itemNames = itemNames(deps, row.species)
      end
    else
      row.name = "??????????"
    end
    row.method = table.concat(row.methods, "/")
    row.methodSet = nil
  end
  return order
end

function Qol.buildDexRows(deps, session)
  deps = deps or Qol._deps
  return buildDexRows(deps, session or (deps and sessionOf(deps)))
end

local function randomBelow(deps, limit)
  limit = math.max(1, math.floor(tonumber(limit) or 1))
  if type(deps.random) == "function" then
    local ok, value = pcall(deps.random, limit)
    if ok and tonumber(value) then return math.floor(tonumber(value)) % limit end
  end
  if deps.Rng and type(deps.Rng.Random) == "function" then
    local ok, value = pcall(deps.Rng.Random)
    if ok and tonumber(value) then return math.floor(tonumber(value)) % limit end
  end
  return math.random(0, limit - 1)
end

local function tierChance(level, values)
  if level < 5 then return values[1] end
  if level < 10 then return values[2] end
  if level < 25 then return values[3] end
  if level < 50 then return values[4] end
  if level < 100 then return values[5] end
  return values[6]
end

local EGG_MOVE_CHANCE = { 0, 21, 46, 58, 63, 83 }
local HIDDEN_ABILITY_CHANCE = { 0, 0, 5, 15, 20, 23 }
local POTENTIAL = {
  { 0, 0, 0 }, { 14, 1, 0 }, { 17, 9, 1 },
  { 17, 16, 7 }, { 15, 17, 6 }, { 8, 24, 12 },
}

local function potentialFor(deps, level)
  local chances
  if level < 5 then chances = POTENTIAL[1]
  elseif level < 10 then chances = POTENTIAL[2]
  elseif level < 25 then chances = POTENTIAL[3]
  elseif level < 50 then chances = POTENTIAL[4]
  elseif level < 100 then chances = POTENTIAL[5]
  else chances = POTENTIAL[6] end
  local roll = randomBelow(deps, 100)
  if roll < chances[1] then return 1 end
  if roll < chances[1] + chances[2] then return 2 end
  if roll < chances[1] + chances[2] + chances[3] then return 3 end
  return 0
end

local function normalAbility(deps, species, roll)
  local list = deps.Pokemon.abilities and deps.Pokemon.abilities(species) or { 0, 0 }
  local first, second = tonumber(list[1]) or 0, tonumber(list[2]) or 0
  if second > 0 and roll % 2 == 1 then return second end
  return first > 0 and first or nil
end

local function abilityFor(deps, session, species, level)
  local roll = randomBelow(deps, 100)
  local hidden = hiddenAbility(deps, species)
  if hidden > 0 and caught(deps, session, species)
      and roll < tierChance(level, HIDDEN_ABILITY_CHANCE) then
    return hidden, true
  end
  return normalAbility(deps, species, roll), false
end

local function heldItemFor(deps, species, level)
  local meta = deps.Pokemon.speciesMeta and deps.Pokemon.speciesMeta(species)
  if not meta then return 0 end
  local common = tonumber(meta.itemCommon) or 0
  local rare = tonumber(meta.itemRare) or 0
  if common > 0 and common == rare then return common end
  local bonus = math.floor(level / 16)
  local noItem = math.max(0, 45 - bonus)
  local rareAt = math.max(0, 95 - bonus)
  local roll = randomBelow(deps, 100)
  if roll < noItem then return 0 end
  if roll < rareAt then return common end
  return rare
end

local function ivsFor(deps, potential)
  local ivs = {}
  for _, key in ipairs(IV_KEYS) do ivs[key] = randomBelow(deps, 32) end
  local available = { 1, 2, 3, 4, 5, 6 }
  for _ = 1, math.min(3, tonumber(potential) or 0) do
    local pick = randomBelow(deps, #available) + 1
    ivs[IV_KEYS[table.remove(available, pick)]] = 31
  end
  return ivs
end

local function levelFor(deps, slot, chain)
  local lo = tonumber(slot.minLevel) or 1
  local hi = tonumber(slot.maxLevel) or lo
  if hi < lo then lo, hi = hi, lo end
  -- CFRU's GetEncounterLevel uses max-min (not max-min+1).
  local level = lo + ((hi > lo) and randomBelow(deps, hi - lo) or 0)
  level = level + math.floor((tonumber(chain) or 0) / 5)
  if randomBelow(deps, 100) < 4 then level = level + 10 end
  return math.max(1, math.min(100, level))
end

local function movesFor(deps, species, level, search)
  local moves = {}
  if deps.Pokemon.movesAtLevel then
    local ok, list = pcall(deps.Pokemon.movesAtLevel, species, level)
    if ok and type(list) == "table" then
      for i = 1, math.min(4, #list) do moves[i] = list[i] end
    end
  end
  if #moves == 0 then return nil, "This species has no usable moves." end
  if randomBelow(deps, 100) < tierChance(search, EGG_MOVE_CHANCE)
      and deps.Pokemon.eggMoves then
    local ok, eggs = pcall(deps.Pokemon.eggMoves, species)
    if ok and type(eggs) == "table" and #eggs > 0 then
      moves[1] = eggs[randomBelow(deps, #eggs) + 1]
    end
  end
  return moves
end

local function randomPersonality(deps)
  if deps.Rng and type(deps.Rng.Random32) == "function" then
    local ok, value = pcall(deps.Rng.Random32)
    if ok and tonumber(value) then return tonumber(value) % 4294967296 end
  end
  return randomBelow(deps, 65536) * 65536 + randomBelow(deps, 65536)
end

local function shinyChecks(deps, search, chain)
  local adjusted, value = search, 0
  if adjusted > 200 then
    value = value + ((adjusted == 255) and 799 or (adjusted - 200))
    adjusted = 200
  end
  if adjusted > 100 then
    value = value + adjusted * 2 - 200
    adjusted = 100
  end
  if adjusted > 0 then value = value + adjusted * 6 end
  value = math.floor(value / 100)
  local checks = 1 + ((chain == 50 and 5) or (chain == 100 and 10) or 0)
  if randomBelow(deps, 100) < 4 then checks = checks + 4 end
  for _ = 1, checks do
    if randomBelow(deps, 10000) < value then return true end
  end
  return false
end

local function shinyPersonality(deps, session)
  local ok, bit = pcall(require, "bit")
  if not ok or not bit or not bit.bxor then return randomPersonality(deps) end
  local low = randomBelow(deps, 65536)
  local trainer = math.floor(tonumber(session and (session.trainerId
    or session.id or session.playerId)) or 0) % 65536
  local secret = math.floor(tonumber(session and (session.secretId
    or session.otSecretId)) or 0) % 65536
  local high = bit.bxor(trainer, secret, low) % 65536
  return high * 65536 + low
end

local function hasRequiredItem(deps, session, item)
  if not item then return true end
  return deps.Bag and deps.Bag.has
    and deps.Bag.has(session and session.bag, item, 1) == true
end

local function scanSlot(deps, session, row)
  local fallback
  for _, slot in ipairs(row.scanSlots or {}) do
    fallback = fallback or slot
    if hasRequiredItem(deps, session, slot.requiredItem) then return slot end
  end
  return fallback
end

function Qol.generateDexNavEncounter(deps, session, row)
  deps = deps or Qol._deps
  if not (deps and session and row and row.revealed and tonumber(row.species)) then
    return nil, "No data for this slot."
  end
  local slot = scanSlot(deps, session, row)
  if not slot then return nil, "This Pokemon cannot be searched here." end
  if slot.requiredItem and not hasRequiredItem(deps, session, slot.requiredItem) then
    local name = slot.label or "required Rod"
    return nil, "You need the " .. name .. "."
  end
  local state = dexNavState(session)
  syncChainMap(state, session)
  local search = searchLevel(deps, state, row.species)
  local level = levelFor(deps, slot, state.chain)
  local potential = potentialFor(deps, search)
  local moves, moveErr = movesFor(deps, row.species, level, search)
  if not moves then return nil, moveErr end
  local ability, hidden = abilityFor(deps, session, row.species, search)
  local personality = shinyChecks(deps, search, state.chain)
    and shinyPersonality(deps, session) or randomPersonality(deps)
  local encounter = {
    species = row.species,
    level = level,
    moves = moves,
    ivs = ivsFor(deps, potential),
    ability = ability,
    item = heldItemFor(deps, row.species, search),
    personality = personality,
    rrDexNav = true,
    dexNavSearchLevel = search,
    dexNavPotential = potential,
    dexNavHiddenAbility = hidden,
    dexNavMethod = slot.label,
  }
  return encounter
end

local function installDexNav(mod, deps)
  if Qol._dexNav then return Qol._dexNav end
  local okStack, Stack = pcall(require, "src.ui.game3.stack")
  if not okStack then return nil end

  local DexNav = {
    open = false,
    cursor = 1,
    scroll = 1,
    rows = {},
    session = nil,
    game = nil,
    mode = "browse",
    contextCursor = 1,
    status = nil,
    fieldHeld = {},
  }

  local function selectedRow()
    return DexNav.rows[DexNav.cursor]
  end

  local function adjustScroll()
    if DexNav.cursor < DexNav.scroll then DexNav.scroll = DexNav.cursor end
    if DexNav.cursor > DexNav.scroll + 5 then DexNav.scroll = DexNav.cursor - 5 end
  end

  function DexNav.show(game, session)
    if session == nil and type(game) == "table" and game.map then
      session, game = game, nil
    end
    DexNav.open = true
    DexNav.game = game
    DexNav.session = session
    DexNav.rows = buildDexRows(deps, session)
    DexNav.cursor, DexNav.scroll = 1, 1
    DexNav.mode, DexNav.contextCursor, DexNav.status = "browse", 1, nil
    Stack.push("rr_dexnav", DexNav, { hideBelow = true, fullscreen = true })
    playSelect()
  end

  function DexNav.close(silent)
    if not DexNav.open then return end
    DexNav.open = false
    DexNav.mode = "browse"
    Stack.pop("rr_dexnav")
    if not silent then playSelect() end
  end

  function DexNav.isOpen() return DexNav.open end

  function DexNav.registerSelected()
    local row = selectedRow()
    if not row or not row.revealed then
      DexNav.status = "No data for this slot."
      return false
    end
    local slot = scanSlot(deps, DexNav.session, row)
    if slot and slot.requiredItem
        and not hasRequiredItem(deps, DexNav.session, slot.requiredItem) then
      DexNav.status = "You need the " .. tostring(slot.label) .. "."
      return false
    end
    local state = dexNavState(DexNav.session)
    state.registeredSpecies = row.species
    state.registeredArea = row.area
    state.registeredMethod = slot and slot.label or row.method
    DexNav.status = row.name .. " was registered."
    DexNav.mode = "browse"
    playSelect()
    return true
  end

  function DexNav.generateSelected()
    return Qol.generateDexNavEncounter(deps, DexNav.session, selectedRow())
  end

  local function beginWild(encounter, done)
    if type(deps.startWildBattle) == "function" then
      return deps.startWildBattle(DexNav.game, encounter, done)
    end
    local ok, BattleBridge = pcall(require, "src.core.game3.battle_bridge")
    if not ok then return nil, "battle system unavailable" end
    return BattleBridge.startWild(mod, DexNav.game, encounter, { done = done })
  end

  function DexNav.scanSelected()
    local row = selectedRow()
    local encounter, err = DexNav.generateSelected()
    if not encounter then
      DexNav.status = err
      DexNav.mode = "browse"
      return false, err
    end
    local state = dexNavState(DexNav.session)
    state.pendingSpecies = row.species
    state.chainMap = DexNav.session and DexNav.session.map
    local function finished(result)
      state.pendingSpecies = nil
      if result == "win" or result == "won" or result == "caught"
          or result == "catch" then
        state.chain = state.chain >= 100 and 1 or (state.chain + 1)
        state.chainMap = DexNav.session and DexNav.session.map
      else
        resetChain(state)
      end
    end
    local started, startErr = beginWild(encounter, finished)
    if not started then
      state.pendingSpecies = nil
      DexNav.status = "Search failed: " .. tostring(startErr or "battle unavailable")
      DexNav.mode = "browse"
      return false, startErr
    end
    setSearchLevel(deps, state, row.species,
      searchLevel(deps, state, row.species) + 1)
    state.lastSpecies = row.species
    DexNav.lastEncounter = encounter
    DexNav.close(true)
    local okStart, StartMenu = pcall(require, "src.ui.game3.start_menu")
    if okStart and StartMenu.isOpen and StartMenu.isOpen() then
      StartMenu.close(true)
    end
    return true, encounter
  end

  -- CFRU's registered species can be searched directly with R from the
  -- overworld.  Android layouts without a shoulder button can still use the
  -- Start-menu DexNav and SELECT fallback; do not steal SELECT from FireRed's
  -- registered-key-item action in the field.
  function DexNav.quickScan(game, session)
    session = session or sessionOf(deps)
    local state = dexNavState(session)
    local species = tonumber(state.registeredSpecies)
    if not species then return false end
    DexNav.show(game, session)
    for index, row in ipairs(DexNav.rows) do
      if row.species == species and row.area == state.registeredArea then
        DexNav.cursor = index
        adjustScroll()
        local started = DexNav.scanSelected()
        if not started then DexNav.open = true end
        return true
      end
    end
    DexNav.status = "The registered Pokemon is not in this area."
    return true
  end

  function DexNav.handleFieldInput(game)
    if not game or not game.input or not game.input.wasPressed then return false end
    local input = game.input
    local function queued(key)
      for _, value in ipairs(input.pressQueue or {}) do
        if value == key then return true end
      end
      return false
    end
    local function edge(key)
      -- core.update surrounds the fixed-step loop. Looking only at
      -- wasPressed can lose a tap when turbo/catch-up executes several input
      -- steps in one rendered frame, so include the unconsumed queue and a
      -- held-button edge while suppressing repeats across zero-step frames.
      local active = queued(key) or input:wasPressed(key)
      if input.isDown then active = input:isDown(key) or active end
      local previous = DexNav.fieldHeld[key] == true
      DexNav.fieldHeld[key] = active and true or false
      return active and not previous
    end
    local rPressed = edge("r")
    local selectPressed = edge("select")
    if game.phase ~= "field" or Stack.busy() then return false end
    local okBattle, Battle = pcall(require, "src.core.game3.battle")
    if okBattle and Battle and Battle.isActive and Battle.isActive() then
      return false
    end
    -- DexAll reveals encounter information; it does not grant the DexNav.
    -- The field shortcut only exists after the actual DexNav story unlock.
    if not flagOn(deps, Qol.FLAG.DEX_NAV) then
      return false
    end
    local session = game.session or sessionOf(deps)
    if rPressed then return DexNav.quickScan(game, session) end
    -- Android's default overlay has SELECT but no R shoulder. Preserve
    -- FireRed's registered-key-item binding whenever one exists; otherwise
    -- SELECT is the field shortcut for the registered DexNav species.
    if selectPressed and session and session.registeredItem == nil then
      return DexNav.quickScan(game, session)
    end
    return false
  end

  function DexNav.handleInput(input)
    if not DexNav.open or not input then return false end
    if DexNav.mode == "context" then
      if input:wasPressed("up") then
        DexNav.contextCursor = ((DexNav.contextCursor + 1) % 3) + 1
        playSelect()
      elseif input:wasPressed("down") then
        DexNav.contextCursor = (DexNav.contextCursor % 3) + 1
        playSelect()
      elseif input:wasPressed("b") then
        DexNav.mode, DexNav.status = "browse", nil
        playSelect()
      elseif input:wasPressed("a") then
        if DexNav.contextCursor == 1 then
          DexNav.registerSelected()
        elseif DexNav.contextCursor == 2 then
          DexNav.scanSelected()
        else
          DexNav.mode, DexNav.status = "browse", nil
          playSelect()
        end
      end
      return true
    end
    local n = #DexNav.rows
    local old = DexNav.cursor
    if input:wasPressed("up") and n > 0 then
      DexNav.cursor = ((DexNav.cursor - 2) % n) + 1
    elseif input:wasPressed("down") and n > 0 then
      DexNav.cursor = (DexNav.cursor % n) + 1
    elseif input:wasPressed("left") and n > 0 then
      DexNav.cursor = ((DexNav.cursor - 8) % n) + 1
    elseif input:wasPressed("right") and n > 0 then
      DexNav.cursor = ((DexNav.cursor + 6) % n) + 1
    elseif input:wasPressed("a") and n > 0 then
      local row = selectedRow()
      if row and row.revealed then
        DexNav.mode, DexNav.contextCursor = "context", 1
        DexNav.status = row.name .. " selected."
        playSelect()
      else
        DexNav.status = "No data for this slot."
      end
      return true
    elseif (input:wasPressed("r") or input:wasPressed("select")) and n > 0 then
      DexNav.registerSelected()
      return true
    elseif input:wasPressed("b") or input:wasPressed("start") then
      DexNav.close()
      return true
    else
      return true
    end
    if DexNav.cursor ~= old then
      adjustScroll()
      DexNav.status = nil
      playSelect()
    end
    return true
  end

  function DexNav.draw()
    if not DexNav.open or not (love and love.graphics) then return end
    local g = love.graphics
    local okFont, FrlgFont = pcall(require, "src.ui.game3.frlg_font")
    g.setColor(0.94, 0.95, 0.86, 1)
    g.rectangle("fill", 0, 0, 240, 160)
    g.setColor(0.10, 0.34, 0.58, 1)
    g.rectangle("fill", 0, 0, 240, 20)
    g.setColor(1, 1, 1, 1)
    local function text(value, x, y, color)
      if okFont and FrlgFont and FrlgFont.draw then
        FrlgFont.draw(tostring(value), x, y, {
          small = true,
          colors = color or FrlgFont.COLOR.NORMAL,
        })
      else
        g.setColor(0.08, 0.08, 0.1, 1)
        g.print(tostring(value), x, y)
      end
    end
    text("DEXNAV  " .. tostring((DexNav.session and DexNav.session.map) or "AREA"), 6, 4)
    if #DexNav.rows == 0 then
      text("No wild Pokemon in this area.", 16, 64)
    else
      for visible = 0, 5 do
        local index = DexNav.scroll + visible
        local row = DexNav.rows[index]
        if not row then break end
        local y = 25 + visible * 17
        if index == DexNav.cursor then
          g.setColor(0.72, 0.84, 0.94, 1)
          g.rectangle("fill", 3, y - 2, 116, 16)
        end
        local state = dexNavState(DexNav.session)
        local registered = tonumber(state.registeredSpecies) == row.species
          and state.registeredArea == row.area
        text(index == DexNav.cursor and ">" or (registered and "R" or " "), 6, y)
        local label = row.name
        if #label > 10 then label = label:sub(1, 10) end
        text(label, 17, y)
        if row.revealed then
          text(("%d-%d"):format(row.minLevel, row.maxLevel), 83, y)
        end
      end
      local row = selectedRow()
      if row then
        g.setColor(0.82, 0.86, 0.92, 1)
        g.rectangle("fill", 122, 22, 116, 116)
        if row.revealed then
          local type1, type2 = "?", "?"
          if deps.Types and deps.Types.name and row.types then
            local ok1, one = pcall(deps.Types.name, row.types[1])
            local ok2, two = pcall(deps.Types.name, row.types[2])
            if ok1 then type1 = one end
            if ok2 then type2 = two end
          end
          text(row.name, 127, 26)
          text("SEARCH LV. " .. tostring(row.searchLevel or 0), 127, 42)
          text("CHAIN " .. tostring(dexNavState(DexNav.session).chain or 0), 127, 56)
          text("TYPE " .. tostring(type1)
            .. ((type2 ~= type1) and ("/" .. tostring(type2)) or ""), 127, 70)
          text(row.method, 127, 84)
          if row.caught then
            text("HA " .. tostring(row.hiddenAbilityName or "-------"), 127, 98)
            local items = row.itemNames or {}
            text("ITEM " .. tostring(items[1] or "None"), 127, 112)
            if items[2] then text(tostring(items[2]), 127, 126) end
          else
            text("Capture to see HA/items", 127, 104)
          end
        else
          text("No info", 157, 72)
        end
      end
    end
    local footer = DexNav.status
      or (Qol.dexAllEnabled(deps) and "DexAll active  A: Menu  B: Back"
        or "A: Menu  SELECT/R: Register  B: Back")
    text(footer, 7, 145)
    if DexNav.mode == "context" then
      g.setColor(0.96, 0.96, 0.91, 1)
      g.rectangle("fill", 157, 63, 75, 59)
      g.setColor(0.12, 0.20, 0.30, 1)
      g.rectangle("line", 157, 63, 75, 59)
      local options = { "Register", "Scan", "Cancel" }
      for i, option in ipairs(options) do
        text((DexNav.contextCursor == i and ">" or " ") .. option,
          162, 68 + (i - 1) * 17)
      end
    end
    g.setColor(1, 1, 1, 1)
  end

  Qol._dexNav = DexNav
  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local base = next(game, items)
    if type(base) ~= "table" then base = items end
    local out, inserted, already = {}, false, false
    -- DexAll is disclosure-only. Do not make the Start-menu DexNav appear
    -- before the cartridge's real DexNav unlock flag is earned.
    local unlocked = flagOn(deps, Qol.FLAG.DEX_NAV)
    if not unlocked then return base or {} end
    for _, item in ipairs(base or {}) do
      if item.id == "rr_dexnav" then already = true end
    end
    for _, item in ipairs(base or {}) do
      out[#out + 1] = item
      if not already and not inserted and item.id == "pokedex" then
        out[#out + 1] = {
          id = "rr_dexnav",
          label = "DEXNAV",
          onSelect = function(game, session) DexNav.show(game, session) end,
        }
        inserted = true
      end
    end
    return out
  end, 900)

  mod.events:on("map.entered", function()
    local session = sessionOf(deps)
    if not session then return end
    local state = dexNavState(session)
    syncChainMap(state, session)
  end)
  mod.events:on("battle.ended", function()
    local session = sessionOf(deps)
    if not session then return end
    local state = dexNavState(session)
    if not state.pendingSpecies then resetChain(state) end
  end)
  return DexNav
end


local SKILL_SCHEMA = 1
local SKILL_ITEM_KEYS = {
  timeChanger = "TIMECHANGER",
  infiniteRepel = "INFINITEREPEL",
  pokeVial = "POKEVIAL",
}
local TIME_CHOICES = {
  { key = "current", label = "CURRENT TIME", hour = nil },
  { key = "day", label = "DAY", hour = 12 },
  { key = "dusk", label = "DUSK", hour = 18 },
  { key = "night", label = "NIGHT", hour = 22 },
}

local function skillState(session)
  if type(session) ~= "table" then
    return {
      schema = SKILL_SCHEMA, unlocked = { autoRun = true },
      autoRun = false, infiniteRepel = false, timeMode = "current",
      vialCharges = 0,
    }
  end
  if type(session.modData) ~= "table" then session.modData = {} end
  local root = session.modData[DEXNAV_SAVE_ROOT]
  if type(root) ~= "table" then
    root = {}
    session.modData[DEXNAV_SAVE_ROOT] = root
  end
  if type(root.skills) ~= "table" then root.skills = {} end
  local state = root.skills
  state.schema = SKILL_SCHEMA
  if type(state.unlocked) ~= "table" then state.unlocked = {} end
  state.unlocked.autoRun = true
  state.autoRun = state.autoRun == true
  state.infiniteRepel = state.infiniteRepel == true
  if state.timeMode ~= "day" and state.timeMode ~= "dusk"
      and state.timeMode ~= "night" then
    state.timeMode = "current"
  end
  if state.vialCharges ~= nil then
    state.vialCharges = math.max(0, math.min(6,
      math.floor(tonumber(state.vialCharges) or 0)))
  end
  return state
end

local function normalizedItemName(value)
  local s = tostring(value or "")
  s = s:gsub("é", "e"):gsub("É", "E")
  return s:upper():gsub("[^A-Z0-9]", "")
end

local function discoverSkillItems(deps)
  if Qol._skillItems then return Qol._skillItems end
  local found = {}
  if not (deps.ItemsData and deps.ItemsData.ensureLoaded) then
    Qol._skillItems = found
    return found
  end
  local ok, items = pcall(deps.ItemsData.ensureLoaded)
  if ok and type(items) == "table" then
    for id, row in pairs(items) do
      local normalized = normalizedItemName(type(row) == "table" and row.name or nil)
      for key, wanted in pairs(SKILL_ITEM_KEYS) do
        if normalized == wanted then found[key] = tonumber(id) or id end
      end
    end
  end
  Qol._skillItems = found
  return found
end

local function refreshSkillUnlocks(deps, session)
  local state = skillState(session)
  local items = discoverSkillItems(deps)
  local bag = session and session.bag
  for key, id in pairs(items) do
    if id ~= nil and bag and deps.Bag and deps.Bag.has
        and deps.Bag.has(bag, id, 1) then
      local first = state.unlocked[key] ~= true
      state.unlocked[key] = true
      if key == "pokeVial" and (first or state.vialCharges == nil) then
        state.vialCharges = 6
      end
    end
  end
  if state.vialCharges == nil then state.vialCharges = 0 end
  return state
end

local function applySkillTime(deps, state)
  if not (deps.RR_Encounters and deps.RR_Encounters.setOverrideHour) then return end
  local hour
  for _, row in ipairs(TIME_CHOICES) do
    if row.key == state.timeMode then hour = row.hour break end
  end
  deps.RR_Encounters.setOverrideHour(hour)
end

local function installSkills(mod, deps)
  if Qol._skills then return Qol._skills end
  local okStack, Stack = pcall(require, "src.ui.game3.stack")
  if not okStack then return nil end

  local Skills = {
    open = false,
    cursor = 1,
    mode = "main",
    timeCursor = 1,
    game = nil,
    session = nil,
    status = nil,
    fieldHeld = false,
    usingVial = false,
  }

  local function state()
    local session = Skills.session or sessionOf(deps)
    return refreshSkillUnlocks(deps, session), session
  end

  local function timeIndex(key)
    for i, row in ipairs(TIME_CHOICES) do
      if row.key == key then return i end
    end
    return 1
  end

  local function skillRows(st)
    return {
      { key = "autoRun", label = "AUTO RUN", unlocked = true },
      { key = "timeChanger", label = "TIME CHANGER",
        unlocked = st.unlocked.timeChanger == true },
      { key = "infiniteRepel", label = "INFINITE REPEL",
        unlocked = st.unlocked.infiniteRepel == true },
      { key = "pokeVial", label = "POKEVIAL",
        unlocked = st.unlocked.pokeVial == true },
    }
  end

  function Skills.itemIds()
    local ids = discoverSkillItems(deps)
    return {
      timeChanger = ids.timeChanger,
      infiniteRepel = ids.infiniteRepel,
      pokeVial = ids.pokeVial,
    }
  end

  function Skills.show(game, session)
    if Skills.open then return true end
    Skills.game = game
    Skills.session = session or (game and game.session) or sessionOf(deps)
    local st = refreshSkillUnlocks(deps, Skills.session)
    applySkillTime(deps, st)
    Skills.cursor = math.max(1, math.min(4, Skills.cursor or 1))
    Skills.mode = "main"
    Skills.timeCursor = timeIndex(st.timeMode)
    Skills.status = nil
    Skills.open = true
    Stack.push("rr_skills", Skills, { hideBelow = true, fullscreen = true })
    playSelect()
    return true
  end

  function Skills.close(silent)
    if not Skills.open then return end
    Skills.open = false
    Skills.mode = "main"
    Stack.pop("rr_skills")
    if not silent then playSelect() end
  end

  function Skills.isOpen() return Skills.open end

  local function partyNeedsVial(session)
    for _, mon in ipairs((session and session.party) or {}) do
      if type(mon) == "table" then
        if mon.maxHp and (tonumber(mon.hp) or 0) < tonumber(mon.maxHp) then
          return true
        end
        if mon.status ~= nil or mon.sleep ~= nil then return true end
        if type(mon.pp) == "table" and type(mon.moves) == "table" then
          for i = 1, 4 do
            if mon.moves[i] then
              local cur = tonumber(mon.pp[i]) or 0
              local mx = tonumber(mon.maxPp and mon.maxPp[i])
              if mx and cur < mx then return true end
            end
          end
        end
      end
    end
    return false
  end

  function Skills.useVial()
    local st, session = state()
    if not st.unlocked.pokeVial then
      Skills.status = "POKEVIAL is still locked."
      return false
    end
    if (tonumber(st.vialCharges) or 0) <= 0 then
      Skills.status = "POKEVIAL is empty. Heal to refill it."
      return false
    end
    if not partyNeedsVial(session) then
      Skills.status = "Your party is already healthy."
      return false
    end
    local Party = require("src.core.game3.party")
    Skills.usingVial = true
    local ok, err = pcall(Party.healAll, session.party)
    Skills.usingVial = false
    if not ok then
      Skills.status = "POKEVIAL failed: " .. tostring(err)
      return false
    end
    st.vialCharges = st.vialCharges - 1
    Skills.status = ("Party restored. %d/6 uses remain."):format(st.vialCharges)
    playSelect()
    return true
  end

  local function activateMain()
    local st = state()
    local row = skillRows(st)[Skills.cursor]
    if not row or not row.unlocked then
      Skills.status = "That skill has not been unlocked yet."
      playSelect()
      return
    end
    if row.key == "autoRun" then
      st.autoRun = not st.autoRun
      Skills.status = "Auto Run " .. (st.autoRun and "ON" or "OFF")
      playSelect()
    elseif row.key == "timeChanger" then
      Skills.mode = "time"
      Skills.timeCursor = timeIndex(st.timeMode)
      Skills.status = nil
      playSelect()
    elseif row.key == "infiniteRepel" then
      st.infiniteRepel = not st.infiniteRepel
      Skills.status = "Infinite Repel " .. (st.infiniteRepel and "ON" or "OFF")
      playSelect()
    elseif row.key == "pokeVial" then
      Skills.useVial()
    end
  end

  function Skills.handleInput(input)
    if not Skills.open or not input then return false end
    if Skills.mode == "time" then
      if input:wasPressed("up") then
        Skills.timeCursor = ((Skills.timeCursor - 2) % #TIME_CHOICES) + 1
        playSelect()
      elseif input:wasPressed("down") then
        Skills.timeCursor = (Skills.timeCursor % #TIME_CHOICES) + 1
        playSelect()
      elseif input:wasPressed("a") then
        local st = state()
        local row = TIME_CHOICES[Skills.timeCursor]
        st.timeMode = row.key
        applySkillTime(deps, st)
        Skills.mode = "main"
        Skills.status = "Time set to " .. row.label .. "."
        playSelect()
      elseif input:wasPressed("b") then
        Skills.mode = "main"
        Skills.status = nil
        playSelect()
      end
      return true
    end
    if input:wasPressed("up") then
      Skills.cursor = ((Skills.cursor - 2) % 4) + 1
      Skills.status = nil
      playSelect()
    elseif input:wasPressed("down") then
      Skills.cursor = (Skills.cursor % 4) + 1
      Skills.status = nil
      playSelect()
    elseif input:wasPressed("a") then
      activateMain()
    elseif input:wasPressed("b") or input:wasPressed("start") then
      Skills.close()
    end
    return true
  end

  function Skills.handleFieldInput(game)
    if not game or not game.input or not game.input.wasPressed then return false end
    local input = game.input
    local queued = false
    for _, value in ipairs(input.pressQueue or {}) do
      if value == "l" then queued = true break end
    end
    local active = queued or input:wasPressed("l")
    if input.isDown then active = input:isDown("l") or active end
    local pressed = active and not Skills.fieldHeld
    Skills.fieldHeld = active and true or false
    if not pressed or game.phase ~= "field" or Stack.busy() then return false end
    local okBattle, Battle = pcall(require, "src.core.game3.battle")
    if okBattle and Battle and Battle.isActive and Battle.isActive() then return false end
    local Field = package.loaded["src.core.game3.field"]
    if Field and Field.locked then return false end
    local Space = package.loaded["src.core.game3.scripting.space"]
    if Space and Space.vm and Space.vm.isRunning and Space.vm:isRunning() then
      return false
    end
    return Skills.show(game, game.session or sessionOf(deps))
  end

  local function drawText(value, x, y, color)
    local okFont, FrlgFont = pcall(require, "src.ui.game3.frlg_font")
    if okFont and FrlgFont and FrlgFont.draw then
      FrlgFont.draw(tostring(value), x, y, {
        small = true, colors = color or FrlgFont.COLOR.NORMAL,
      })
    elseif love and love.graphics then
      love.graphics.setColor(0.08, 0.08, 0.1, 1)
      love.graphics.print(tostring(value), x, y)
    end
  end

  function Skills.draw()
    if not Skills.open or not (love and love.graphics) then return end
    local g = love.graphics
    local st = state()
    g.setColor(0.94, 0.95, 0.86, 1)
    g.rectangle("fill", 0, 0, 240, 160)
    g.setColor(0.10, 0.34, 0.58, 1)
    g.rectangle("fill", 0, 0, 240, 20)
    g.setColor(1, 1, 1, 1)
    drawText("SKILLS", 96, 4)

    if Skills.mode == "time" then
      drawText("TIME CHANGER", 72, 28)
      for i, row in ipairs(TIME_CHOICES) do
        local y = 49 + (i - 1) * 20
        if i == Skills.timeCursor then
          g.setColor(0.72, 0.84, 0.94, 1)
          g.rectangle("fill", 46, y - 2, 148, 16)
          g.setColor(1, 1, 1, 1)
        end
        drawText((i == Skills.timeCursor and "> " or "  ") .. row.label, 54, y)
      end
      drawText("A: SET   B: BACK", 68, 139)
      return
    end

    local rows = skillRows(st)
    for i, row in ipairs(rows) do
      local y = 34 + (i - 1) * 24
      if i == Skills.cursor then
        g.setColor(0.72, 0.84, 0.94, 1)
        g.rectangle("fill", 12, y - 3, 216, 19)
        g.setColor(1, 1, 1, 1)
      end
      local suffix
      if not row.unlocked then
        suffix = "LOCKED"
      elseif row.key == "autoRun" then
        suffix = st.autoRun and "ON" or "OFF"
      elseif row.key == "timeChanger" then
        suffix = tostring(st.timeMode):upper()
      elseif row.key == "infiniteRepel" then
        suffix = st.infiniteRepel and "ON" or "OFF"
      else
        suffix = ("%d/6"):format(tonumber(st.vialCharges) or 0)
      end
      drawText((i == Skills.cursor and "> " or "  ") .. row.label, 20, y)
      drawText(suffix, 166, y)
    end
    drawText(Skills.status or "A: USE/TOGGLE   B: BACK", 18, 139)
    g.setColor(1, 1, 1, 1)
  end

  -- Auto Run mirrors Radical Red's convenience toggle without changing the
  -- running-shoes flag itself.  When enabled, B temporarily means WALK.
  local okPlayer, Player = pcall(require, "src.core.game3.player")
  if okPlayer and Player and not Player.__rrAutoRunInstalled then
    Player.__rrAutoRunInstalled = true
    local originalUpdate = assert(Player.update)
    Player.update = function(game, input)
      local session = (game and game.session) or sessionOf(deps)
      local st = refreshSkillUnlocks(deps, session)
      if not (st.autoRun and input and input.isDown) then
        return originalUpdate(game, input)
      end
      local proxy = setmetatable({}, {
        __index = function(_, key)
          local value = input[key]
          if type(value) ~= "function" then return value end
          if key == "isDown" then
            return function(_, button)
              if button == "b" then return not input:isDown("b") end
              return input:isDown(button)
            end
          end
          return function(_, ...) return value(input, ...) end
        end,
      })
      return originalUpdate(game, proxy)
    end
  end

  -- A PokéVial is refilled by a normal full-party heal. Guard the Vial's own
  -- heal so spending a charge cannot instantly refill itself.
  local Party = require("src.core.game3.party")
  if not Party.__rrPokeVialInstalled then
    Party.__rrPokeVialInstalled = true
    local originalHealAll = assert(Party.healAll)
    Party.healAll = function(sessionParty)
      local result = originalHealAll(sessionParty)
      if not Skills.usingVial then
        local session = sessionOf(deps)
        if session and session.party == sessionParty then
          local st = refreshSkillUnlocks(deps, session)
          if st.unlocked.pokeVial then st.vialCharges = 6 end
        end
      end
      return result
    end
  end

  mod.hooks:wrap("encounter.roll", function(next, encounterTable, ctx)
    local session = sessionOf(deps)
    local st = refreshSkillUnlocks(deps, session)
    if st.unlocked.infiniteRepel and st.infiniteRepel then return nil end
    return next(encounterTable, ctx)
  end, 1000)

  for _, event in ipairs({ "save.created", "save.loaded", "map.entered", "map.reloaded" }) do
    mod.events:on(event, function()
      local session = sessionOf(deps)
      if not session then return end
      local st = refreshSkillUnlocks(deps, session)
      applySkillTime(deps, st)
    end)
  end

  Qol._skills = Skills
  return Skills
end

local function drawMonIcon(Pokemon, mon, cx, cy)
  local ok, icon = pcall(Pokemon.monIcon, mon)
  if not ok or not icon or not icon.image then return false end
  local quad = icon.quads and (icon.quads[0] or icon.quads[1])
  local w, h = tonumber(icon.w) or 32, tonumber(icon.h) or 32
  if quad then love.graphics.draw(icon.image, quad, cx, cy, 0, 1, 1, w / 2, h / 2)
  else love.graphics.draw(icon.image, cx, cy, 0, 1, 1, w / 2, h / 2) end
  return true
end

local function installTeamPreview(deps)
  local ok, Ui = pcall(require, "src.core.game3.battle.ui")
  if not ok or Ui.__rrTeamPreviewInstalled then return ok end
  Ui.__rrTeamPreviewInstalled = true
  local originalReset = Ui.reset
  local originalHandle = Ui.handleInput
  local originalDraw = Ui.draw

  local function allowed()
    local st = Ui._st
    return st ~= nil and not st.wild and not st.oldManTutorial
      and not st.pokedude and Qol.teamPreviewEnabled(deps)
  end

  local function pressed(input, names)
    for _, name in ipairs(names) do
      if input:wasPressed(name) then return true end
    end
    return false
  end

  Ui.reset = function(...)
    Ui._rrTeamPreview = false
    return originalReset(...)
  end

  Ui.handleInput = function(input)
    if Ui._rrTeamPreview then
      if input and pressed(input, { "a", "b", "l", "select", "up", "down", "left", "right" }) then
        Ui._rrTeamPreview = false
        playSelect()
      end
      return true
    end
    if input and Ui._mode == "menu" and allowed()
        and pressed(input, { "l", "select" }) then
      Ui._rrTeamPreview = true
      playSelect()
      return true
    end
    return originalHandle(input)
  end

  local function drawPreview()
    local g = love and love.graphics
    if not g then return end
    local Pokemon = deps.Pokemon
    local FrlgFont = require("src.ui.game3.frlg_font")
    local Window = require("src.ui.game3.window")
    g.setColor(0.18, 0.24, 0.36, 1)
    g.rectangle("fill", 0, 0, 240, 160)
    g.setColor(1, 1, 1, 1)
    Window.stdFrame(Window.template(5, 1, 20, 12))
    FrlgFont.draw("OPPONENT'S TEAM", 65, 8, { small = true, colors = FrlgFont.COLOR.NORMAL })
    local party = (Ui._st and (Ui._st.foeParty or Ui._st.enemyParty)) or {}
    for i = 1, math.min(6, #party) do
      local mon = party[i]
      local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
      local cx, cy = 80 + col * 40, 36 + row * 40
      drawMonIcon(Pokemon, mon, cx, cy)
      local species = speciesOf(mon)
      local okName, name = pcall(Pokemon.name, species)
      name = okName and tostring(name) or "?????"
      if #name > 10 then name = name:sub(1, 10) end
      FrlgFont.draw(name, cx - 18, cy + 15, {
        small = true, colors = FrlgFont.COLOR.NORMAL,
      })
      if (tonumber(mon and (mon.hp or mon.currentHp)) or 1) <= 0 then
        g.setColor(0.82, 0.82, 0.82, 0.45)
        g.rectangle("fill", cx - 16, cy - 16, 32, 32)
        g.setColor(1, 1, 1, 1)
      end
    end
    FrlgFont.draw("A/B/L/D-PAD: BACK", 54, 139, {
      small = true, colors = FrlgFont.COLOR.NORMAL,
    })
    g.setColor(1, 1, 1, 1)
  end

  Ui.draw = function(...)
    originalDraw(...)
    if Ui._rrTeamPreview then
      local okDraw, err = pcall(drawPreview)
      if not okDraw then
        Ui._rrTeamPreview = false
        print("[radical-red] team preview draw failed: " .. tostring(err))
      end
    elseif allowed() and Ui._mode == "menu" and love and love.graphics then
      local FrlgFont = require("src.ui.game3.frlg_font")
      FrlgFont.draw("L/SELECT: TEAM", 4, 108, {
        small = true, colors = FrlgFont.COLOR.NORMAL,
      })
    end
  end
  return true
end



local POKE_RIDER_ITEM_ID = 363 -- FireRed's Fame Checker slot, repurposed by RR.

local function installPokeRider(mod, deps)
  if Qol._pokeRiderInstalled then return true end
  if not (mod and mod.hooks and mod.hooks.wrap and deps.ItemsData) then return false end

  local function numericId(id)
    if deps.ItemsData.toNumericId then
      local ok, value = pcall(deps.ItemsData.toNumericId, id)
      if ok and tonumber(value) then return tonumber(value) end
    end
    return tonumber(id)
  end

  local function isPokeRider(id)
    if numericId(id) ~= POKE_RIDER_ITEM_ID then return false end
    if not deps.ItemsData.displayName then return false end
    local ok, display = pcall(deps.ItemsData.displayName, id)
    return ok and normalizedItemName(display) == "POKERIDER"
  end

  local function leadMon(session)
    for _, mon in ipairs((session and session.party) or {}) do
      if type(mon) == "table" and not mon.isEgg and not mon.egg
          and (tonumber(mon.hp) or 1) > 0 then
        return mon
      end
    end
    return session and session.party and session.party[1] or nil
  end

  local function openRider(game, session)
    local Field = require("src.core.game3.field")
    local RegionMap = require("src.ui.game3.region_map")
    Field.locked = true
    RegionMap.show({
      session = session,
      mode = "fly",
      onPick = function(section)
        local ok, err = pcall(Field.flyTo, section, leadMon(session))
        if not ok then
          Field.locked = false
          error(err, 0)
        end
      end,
      onClose = function()
        Field.locked = false
      end,
    })
    return true
  end

  mod.hooks:wrap("item.use",
    function(next, game, battle, id, target, list, moveIndex, picker)
      -- Never reinterpret the numeric FireRed slot on its own. The live RR
      -- item name is the disambiguator, so vanilla FireRed's real Fame Checker
      -- remains untouched when this conversion is not active.
      if battle ~= nil or not isPokeRider(id) then
        return next(game, battle, id, target, list, moveIndex, picker)
      end

      local session = (game and game.session) or sessionOf(deps)
      if not session then return next(game, battle, id, target, list, moveIndex, picker) end

      local function open()
        return openRider(game, session)
      end
      local okUse, ItemUse = pcall(require, "src.core.game3.item_use")
      if okUse and ItemUse and ItemUse.setUpOnFieldCallback
          and ItemUse.setUpOnFieldCallback(open) then
        -- Reuse the stock field-item exit choreography: Bag and Start close,
        -- the field fades back in, then runOnFieldCallback opens the Rider map.
        return true, "escape", nil
      end

      -- Registered-key-item or other direct field use: there is no Bag to
      -- dismiss, so opening the Rider map immediately is the correct path.
      open()
      return true, "poke_rider", nil
    end, 1200)

  Qol._pokeRiderInstalled = true
  return true
end

local function installFanfareRecovery()
  local okAudio, Audio = pcall(require, "src.core.game3.audio")
  if not okAudio or not Audio or Audio.__rrFanfareRecovery then return okAudio end
  Audio.__rrFanfareRecovery = true
  local originalUpdate = assert(Audio.update)
  local candidate, recoveryFrames

  local function fieldCandidate()
    local okBattle, Battle = pcall(require, "src.core.game3.battle")
    if okBattle and Battle and Battle.isActive and Battle.isActive() then return nil end
    local cur = Audio.currentSong and Audio.currentSong()
    return cur and cur.id or Audio._mapSong
  end

  local function sourceSilent()
    if Audio._bgmPaused then return true end
    local src = Audio._bgmSource
    if src and src.isPlaying then
      local ok, playing = pcall(src.isPlaying, src)
      if ok then return not playing end
    end
    return Audio._bgmGen ~= nil and src == nil
  end

  Audio.update = function(dt)
    local wasFanfare = Audio._fanfareActive == true
    if wasFanfare and not candidate then candidate = fieldCandidate() end
    local result = originalUpdate(dt)
    if wasFanfare and not Audio._fanfareActive and candidate then
      recoveryFrames = 3
    end
    if recoveryFrames then
      if Audio._fanfareActive then
        recoveryFrames = nil
      else
        recoveryFrames = recoveryFrames - 1
        if recoveryFrames <= 0 then
          local cur = Audio.currentSong and Audio.currentSong()
          local sameSong = cur == nil or cur.id == candidate
          if sameSong and sourceSilent() and Audio.playSong then
            -- Android can occasionally leave the queue stopped after a
            -- fanfare. Restart only when it is actually silent; never stomp a
            -- script that deliberately changed music during the fanfare.
            pcall(Audio.playSong, candidate, { restart = true })
          end
          recoveryFrames, candidate = nil, nil
        end
      end
    elseif not Audio._fanfareActive then
      candidate = nil
    end
    return result
  end
  return true
end

local function installVsIntroFix()
  local okBt, BattleTransition = pcall(require, "src.core.game3.battle_transition")
  if not okBt or not BattleTransition or BattleTransition.__rrVsIntroFix then return okBt end
  BattleTransition.__rrVsIntroFix = true
  local originalPick = assert(BattleTransition.pickTrainer)
  local ID = BattleTransition.ID or {}
  local byName = {
    LORELEI = ID.LORELEI,
    BRUNO = ID.BRUNO,
    AGATHA = ID.AGATHA,
    LANCE = ID.LANCE,
  }
  BattleTransition.pickTrainer = function(opts)
    opts = opts or {}
    local tid = tonumber(opts.trainerId)
    if tid then
      local okTr, Trainers = pcall(require, "src.core.game3.scripting.trainers")
      local row = okTr and Trainers and Trainers.get and Trainers.get(tid)
      local name = row and tostring(row.name or ""):upper() or ""
      local mapped = byName[name]
      if mapped then return mapped end
    end
    return originalPick(opts)
  end
  return true
end

local function installBattleMusicReturn(mod)
  local returnSong
  mod.hooks:wrap("trainer.party", function(next, trainerClass, trainerId, party)
    local okA, Audio = pcall(require, "src.core.game3.audio")
    if okA and Audio then
      local mapSong = Audio._mapSong
      if mapSong ~= nil then returnSong = mapSong end
    end
    return next(trainerClass, trainerId, party)
  end, 850)

  mod.events:on("battle.ended", function()
    if returnSong == nil then return end
    local okA, Audio = pcall(require, "src.core.game3.audio")
    if okA and Audio then
      if Audio.setMapSong then pcall(Audio.setMapSong, returnSong)
      else Audio._mapSong = returnSong end
    end
    returnSong = nil
  end)
  return true
end

function Qol.install(mod, overrides)
  local deps = mergeDefaults(overrides)
  Qol._deps = deps
  local dexNav = installDexNav(mod, deps)
  local skills = installSkills(mod, deps)
  local pokeRider = installPokeRider(mod, deps)

  -- New games can reload the already-selected start map, which emits
  -- save.created/map.reloaded rather than map.entered.  Cover every adoption
  -- path so the flag is present before the player takes their first step.
  for _, event in ipairs({ "save.created", "save.loaded", "map.entered", "map.reloaded" }) do
    mod.events:on(event, function() Qol.ensureRunningShoes(deps) end)
  end
  mod.hooks:wrap("core.update", function(next, game, dt)
    Qol.ensureRunningShoes(deps)
    if skills then skills.handleFieldInput(game) end
    if dexNav then dexNav.handleFieldInput(game) end
    return next(game, dt)
  end, 950)

  mod.hooks:wrap("catch.rate", function(next, ball, mon, species, opts)
    if Qol.ezCatchEnabled(deps) then return true, 4 end
    return next(ball, mon, species, opts)
  end, 950)

  local teamPreview = installTeamPreview(deps)
  local fanfareRecovery = installFanfareRecovery()
  local vsIntroFix = installVsIntroFix()
  local battleMusicReturn = installBattleMusicReturn(mod)
  Qol.ensureRunningShoes(deps)
  return {
    runningShoes = true,
    dexAll = dexNav ~= nil,
    teamPreview = teamPreview == true,
    ezCatch = true,
    dexNavReliableFieldEdge = true,
    dexNavFieldSelect = true,
    skillsMenu = skills ~= nil,
    autoRunSkill = skills ~= nil,
    timeChangerSkill = skills ~= nil,
    infiniteRepelSkill = skills ~= nil,
    pokeVialSkill = skills ~= nil,
    skillItemIds = skills and skills.itemIds() or {},
    pokeRider = pokeRider == true,
    pokeRiderItemId = POKE_RIDER_ITEM_ID,
    fanfareBgmRecovery = fanfareRecovery == true,
    eliteFourVsIntroFix = vsIntroFix == true,
    battleMusicReturn = battleMusicReturn == true,
    consoleFlags = {
      SO2Toxic = Qol.FLAG.SO2_TOXIC,
      Woyaopp = Qol.FLAG.WOYAOPP,
      DexAll = Qol.FLAG.DEX_ALL,
      TeamPreview = Qol.FLAG.TEAM_PREVIEW,
      EZCatch = Qol.FLAG.EZ_CATCH,
    },
  }
end

return Qol
