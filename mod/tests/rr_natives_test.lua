package.path = "./?.lua;./?/init.lua;" .. package.path

local session = {
  party = {
    {
      species = 1, speciesId = 1, personality = 100, level = 50,
      hp = 100, maxHp = 100, friendship = 70, happiness = 70,
      moves = { 70 },
      ivs = { hp = 1, atk = 2, def = 3, spe = 4, spa = 5, spd = 6 },
      evs = { hp = 10, atk = 20, def = 30, spe = 40, spa = 50, spd = 60 },
    },
    { species = 2, hp = 50, maxHp = 50, moves = { 33 }, ivs = {}, evs = {} },
    { species = 3, hp = 50, maxHp = 50, moves = { 33 }, ivs = {}, evs = {} },
  },
}

package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }

local store = { vars = {}, flags = {} }
package.loaded["src.core.game3.scripting.space"] = {
  store = store,
  bundle = { text = {
    ["g3:09000000"] = { { t = "text", s = "HELLO" }, { t = "eos" } },
  } },
}

local Flags = {}
function Flags.getVar(s, ctx, id)
  if id >= 0x8000 and id <= 0x8014 then return (ctx.specialVars or {})[id] or 0 end
  if id < 0x4000 then return id end
  return (s and s.vars and s.vars[id]) or 0
end
function Flags.setVar(s, ctx, id, value)
  value = (tonumber(value) or 0) % 0x10000
  if id >= 0x8000 and id <= 0x8014 then
    ctx.specialVars = ctx.specialVars or {}
    ctx.specialVars[id] = value
  elseif s and s.vars then
    s.vars[id] = value
  end
end

local Natives = { ALLOW = {} }
function Natives.yieldHost(ctx, _, start)
  local done = false
  ctx.mode, ctx.status = "native", "waiting"
  ctx.nativePoll = function() return done end
  start(function() done = true end)
  return not done
end
local stockListCalls = 0
Natives.ALLOW["special:344"] = function()
  stockListCalls = stockListCalls + 1
  return false, "stock-list"
end

-- The stock menu closes before its onSelect callback runs.  Keep a deliberately
-- racy fixture here so the RR wrapper must commit the chosen slot itself.
local selectedSlotObserved
local FakePartyMenu = { open = false }
package.loaded["src.ui.game3.party_menu"] = FakePartyMenu
function Natives.choosePartyMon(ctx, adapters, menuType)
  if adapters and adapters.chooseParty then
    return adapters.chooseParty({ menuType = menuType }, function() end)
  end
  FakePartyMenu.open = true
  FakePartyMenu._onSelect = function()
    selectedSlotObserved = Flags.getVar(store, ctx, 0x8004)
  end
  return true
end

local Pokemon = {}
function Pokemon.evsOf(mon) mon.evs = mon.evs or {} return mon.evs end
function Pokemon.friendshipOf(mon) return mon.friendship or mon.happiness or 0 end
function Pokemon.setFriendship(mon, n) mon.friendship, mon.happiness = n, n end
function Pokemon.applyStats(mon) mon._statsApplied = (mon._statsApplied or 0) + 1 end
function Pokemon.name(id) return "SPECIES_" .. id end
function Pokemon.abilityId(_, pid) return pid % 2 + 1 end
function Pokemon.gender(_, pid) return pid % 2 == 0 and "M" or "F" end

local Storage = {}
function Storage.ensure(s) s.storage = s.storage or { boxes = { { mons = {} } } } return s.storage end
function Storage.getBoxMon(s, box, slot) return s.boxes[box] and s.boxes[box].mons[slot] end

local savedParty
local Tower = {}
function Tower.savePlayerParty(s)
  savedParty = {}
  for i, mon in ipairs(s.party) do savedParty[i] = mon end
end
function Tower.loadPlayerParty(s) s.party = savedParty end
function Tower.clearSelectedOrder(s) s.order = { 0, 0, 0 } end
function Tower.setSelectedOrder(s, picks)
  s.order = { 0, 0, 0 }
  for i = 1, math.min(3, #picks) do s.order[i] = picks[i] end
  return s.order
end
function Tower.reducePartyToThree(s)
  local p = {}
  for i = 1, 3 do if s.order[i] ~= 0 then p[i] = s.party[s.order[i]] end end
  s.party = p
end

local Follower = { _spawn = function() return false end }
function Follower.setShouldSpawn(fn) Follower._spawn = fn end
function Follower.update() end
function Follower.current() return nil end
function Follower.reset() end

local FieldMoves = {}
function FieldMoves.partyMoveUser(party, move)
  assert(move == "STRENGTH")
  return party and party[1], party and 0 or 6
end
function FieldMoves.hasBadge() return true end

local TextIR = {}
function TextIR.toPlain(ir)
  local out = {}
  for _, row in ipairs(ir or {}) do if row.s then out[#out + 1] = row.s end end
  return table.concat(out)
end

local Multichoice = { LISTS = {} }
local shownList
local ListMenu = {
  HANDLERS = { [0x158] = Natives.ALLOW["special:344"] },
  presentItems = function(ctx, key, labels, layout, onPick)
    shownList = { ctx = ctx, key = key, labels = labels, layout = layout }
    onPick(math.max(0, #labels - 1))
    return false
  end,
}
local RRListMenus = { version = 1, count = 16, lists = {} }
for id = 0, 15 do
  local count = id % 8 + 1
  local labels = {}
  for i = 1, count do labels[i] = ("List %d item %d"):format(id, i) end
  RRListMenus.lists[id] = { count = count, labels = labels }
end
RRListMenus.lists[12] = {
  count = 8,
  labels = { "Johto", "Hoenn", "Sinnoh", "Unova", "Kalos", "Alola", "Galar", "Paldea" },
}
local deps = {
  Natives = Natives,
  Flags = Flags,
  Pokemon = Pokemon,
  Storage = Storage,
  Tower = Tower,
  TowerNatives = { chooseOptions = function() return { count = 3 } end },
  FieldMoves = FieldMoves,
  Opcodes = { key = function(p) return type(p) == "string" and p or ("g3:%08x"):format(p) end },
  TextIR = TextIR,
  Multichoice = Multichoice,
  ListMenu = ListMenu,
  RRListMenus = RRListMenus,
  Follower = Follower,
}

local RRNative = assert(loadfile("lib/rr_natives.lua"))()
local report = RRNative.install(nil, deps)
assert(report.specials == 27)
assert(report.nativeCallbacks == 21)
assert(report.starterRegionMenu == true)
assert(report.cartridgeListMenus == true and report.customListMenus == 16)
assert(report.partySelectionCommit == true)

local ctx = { specialVars = {}, stringVars = {}, data = {} }
local function var(id, value)
  if value ~= nil then Flags.setVar(store, ctx, id, value) end
  return Flags.getVar(store, ctx, id)
end
local function special(id, adapters)
  local handler = assert(Natives.ALLOW["special:" .. id], ("missing special %X"):format(id))
  return handler(ctx, adapters)
end

var(0x8004, 0)
Natives.choosePartyMon(ctx, {
  chooseParty = function(opts, done)
    assert(opts.menuType == "choose_single")
    done(2) -- adapters already return the zero-based party slot
  end,
}, "choose_single")
assert(var(0x8004) == 2 and ctx.rrSelectedPartySlot == 2,
  "adapter party selection did not commit the chosen slot")

var(0x8004, 0)
Natives.choosePartyMon(ctx, nil, "choose_single")
assert(type(FakePartyMenu._onSelect) == "function")
FakePartyMenu._onSelect(2) -- the live party UI returns a one-based slot
assert(var(0x8004) == 1 and ctx.rrSelectedPartySlot == 1
    and selectedSlotObserved == 1,
  "live party selection resumed before slot two was committed")

for id = 0, 15 do
  var(0x8004, 0)
  var(0x8000, id)
  var(0x8001, 6)
  special(0x158)
  local expected = RRListMenus.lists[id]
  local expectedRows = math.min(expected.count, 6)
  if expectedRows < 2 or expectedRows > 6 then expectedRows = 6 end
  assert(shownList and shownList.key == "rr_custom_list_" .. id)
  assert(shownList.labels == expected.labels)
  assert(shownList.layout.left == 1 and shownList.layout.top == 1
    and shownList.layout.count == expected.count
    and shownList.layout.maxShowed == expectedRows
    and shownList.layout.height == expectedRows * 2 - 1)
  assert(var(0x800D) == expected.count - 1,
    "custom list selection did not reach VAR_RESULT for id " .. id)
end

var(0x8004, 1)
var(0x8000, 2)
local _, stockResult = special(0x158)
assert(stockListCalls == 1 and stockResult == "stock-list",
  "non-custom FireRed list menus did not delegate to the stock handler")

var(0x8004, 0)
var(0x8005, 4)
local _, value = special(0x007)
assert(value == 50, "EV checker")

var(0x8005, 0)
var(0x8006, 0x100 + 4)
special(0x00F)
assert(session.party[1].evs.hp == 6, "EV subtraction")
var(0x8006, 255)
special(0x00F)
assert(session.party[1].evs.hp == 252, "EV cap")

var(0x8005, 6)
var(0x8006, 31)
special(0x010)
for _, key in ipairs({ "hp", "atk", "def", "spe", "spa", "spd" }) do
  assert(session.party[1].ivs[key] == 31, "set all IVs")
end

var(0x8005, 0x100 + 100)
special(0x013)
assert(session.party[1].friendship == 0, "friendship floor")

var(0x8005, 25)
special(0x016)
assert(session.party[1].species == 25 and session.party[1].name == "SPECIES_25")

ctx.data[0] = 0x09000000
var(0x8006, 2)
special(0x025)
assert(Multichoice.LISTS[37].labels[3] == "HELLO")
assert(#Multichoice.LISTS[32].labels == 2)
assert(#Multichoice.LISTS[34].labels == 4)
assert(Multichoice.LISTS[34].labels[3] == "HELLO")
assert(#Multichoice.LISTS[37].labels == 7)

RRNative._testNow = function()
  return { minute = 34, hour = 12, day = 26, month = 9, year = 2026 }
end
var(0x8000, 0x5050)
special(0x0A1)
local unpacked = RRNative.unpackDate(store.vars[0x5050], store.vars[0x5051])
assert(unpacked.minute == 34 and unpacked.hour == 12 and unpacked.day == 26)
assert(unpacked.month == 9 and unpacked.year == 2026)
var(0x8001, 1)
local _, sameDay = special(0x0A0)
assert(sameDay == 0)
store.vars[0x5050], store.vars[0x5051] = RRNative.packDate({
  minute = 0, hour = 0, day = 25, month = 9, year = 2026,
})
local _, nextDay = special(0x0A0)
assert(nextDay == 1)

var(0x8000, 1)
local naming = {
  openNaming = function(opts, done)
    assert(opts.title == "ENTER PASSWORD" and opts.maxLen == 12)
    done("HELLO")
  end,
  setStringVar = function(index, text) ctx.stringVars[index] = text end,
}
special(0x12C, naming)
assert(ctx.stringVars[1] == "HELLO")
local _, compare = special(0x12D)
assert(compare == 0)

var(0x8004, 99)
special(0x10C)
assert(var(0x8004) == 0, "Strength user slot")

session.party = { session.party[1], session.party[2], session.party[3] }
local chooser = {
  chooseParty = function(opts, done)
    assert(opts.count == 3)
    done({ 1, 2, 3 })
  end,
}
special(0x0F5, chooser)
assert(var(0x800D) == 1 and #session.party == 3, "three-mon selection")

var(0x8004, 0)
local natureHandler = assert(Natives.ALLOW["native:" .. 0x090B18C1])
natureHandler(ctx)
assert(session.party[1].personality % 25 == 3)
assert(session.party[1].personality % 2 == 0, "ability-slot parity preserved")

print("PASS rr_natives_test: RR field specials, party selection, and nature callbacks")
