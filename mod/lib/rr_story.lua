-- Radical Red v4.1 story, follower, and utility native callbacks.
--
-- These functions are invoked directly by the extracted RR event scripts.
-- The original routines live in expansion ROM Thumb code, so the host must
-- provide equivalent behavior while continuing to read all player data from
-- gen1recomp's live session.

local Story = {}

Story.ADDR = {
  FOLLOWER_HIDE = 0x090964B1,
  FOLLOWER_DELAY = 0x09096501,
  FOLLOWER_NICKNAME = 0x09096DF5,
  FOLLOWER_FRIENDSHIP = 0x09096EAD,
  FOLLOWER_SYNC = 0x090988E5,
  FOLLOWER_AVAILABLE = 0x0909921D,
  FOLLOWER_REACTION = 0x090992E5,
  PLAY_SE_154 = 0x09099421,
  PLAY_SE_194 = 0x09099431,
  FOLLOWER_SMILE = 0x090995D5,
  FOLLOWER_ORAN = 0x09099621,
  FOLLOWER_JUMP_RIGHT = 0x0909971D,
  FOLLOWER_JUMP_TOWARD = 0x090997B5,
  FOLLOWER_MEWTWO_EVENT = 0x09099835,
  FORCE_STEREO = 0x090B0939,
  ACTIVE_ROAMER = 0x090B8201,
  NEW_GAME_PLUS = 0x090BB2A1,
  PLURALIZE_ITEM = 0x090BBD3D,
}

local VAR = {
  FOLLOWER_SPECIES = 0x5130,
  ITEM_AMOUNT = 0x8005,
  RESULT = 0x800D,
}

local FLAG = {
  HARDCORE = 0x1034,
  MEWTWO_EVENT_DONE = 0x1074,
  GAME_CLEAR = 0x82C,
}

local TYPE = {
  FIGHTING = 1,
  FLYING = 2,
  GROUND = 4,
  ROCK = 5,
  STEEL = 8,
  FIRE = 10,
  WATER = 11,
  ELECTRIC = 13,
}

local MOVEMENT = {
  JUMP_DOWN = 0x52,
  JUMP_UP = 0x53,
  JUMP_LEFT = 0x54,
  JUMP_RIGHT = 0x55,
  SMILE = 0x66,
}

local function mergeDefaults(overrides)
  local deps = {}
  for key, value in pairs(overrides or {}) do deps[key] = value end
  local modules = {
    Natives = "src.core.game3.scripting.natives",
    Flags = "src.core.game3.scripting.flags",
    Pokemon = "src.core.game3.pokemon",
    Options = "src.core.game3.options",
    Audio = "src.core.game3.audio",
    Follower = "src.world.game3.Follower",
    FieldEffects = "src.core.game3.field_effects",
    SaveData = "src.core.SaveData",
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

local function followerState(deps)
  if deps.getFollowerState then return deps.getFollowerState() or {} end
  return Story._fallbackFollower
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

local function setString(ctx, adapters, index, value)
  value = tostring(value or "")
  if ctx then
    ctx.stringVars = ctx.stringVars or {}
    ctx.stringVars[index] = value
  end
  if adapters and adapters.setStringVar then adapters.setStringVar(index, value) end
end

local function heldItem(mon)
  return tonumber(mon and (mon.heldItem or mon.itemId or mon.item)) or 0
end

local function speciesOf(deps, mon)
  if not mon then return nil end
  if deps.Pokemon.speciesOf then return tonumber(deps.Pokemon.speciesOf(mon)) end
  return tonumber(mon.species or mon.speciesId or mon.id)
end

local function monMatchesSpecies(deps, mon, wanted)
  local species = speciesOf(deps, mon)
  if species == wanted then return true end
  for _, key in ipairs({ "formSpecies", "battleSpecies", "displaySpecies", "transformedSpecies" }) do
    if tonumber(mon and mon[key]) == wanted then return true end
  end
  -- RR resolves Mega forms from the held stone before comparing the selected
  -- follower species.  EVO_MEGA is method 0xFE in its evolution table.
  if species and deps.Pokemon.evolutions then
    local item = heldItem(mon)
    for _, evo in ipairs(deps.Pokemon.evolutions(species) or {}) do
      if tonumber(evo.method) == 0xFE and tonumber(evo.param) == item
          and tonumber(evo.target or evo.targetSpecies) == wanted then
        return true
      end
    end
  end
  return false
end

local function livingFollowerMon(deps, ctx)
  local session = sessionOf(deps)
  local wanted = getVar(deps, ctx, VAR.FOLLOWER_SPECIES)
  if not session or wanted == 0 then return nil end
  for _, mon in ipairs(session.party or {}) do
    local hp = tonumber(mon and mon.hp) or 0
    local egg = deps.Pokemon.isEgg and deps.Pokemon.isEgg(mon) or (mon and mon.isEgg)
    if hp > 0 and not egg and monMatchesSpecies(deps, mon, wanted) then return mon end
  end
  return nil
end

local function followerNpc(deps)
  return deps.Follower and deps.Follower.current and deps.Follower.current() or nil
end

local function setFollowerVisible(deps, visible)
  local state = followerState(deps)
  state.hidden = not visible
  local npc = followerNpc(deps)
  if deps.Follower and deps.Follower.setVisible then
    deps.Follower.setVisible(nil, visible)
  elseif npc then
    npc.hidden = not visible
  end
end

local FACING_BY_MOVEMENT = {
  [MOVEMENT.JUMP_DOWN] = "down",
  [MOVEMENT.JUMP_UP] = "up",
  [MOVEMENT.JUMP_LEFT] = "left",
  [MOVEMENT.JUMP_RIGHT] = "right",
}

local function playFollowerMovement(deps, movement)
  local npc = followerNpc(deps)
  local state = followerState(deps)
  state.lastMovement = movement
  if not npc then return false end
  if movement == MOVEMENT.SMILE then
    if deps.FieldEffects and deps.FieldEffects.startEmote then
      deps.FieldEffects.startEmote(npc, "smile")
    end
    return true
  end
  npc.facing = FACING_BY_MOVEMENT[movement] or npc.facing
  npc.rrJumpFrames = 16
  npc.rrJumpDuration = 16
  return true
end

local function installFollowerPresentation(deps)
  local Follower = deps.Follower
  if not Follower then return false end
  if not Follower._rrStoryOriginalUpdate then
    Follower._rrStoryOriginalUpdate = Follower.update
    Follower.update = function(game)
      if Follower._rrStoryOriginalUpdate then Follower._rrStoryOriginalUpdate(game) end
      local npc = Follower.current and Follower.current()
      local state = followerState(deps)
      if npc then
        npc.hidden = state.hidden == true
        if (tonumber(npc.rrJumpFrames) or 0) > 0 then
          npc.rrJumpFrames = npc.rrJumpFrames - 1
        end
      end
    end
  end
  if not Follower._rrStoryOriginalActor then
    Follower._rrStoryOriginalActor = Follower.actor
    Follower.actor = function(...)
      local actor = Follower._rrStoryOriginalActor and Follower._rrStoryOriginalActor(...) or nil
      local npc = Follower.current and Follower.current()
      if actor and npc and (tonumber(npc.rrJumpFrames) or 0) > 0 then
        local duration = tonumber(npc.rrJumpDuration) or 16
        local progress = duration - npc.rrJumpFrames
        local lift = math.sin(math.pi * progress / duration) * 5
        actor.y = actor.y - lift
      end
      return actor
    end
  end
  return true
end

local function containsType(types, wanted)
  return tonumber(types and types[1]) == wanted or tonumber(types and types[2]) == wanted
end

local function packedMapId(deps, session)
  if not session then return nil end
  local group = tonumber(session.mapGroup or (session.location and session.location.mapGroup))
  local num = tonumber(session.mapNum or (session.location and session.location.mapNum))
  if group == nil or num == nil then
    local Catalog = deps.MapCatalog
    if not Catalog then
      local ok, loaded = pcall(require, "src.import.gba.map_catalog")
      if ok then Catalog = loaded end
    end
    local key = Catalog and Catalog.slotKeyFor and Catalog.slotKeyFor(session.map)
    if key then
      group, num = key:match("^(%d+)_(%d+)$")
      group, num = tonumber(group), tonumber(num)
    end
  end
  if group == nil or num == nil then return nil end
  return group % 0x100 + (num % 0x100) * 0x100
end

local function currentMapSection(deps, session)
  if not session then return nil end
  if deps.Pokemon.currentMapSec then return tonumber(deps.Pokemon.currentMapSec(session)) end
  return tonumber(session.regionMapSectionId or session.mapSec)
end

local function saveFlag(save, id)
  local flags = type(save) == "table" and save.flags
  return type(flags) == "table" and (flags[id] == true or flags[tostring(id)] == true)
end

local function hasHallOfFame(save)
  if type(save) ~= "table" then return false end
  if save.game_cleared == true or save.hasHallOfFameRecords == true then return true end
  if type(save.hallOfFameTeams) == "table" and #save.hallOfFameTeams > 0 then return true end
  return saveFlag(save, FLAG.GAME_CLEAR)
end

local function activeRoamer(session)
  if type(session) ~= "table" then return false end
  for _, key in ipairs({ "rrRoamers", "roamers" }) do
    local roamers = session[key]
    if type(roamers) == "table" then
      for _, roamer in pairs(roamers) do
        if type(roamer) == "table"
            and (tonumber(roamer.species or roamer.speciesId) or 0) ~= 0 then
          return true
        end
      end
    end
  end
  local roamer = session.roamer
  return type(roamer) == "table"
    and (tonumber(roamer.species or roamer.speciesId) or 0) ~= 0
end

local function pluralize(value)
  value = tostring(value or "")
  if value == "" then return value end
  local last = value:sub(-1)
  if last == "y" then return value:sub(1, -2) .. "ies" end
  if last == "Y" then return value:sub(1, -2) .. "IES" end
  if last == "x" then return value .. "es" end
  if last == "X" then return value .. "ES" end
  if last == "s" or last == "S" then return value end
  return value .. "s"
end

local function buildHandlers(deps)
  local H = {}

  H[Story.ADDR.FOLLOWER_HIDE] = function()
    local state = followerState(deps)
    state.locked = false
    state.delayedState = 1
    setFollowerVisible(deps, false)
    return false
  end

  H[Story.ADDR.FOLLOWER_DELAY] = function()
    followerState(deps).delayedState = 1
    return false
  end

  H[Story.ADDR.FOLLOWER_NICKNAME] = function(ctx, adapters)
    local mon = livingFollowerMon(deps, ctx)
    if mon then setString(ctx, adapters, 2, deps.Pokemon.displayName(mon)) end
    return false
  end

  H[Story.ADDR.FOLLOWER_FRIENDSHIP] = function(ctx)
    local mon = livingFollowerMon(deps, ctx)
    local friendship = mon and deps.Pokemon.friendshipOf(mon) or 0
    local result = friendship > 200 and 1 or friendship > 150 and 2
      or friendship > 100 and 3 or 4
    setResult(deps, ctx, result)
    return false, result
  end

  H[Story.ADDR.FOLLOWER_SYNC] = function(ctx)
    local state = followerState(deps)
    state.species = getVar(deps, ctx, VAR.FOLLOWER_SPECIES)
    state.delayedState = 0
    setFollowerVisible(deps, state.active == true)
    return false
  end

  H[Story.ADDR.FOLLOWER_AVAILABLE] = function(ctx, adapters)
    local mon = livingFollowerMon(deps, ctx)
    local available = mon ~= nil
    if available and deps.canFollowSpecies then
      available = deps.canFollowSpecies(speciesOf(deps, mon)) ~= false
    end
    if available then
      setString(ctx, adapters, 2, deps.Pokemon.displayName(mon))
      followerState(deps).species = getVar(deps, ctx, VAR.FOLLOWER_SPECIES)
    end
    local result = setResult(deps, ctx, available and 1 or 0)
    return false, result
  end

  H[Story.ADDR.FOLLOWER_REACTION] = function(ctx)
    local result = 0
    local mon = livingFollowerMon(deps, ctx)
    if mon then
      local species = speciesOf(deps, mon) or 0
      local types = deps.Pokemon.types(species) or { 0, 0 }
      local state = followerState(deps)
      local session = sessionOf(deps)
      if state.interactionMode == 2 or state.locked == 2 then
        if containsType(types, TYPE.FIRE) and species ~= 0x33E then
          result = 1
        elseif containsType(types, TYPE.ROCK)
            and not (tonumber(types[1]) == TYPE.WATER and tonumber(types[2]) == TYPE.WATER)
            and species ~= 0x185 then
          result = 1
        end
      else
        local section = currentMapSection(deps, session)
        local mapId = packedMapId(deps, session)
        if section == 142 and containsType(types, TYPE.ELECTRIC)
            and not getFlag(deps, ctx, FLAG.HARDCORE) then
          result = 2
        elseif section == 138 and (containsType(types, TYPE.GROUND)
            or containsType(types, TYPE.ROCK) or containsType(types, TYPE.STEEL)) then
          result = 3
        elseif mapId == 0x100A and (containsType(types, TYPE.FLYING)
            or containsType(types, TYPE.FIRE)) then
          result = 4
        elseif mapId == 0x020E and containsType(types, TYPE.FIGHTING) then
          result = 5
        end
      end
    end
    setResult(deps, ctx, result)
    return false, result
  end

  H[Story.ADDR.PLAY_SE_154] = function()
    deps.Audio.playSe(154)
    return false
  end

  H[Story.ADDR.PLAY_SE_194] = function()
    deps.Audio.playSe(194)
    return false
  end

  H[Story.ADDR.FOLLOWER_SMILE] = function()
    playFollowerMovement(deps, MOVEMENT.SMILE)
    return false
  end

  H[Story.ADDR.FOLLOWER_ORAN] = function(ctx)
    local mon = livingFollowerMon(deps, ctx)
    if mon then
      local friendship = deps.Pokemon.friendshipOf(mon)
      local amount = friendship <= 99 and 70 or friendship <= 199 and 60 or 40
      deps.Pokemon.setFriendship(mon, math.min(255, friendship + amount))
    end
    return false
  end

  H[Story.ADDR.FOLLOWER_JUMP_RIGHT] = function()
    playFollowerMovement(deps, MOVEMENT.JUMP_RIGHT)
    return false
  end

  H[Story.ADDR.FOLLOWER_JUMP_TOWARD] = function()
    local npc = followerNpc(deps)
    local Player = deps.Player or package.loaded["src.core.game3.player"]
    local movement = MOVEMENT.JUMP_DOWN
    if npc and Player then
      local dx = (tonumber(Player.cellX) or 0) - (tonumber(npc.cellX) or 0)
      local dy = (tonumber(Player.cellY) or 0) - (tonumber(npc.cellY) or 0)
      if math.abs(dx) > math.abs(dy) then
        movement = dx >= 0 and MOVEMENT.JUMP_RIGHT or MOVEMENT.JUMP_LEFT
      else
        movement = dy >= 0 and MOVEMENT.JUMP_DOWN or MOVEMENT.JUMP_UP
      end
    end
    playFollowerMovement(deps, movement)
    return false
  end

  H[Story.ADDR.FOLLOWER_MEWTWO_EVENT] = function(ctx)
    local session = sessionOf(deps)
    local result = getVar(deps, ctx, VAR.FOLLOWER_SPECIES) == 150
      and packedMapId(deps, session) == 0x6D01
      and not getFlag(deps, ctx, FLAG.MEWTWO_EVENT_DONE) and 1 or 0
    setResult(deps, ctx, result)
    return false, result
  end

  H[Story.ADDR.FORCE_STEREO] = function()
    local session = sessionOf(deps)
    if session then
      deps.Options.set(session, "sound", 1)
      if deps.Audio.applyOptions then deps.Audio.applyOptions(session) end
    end
    return false
  end

  H[Story.ADDR.ACTIVE_ROAMER] = function(ctx)
    local result = activeRoamer(sessionOf(deps)) and 1 or 0
    setResult(deps, ctx, result)
    return false, result
  end

  H[Story.ADDR.NEW_GAME_PLUS] = function(ctx)
    local save = sessionOf(deps)
    if not hasHallOfFame(save) then
      local ok, loaded
      if deps.loadSave then
        ok, loaded = pcall(deps.loadSave)
      elseif deps.SaveData and deps.SaveData.load then
        ok, loaded = pcall(deps.SaveData.load)
      end
      if ok then save = loaded end
    end
    local result = hasHallOfFame(save) and 1 or 0
    setResult(deps, ctx, result)
    return false, result
  end

  H[Story.ADDR.PLURALIZE_ITEM] = function(ctx, adapters)
    if getVar(deps, ctx, VAR.ITEM_AMOUNT) > 1 then
      local current = ctx and ctx.stringVars and ctx.stringVars[2] or ""
      setString(ctx, adapters, 2, pluralize(current))
    end
    return false
  end

  return H
end

function Story.install(mod, overrides)
  local deps = mergeDefaults(overrides)
  local handlers = buildHandlers(deps)
  local count = 0
  for address, handler in pairs(handlers) do
    deps.Natives.ALLOW["native:" .. address] = handler
    count = count + 1
  end
  installFollowerPresentation(deps)
  Story._deps = deps
  Story._handlers = handlers
  if mod and mod.log and mod.log.info then
    mod.log:info(("Radical Red story layer: %d native callbacks"):format(count))
  end
  return {
    nativeCallbacks = count,
    followerInteractions = true,
    newGamePlus = true,
    roamerCheck = true,
    stereoSetup = true,
    itemPluralization = true,
  }
end

Story._fallbackFollower = { active = false }
Story._pluralize = pluralize

return Story
