package.path = "./?.lua;./?/init.lua;" .. package.path

local function blank(size)
  local out = {}
  for i = 1, size do out[i] = 0 end
  return out
end

local function put16(row, offset, value)
  row[offset + 1] = value % 256
  row[offset + 2] = math.floor(value / 256) % 256
end

local function put32(row, offset, value)
  put16(row, offset, value % 65536)
  put16(row, offset + 2, math.floor(value / 65536) % 65536)
end

local function bytes(row)
  return string.char(unpack(row))
end

local fragments = {}
local function fragment(offset, value) fragments[#fragments + 1] = { offset, value } end

local RAID_TABLE = 0x1134C34
local MAP_INDEX, STARS = 15, 1
local RAID_RECORD = 0x20000
local PARTNER_NAME = 0x40000
local PARTNER_SPREAD = 0x30000
local BASE_STATS = 0x50000

local descriptor = blank(8)
put32(descriptor, 0, 0x08000000 + RAID_RECORD)
put16(descriptor, 4, 1)
fragment(RAID_TABLE + (MAP_INDEX * 7 + STARS) * 8, bytes(descriptor))

local record = blank(30)
put16(record, 0, 127)
record[5] = 1 -- force ability slot one
put16(record, 6, 242)
put16(record, 8, 2)
fragment(RAID_RECORD, bytes(record))

fragment(0x1134176, string.char(1))
local partner = blank(60)
put16(partner, 0, 32)
partner[3], partner[4], partner[5] = 4, 5, 1
put32(partner, 8, 0x12345678)
put32(partner, 12, 0x08000000 + PARTNER_NAME)
put32(partner, 16 + STARS * 4, 0x08000000 + PARTNER_SPREAD)
put16(partner, 44 + STARS * 2, 1)
fragment(0x1134178, bytes(partner))
fragment(PARTNER_NAME, string.char(0xBD, 0xBB, 0xCE, 0xFF)) -- CAT

local spread = blank(28)
put16(spread, 0, 25)
spread[3], spread[4] = 3, 4
put32(spread, 4, 0x3FFFFFFF)
for i = 8, 13 do spread[i + 1] = 4 end
put16(spread, 14, 1)
put16(spread, 16, 33)
put16(spread, 18, 45)
put16(spread, 20, 0)
put16(spread, 22, 0)
spread[26] = 0x10
fragment(PARTNER_SPREAD, bytes(spread))
fragment(0x113B0D8, bytes(spread))

local ppUpType = blank(2)
put16(ppUpType, 0, 4)
fragment(0x115740C + 69 * 2, bytes(ppUpType))

local base127 = blank(28)
base127[1], base127[2], base127[3] = 45, 100, 45
base127[4], base127[5], base127[6] = 70, 60, 50
base127[23], base127[24], base127[27] = 10, 20, 30
fragment(BASE_STATS + 127 * 28, bytes(base127))
local base25 = blank(28)
base25[1], base25[2], base25[3] = 35, 55, 40
base25[4], base25[5], base25[6] = 90, 50, 50
base25[23], base25[24], base25[27] = 9, 31, 0
fragment(BASE_STATS + 25 * 28, bytes(base25))

local rom = {}
function rom:_read(offset, length)
  local out = blank(length)
  for _, f in ipairs(fragments) do
    local first = math.max(offset, f[1])
    local last = math.min(offset + length, f[1] + #f[2])
    for absolute = first, last - 1 do
      out[absolute - offset + 1] = f[2]:byte(absolute - f[1] + 1)
    end
  end
  return bytes(out)
end
function rom:pointerAt(slot)
  assert(slot == 0x1BC)
  return BASE_STATS, 0x08000000 + BASE_STATS
end

local session = {
  regionMapSectionId = 0x57 + MAP_INDEX,
  trainerId = 0xBEEF,
  secretId = 0x1234,
  dynamicWarp = { mapGroup = 1, mapNum = 2, warpId = 3, x = 4, y = 5 },
  party = { { species = 1, hp = 20, maxHp = 20, level = 15, moves = { 33 } } },
  bag = {},
}

local store = { vars = {}, flags = { [0x820] = true } }
package.loaded["src.core.game3.scripting.space"] = { store = store }

local Flags = {}
function Flags.getVar(s, ctx, id)
  if id >= 0x8000 and id <= 0x8014 then return (ctx.specialVars or {})[id] or 0 end
  if id < 0x4000 then return id end
  return (s.vars or {})[id] or 0
end
function Flags.setVar(s, ctx, id, value)
  if id >= 0x8000 and id <= 0x8014 then
    ctx.specialVars = ctx.specialVars or {}
    ctx.specialVars[id] = value % 0x10000
  else
    s.vars[id] = value % 0x10000
  end
end
function Flags.getFlag(s, _, id) return s.flags[id] == true end
function Flags.setFlag(s, _, id, on) s.flags[id] = on and true or nil end

local Pokemon = {}
function Pokemon.currentMapSec(s) return s.regionMapSectionId end
function Pokemon.name(id) return "MON_" .. id end
function Pokemon.natureId(pid) return pid % 25 end
function Pokemon.gender() return "M" end
function Pokemon.movesAtLevel()
  return { 33, 45 }, { 35, 40 }, { 35, 40 }
end
function Pokemon.movePp(id) return id == 45 and 40 or 35 end
function Pokemon.eggMoves() return nil end
function Pokemon.types() return { 0, 0 } end
function Pokemon.stats(species)
  if species == 127 then return { hp = 45, atk = 100, def = 45, spe = 70, spa = 60, spd = 50 } end
  return { hp = 35, atk = 55, def = 40, spe = 90, spa = 50, spd = 50 }
end
function Pokemon.applyStats(mon)
  local base = Pokemon.stats(mon.species)
  mon.maxHp = base.hp + mon.level
  mon.attack, mon.defense, mon.speed = base.atk, base.def, base.spe
  mon.spAtk, mon.spDef = base.spa, base.spd
  mon.atk, mon.def, mon.spe, mon.spa, mon.spd = mon.attack, mon.defense, mon.speed, mon.spAtk, mon.spDef
  mon.hp = mon.maxHp
  return mon
end

local Natives = { ALLOW = {}, B_OUTCOME = { WON = 1 } }
function Natives.outcome_to_code(result) return result == "win" and 1 or 2 end
function Natives.yieldHost(ctx, _, start)
  local finished = false
  start(function() finished = true end)
  return not finished
end

local ItemsData = {}
function ItemsData.toNumericId(id)
  if id == "WISHING_PIECE" then return 195 end
  return tonumber(id)
end
function ItemsData.pocketOf(id) return id == 2 and "POKE_BALLS" or "ITEMS" end
function ItemsData.displayName(id) return "ITEM_" .. id end
function ItemsData.fieldUseKind() return "none" end
function ItemsData.isBerry() return false end

local deps = {
  Natives = Natives, Flags = Flags, Pokemon = Pokemon,
  Party = { healAll = function() end },
  Bag = {
    has = function(bag, id, qty)
      return (tonumber(bag and bag[id]) or 0) >= (tonumber(qty) or 1)
    end,
    remove = function(bag, id, qty)
      qty = tonumber(qty) or 1
      local have = tonumber(bag and bag[id]) or 0
      if have < qty then return false end
      bag[id] = have - qty
      return true
    end,
  },
  ItemsData = ItemsData,
  Rng = { Random = function() return 0 end, Random32 = function() return 0 end },
  bit = require("bit"),
  getSession = function() return session end,
  raidRandomNumber = function() return 0 end,
  random16 = function() return 0 end,
  random32 = function() return 0 end,
  skipBattleHooks = true,
  skipCaptureUi = true,
}

local Raids = assert(loadfile("mods/radical_red_experience/lib/rr_raids.lua"))()
local report = Raids.install(nil, rom, deps)
assert(report.specialCallbacks == 8 and report.nativeCallbacks == 1 and report.romBacked)
assert(report.wishingPieceRespawn == true,
  "raid runtime did not advertise Wishing Piece den reactivation")

-- Source-matched combat thresholds and the v4.1 Max-move registry.
local combat = assert(Raids._combat)
assert(combat.koStatIncrease({}, { mon = { level = 19 } }) == 0)
assert(combat.koStatIncrease({}, { mon = { level = 40 } }) == 1)
assert(combat.koStatIncrease({}, { mon = { level = 70 } }) == 2)
assert(combat.koStatIncrease({}, { mon = { level = 71 } }) == 3)
assert(combat.repeatedAttackChance({ facility = true }, { mon = { level = 1 } }) == 70)
assert(combat.statNullificationChance({}, { mon = { level = 60 }, isFirstTurn = 1 }) == 0)
assert(combat.statNullificationChance({}, { mon = { level = 60 }, isFirstTurn = 0 }) == 35)
assert(combat.maxMoveFor({ category = "physical", type = 0, power = 40 }) == 902)
assert(combat.maxMoveFor({ category = "special", type = 23, power = 80 }) == 937)
assert(combat.maxMovePower(40, 0) == 90 and combat.maxMovePower(150, 0) == 150)
assert(combat.maxMovePower(40, 1) == 70 and combat.maxMovePower(150, 3) == 100)
assert(combat.shieldBreaksFor({ isMax = true }) == 2)
assert(combat.shieldBreaksFor({ isZ = true }) == 3)

local originalStats = Pokemon.stats
Pokemon.stats = function(species)
  if species == 999 then return { hp = 100, atk = 100, def = 100, spe = 100, spa = 100, spd = 100 } end
  return originalStats(species)
end
assert(combat.shieldCount(deps, 999, false) == 4)
assert(combat.shieldCount(deps, 999, true) == 5)
Pokemon.stats = originalStats

-- A Max/Brick Break-style hit removes two barrier segments, while a
-- multi-hit move still consumes segments only once for the whole action.
local battleState = {
  enemy = { side = "enemy", species = 999,
    mon = { hp = 300, maxHp = 400, level = 60 }, stages = {} },
  raid = {
    shieldsUp = true, shieldCount = 4, shieldsDestroyed = 0,
    currentMove = { serial = 1, isMax = true, effect = 0 },
  },
}
local messages = {}
local raidAdapter = {
  applyHpLoss = function(_, battler, amount)
    local lost = math.min(battler.mon.hp, math.max(0, math.floor(amount)))
    battler.mon.hp = battler.mon.hp - lost
    return lost
  end,
  emitFaint = function(_, battler) battler.fainted = true end,
  abilityOf = function(_, battler) return battler.ability end,
  isFainted = function(_, battler) return battler.fainted or battler.mon.hp <= 0 end,
  changeStages = function(_, battler, changes)
    local changed = {}
    for key, delta in pairs(changes) do
      battler.stages[key] = (battler.stages[key] or 0) + delta
      changed[key] = { delta = delta }
    end
    return changed
  end,
  roll = function() return 99 end,
  say = function(_, message) messages[#messages + 1] = message end,
}
Raids._decorateRaidAdapter(deps, raidAdapter, battleState)
raidAdapter:applyHpLoss(battleState.enemy, 100, { hit = true })
assert(battleState.raid.shieldsDestroyed == 2)
raidAdapter:applyHpLoss(battleState.enemy, 100, { hit = true })
assert(battleState.raid.shieldsDestroyed == 2)
battleState.raid.currentMove = { serial = 2, effect = 186 }
raidAdapter:applyHpLoss(battleState.enemy, 100, { hit = true })
assert(not battleState.raid.shieldsUp and battleState.raid.shieldsDestroyed == 4)
assert(messages[#messages] == "The mysterious barrier was broken!")

local ctx = { specialVars = {}, stringVars = {} }
local function var(id, value)
  if value ~= nil then Flags.setVar(store, ctx, id, value) end
  return Flags.getVar(store, ctx, id)
end
local function call(id, adapters)
  return assert(Natives.ALLOW["special:" .. id], ("missing special %03X"):format(id))(ctx, adapters)
end
local function callNative(address)
  return assert(Natives.ALLOW["native:" .. address],
    ("missing native %08X"):format(address))(ctx)
end

call(Raids.SPECIAL.AVAILABLE)
assert(var(0x800D) == 1)

local adapters = {
  openMessageStay = function(_, done) done() end,
  closeMessage = function() end,
  setStringVar = function(index, value) ctx.stringVars[index] = value end,
  multichoice = function(_, done) done(0) end,
  startWildBattle = function(foe, done)
    assert(foe.species == 127 and foe.level == 15 and foe.rrRaid)
    assert(foe.maxHp == (45 + 15) * 4)
    assert(#foe.partnerParty == 1 and foe.partnerParty[1].species == 25)
    done("win")
  end,
}

call(Raids.SPECIAL.INTRO, adapters)
assert(var(0x800D) == 1 and ctx.stringVars[1] == "CAT")
assert(store.flags[Raids.FLAG.TAG_BATTLE] == true)
call(Raids.SPECIAL.CREATE_MON)
assert(Raids._state.foe and Raids._state.foe.ivs.hp == 31)
call(Raids.SPECIAL.START_BATTLE, adapters)
assert(ctx.lastBattleOutcome == 1 and not store.flags[Raids.FLAG.RAID_BATTLE])

call(Raids.SPECIAL.ALL_DONE)
assert(var(0x800D) == 0)
call(Raids.SPECIAL.SET_DONE)
assert(store.flags[0x1800 + MAP_INDEX] == true)

-- A cleared den is empty until the player has a Wishing Piece. Merely checking
-- availability must not spend it; entering the raid flow spends exactly one,
-- clears the done flag, and advances RR's deterministic raid-number offset.
-- Feed the offset into the stable number so this proves the reroll itself,
-- rather than only checking that the variable changed.
deps.raidRandomNumber = function()
  return var(Raids.VAR.RAID_NUMBER_OFFSET)
end
session.bag[195] = 0
call(Raids.SPECIAL.AVAILABLE)
assert(var(0x800D) == 0, "a cleared den was available without a Wishing Piece")
session.bag[195] = 1
local beforeOffset = var(Raids.VAR.RAID_NUMBER_OFFSET)
local beforeStable = Raids._state.stable
call(Raids.SPECIAL.AVAILABLE)
assert(var(0x800D) == 1 and session.bag[195] == 1
    and var(Raids.VAR.RAID_NUMBER_OFFSET) == beforeOffset
    and Raids._state.stable == beforeStable,
  "checking a cleared den consumed or committed the Wishing Piece preview")
call(Raids.SPECIAL.INTRO, adapters)
local rerolledOffset = (beforeOffset + 1) % 0x10000
assert(session.bag[195] == 0
    and not store.flags[0x1800 + MAP_INDEX]
    and var(Raids.VAR.RAID_NUMBER_OFFSET) == rerolledOffset
    and Raids._state.stable == rerolledOffset,
  "Wishing Piece did not transactionally reroll and reactivate the den")

-- The 16-bit reroll counter wraps exactly, and AVAILABLE still remains a pure
-- preview at the boundary.
call(Raids.SPECIAL.SET_DONE)
assert(store.flags[0x1800 + MAP_INDEX] == true)
var(Raids.VAR.RAID_NUMBER_OFFSET, 0xFFFF)
session.bag[195] = 1
call(Raids.SPECIAL.AVAILABLE)
assert(var(0x800D) == 1 and session.bag[195] == 1
    and var(Raids.VAR.RAID_NUMBER_OFFSET) == 0xFFFF,
  "Wishing Piece availability committed the 16-bit offset wrap early")
call(Raids.SPECIAL.INTRO, adapters)
assert(session.bag[195] == 0
    and not store.flags[0x1800 + MAP_INDEX]
    and var(Raids.VAR.RAID_NUMBER_OFFSET) == 0
    and Raids._state.stable == 0,
  "Wishing Piece reroll did not wrap 0xFFFF -> 0")

-- A stale done flag on a map that cannot produce a raid must never advertise
-- or consume a Wishing Piece. This is the transactional failure case.
call(Raids.SPECIAL.SET_DONE)
local BAD_MAP_INDEX = MAP_INDEX + 1
session.regionMapSectionId = 0x57 + BAD_MAP_INDEX
store.flags[0x1800 + BAD_MAP_INDEX] = true
session.bag[195] = 1
var(Raids.VAR.RAID_NUMBER_OFFSET, 7)
call(Raids.SPECIAL.AVAILABLE)
assert(var(0x800D) == 0 and session.bag[195] == 1
    and var(Raids.VAR.RAID_NUMBER_OFFSET) == 7
    and store.flags[0x1800 + BAD_MAP_INDEX] == true,
  "invalid cleared den advertised or committed a Wishing Piece reroll")
call(Raids.SPECIAL.INTRO, adapters)
assert(var(0x800D) == 0 and session.bag[195] == 1
    and var(Raids.VAR.RAID_NUMBER_OFFSET) == 7
    and store.flags[0x1800 + BAD_MAP_INDEX] == true,
  "invalid cleared den consumed a Wishing Piece during INTRO")
store.flags[0x1800 + BAD_MAP_INDEX] = nil
session.regionMapSectionId = 0x57 + MAP_INDEX
session.bag[195] = 0

call(Raids.SPECIAL.ALL_DONE)
assert(var(0x800D) == 1)

var(0x4000, 0)
call(Raids.SPECIAL.REWARD)
assert(var(0x8000) == 242 and var(0x8001) == 1 and var(0x4000) == 1)
var(0x8000, 0)
call(Raids.SPECIAL.CLEAR_DONE)
assert(not store.flags[0x1800 + MAP_INDEX])

-- Restore the fixed facility fixture after the Wishing Piece tests above used
-- the live reroll offset as the stable raid number.
deps.raidRandomNumber = function() return 0 end

-- Battle-facility raids use the Frontier spread pools even if the map's raid
-- descriptor is absent.  This was the path that previously claimed a den was
-- available and then failed during the intro/create step.
store.flags[Raids.FLAG.BATTLE_FACILITY] = true
var(0x5016, 50)
callNative(Raids.ADDR.DETERMINE_STARS)
assert(Raids._state.stars == 5)
call(Raids.SPECIAL.AVAILABLE)
assert(var(0x800D) == 1 and Raids._state.current.facility)
call(Raids.SPECIAL.CREATE_MON)
assert(Raids._state.foe.species == 25 and Raids._state.foe.level == 50)
assert(Raids._state.foe.rrFacility and Raids._state.foe.maxHp == (35 + 50) * 4)
var(0x4000, 0)
call(Raids.SPECIAL.REWARD)
assert(var(0x8000) == 69 and var(0x8001) == 1)

print("PASS rr_raids_test: ROM raids, facility spreads, battle handoff, flags, and rewards")
