local romPath = assert(arg[1], "usage: lua tests/rr_battle_test.lua <radical-red-v4.1.gba>")
local handle = assert(io.open(romPath, "rb"))
local size = assert(handle:seek("end"))

local imports = {}
function imports:info(id)
  return { id = id, size = size, md5 = "8529f3a45d32bce4da637976fcf269d4" }
end
function imports:read(_, offset, length)
  assert(handle:seek("set", offset))
  return assert(handle:read(length))
end

local RR = assert(loadfile("lib/rr_rom.lua"))()
local Battle = assert(loadfile("lib/rr_battle.lua"))()
local rom = RR.open(imports, RR.IMPORT_ID)
rom:verify()

local Types = {
  ID = {}, NAME = {}, TABLE = {},
  isPhysical = function(typeId)
    typeId = tonumber(typeId) or 0
    return typeId >= 0 and typeId <= 8
  end,
  name = function(id) return "TYPE_" .. tostring(id) end,
}
Types.get = Types.name

function Types.typeCalc(attackType, defenseType1, defenseType2, damage, foresight)
  if defenseType2 == nil then defenseType2 = defenseType1 end
  local flags = { super = false, notVery = false, immune = false }
  local product = 1
  local function apply(multiplier)
    product = product * multiplier / 10
    if damage then damage = math.floor(damage * multiplier / 10) end
    if multiplier == 0 then flags.immune = true
    elseif multiplier == 5 then flags.notVery = true
    elseif multiplier == 20 then flags.super = true end
  end
  for i = 1, #Types.TABLE, 3 do
    local a, d, multiplier = Types.TABLE[i], Types.TABLE[i + 1], Types.TABLE[i + 2]
    if a == -1 then
      if foresight then break end
    elseif a == attackType then
      if d == defenseType1 then apply(multiplier) end
      if d == defenseType2 and defenseType2 ~= defenseType1 then apply(multiplier) end
    end
  end
  return damage, flags, product
end

local moveTypes = {
  [1] = 0, [14] = 0, [44] = 17, [52] = 10, [247] = 7,
}
local Moves = {}
function Moves.get(id)
  id = tonumber(id)
  return { id = "MOVE_" .. tostring(id), numId = id, type = moveTypes[id] or 0,
    power = id == 14 and 0 or 40 }
end

local Damage = {}
function Damage.base(_, _, move)
  return Types.isPhysical(move.type)
end
function Damage.calc(_, _, move)
  local physical = Types.isPhysical(move.type)
  return physical and 100 or 50, { physical = physical }
end

local Engine = {}
function Engine.resolveMove(user, _, moveId)
  if type(user) == "table" then
    moveId = user.expLockedMove or user.expEncoreMove or moveId
  end
  local move = Moves.get(moveId)
  return { physical = Types.isPhysical(move.type), category = move.category }
end
function Engine.resumeChoice(st)
  local move = st.pendingChoice.M.move
  return { physical = Types.isPhysical(move.type), category = move.category }
end

local State = {
  occupant = function(st, id) return st.battlers[id] end,
  displayName = function(ref) return ref.nickname or ref.name end,
}
local BattleText = {}
function BattleText.context(fill)
  return {
    battle = setmetatable({}, {
      __index = function(_, code)
        if code == 0x30 then return assert(fill.buff3) end
        if code == 0x10 then
          local defender = assert(fill.def,
            "battle text {B_DEF_NAME_WITH_PREFIX} needs fill.def")
          return defender.nickname or defender.name or tostring(defender)
        end
        error("battle text placeholder code " .. tostring(code) .. " is not a B_TXT id")
      end,
    }),
  }
end
local TextIR = { B_TXT = {} }
local activeEffect
local EffectCtx = { current = function() return activeEffect end }
local report = Battle.install(rom, {
  Types = Types, Moves = Moves, Damage = Damage, Engine = Engine, State = State,
  BattleText = BattleText, TextIR = TextIR, EffectCtx = EffectCtx,
})

assert(report.moveCategories == 1004)
assert(report.categoryCounts.physical == 435)
assert(report.categoryCounts.special == 305)
assert(report.categoryCounts.status == 264)
assert(report.expandedBattlePlaceholders == 3 and report.expTextPlaceholder)
local expCtx = BattleText.context({ buff3 = "69" })
assert(expCtx.battle[0x34] == "69", "CFRU B_BUFF3 did not resolve EXP")
assert(BattleText.context({ atk = "player" }).battle[0x38] == "Your")
assert(BattleText.context({ atk = "enemy" }).battle[0x38] == "Foe's")
assert(BattleText.context({ opponentMon1 = { nickname = "Sparky" } }).battle[0x3A]
  == "Sparky")
activeEffect = {
  user = { side = "player", nickname = "ROOSTER" },
  target = { side = "enemy", nickname = "WRONG TARGET" },
  move = { target = 16 },
}
assert(BattleText.context({}).battle[0x10] == "ROOSTER",
  "Roost did not recover B_DEF_NAME_WITH_PREFIX from the active self-target effect")
local explicitDef = { side = "enemy", nickname = "EXPLICIT" }
assert(BattleText.context({ def = explicitDef }).battle[0x10] == "EXPLICIT",
  "effect-context recovery replaced an explicitly supplied defender")
activeEffect = nil
assert(TextIR.B_TXT[0x34] == "B_BUFF3"
  and TextIR.B_TXT[0x38] == "B_ATK_TEAM2"
  and TextIR.B_TXT[0x3A] == "B_DEF_TEAM1")
assert(Types.ID.FAIRY == 23 and Types.name(23) == "FAIRY")
assert(Types.effectiveness(16, 23) == 0)
assert(Types.effectiveness(23, 16) == 2)
assert(Types.effectiveness(17, 8) == 1)
assert(Types.effectiveness(7, 8) == 1)
assert(Types.effectiveness(1, 23) == 0.5)
assert(Types.effectiveness(3, 23) == 2)

local normalGhostDamage, normalGhostFlags = Types.typeCalc(0, 7, 7, 100, false)
local foresightDamage, foresightFlags = Types.typeCalc(0, 7, 7, 100, true)
assert(normalGhostDamage == 0 and normalGhostFlags.immune)
assert(foresightDamage == 100 and not foresightFlags.immune)

assert(Moves.get(44).category == "physical")
assert(Moves.get(52).category == "special")
assert(Moves.get(247).category == "special")
assert(Moves.get(14).category == "status")

local bite = Moves.get(44)
local shadowBall = Moves.get(247)
assert(Damage.base({}, {}, bite) == true,
  "Dark-type Bite must use physical stats")
local _, shadowInfo = Damage.calc({}, {}, shadowBall)
assert(shadowInfo.physical == false,
  "Ghost-type Shadow Ball must use special stats")
assert(Types.isPhysical(7) == true,
  "category context must be popped after a wrapped calculation")

assert(Engine.resolveMove({}, nil, 44).physical == true)
assert(Engine.resolveMove({}, nil, 247).physical == false)
assert(Engine.resolveMove({ expLockedMove = 247 }, nil, 44).physical == false)
assert(Engine.resolveMove({ expEncoreMove = 44, expEncoreTurns = 2 }, nil, 247).physical == true)

local numericState = { battlers = { [0] = { expLockedMove = 247 } } }
assert(Engine.resolveMove(0, nil, 44, nil, nil, numericState).physical == false)

local pending = { pendingChoice = { M = { move = Moves.get(247) } } }
assert(Engine.resumeChoice(pending).physical == false)

-- A second install refreshes private-ROM data without wrapping functions twice.
assert(Battle.install(rom, {
  Types = Types, Moves = Moves, Damage = Damage, Engine = Engine, State = State,
  BattleText = BattleText, TextIR = TextIR,
}).fairyTypeId == 23)
assert(Damage.base({}, {}, bite) == true)

handle:close()
print("PASS rr_battle_test: exact RR split and Fairy chart drive runtime wrappers")
