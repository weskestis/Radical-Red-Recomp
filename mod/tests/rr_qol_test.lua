package.path = "./?.lua;./?/init.lua;" .. package.path

local store = { flags = {} }
local session = {
  map = "FR_VIRIDIAN_CITY",
  dex = { seen = { [25] = true }, owned = {}, caught = {} },
}

local Flags = {}
function Flags.getFlag(s, _, id) return s.flags[id] == true end
function Flags.setFlag(s, _, id, value) s.flags[id] = value == true end

local Encounters = {}
function Encounters.tableFor(map)
  assert(map == "FR_VIRIDIAN_CITY")
  return {
    land = { slots = {
      { species = 25, minLevel = 3, maxLevel = 5 },
      { species = 468, minLevel = 4, maxLevel = 6 },
    } },
    water = { slots = {
      { species = 7, minLevel = 5, maxLevel = 5 },
    } },
  }
end

local Pokemon = {}
function Pokemon.name(id)
  return ({ [7] = "Squirtle", [25] = "Pikachu", [468] = "Combee" })[id]
    or ("MON_" .. tostring(id))
end

local Dex = {}
function Dex.isSeen(dex, id) return dex.seen[id] == true end

local Stack = { pushed = {}, popped = {} }
function Stack.push(id, screen, opts)
  Stack.pushed[#Stack.pushed + 1] = { id = id, screen = screen, opts = opts }
end
function Stack.pop(id) Stack.popped[#Stack.popped + 1] = id end
package.loaded["src.ui.game3.stack"] = Stack

local BattleUi = {
  _mode = "menu",
  _st = { wild = false, foeParty = { { species = 25, hp = 10 } } },
}
function BattleUi.reset() BattleUi._reset = true end
function BattleUi.handleInput() BattleUi._stockInput = true return false end
function BattleUi.draw() BattleUi._stockDraw = true end
package.loaded["src.core.game3.battle.ui"] = BattleUi

local wrappers, events = {}, {}
local mod = {
  hooks = {
    wrap = function(_, name, fn) wrappers[name] = fn end,
  },
  events = {
    on = function(_, name, fn) events[name] = fn end,
  },
}

local Qol = assert(loadfile("lib/rr_qol.lua"))()
local report = Qol.install(mod, {
  Flags = Flags,
  Encounters = Encounters,
  Pokemon = Pokemon,
  Dex = Dex,
  getStore = function() return store end,
  getSession = function() return session end,
})

assert(report.runningShoes and report.dexAll and report.teamPreview and report.ezCatch)
assert(store.flags[Qol.FLAG.RUNNING_SHOES] == true,
  "new games did not receive running shoes immediately")
store.flags[Qol.FLAG.RUNNING_SHOES] = false
events["map.entered"]()
assert(store.flags[Qol.FLAG.RUNNING_SHOES] == true,
  "existing saves were not repaired on map entry")
store.flags[Qol.FLAG.RUNNING_SHOES] = false
events["save.created"]()
assert(store.flags[Qol.FLAG.RUNNING_SHOES] == true,
  "new games were not repaired before their first step")

local rows = Qol.buildDexRows(nil, session)
assert(#rows == 3 and rows[1].name == "Pikachu"
    and rows[2].name == "??????????" and rows[3].name == "??????????",
  "DexNav revealed unseen data without DexAll")
store.flags[Qol.FLAG.DEX_ALL] = true
rows = Qol.buildDexRows(nil, session)
assert(rows[2].name == "Combee" and rows[2].minLevel == 4
    and rows[2].maxLevel == 6 and rows[2].method == "GRASS"
    and rows[3].name == "Squirtle" and rows[3].method == "WATER",
  "DexAll did not reveal complete current-area encounter info")

local menu = wrappers["ui.start_menu.items"](function(_, items) return items end,
  {}, { { id = "pokedex", label = "POKEDEX" }, { id = "save", label = "SAVE" } })
assert(#menu == 3 and menu[2].id == "rr_dexnav")
menu[2].onSelect(nil, session)
assert(Stack.pushed[#Stack.pushed].id == "rr_dexnav")

local caught, shakes = wrappers["catch.rate"](
  function() return false, 0 end, "POKE_BALL", {}, {}, {})
assert(caught == false and shakes == 0)
store.flags[Qol.FLAG.EZ_CATCH] = true
caught, shakes = wrappers["catch.rate"](
  function() return false, 0 end, "POKE_BALL", {}, {}, {})
assert(caught == true and shakes == 4,
  "EZCatch did not force a four-shake catch")

local pressed = {}
local input = { wasPressed = function(_, key) return pressed[key] == true end }
store.flags[Qol.FLAG.TEAM_PREVIEW] = true
pressed.select = true
assert(BattleUi.handleInput(input) == true and BattleUi._rrTeamPreview == true,
  "TeamPreview did not open from the Android SELECT fallback")
pressed.select, pressed.b = false, true
assert(BattleUi.handleInput(input) == true and BattleUi._rrTeamPreview == false,
  "TeamPreview did not close")

print("PASS rr_qol_test: running shoes and all console-code host effects")
