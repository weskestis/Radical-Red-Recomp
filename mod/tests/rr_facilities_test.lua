package.path = "./?.lua;./?/init.lua;" .. package.path

local function blank(size)
  local row = {}
  for i = 1, size do row[i] = 0 end
  return row
end

local function put16(row, offset, value)
  row[offset + 1] = value % 256
  row[offset + 2] = math.floor(value / 256) % 256
end

local function put32(row, offset, value)
  put16(row, offset, value % 65536)
  put16(row, offset + 2, math.floor(value / 65536) % 65536)
end

local function bytes(row) return string.char(unpack(row)) end

local fragments = {}
local function fragment(offset, value) fragments[#fragments + 1] = { offset, value } end

local SPECIAL_POOL = 0x22000
local NAME_0, NAME_1, INTRO = 0x23000, 0x23100, 0x23200
local BASE_STATS = 0x24000
local RENTAL_POOL = 0x25000

fragment(0x114A5BC, string.char(2, 0))
fragment(0x114A5BE, string.char(2, 0))
fragment(0x1151ABC, string.char(1, 0))
fragment(0x1151ABE, string.char(1, 0))

local femalePtr, malePtr = blank(4), blank(4)
put32(femalePtr, 0, 0x08000000 + NAME_0)
put32(malePtr, 0, 0x08000000 + NAME_1)
fragment(0x1151AC0, bytes(femalePtr))
fragment(0x1151C50, bytes(malePtr))
fragment(NAME_0, string.char(0xBB, 0xC6, 0xCD, 0xFF)) -- ALS
fragment(NAME_1, string.char(0xBC, 0xC9, 0xBC, 0xFF)) -- BOB
fragment(INTRO, string.char(0xCC, 0xBF, 0xBB, 0xBE, 0xD3, 0xFE,
  0xCA, 0xCC, 0xBF, 0xCA, 0xBB, 0xCC, 0xBF, 0xBE, 0xAD, 0xFF))

local regular = blank(20)
put16(regular, 0, 55)
regular[3], regular[4], regular[5] = 4, 5, 0
put32(regular, 8, 0x08000000 + INTRO)
put32(regular, 12, 0x08000000 + INTRO)
put32(regular, 16, 0x08000000 + INTRO)
fragment(0x114AB3C, bytes(regular) .. bytes(regular))

local function specialRecord(monotype, namePtr)
  local row = blank(52)
  put16(row, 0, 77)
  row[3], row[4], row[5], row[6] = 8, 9, 1, monotype and 1 or 0
  put32(row, 8, 0x08000000 + namePtr)
  put32(row, 12, 0x08000000 + INTRO)
  put32(row, 16, 0x08000000 + INTRO)
  put32(row, 20, 0x08000000 + INTRO)
  put32(row, 24, 0x08000000 + SPECIAL_POOL)
  put16(row, 40, 6)
  put16(row, 48, 300)
  return bytes(row)
end
fragment(0x114A8CC, specialRecord(false, NAME_0) .. specialRecord(true, NAME_1))
fragment(0x114A72C, specialRecord(true, NAME_1))

local function spread(species, level)
  local row = blank(28)
  put16(row, 0, species)
  row[3], row[4] = species % 25, 4
  put32(row, 4, 0x3FFFFFFF)
  row[9], row[10], row[11], row[12], row[13], row[14] = 4, 8, 12, 16, 20, 24
  put16(row, 14, 100 + species)
  put16(row, 16, 33)
  put16(row, 18, 45)
  row[26] = 0x16 -- singles + doubles + ability slot one
  row[27] = level or 50
  return bytes(row)
end

local pool = {}
for i = 1, 6 do pool[#pool + 1] = spread(100 + i, 70 + i) end
fragment(SPECIAL_POOL, table.concat(pool))
fragment(0x112C860, table.concat(pool))
fragment(0x112C908, table.concat(pool))
fragment(RENTAL_POOL, table.concat(pool))

local pointerRow = blank(4)
put32(pointerRow, 0, 0x08000000 + RENTAL_POOL)
fragment(0x1124D00 + 36, bytes(pointerRow))
fragment(0x1124D00 + 156, bytes(pointerRow))

local sim = blank(51 * 4)
for i = 0, 50 do put32(sim, i * 4, 48 + i) end
fragment(0x134E858, bytes(sim))

for species = 101, 106 do
  local row = blank(28)
  row[1], row[2], row[3], row[4], row[5], row[6] = 50, 60, 50, 60, 70, 50
  row[23], row[24], row[27] = 10, 20, 30
  fragment(BASE_STATS + species * 28, bytes(row))
end

local rom = {}
function rom:_read(offset, length)
  local out = blank(length)
  for _, part in ipairs(fragments) do
    local first = math.max(offset, part[1])
    local last = math.min(offset + length, part[1] + #part[2])
    for absolute = first, last - 1 do
      out[absolute - offset + 1] = part[2]:byte(absolute - part[1] + 1)
    end
  end
  return bytes(out)
end
function rom:pointerAt(slot)
  assert(slot == 0x1BC)
  return BASE_STATS, 0x08000000 + BASE_STATS
end

local originalParty = { { species = 1, speciesId = 1, level = 10, hp = 25, maxHp = 25 } }
local session = { name = "RED", trainerId = 123, party = originalParty }
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

local Pokemon = { NUMBERING_INTERNAL = "internal" }
function Pokemon.name(id) return "MON_" .. id end
function Pokemon.gender() return "M" end
function Pokemon.growthRate() return 0 end
function Pokemon.movePp(id) return id == 33 and 35 or 40 end
function Pokemon.applyStats(mon)
  mon.maxHp = mon.level + 50
  mon.hp = mon.maxHp
  return mon
end

local function deepCopy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, child in pairs(value) do out[key] = deepCopy(child) end
  return out
end

local Tower = {}
function Tower.savePlayerParty(s)
  s.savedPlayerParty = deepCopy(s.party)
  return s.savedPlayerParty
end
function Tower.loadPlayerParty(s)
  s.party = deepCopy(s.savedPlayerParty)
  return s.party
end

local Trainers = {}
function Trainers.pack() return { classNames = { [8] = "ACE TRAINER" } } end
function Trainers.get() return nil end
function Trainers.foeFromId() return nil end
function Trainers.info() return nil end
function Trainers.dialogs() return {} end
function Trainers.getEncounterMusic() return 285 end

local Natives = { ALLOW = {} }
Natives.ALLOW["special:39"] = function() Tower.savePlayerParty(session); return false end
Natives.ALLOW["special:40"] = function() Tower.loadPlayerParty(session); return false end

local function decodePlain(raw)
  local out = {}
  for i = 1, #raw do
    local b = raw:byte(i)
    if b == 0xFF then break end
    if b == 0 then out[#out + 1] = " "
    elseif b == 0xFE then out[#out + 1] = "\n"
    elseif b >= 0xBB and b <= 0xD4 then out[#out + 1] = string.char(65 + b - 0xBB)
    elseif b >= 0xD5 and b <= 0xEE then out[#out + 1] = string.char(97 + b - 0xD5)
    elseif b == 0xAD then out[#out + 1] = "." end
  end
  return table.concat(out)
end

local TextIR = {}
function TextIR.decode(raw) return raw end
function TextIR.toPlain(raw) return decodePlain(raw) end
local RomText = { overrides = {} }

local randomValues, randomCursor = { 0, 1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }, 0
local function random16()
  randomCursor = randomCursor + 1
  return randomValues[randomCursor] or (randomCursor - 1)
end

local events, hook
local mod = {
  events = { on = function(_, name, callback) events[name] = callback end },
  hooks = { wrap = function(_, name, callback) assert(name == "script.command"); hook = callback end },
  log = { info = function() end },
}
events = {}

local deps = {
  Natives = Natives, Flags = Flags, Pokemon = Pokemon, Tower = Tower,
  Trainers = Trainers, TextIR = TextIR, RomText = RomText,
  SummaryData = { expForLevel = function(_, level) return level ^ 3 end },
  Rng = {}, getSession = function() return session end,
  random16 = random16, random32 = function() return 123456 end,
}

local Facilities = assert(loadfile("mods/radical_red_experience/lib/rr_facilities.lua"))()
local report = Facilities.install(mod, rom, deps)
assert(report.specialCallbacks == 2 and report.nativeCallbacks == 10)
assert(report.romTrainerTables and report.rentalParties and report.partyRestore)

local ctx = { specialVars = {}, stringVars = {}, data = {} }
local function var(id, value)
  if value ~= nil then Flags.setVar(store, ctx, id, value) end
  return Flags.getVar(store, ctx, id)
end
local function special(id, adapters)
  return assert(Natives.ALLOW["special:" .. id])(ctx, adapters)
end
local function native(address)
  return assert(Natives.ALLOW["native:" .. address])(ctx)
end

var(0x5015, 6)
var(0x5016, 100)
var(0x5017, 0)
var(0x5018, 6)
var(0x8000, 0)
var(0x8001, 1)
local _, ow = special(Facilities.SPECIAL.GENERATE_TRAINER)
assert(ow == 77 and store.vars[0x501C] == 1 and ctx.stringVars[1] == "BOB")
special(Facilities.SPECIAL.LOAD_INTRO)
assert(type(ctx.data[0]) == "string" and RomText.overrides[ctx.data[0]])
assert(var(0x8012) == 1)

local foe = Trainers.foeFromId(Facilities.TRAINER.SPECIAL)
assert(foe and foe.rrFacility and #foe.party == 6)
local seen = {}
for _, mon in ipairs(foe.party) do
  assert(mon.level == 100 and mon.moves[1] == 33 and mon.heldItem)
  assert(not seen[mon.species]); seen[mon.species] = true
end
assert(Trainers.info(Facilities.TRAINER.SPECIAL).name == "BOB")
assert(Trainers.dialogs(Facilities.TRAINER.SPECIAL).intro:find("READY", 1, true))

-- Random singles (type 4) must stay singles, while a doubles mode rebuilds
-- the cached definition with doubles-eligible spreads.
local singlesDefinition = Trainers.get(Facilities.TRAINER.SPECIAL)
var(0x5017, 4)
local randomSinglesDefinition = Trainers.get(Facilities.TRAINER.SPECIAL)
assert(randomSinglesDefinition ~= singlesDefinition and not randomSinglesDefinition.doubleBattle)
var(0x5017, 1)
local doublesDefinition = Trainers.get(Facilities.TRAINER.SPECIAL)
assert(doublesDefinition ~= randomSinglesDefinition and doublesDefinition.doubleBattle)
var(0x5017, 0)

-- Save the real party, mount a six-mon rental party, then restore at battle end.
Natives.ALLOW["special:39"](ctx)
var(0x512B, 6)
native(Facilities.ADDR.FIXED_PARTY)
assert(#session.party == 6 and session.party[1].species == 101)
assert(session.rrFacilityPartyBackup)
events["battle.ended"]()
assert(#session.party == 1 and session.party[1].species == 1)
assert(not session.rrFacilityPartyBackup)

var(0x5127, 0)
native(Facilities.ADDR.RENTAL_PARTY_A)
assert(#session.party == 6 and session.party[6].level == 76)
events["script.ended"]()
assert(session.party[1].species == 1)

native(Facilities.ADDR.ROLL_THREE)
assert(store.vars[0x5140] ~= store.vars[0x5142]
  and store.vars[0x5142] ~= store.vars[0x5143])

store.vars[0x5134], store.vars[0x5135], store.vars[0x5136] = 2, 6, 7
native(Facilities.ADDR.SIMULATOR_COMPARE)
assert(var(0x800D) == 1)
store.flags[0x1066] = true
native(Facilities.ADDR.SIMULATOR_COMPARE)
assert(var(0x800D) == 0)
store.flags[0x1065] = true
store.vars[0x5135] = 8
native(Facilities.ADDR.SIMULATOR_TARGET)
assert(var(0x800D) == 1)
store.vars[0x513F] = 10
native(Facilities.ADDR.SIMULATOR_ADD_SCORE)
native(Facilities.ADDR.SIMULATOR_BONUS)
assert(store.vars[0x513F] == 23)

-- Trainerbattle rows that name a script variable must resolve before vanilla.
var(0x800D, Facilities.TRAINER.SPECIAL)
local passed
hook(function(_, op, row) passed = { op = op, row = row }; return false end,
  ctx, "trainerbattle", { trainer = 0x800D, [1] = 0x800D })
assert(passed.row.trainer == Facilities.TRAINER.SPECIAL
  and passed.row[1] == Facilities.TRAINER.SPECIAL)

if arg and arg[1] then
  local handle = assert(io.open(arg[1], "rb"))
  local realRom = {}
  function realRom:_read(offset, length)
    assert(handle:seek("set", offset))
    return assert(handle:read(length))
  end
  function realRom:pointerAt(slot)
    local raw = self:_read(slot, 4)
    local value = raw:byte(1) + raw:byte(2) * 256 + raw:byte(3) * 65536
      + raw:byte(4) * 16777216
    return value - 0x08000000, value
  end
  local real = assert(Facilities._trainerRecord(deps, realRom, 1, 0, 0, ctx))
  assert(real.name ~= "" and real.pools.regular[2] > 0)
  local first = assert(Facilities._spreadAt(realRom, real.pools.regular[1], 0, false))
  assert(first.species > 0 and #first.moves > 0)
  handle:close()
end

print("PASS rr_facilities_test: ROM trainers, six-mon spreads, rentals, restore, simulator, dynamic IDs")
