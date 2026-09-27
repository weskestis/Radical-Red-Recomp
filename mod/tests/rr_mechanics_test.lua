package.path = "./?.lua;./?/init.lua;" .. package.path

local function u16Bytes(values)
  local out = {}
  for _, value in ipairs(values) do
    out[#out + 1] = string.char(value % 256, math.floor(value / 256) % 256)
  end
  return table.concat(out)
end

local caps = {
  15, 22, 27, 34, 44, 47, 56, 57, 59, 68, 73, 76, 79, 80, 81, 82, 85, 100,
  16, 23, 28, 36, 44, 47, 56, 57, 59, 68, 73, 76, 79, 80, 81, 82, 85, 100,
}
local eggPool = { 1283, 1282, 1276, 1287, 1274, 1278, 1285, 1289, 1292, 1294, 866, 1200 }
local randomPool, categoryPool = {}, {}
for i = 1, 330 do randomPool[i] = 200 + i end
for i = 1, 68 do categoryPool[i] = 600 + i end

local romData = {
  [0x135013C] = string.char(unpack(caps)),
  [0x11636D0] = u16Bytes(eggPool),
  [0x1165E1A] = u16Bytes(randomPool),
  [0x1163246] = u16Bytes(categoryPool),
}
local rom = {}
function rom:_read(offset, length)
  local bytes = assert(romData[offset], ("unexpected ROM read 0x%X"):format(offset))
  assert(#bytes >= length)
  return bytes:sub(1, length)
end

local session = {
  party = {
    {
      species = 1, speciesId = 1, name = "Bulbasaur", nickname = "BULB",
      personality = 200, level = 5, growthRate = 0, exp = 125,
      hp = 1, maxHp = 20, ability = 10, abilityId = 10,
      moves = { { id = 33, pp = 1, maxPp = 35 } },
    },
    { species = 152, level = 5, hp = 0, maxHp = 20 },
  },
}

local store = { vars = {}, flags = {} }
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

local Pokemon = {}
function Pokemon.isEgg(mon) return mon and mon.isEgg == true end
function Pokemon.isShiny(mon) return mon and mon.isShiny == true end
function Pokemon.stats(species)
  if species == 1 then return { hp = 45, atk = 130, def = 49, spe = 45, spa = 65, spd = 65 } end
  return { hp = 50, atk = 50, def = 50, spe = 50, spa = 50, spd = 50 }
end
function Pokemon.types(species) return species == 999 and { 23, 0 } or { 12, 3 } end
function Pokemon.gender(_, pid) return pid % 256 < 128 and "F" or "M" end
function Pokemon.growthRate() return 0 end
function Pokemon.applyStats(mon) mon.maxHp = 10 + mon.level; mon._applied = true end
function Pokemon.abilities() return { 10, 20 } end
function Pokemon.abilityId(_, pid) return pid % 2 == 1 and 20 or 10 end
function Pokemon.abilityName(id) return "ABILITY_" .. id end
function Pokemon.name(id) return "SPECIES_" .. id end

local givenEggs = {}
local Party = {}
function Party.giveEggToPlayer(s, species)
  givenEggs[#givenEggs + 1] = species
  return 0, { species = species, isEgg = true }
end

local Storage = {}
function Storage.ensure(s) return s.storage end
function Storage.getBoxMon(s, box, slot) return s.boxes[box].mons[slot] end
function Storage.fullHealMon(mon)
  if mon then mon.hp = mon.maxHp; mon.status = nil end
  return mon
end

local SummaryData = {}
function SummaryData.expForLevel(_, level) return level * level * level end

local Natives = { ALLOW = {} }
local nextRandom = 0
local deps = {
  Natives = Natives,
  Flags = Flags,
  Pokemon = Pokemon,
  Party = Party,
  Storage = Storage,
  SummaryData = SummaryData,
  Rng = {},
  getSession = function() return session end,
  randomIndex = function(count)
    local value = nextRandom % count
    nextRandom = nextRandom + 1
    return value
  end,
}

local Mechanics = assert(loadfile("lib/rr_mechanics.lua"))()
local report = Mechanics.install(nil, rom, deps)
assert(report.nativeCallbacks == 22)

local ctx = { specialVars = {}, stringVars = {} }
local function var(id, value)
  if value ~= nil then Flags.setVar(store, ctx, id, value) end
  return Flags.getVar(store, ctx, id)
end
local function call(address, adapters)
  return assert(Natives.ALLOW["native:" .. address], ("missing native %08X"):format(address))(ctx, adapters)
end

var(0x8004, 0)
call(Mechanics.ADDR.SET_TO_LEVEL_CAP)
assert(session.party[1].level == 15 and session.party[1].exp == 3375)
assert(var(0x800D) == 1)
call(Mechanics.ADDR.SET_TO_LEVEL_CAP)
assert(var(0x800D) == 0)

store.flags[0x991], store.flags[0x827] = true, true
store.flags[0x1034], store.flags[0x1033] = true, true
call(Mechanics.ADDR.BUFFER_LEVEL_CAP)
assert(ctx.stringVars[1] == "31", "RR restricted cap plus three")

call(Mechanics.ADDR.GIVE_RANDOM_EGG)
assert(givenEggs[1] == eggPool[1] and store.vars[0x514A] == eggPool[1])
call(Mechanics.ADDR.GIVE_DIFFERENT_RANDOM_EGG)
assert(givenEggs[2] ~= givenEggs[1])

call(Mechanics.ADDR.BUILD_RANDOM_STARTERS)
local seen = {}
for id = 0x5142, 0x5147 do
  assert(store.vars[id] and not seen[store.vars[id]])
  seen[store.vars[id]] = true
end
store.vars[0x5140] = 0
call(Mechanics.ADDR.BUILD_CATEGORY_STARTERS)
for id = 0x5142, 0x5147 do assert(store.vars[id] >= 601 and store.vars[id] <= 668) end

call(Mechanics.ADDR.CHECK_ATTACK)
assert(var(0x800D) == 1)
call(Mechanics.ADDR.CHECK_SPEED)
assert(var(0x800D) == 0)
call(Mechanics.ADDR.CHECK_STARTERS_ONLY)
assert(var(0x800D) == 1)
call(Mechanics.ADDR.CHECK_ONE_USABLE_MON)
assert(var(0x800D) == 1)

session.party[1].species, session.party[1].speciesId = 999, 999
call(Mechanics.ADDR.CHECK_NO_FAIRY)
assert(var(0x800D) == 0)

session.party[1].species, session.party[1].speciesId = 346, 346
session.party[1].gender, session.party[1].personality = "M", 200
call(Mechanics.ADDR.CHECK_GENDER_CHANGE)
assert(var(0x800D) == 1 and ctx.stringVars[1] == "Female")
call(Mechanics.ADDR.CHANGE_GENDER)
assert(session.party[1].gender == "F" and session.party[1].personality % 25 == 0)

-- Regression from device: selecting a Combee in party slot two must inspect
-- and mutate that slot, not silently fall back to the first party member.
session.party[2].species, session.party[2].speciesId = 468, 468
session.party[2].name = "Combee"
session.party[2].gender, session.party[2].personality = "M", 200
var(0x8004, 1)
call(Mechanics.ADDR.CHECK_GENDER_CHANGE)
assert(var(0x800D) == 1 and ctx.stringVars[1] == "Female",
  "slot-two Combee was rejected by the gender changer")
call(Mechanics.ADDR.CHANGE_GENDER)
assert(session.party[2].gender == "F" and session.party[2].personality % 25 == 0,
  "slot-two Combee gender was not changed")

-- A converted save can temporarily carry the National id while preserving
-- the correct display name.  The compatibility fallback must accept it too.
session.party[2].species, session.party[2].speciesId = 415, 415
session.party[2].name, session.party[2].gender = "Combee", "M"
call(Mechanics.ADDR.CHECK_GENDER_CHANGE)
assert(var(0x800D) == 1,
  "converted-save Combee name fallback was rejected")

var(0x8004, 0)

session.party[1].ability, session.party[1].abilityId = 10, 10
call(Mechanics.ADDR.CHECK_ABILITY_SWAP)
assert(var(0x800D) == 1 and ctx.stringVars[2] == "ABILITY_20")
call(Mechanics.ADDR.SWAP_ABILITY)
assert(session.party[1].abilityId == 20 and session.party[1].personality % 25 == 0)

session.party[1].species, session.party[1].speciesId = 410, 410
call(Mechanics.ADDR.CHECK_DEOXYS)
assert(var(0x800D) == 1)
store.vars[0x5142] = 1041
call(Mechanics.ADDR.CHANGE_DEOXYS_FORM)
assert(session.party[1].species == 1041 and var(0x800D) == 0)
call(Mechanics.ADDR.CHECK_PARTY_DEOXYS)
assert(var(0x800D) == 2)

session.party[1].hp, session.party[1].maxHp = 1, 42
call(Mechanics.ADDR.HEAL_CHOSEN_MON)
assert(session.party[1].hp == 42)

print("PASS rr_mechanics_test: RR pools, caps, validators, Combee, forms, and party mutations")
