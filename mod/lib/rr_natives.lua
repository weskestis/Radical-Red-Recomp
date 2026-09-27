-- Radical Red v4.1 field-script compatibility.
--
-- Radical Red replaces a number of FireRed specials and calls functions in
-- expansion ROM space directly.  The stock host quite correctly skips those
-- unknown callbacks.  For this total conversion we register host equivalents
-- against the existing script VM.  Nothing in the launcher or engine tree is
-- modified on disk.

local RRNative = {}

local SPECIAL = {
  CHECK_EV = 0x007,
  CHECK_IV = 0x008,
  CHECK_FRIENDSHIP = 0x00D,
  CHANGE_EV = 0x00F,
  SET_IV = 0x010,
  CHANGE_FRIENDSHIP = 0x013,
  CHANGE_BALL = 0x014,
  CHANGE_SPECIES = 0x016,
  CHECK_SPECIES = 0x018,
  ADD_MULTICHOICE_TEXT = 0x025,
  STOP_TIMER = 0x049,
  GENERATE_FACILITY_TRAINER = 0x052,
  LOAD_FACILITY_INTRO = 0x053,
  CHECK_DAILY_EVENT = 0x0A0,
  UPDATE_TIME_VARS = 0x0A1,
  LOAD_TRAINER_B_DEFEAT = 0x0AC,
  START_FOLLOWER = 0x0D1,
  STOP_FOLLOWER = 0x0D2,
  FACE_FOLLOWER = 0x0D3,
  HAS_FOLLOWER = 0x0E1,
  SHOW_ITEM = 0x0E4,
  HIDE_ITEM = 0x0E5,
  CHOOSE_THREE = 0x0F5,
  CAN_USE_STRENGTH = 0x10C,
  ENTER_PHRASE = 0x12C,
  COMPARE_PHRASE = 0x12D,
  LIST_MENU = 0x158,
}

local STARTER_REGIONS = {
  "Johto", "Hoenn", "Sinnoh", "Unova",
  "Kalos", "Alola", "Galar", "Paldea",
}

local function loadCustomListMenus(mod, supplied)
  local data = supplied
  if data == nil and mod and mod.cache and mod.cache.read then
    local rel = "data/" .. "generated/gba/scripts/rr_listmenus.lua"
    local source = mod.cache:read(rel)
    assert(type(source) == "string" and #source > 0,
      "Radical Red custom list-menu cache is missing")
    local chunk, err = load(source, "@" .. rel, "t", {})
    assert(chunk, "Radical Red custom list-menu cache is invalid: " .. tostring(err))
    local ok, value = pcall(chunk)
    assert(ok, "Radical Red custom list-menu cache failed to load: " .. tostring(value))
    data = value
  end
  assert(type(data) == "table" and data.version == 1 and data.count == 16
      and type(data.lists) == "table",
    "Radical Red custom list-menu registry is incomplete")
  for id = 0, 15 do
    local entry = data.lists[id]
    assert(type(entry) == "table" and type(entry.labels) == "table"
        and tonumber(entry.count) == #entry.labels and entry.count > 0,
      "Radical Red custom list-menu registry omitted list " .. id)
  end
  assert(table.concat(data.lists[12].labels, ",")
      == table.concat(STARTER_REGIONS, ","),
    "Radical Red starter-region labels are invalid")
  return data
end

local EV_KEYS = {
  [0] = "hp", [1] = "atk", [2] = "def",
  [3] = "spe", [4] = "spa", [5] = "spd",
  [6] = "cool", [7] = "beauty", [8] = "cute",
  [9] = "smart", [10] = "tough", [11] = "sheen",
}

local IV_KEYS = {
  [0] = "hp", [1] = "atk", [2] = "def",
  [3] = "spe", [4] = "spa", [5] = "spd",
}

-- These are the 21 non-neutral choices exposed by the Celadon nature changer
-- in RR 4.1.  The address order was recovered from the v4.1 scripts.
local NATURE_NATIVES = {
  [0x090B18C1] = 3,  -- Adamant
  [0x090B18CB] = 1,  -- Lonely
  [0x090B18D5] = 18, -- Bashful
  [0x090B18DF] = 21, -- Gentle
  [0x090B18E9] = 9,  -- Lax
  [0x090B18F3] = 2,  -- Brave
  [0x090B18FD] = 4,  -- Naughty
  [0x090B1907] = 5,  -- Bold
  [0x090B1911] = 7,  -- Relaxed
  [0x090B191B] = 8,  -- Impish
  [0x090B1925] = 10, -- Timid
  [0x090B192F] = 11, -- Hasty
  [0x090B1939] = 13, -- Jolly
  [0x090B1943] = 14, -- Naive
  [0x090B194D] = 15, -- Modest
  [0x090B1957] = 16, -- Mild
  [0x090B1961] = 17, -- Quiet
  [0x090B196B] = 19, -- Rash
  [0x090B1975] = 20, -- Calm
  [0x090B197F] = 22, -- Sassy
  [0x090B1989] = 23, -- Careful
}

local state = {
  follower = { active = false },
  item = { visible = false },
  -- RR's multichoice IDs 32..37 are six views over the same seven-entry
  -- EWRAM pointer array.  Special 0x25 writes one label into that shared
  -- array; each list exposes the first 2..7 entries respectively.
  dynamicMultichoice = {},
  timerStarted = nil,
  timerStopped = 0,
  stockListMenus = setmetatable({}, { __mode = "k" }),
  partySelectionFixes = setmetatable({}, { __mode = "k" }),
}

local function mergeDefaults(overrides)
  local deps = {}
  for key, value in pairs(overrides or {}) do deps[key] = value end
  local modules = {
    Natives = "src.core.game3.scripting.natives",
    Flags = "src.core.game3.scripting.flags",
    Pokemon = "src.core.game3.pokemon",
    Storage = "src.core.game3.storage",
    Tower = "src.core.game3.trainer_tower",
    TowerNatives = "src.core.game3.scripting.natives_tower",
    FieldMoves = "src.core.game3.field_moves",
    Opcodes = "src.core.game3.scripting.opcodes",
    TextIR = "src.core.game3.scripting.text_ir",
    Multichoice = "src.core.game3.scripting.multichoice",
    ListMenu = "src.core.game3.scripting.natives_listmenu",
  }
  for key, moduleName in pairs(modules) do
    if deps[key] == nil then deps[key] = require(moduleName) end
  end
  return deps
end

local function space()
  -- A loaded mod can have a capability-scoped package table.  Resolve the
  -- live engine module through require instead of trusting that shadow table;
  -- otherwise dynamic RR text is looked up in an empty stale Space bundle.
  local ok, Space = pcall(require, "src.core.game3.scripting.space")
  if ok then return Space end
  return package.loaded["src.core.game3.scripting.space"]
end

local function storeOf()
  local Space = space()
  return Space and Space.store or nil
end

local function sessionOf()
  local ok, Runtime = pcall(require, "src.core.game3.runtime")
  if not ok then Runtime = package.loaded["src.core.game3.runtime"] end
  return Runtime and Runtime.getSession and Runtime.getSession() or nil
end

local function getVar(deps, ctx, id)
  return tonumber(deps.Flags.getVar(storeOf(), ctx, id)) or 0
end

local function setVar(deps, ctx, id, value)
  deps.Flags.setVar(storeOf(), ctx, id, tonumber(value) or 0)
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
  local session = sessionOf()
  if not session then return nil end
  -- CFRU SELECT_FROM_PC: 0x8003 == 1 selects box 0x8000 / slot 0x8001.
  if getVar(deps, ctx, 0x8003) == 1 then
    local storage = deps.Storage.ensure(session)
    return deps.Storage.getBoxMon(storage,
      getVar(deps, ctx, 0x8000) + 1, getVar(deps, ctx, 0x8001) + 1)
  end
  local slot = getVar(deps, ctx, 0x8004)
  if slot < 0 or slot >= 6 then return nil end
  return session.party and session.party[slot + 1] or nil
end

local function installPartySelectionCommit(deps)
  local Natives = deps.Natives
  if type(Natives.choosePartyMon) ~= "function" then return false end
  if state.partySelectionFixes[Natives] then return true end
  local original = Natives.choosePartyMon
  state.partySelectionFixes[Natives] = original

  Natives.choosePartyMon = function(ctx, adapters, menuType)
    if ctx then ctx.rrSelectedPartySlot = nil end
    local function commit(slot0)
      slot0 = math.floor(tonumber(slot0) or 7)
      setVar(deps, ctx, 0x8004, slot0)
      if ctx then ctx.rrSelectedPartySlot = slot0 end
      return slot0
    end

    local effectiveAdapters = adapters
    if adapters and type(adapters.chooseParty) == "function" then
      effectiveAdapters = {}
      for key, value in pairs(adapters) do effectiveAdapters[key] = value end
      effectiveAdapters.chooseParty = function(opts, done)
        return adapters.chooseParty(opts, function(slot0)
          slot0 = commit(slot0)
          done(slot0)
        end)
      end
    end

    local yielded = original(ctx, effectiveAdapters, menuType)
    -- The stock PartyMenu closes (and signals the waiting script) immediately
    -- before it invokes onSelect. Commit in that callback itself so the next
    -- callnative always sees the selected slot, including slot 2+.
    local okParty, PartyMenu = pcall(require, "src.ui.game3.party_menu")
    if not okParty then PartyMenu = package.loaded["src.ui.game3.party_menu"] end
    if PartyMenu and PartyMenu.open and type(PartyMenu._onSelect) == "function" then
      local stockSelect = PartyMenu._onSelect
      PartyMenu._onSelect = function(slot, ...)
        commit(slot and ((tonumber(slot) or 1) - 1) or 7)
        return stockSelect(slot, ...)
      end
    end
    return yielded
  end
  return true
end

local function clamp(value, low, high)
  value = math.floor(tonumber(value) or 0)
  if value < low then return low end
  if value > high then return high end
  return value
end

local function applyStats(deps, mon)
  if mon and deps.Pokemon.applyStats then deps.Pokemon.applyStats(mon) end
end

local function textAtPointer(deps, ctx, ptr)
  ptr = ptr or (ctx and ctx.data and ctx.data[0])
  local key = deps.Opcodes.key(ptr)
  local Space = space()
  local ir
  if Space and Space.vm and Space.vm.getText then
    ir = Space.vm:getText(key) or Space.vm:getText(ptr)
  end
  if not ir and Space and Space.bundle and Space.bundle.text then
    ir = Space.bundle.text[key] or Space.bundle.text[ptr]
  end
  if type(ir) == "string" then return ir end
  if type(ir) == "table" then
    return deps.TextIR.toPlain(ir, {
      stringVars = (ctx and ctx.stringVars) or {},
      playerName = ctx and ctx.playerName,
    })
  end
  return ""
end

local function nowTable()
  local t = os.date("*t")
  return {
    minute = tonumber(t.min) or 0,
    hour = tonumber(t.hour) or 0,
    day = tonumber(t.day) or 1,
    month = tonumber(t.month) or 1,
    year = tonumber(t.year) or 2000,
  }
end

local function packDate(t)
  local year = clamp(t.year, 0, 3199)
  local low = clamp(t.minute, 0, 59)
    + clamp(t.hour, 0, 23) * 0x40
    + clamp(t.day, 0, 31) * 0x800
  local high = clamp(t.month, 0, 15)
    + (year % 100) * 0x10
    + math.floor(year / 100) * 0x800
  return low % 0x10000, high % 0x10000
end

local function unpackDate(low, high)
  low, high = tonumber(low) or 0, tonumber(high) or 0
  return {
    minute = low % 0x40,
    hour = math.floor(low / 0x40) % 0x20,
    day = math.floor(low / 0x800) % 0x20,
    month = high % 0x10,
    year = (math.floor(high / 0x10) % 0x80)
      + (math.floor(high / 0x800) % 0x20) * 100,
  }
end

local function writeDate(deps, ctx, varId, t)
  local low, high = packDate(t)
  setVar(deps, ctx, varId, low)
  setVar(deps, ctx, varId + 1, high)
end

local function dateOrder(t)
  return (tonumber(t.year) or 0) * 10000
    + (tonumber(t.month) or 0) * 100 + (tonumber(t.day) or 0)
end

local function runtimeTime()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

local function setNature(deps, ctx, nature)
  local mon = selectedMon(deps, ctx)
  if not mon then return false end
  local old = math.floor(tonumber(mon.personality) or 0)
  local base = old - (old % 50)
  local personality = base + nature
  -- Nature is PID % 25.  Adding 25 preserves nature and flips parity, so use
  -- the variant that preserves the ability slot.
  if personality % 2 ~= old % 2 then personality = personality + 25 end
  if personality > 0xFFFFFFFF then personality = personality - 50 end
  mon.personality = personality
  mon.nature = nature
  if deps.Pokemon.abilityId then
    local id = deps.Pokemon.abilityId(mon.species or mon.speciesId, personality)
    mon.ability, mon.abilityId = id, id
  end
  if deps.Pokemon.gender then
    mon.gender = deps.Pokemon.gender(mon.species or mon.speciesId, personality)
  end
  applyStats(deps, mon)
  return false
end

local function installFollowerHook(deps)
  local Follower = deps and deps.Follower
  if not Follower then
    local ok, loaded = pcall(require, "src.world.game3.Follower")
    if ok then Follower = loaded end
  end
  if not Follower then return false end
  Follower.setShouldSpawn(function() return state.follower.active end)
  if not Follower._rrOriginalUpdate then
    Follower._rrOriginalUpdate = Follower.update
    Follower.update = function(game)
      Follower._rrOriginalUpdate(game)
      local npc = Follower.current()
      if npc and state.follower.active then
        npc.sprite = state.follower.sprite or npc.sprite
        npc.graphicsId = state.follower.graphicsId or npc.graphicsId
        npc.rrFollowerFlags = state.follower.flags
      end
    end
  end
  return true
end

local function startFollower(deps, ctx)
  local localOrVar = getVar(deps, ctx, 0x8000)
  local localId = getVar(deps, ctx, localOrVar)
  local Objects = package.loaded["src.core.game3.objects"]
  local source = Objects and Objects.find and Objects.find(localId)
  state.follower.active = source ~= nil
  state.follower.localId = localId
  state.follower.flags = getVar(deps, ctx, 0x8001)
  state.follower.sprite = source and source.sprite or nil
  state.follower.graphicsId = source and (source.graphicsId
    or (source.def and (source.def.graphicsId or source.def.graphics))) or nil
  if source then
    source.hidden = true
    source.visible = false
    source.invisible = true
  end
  installFollowerHook(deps)
  return false
end

local function stopFollower()
  local Objects = package.loaded["src.core.game3.objects"]
  if state.follower.active and Objects and Objects.removeObject then
    Objects.removeObject(state.follower.localId)
  end
  state.follower = { active = false }
  local Follower = package.loaded["src.world.game3.Follower"]
  if Follower and Follower.reset then Follower.reset() end
  return false
end

local function faceFollower()
  if not state.follower.active then return false end
  local Follower = package.loaded["src.world.game3.Follower"]
  local Player = package.loaded["src.core.game3.player"]
  local npc = Follower and Follower.current and Follower.current()
  if not (npc and Player) then return false end
  local dx = (tonumber(npc.cellX) or 0) - (tonumber(Player.cellX) or 0)
  local dy = (tonumber(npc.cellY) or 0) - (tonumber(Player.cellY) or 0)
  local playerFacing, followerFacing
  if math.abs(dx) > math.abs(dy) then
    playerFacing = dx > 0 and "right" or "left"
    followerFacing = dx > 0 and "left" or "right"
  else
    playerFacing = dy > 0 and "down" or "up"
    followerFacing = dy > 0 and "up" or "down"
  end
  Player.facing = playerFacing
  npc.facing = followerFacing
  return false
end

local function chooseThree(deps, ctx, adapters)
  local session = sessionOf()
  if not session then
    setResult(deps, ctx, 0)
    return false
  end
  deps.Tower.clearSelectedOrder(session)
  -- Rental-team callbacks save the real party before replacing it.  Saving
  -- again here would overwrite that backup with the temporary rental team.
  if not session.rrFacilityPartyBackup then deps.Tower.savePlayerParty(session) end
  local function finish(picks)
    local normalized = {}
    if type(picks) == "number" then
      normalized[1] = math.floor(picks) + 1
    elseif type(picks) == "table" then
      for _, slot in ipairs(picks) do
        slot = tonumber(slot)
        -- Adapters returns one-based multi-select slots.
        if slot then normalized[#normalized + 1] = math.floor(slot) end
      end
    end
    local order = deps.Tower.setSelectedOrder(session, normalized)
    local count = 0
    for i = 1, 3 do if tonumber(order[i]) and order[i] ~= 0 then count = count + 1 end end
    if count == 3 then
      deps.Tower.reducePartyToThree(session)
      setResult(deps, ctx, 1)
    else
      deps.Tower.loadPlayerParty(session)
      session.rrFacilityPartyBackup = nil
      session.rrFacilityFreshBackup = nil
      setResult(deps, ctx, 0)
    end
  end
  if adapters and adapters.chooseParty then
    return deps.Natives.yieldHost(ctx, adapters, function(done)
      adapters.chooseParty(deps.TowerNatives.chooseOptions(), function(picks)
        finish(picks)
        done()
      end)
    end)
  end
  finish(nil)
  return false
end

local function buildHandlers(deps)
  local H = {}

  H[SPECIAL.CHECK_EV] = function(ctx)
    local mon = selectedMon(deps, ctx)
    local key = EV_KEYS[getVar(deps, ctx, 0x8005)]
    local value = mon and key and tonumber((mon.evs and mon.evs[key]) or mon[key]) or 0
    return false, clamp(value, 0, 255)
  end

  H[SPECIAL.CHECK_IV] = function(ctx)
    local mon = selectedMon(deps, ctx)
    local key = IV_KEYS[getVar(deps, ctx, 0x8005)]
    return false, clamp(mon and key and mon.ivs and mon.ivs[key] or 0, 0, 31)
  end

  H[SPECIAL.CHECK_FRIENDSHIP] = function(ctx)
    local mon = selectedMon(deps, ctx)
    return false, mon and deps.Pokemon.friendshipOf(mon) or 0
  end

  H[SPECIAL.CHANGE_EV] = function(ctx)
    local mon = selectedMon(deps, ctx)
    local key = EV_KEYS[getVar(deps, ctx, 0x8005)]
    if mon and key and IV_KEYS[getVar(deps, ctx, 0x8005)] then
      local evs = deps.Pokemon.evsOf(mon)
      local amount = getVar(deps, ctx, 0x8006)
      if math.floor(amount / 0x100) % 2 == 1 then amount = -(amount - 0x100) end
      evs[key] = clamp((tonumber(evs[key]) or 0) + amount, 0, 252)
      applyStats(deps, mon)
    end
    return false
  end

  H[SPECIAL.SET_IV] = function(ctx)
    local mon = selectedMon(deps, ctx)
    if mon then
      mon.ivs = mon.ivs or {}
      local stat = getVar(deps, ctx, 0x8005)
      local amount = clamp(getVar(deps, ctx, 0x8006), 0, 31)
      if stat == 6 then
        for _, key in pairs(IV_KEYS) do mon.ivs[key] = amount end
      elseif IV_KEYS[stat] then
        mon.ivs[IV_KEYS[stat]] = amount
      end
      applyStats(deps, mon)
    end
    return false
  end

  H[SPECIAL.CHANGE_FRIENDSHIP] = function(ctx)
    local mon = selectedMon(deps, ctx)
    if mon then
      local amount = getVar(deps, ctx, 0x8005)
      if math.floor(amount / 0x100) % 2 == 1 then amount = -(amount - 0x100) end
      deps.Pokemon.setFriendship(mon,
        clamp(deps.Pokemon.friendshipOf(mon) + amount, 0, 255))
    end
    return false
  end

  H[SPECIAL.CHANGE_BALL] = function(ctx)
    local mon = selectedMon(deps, ctx)
    local ball = getVar(deps, ctx, 0x8005)
    if mon and ball >= 0 and ball < 27 then
      mon.ball, mon.ballType, mon.pokeball = ball, ball, ball
    end
    return false
  end

  H[SPECIAL.CHANGE_SPECIES] = function(ctx)
    local mon = selectedMon(deps, ctx)
    local species = getVar(deps, ctx, 0x8005)
    if mon and species > 0 then
      local oldMax, oldHp = tonumber(mon.maxHp) or 0, tonumber(mon.hp) or 0
      mon.species, mon.speciesId = species, species
      if deps.Pokemon.name then mon.name = deps.Pokemon.name(species) end
      local pid = tonumber(mon.personality) or 0
      if deps.Pokemon.abilityId then
        local id = deps.Pokemon.abilityId(species, pid)
        mon.ability, mon.abilityId = id, id
      end
      if deps.Pokemon.gender then mon.gender = deps.Pokemon.gender(species, pid) end
      applyStats(deps, mon)
      if oldMax > 0 and oldHp > 0 then
        mon.hp = math.max(1, math.floor((tonumber(mon.maxHp) or 1) * oldHp / oldMax))
      end
    end
    return false
  end

  H[SPECIAL.CHECK_SPECIES] = function(ctx)
    local mon = selectedMon(deps, ctx)
    return false, tonumber(mon and (mon.species or mon.speciesId)) or 0
  end

  H[SPECIAL.ADD_MULTICHOICE_TEXT] = function(ctx)
    local index = getVar(deps, ctx, 0x8006)
    if index <= 6 then
      local dynamicText = textAtPointer(deps, ctx)
      state.dynamicMultichoice[index + 1] = dynamicText
      -- gMultichoiceLists[32..37] all point at sMultichoiceOptions; their
      -- count fields are 2, 3, 4, 5, 6 and 7.  Publish those exact views so
      -- the original RR scripts (including new-game list 34) see what the
      -- cartridge would display instead of stock placeholder labels.
      for listId = 32, 37 do
        local labels = {}
        for i = 1, listId - 30 do
          labels[i] = state.dynamicMultichoice[i] or ""
        end
        deps.Multichoice.LISTS[listId] = {
          count = #labels,
          labels = labels,
        }
      end
    end
    return false
  end

  H[SPECIAL.STOP_TIMER] = function(ctx)
    local now = runtimeTime()
    if state.timerStarted then
      state.timerStopped = math.floor((now - state.timerStarted) * 1024) % 0x10000
      state.timerStarted = nil
    end
    local value = setResult(deps, ctx, state.timerStopped or 0)
    return false, value
  end

  -- Early-boot fallbacks. rr_facilities replaces both handlers with exact
  -- ROM-table-backed implementations later in main.lua.
  H[SPECIAL.GENERATE_FACILITY_TRAINER] = function(ctx, adapters)
    local battler = clamp(getVar(deps, ctx, 0x8000), 0, 2)
    local kind = clamp(getVar(deps, ctx, 0x8001), 0, 2)
    local id = kind == 2 and getVar(deps, ctx, 0x8002) or math.random(0, 255)
    setVar(deps, ctx, 0x501C + battler, id)
    setString(ctx, adapters, 1, "TRAINER")
    return false, 1
  end

  H[SPECIAL.LOAD_FACILITY_INTRO] = function(ctx)
    ctx.rrFacilityIntroRequested = true
    return false
  end

  H[SPECIAL.CHECK_DAILY_EVENT] = function(ctx)
    local varId = getVar(deps, ctx, 0x8000)
    local stored = unpackDate(getVar(deps, ctx, varId), getVar(deps, ctx, varId + 1))
    local current = (RRNative._testNow and RRNative._testNow()) or nowTable()
    local result = 0
    if dateOrder(stored) <= dateOrder(current) and dateOrder(stored) ~= dateOrder(current) then
      result = 1
      if getVar(deps, ctx, 0x8001) ~= 0 then writeDate(deps, ctx, varId, current) end
    end
    setResult(deps, ctx, result)
    return false, result
  end

  H[SPECIAL.UPDATE_TIME_VARS] = function(ctx)
    local varId = getVar(deps, ctx, 0x8000)
    writeDate(deps, ctx, varId, (RRNative._testNow and RRNative._testNow()) or nowTable())
    return false
  end

  H[SPECIAL.LOAD_TRAINER_B_DEFEAT] = function(ctx)
    local text = textAtPointer(deps, ctx)
    ctx.trainerBDefeatText = text
    ctx.trainerBattleDefeatTextB = text
    return false
  end

  H[SPECIAL.START_FOLLOWER] = function(ctx) return startFollower(deps, ctx) end
  H[SPECIAL.STOP_FOLLOWER] = stopFollower
  H[SPECIAL.FACE_FOLLOWER] = faceFollower
  H[SPECIAL.HAS_FOLLOWER] = function(ctx)
    setResult(deps, ctx, state.follower.active and 1 or 0)
    return false
  end

  H[SPECIAL.SHOW_ITEM] = function(ctx)
    state.item.visible = true
    state.item.id = getVar(deps, ctx, 0x8004)
    state.item.slot = getVar(deps, ctx, 0x8006)
    ctx.rrItemSprite = state.item
    return false
  end
  H[SPECIAL.HIDE_ITEM] = function(ctx)
    state.item.visible = false
    ctx.rrItemSprite = nil
    return false
  end

  H[SPECIAL.CHOOSE_THREE] = function(ctx, adapters)
    return chooseThree(deps, ctx, adapters)
  end

  H[SPECIAL.CAN_USE_STRENGTH] = function(ctx)
    local session = sessionOf()
    local slot = 6
    local mon, candidate = deps.FieldMoves.partyMoveUser(session and session.party, "STRENGTH")
    local hasBadge = true
    if deps.FieldMoves.hasBadge then
      hasBadge = deps.FieldMoves.hasBadge({ store = storeOf(), ctx = ctx }, "STRENGTH")
    end
    if mon and hasBadge then slot = candidate end
    setVar(deps, ctx, 0x8004, slot)
    return false
  end

  H[SPECIAL.ENTER_PHRASE] = function(ctx, adapters)
    local isPassword = getVar(deps, ctx, 0x8000) == 1
    local title = isPassword and "ENTER PASSWORD" or "ENTER PHRASE"
    setString(ctx, adapters, 1, "")
    if adapters and adapters.openNaming then
      return deps.Natives.yieldHost(ctx, adapters, function(done)
        adapters.openNaming({ title = title, maxLen = 12, initial = "" }, function(value)
          setString(ctx, adapters, 1, value or "")
          done()
        end)
      end)
    end
    return false
  end

  H[SPECIAL.COMPARE_PHRASE] = function(ctx)
    local expected = textAtPointer(deps, ctx)
    local entered = tostring(ctx and ctx.stringVars and ctx.stringVars[1] or "")
    local value
    if expected == entered then value = 0 elseif expected < entered then value = -1 else value = 1 end
    value = value % 0x10000
    setResult(deps, ctx, value)
    return false, value
  end

  H[SPECIAL.LIST_MENU] = function(ctx)
    -- RR completely replaces FireRed's badge-list special. 0x8000 selects
    -- one of 16 ROM tables and 0x8001 requests the visible row count. Falling
    -- through for any of these calls is what displayed badge names in nature,
    -- starter, tutor, fossil, type, ball, elevator, and mode selectors.
    if getVar(deps, ctx, 0x8004) == 0 then
      local menuId = getVar(deps, ctx, 0x8000)
      local entry = deps.RRListMenus and deps.RRListMenus.lists[menuId]
      if entry then
        local maxShowed = math.min(entry.count, getVar(deps, ctx, 0x8001))
        if maxShowed < 2 or maxShowed > 6 then maxShowed = 6 end
        return deps.ListMenu.presentItems(ctx, "rr_custom_list_" .. menuId,
          entry.labels, {
            count = entry.count,
            maxShowed = maxShowed,
            left = 1,
            top = 1,
            height = maxShowed * 2 - 1,
            keepOpen = false,
          }, function(index)
          setResult(deps, ctx, index)
        end)
      end
    end
    local stock = deps.StockListMenu
      or (deps.ListMenu.HANDLERS and deps.ListMenu.HANDLERS[SPECIAL.LIST_MENU])
    if stock then return stock(ctx) end
    return false
  end

  return H
end

function RRNative.install(mod, overrides)
  local deps = mergeDefaults(overrides)
  local partySelectionCommit = installPartySelectionCommit(deps)
  deps.RRListMenus = loadCustomListMenus(mod, deps.RRListMenus)
  local listMenuKey = "special:" .. SPECIAL.LIST_MENU
  if not state.stockListMenus[deps.Natives] then
    state.stockListMenus[deps.Natives] = deps.Natives.ALLOW[listMenuKey]
      or (deps.ListMenu.HANDLERS and deps.ListMenu.HANDLERS[SPECIAL.LIST_MENU])
  end
  deps.StockListMenu = state.stockListMenus[deps.Natives]
  local handlers = buildHandlers(deps)
  local specialCount = 0
  for id, handler in pairs(handlers) do
    deps.Natives.ALLOW["special:" .. id] = handler
    specialCount = specialCount + 1
  end

  local natureCount = 0
  for address, nature in pairs(NATURE_NATIVES) do
    deps.Natives.ALLOW["native:" .. address] = function(ctx)
      return setNature(deps, ctx, nature)
    end
    natureCount = natureCount + 1
  end

  installFollowerHook(deps)
  RRNative._deps = deps
  RRNative._handlers = handlers
  RRNative._state = state
  if mod and mod.log and mod.log.info then
    mod.log:info(("Radical Red script layer: %d specials, %d nature callbacks")
      :format(specialCount, natureCount))
  end
  return {
    specials = specialCount,
    nativeCallbacks = natureCount,
    follower = true,
    phraseEntry = true,
    dailyEvents = true,
    partyEditing = true,
    partySelectionCommit = partySelectionCommit,
    facilityBootstrap = true,
    starterRegionMenu = true,
    cartridgeListMenus = true,
    customListMenus = deps.RRListMenus.count,
  }
end

RRNative.SPECIAL = SPECIAL
RRNative.NATURE_NATIVES = NATURE_NATIVES
RRNative.packDate = packDate
RRNative.unpackDate = unpackDate
RRNative.STARTER_REGIONS = STARTER_REGIONS

return RRNative
