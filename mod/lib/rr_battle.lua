-- Radical Red battle-model compatibility installed entirely from a mod.
--
-- Stock gen1recomp derives physical/special from a move's type and ships the
-- Gen III type chart. Radical Red stores a per-move split and a dense modern
-- chart in the player's private ROM. This module wraps the stock Lua battle
-- modules at runtime; it never edits or replaces launcher/engine files.

local Battle = {}
local unpackValues = table.unpack or unpack
local installations = setmetatable({}, { __mode = "k" })
local textInstallations = setmetatable({}, { __mode = "k" })

local function pack(...)
  return { n = select("#", ...), ... }
end

local function copy(record)
  local out = {}
  for key, value in pairs(record or {}) do out[key] = value end
  return out
end

local function scoped(state, category, fn, ...)
  if category ~= "physical" and category ~= "special" and category ~= "status" then
    return fn(...)
  end
  local stack = state.categoryStack
  stack[#stack + 1] = category
  local result = pack(pcall(fn, ...))
  stack[#stack] = nil
  if not result[1] then error(result[2], 0) end
  return unpackValues(result, 2, result.n)
end

local function flattenChart(rows, typeCount)
  local main, foresight = {}, {}
  local function append(into, attackType, defenseType, multiplier)
    into[#into + 1] = attackType
    into[#into + 1] = defenseType
    into[#into + 1] = multiplier
  end
  for attackType = 0, typeCount - 1 do
    for defenseType = 0, typeCount - 1 do
      local multiplier = rows[attackType][defenseType]
      if multiplier ~= 10 then
        -- Foresight only removes Normal/Fighting immunity against Ghost. The
        -- stock TypeCalc recognizes entries after its -1 sentinel as that
        -- special portion of the chart.
        local isForesightImmunity = defenseType == 7
          and (attackType == 0 or attackType == 1)
        append(isForesightImmunity and foresight or main,
          attackType, defenseType, multiplier)
      end
    end
  end
  append(main, -1, -1, 0)
  for i = 1, #foresight do main[#main + 1] = foresight[i] end
  return main
end

local function categoryFromMove(move)
  if type(move) ~= "table" then return nil end
  local category = move.category
  if category == 0 then return "physical" end
  if category == 1 then return "special" end
  if category == 2 then return "status" end
  return category
end

local function effectiveUser(State, user, st)
  if type(user) == "table" or not st or not State or not State.occupant then
    return user
  end
  local ok, battler = pcall(State.occupant, st, user)
  return ok and battler or user
end

local function effectiveMoveId(State, user, moveId, st, opts)
  opts = opts or {}
  user = effectiveUser(State, user, st)
  if not opts.called and type(user) == "table" then
    if user.expLockedMove and not opts.pursuitSwitch then
      return user.expLockedMove
    end
    if user.expEncoreMove and (user.expEncoreTurns or 0) > 0 then
      return user.expEncoreMove
    end
  end
  return moveId
end

local function defaults()
  return {
    Types = require("src.core.game3.battle.types"),
    Moves = require("src.core.game3.battle.moves"),
    Damage = require("src.core.game3.battle.damage"),
    Engine = require("src.core.game3.battle.engine"),
    State = require("src.core.game3.battle.state"),
  }
end

local function battleSide(ref)
  if type(ref) == "table" then return ref.side end
  return ref
end

local function isPlayerSide(ref)
  ref = battleSide(ref)
  return ref == "player" or ref == 0
end

local function displayName(State, ref)
  if type(ref) == "string" then return ref end
  if type(ref) == "table" then
    if ref.nickname and ref.nickname ~= "" then return ref.nickname end
    if ref.name and ref.name ~= "" then return ref.name end
  end
  if State and State.displayName then return State.displayName(ref) end
  return tostring(ref or "")
end

-- CFRU/Radical Red uses the expanded Emerald battle-placeholder layout. The
-- stock FireRed host stops at B_BUFF3=0x30, while this ROM contains 0x34,
-- 0x38, and 0x3A. Wrap the public context instead of editing the engine so
-- cached and freshly extracted text share the same compatibility path.
local function installBattleTextCompat(BattleText, TextIR, State, EffectCtx)
  if not (BattleText and type(BattleText.context) == "function") then return 0 end
  local state = textInstallations[BattleText]
  if not state then
    state = { originalContext = BattleText.context }
    textInstallations[BattleText] = state
    BattleText.context = function(fill)
      fill = fill or {}
      -- CFRU has a few move-effect paths whose text relies on the live
      -- attacker/defender globals instead of explicitly passing both values.
      -- The stock host deliberately requires an explicit fill table.  Bridge
      -- that difference while an effect is active, but never replace a value
      -- a normal engine caller supplied.  Roost's recovered-health text is the
      -- first visible example: it expands B_DEF_NAME_WITH_PREFIX.
      if fill.def == nil and EffectCtx and type(EffectCtx.current) == "function" then
        local active = EffectCtx.current()
        if active then
          local moveTarget = tonumber(active.move and active.move.target)
          fill.def = (moveTarget == 16 and active.user)
            or active.target or active.user
        end
      end
      local ctx = state.originalContext(fill)
      local stock = ctx.battle
      ctx.battle = setmetatable({}, {
        __index = function(values, code)
          local value
          if code == 0x34 then -- B_BUFF3
            value = fill.buff3
            if value == nil then
              error("battle text {B_BUFF3} needs fill.buff3", 0)
            end
          elseif code == 0x38 then -- B_ATK_TEAM2
            local attacker = fill.atk
            if attacker == nil then
              error("battle text {B_ATK_TEAM2} needs fill.atk", 0)
            end
            value = isPlayerSide(attacker) and "Your" or "Foe's"
          elseif code == 0x3A then -- B_DEF_TEAM1
            local defender = fill.opponentMon1 or fill.def
            if defender == nil then
              error("battle text {B_DEF_TEAM1} needs fill.opponentMon1 or fill.def", 0)
            end
            value = displayName(State, defender)
          else
            value = stock[code]
          end
          rawset(values, code, value)
          return value
        end,
      })
      return ctx
    end
  end
  if TextIR and type(TextIR.B_TXT) == "table" then
    TextIR.B_TXT[0x34] = "B_BUFF3"
    TextIR.B_TXT[0x38] = "B_ATK_TEAM2"
    TextIR.B_TXT[0x3A] = "B_DEF_TEAM1"
  end
  return 3
end

function Battle.install(rom, deps)
  assert(type(rom) == "table" and type(rom.move) == "function"
      and type(rom.typeChartRows) == "function",
    "Radical Red battle install requires a verified ROM reader")
  deps = deps or defaults()
  local Types = assert(deps.Types, "missing Types module")
  local Moves = assert(deps.Moves, "missing Moves module")
  local Damage = assert(deps.Damage, "missing Damage module")
  local Engine = assert(deps.Engine, "missing Engine module")
  local State = deps.State
  local BattleText = deps.BattleText
  local TextIR = deps.TextIR
  local EffectCtx = deps.EffectCtx
  if BattleText == nil then
    local ok, module = pcall(require, "src.core.game3.battle.battle_text")
    if ok then BattleText = module end
  end
  if TextIR == nil then
    local ok, module = pcall(require, "src.core.game3.scripting.text_ir")
    if ok then TextIR = module end
  end
  if EffectCtx == nil then
    local ok, module = pcall(require, "src.core.game3.battle.effect_ctx")
    if ok then EffectCtx = module end
  end
  local placeholderCount = installBattleTextCompat(
    BattleText, TextIR, State, EffectCtx)

  local state = installations[Types]
  if not state then
    state = {
      categoryStack = {},
      categories = {},
      originalIsPhysical = assert(Types.isPhysical),
      originalTypeName = assert(Types.name),
      originalTypeGet = Types.get,
      originalMovesGet = assert(Moves.get),
      originalDamageBase = assert(Damage.base),
      originalDamageCalc = assert(Damage.calc),
      originalResolveMove = assert(Engine.resolveMove),
      originalResumeChoice = assert(Engine.resumeChoice),
    }
    installations[Types] = state

    Types.isPhysical = function(typeId)
      local category = state.categoryStack[#state.categoryStack]
      if category == "physical" then return true end
      if category == "special" or category == "status" then return false end
      return state.originalIsPhysical(typeId)
    end

    Types.name = function(id)
      local custom = state.typeNames[tonumber(id)]
      if custom then return custom end
      return state.originalTypeName(id)
    end
    Types.get = function(id)
      return Types.name(id)
    end

    Moves.get = function(moveId)
      local move = state.originalMovesGet(moveId)
      local out = copy(move)
      local index = tonumber(out.numId)
      if index and state.categories[index] then
        out.category = state.categories[index]
      end
      return out
    end

    Damage.base = function(attacker, defender, move, opts)
      return scoped(state, categoryFromMove(move), state.originalDamageBase,
        attacker, defender, move, opts)
    end
    Damage.calc = function(attacker, defender, move, opts)
      return scoped(state, categoryFromMove(move), state.originalDamageCalc,
        attacker, defender, move, opts)
    end

    local function categoryForId(moveId)
      local ok, move = pcall(Moves.get, moveId)
      return ok and categoryFromMove(move) or nil
    end

    Engine.resolveMove = function(user, target, moveId, slot, adapter, st, out, opts)
      local resolvedId = effectiveMoveId(State, user, moveId, st, opts)
      return scoped(state, categoryForId(resolvedId), state.originalResolveMove,
        user, target, moveId, slot, adapter, st, out, opts)
    end
    Engine.resumeChoice = function(st, adapter, value)
      local pending = st and st.pendingChoice
      local category = pending and pending.M and categoryFromMove(pending.M.move)
      return scoped(state, category, state.originalResumeChoice, st, adapter, value)
    end
  end

  state.rom = rom
  state.typeNames = {
    [19] = "ROOSTLESS",
    [20] = "BLANK",
    [23] = "FAIRY",
  }
  state.chart = rom:typeChartRows()
  state.categories = {}
  local categoryCounts = { physical = 0, special = 0, status = 0 }
  local moveCount = 355
  if type(rom.moveCount) == "function" then
    moveCount = assert(tonumber(rom:moveCount()), "invalid Radical Red move count")
  end
  for moveId = 0, moveCount - 1 do
    local category = rom:move(moveId).category
    state.categories[moveId] = category
    categoryCounts[category] = categoryCounts[category] + 1
  end

  Types.ID.ROOSTLESS = 19
  Types.ID.BLANK = 20
  Types.ID.FAIRY = 23
  if type(Types.NAME) == "table" then
    for id, name in pairs(state.typeNames) do Types.NAME[id] = name end
  end
  Types.TABLE = flattenChart(state.chart, 24)
  Types.effectiveness = function(attackType, defenseType1, defenseType2)
    attackType = tonumber(attackType) or 0
    defenseType1 = tonumber(defenseType1) or 0
    defenseType2 = tonumber(defenseType2)
    local row = state.chart[attackType]
    local first = (row and row[defenseType1]) or 10
    local second = 10
    if defenseType2 and defenseType2 ~= defenseType1 then
      second = (row and row[defenseType2]) or 10
    end
    return (first * second) / 100
  end

  return {
    moveCategories = moveCount,
    categoryCounts = categoryCounts,
    typeCount = 24,
    fairyTypeId = 23,
    expandedBattlePlaceholders = placeholderCount,
    expTextPlaceholder = placeholderCount > 0,
  }
end

return Battle
