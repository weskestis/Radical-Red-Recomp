package.path = "./?.lua;./?/init.lua;" .. package.path

local store = { flags = {} }
local session = {
  map = "FR_VIRIDIAN_CITY",
  dex = { seen = { [25] = true }, owned = {}, caught = {} },
  bag = { items = {} },
  modData = {},
  trainerId = 123,
  secretId = 456,
  party = {
    { species = 25, level = 10, hp = 20, maxHp = 30,
      moves = { 84 }, pp = { 5 }, maxPp = { 15 } },
  },
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
    fishing = { slots = {
      { species = 170, minLevel = 5, maxLevel = 5 },
    } },
  }
end

local Pokemon = {}
function Pokemon.name(id)
  return ({ [7] = "Squirtle", [25] = "Pikachu", [170] = "Chinchou",
    [468] = "Combee" })[id]
    or ("MON_" .. tostring(id))
end
function Pokemon.national(id) return id end
function Pokemon.types(id) return id == 25 and { 13, 13 } or { 0, 0 } end
function Pokemon.abilities(id)
  if id == 25 then return { 9, 31 } end
  return { 1, 0 }
end
Pokemon._abilities = { [25] = { 9, 31, 55, hidden = 55 } }
function Pokemon.abilityName(id) return "ABILITY_" .. tostring(id) end
function Pokemon.speciesMeta(id)
  if id == 25 then return { itemCommon = 100, itemRare = 101 } end
  return { itemCommon = 0, itemRare = 0 }
end
function Pokemon.movesAtLevel(id)
  return id == 25 and { 84, 45 } or { 33 }
end
function Pokemon.eggMoves(id) return id == 25 and { 999 } or nil end

local Dex = {}
function Dex.isSeen(dex, id) return dex.seen[id] == true end
function Dex.isCaught(dex, id)
  return dex.caught[id] == true or dex.owned[id] == true
end

local Bag = {}
function Bag.has(bag, id)
  return bag and bag.items and bag.items[id] == true
end

local ItemsData = {}
local skillItems = {
  [363] = { name = "Poké Rider" },
  [601] = { name = "Time Changer" },
  [602] = { name = "Infinite Repel" },
  [603] = { name = "PokéVial" },
}
function ItemsData.ensureLoaded() return skillItems end
function ItemsData.toNumericId(id) return tonumber(id) end
function ItemsData.displayName(id)
  return (skillItems[id] and skillItems[id].name) or ("ITEM_" .. tostring(id))
end

local Player = { biking = false }
function Player.canDash() return true end
function Player.update(_, input)
  Player._sawRun = input and input.isDown and input:isDown("b") or false
  return Player._sawRun
end
package.loaded["src.core.game3.player"] = Player

local Party = {}
function Party.healAll(party)
  for _, mon in ipairs(party or {}) do
    if mon.maxHp then mon.hp = mon.maxHp end
    mon.status, mon.sleep = nil, nil
    if mon.moves and mon.pp and mon.maxPp then
      for i = 1, #mon.moves do mon.pp[i] = mon.maxPp[i] or mon.pp[i] end
    end
  end
end
package.loaded["src.core.game3.party"] = Party

local ItemUse = { _onFieldCB = nil }
function ItemUse.setUpOnFieldCallback(cb)
  ItemUse._onFieldCB = cb
  return true
end
function ItemUse.runOnFieldCallback()
  local cb = ItemUse._onFieldCB
  ItemUse._onFieldCB = nil
  if cb then cb() end
  return cb ~= nil
end
package.loaded["src.core.game3.item_use"] = ItemUse

local Field = { locked = false }
function Field.flyTo(section, mon)
  Field.lastFly = { section = section, mon = mon }
  return true
end
package.loaded["src.core.game3.field"] = Field

local RegionMap = {}
function RegionMap.show(opts) RegionMap.last = opts end
package.loaded["src.ui.game3.region_map"] = RegionMap

local RR_Encounters = { hour = nil }
function RR_Encounters.setOverrideHour(hour) RR_Encounters.hour = hour end

local Types = {}
function Types.name(id) return id == 13 and "ELECTRIC" or "NORMAL" end

local rngValue = 50
local startedBattles = {}
local function startWildBattle(game, encounter, done)
  startedBattles[#startedBattles + 1] = {
    game = game, encounter = encounter, done = done,
  }
  return true
end

local Stack = { pushed = {}, popped = {} }
function Stack.push(id, screen, opts)
  Stack.pushed[#Stack.pushed + 1] = { id = id, screen = screen, opts = opts }
end
function Stack.pop(id) Stack.popped[#Stack.popped + 1] = id end
function Stack.busy() return false end
package.loaded["src.ui.game3.stack"] = Stack

local BattleUi = {
  _mode = "menu",
  _st = { wild = false, foeParty = { { species = 25, hp = 10 } } },
}
function BattleUi.reset() BattleUi._reset = true end
function BattleUi.handleInput() BattleUi._stockInput = true return false end
function BattleUi.draw() BattleUi._stockDraw = true end
package.loaded["src.core.game3.battle.ui"] = BattleUi

local Audio = {
  _fanfareActive = false,
  _mapSong = 321,
  _bgmGen = 321,
  _bgmPaused = false,
  _played = {},
  _setMapSong = nil,
}
local silentSource = { playing = false }
function silentSource:isPlaying() return self.playing end
Audio._bgmSource = silentSource
function Audio.currentSong() return Audio._currentSong or { id = Audio._mapSong } end
function Audio.playSong(id, opts)
  Audio._played[#Audio._played + 1] = { id = id, restart = opts and opts.restart }
  Audio._currentSong = { id = id }
  return true
end
function Audio.setMapSong(id)
  Audio._mapSong = id
  Audio._setMapSong = id
end
function Audio.update()
  if Audio._finishFanfare then
    Audio._fanfareActive = false
    Audio._finishFanfare = false
  end
end
package.loaded["src.core.game3.audio"] = Audio

local Trainers = {}
function Trainers.get(id)
  if id == 999 then
    return { id = id, name = "LANCE", className = "RR BOSS", class = 1 }
  end
  return { id = id, name = "YOUNGSTER", className = "YOUNGSTER", class = 1 }
end
package.loaded["src.core.game3.scripting.trainers"] = Trainers

local BattleTransition = {
  ID = { LORELEI = 12, BRUNO = 13, AGATHA = 14, LANCE = 15, BLUE = 16 },
}
function BattleTransition.pickTrainer() return BattleTransition.ID.BLUE end
package.loaded["src.core.game3.battle_transition"] = BattleTransition

local wrappers, events = {}, {}
local mod = {
  hooks = {
    wrap = function(_, name, fn) wrappers[name] = fn end,
  },
  events = {
    on = function(_, name, fn)
      local previous = events[name]
      if previous then
        events[name] = function(...)
          previous(...)
          return fn(...)
        end
      else
        events[name] = fn
      end
    end,
  },
}

local Qol = assert(loadfile("lib/rr_qol.lua"))()
local report = Qol.install(mod, {
  Flags = Flags,
  Encounters = Encounters,
  Pokemon = Pokemon,
  Dex = Dex,
  Bag = Bag,
  ItemsData = ItemsData,
  Types = Types,
  Rng = { Random = function() return rngValue end,
    Random32 = function() return 0x12345678 end },
  random = function() return rngValue end,
  startWildBattle = startWildBattle,
  getStore = function() return store end,
  getSession = function() return session end,
  RR_Encounters = RR_Encounters,
})

assert(report.runningShoes and report.dexAll and report.teamPreview and report.ezCatch)
assert(report.dexNavReliableFieldEdge == true
    and report.dexNavFieldSelect == true)
assert(report.skillsMenu == true and report.autoRunSkill == true
    and report.timeChangerSkill == true and report.infiniteRepelSkill == true
    and report.pokeVialSkill == true,
  "the four-skill L menu was not installed")
assert(report.skillItemIds.timeChanger == 601
    and report.skillItemIds.infiniteRepel == 602
    and report.skillItemIds.pokeVial == 603,
  "Radical Red skill key items were not discovered by name")
assert(report.pokeRider == true and report.pokeRiderItemId == 363,
  "Poké Rider field-use replacement was not installed")
assert(report.fanfareBgmRecovery == true
    and report.eliteFourVsIntroFix == true
    and report.battleMusicReturn == true,
  "v0.5.18 music/VS presentation fixes were not installed")
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

-- L opens the overworld Skills screen without using the battle Team Preview
-- path. The three earned skills unlock from their real Radical Red key items.
session.bag.items[601], session.bag.items[602], session.bag.items[603] = true, true, true
local skillPressed = { l = true }
local skillInput = {
  pressQueue = {},
  wasPressed = function(_, key) return skillPressed[key] == true end,
  isDown = function(_, key) return skillPressed[key] == true end,
}
local skillGame = { phase = "field", session = session, input = skillInput }
assert(wrappers["core.update"](function() return "updated" end,
    skillGame, 1 / 60) == "updated")
assert(Stack.pushed[#Stack.pushed].id == "rr_skills",
  "L did not open the Radical Red Skills menu")
local Skills = Stack.pushed[#Stack.pushed].screen

-- Auto Run: no physical B means run; holding B temporarily walks.
skillPressed = { a = true }
Skills.handleInput(skillInput)
skillPressed = {}
local runInput = {
  isDown = function(_, key) return false end,
  wasPressed = function() return false end,
}
Player.update(skillGame, runInput)
assert(Player._sawRun == true, "Auto Run did not run without B")
runInput.isDown = function(_, key) return key == "b" end
Player.update(skillGame, runInput)
assert(Player._sawRun == false, "Auto Run did not let B temporarily walk")

-- Time Changer uses the RR day/dusk/night clock override.
Skills.cursor = 2
skillPressed = { a = true }
Skills.handleInput(skillInput)
assert(Skills.mode == "time", "Time Changer did not open")
Skills.timeCursor = 4
Skills.handleInput(skillInput)
assert(RR_Encounters.hour == 22 and Skills.mode == "main",
  "Time Changer did not apply NIGHT")

-- Infinite Repel suppresses only the normal encounter.roll hook.
Skills.cursor = 3
skillPressed = { a = true }
Skills.handleInput(skillInput)
skillPressed = {}
local ordinary = wrappers["encounter.roll"](function() return "WILD" end, {}, {})
assert(ordinary == nil, "Infinite Repel did not suppress walking encounters")

-- PokéVial full-heals, spends one of six charges, and a normal full-party heal
-- refills the Vial without the Vial refilling itself.
Skills.cursor = 4
skillPressed = { a = true }
Skills.handleInput(skillInput)
skillPressed = {}
local skillState = session.modData.radical_red_experience.skills
assert(session.party[1].hp == 30 and session.party[1].pp[1] == 15
    and skillState.vialCharges == 5,
  "PokéVial did not heal the party and spend exactly one charge")
Party.healAll(session.party)
assert(skillState.vialCharges == 6,
  "a normal full-party heal did not refill PokéVial to six uses")
skillPressed = { b = true }
Skills.handleInput(skillInput)
skillPressed = {}

-- Radical Red repurposes FireRed item 363 from Fame Checker to Poké Rider.
-- The hook must defer until the Bag exits, then open Fly-mode visited locations
-- without ever reaching the stock Fame Checker dispatch.
do
  local vanillaCalls = 0
  local ok, kind = wrappers["item.use"](
    function()
      vanillaCalls = vanillaCalls + 1
      return false, "vanilla", nil
    end,
    { session = session }, nil, 363, nil, session.bag)
  assert(ok == true and kind == "escape" and vanillaCalls == 0,
    "Poké Rider fell through to FireRed's Fame Checker item handler")
  assert(ItemUse._onFieldCB ~= nil and RegionMap.last == nil,
    "Poké Rider did not defer its map until the Bag exit")
  assert(ItemUse.runOnFieldCallback() == true)
  assert(RegionMap.last and RegionMap.last.session == session
      and RegionMap.last.mode == "fly" and Field.locked == true,
    "Poké Rider did not open the visited-location Fly map")
  RegionMap.last.onPick("MAPSEC_PALLET_TOWN")
  assert(Field.lastFly and Field.lastFly.section == "MAPSEC_PALLET_TOWN"
      and Field.lastFly.mon == session.party[1],
    "Poké Rider destination did not enter the host travel path")
  RegionMap.last.onClose()
  assert(Field.locked == false, "canceling Poké Rider left the field locked")

  -- Numeric slot 363 alone is not enough: vanilla FireRed must retain its
  -- Fame Checker if this same host module is ever exercised without RR data.
  skillItems[363].name = "Fame Checker"
  local passthrough = wrappers["item.use"](
    function() vanillaCalls = vanillaCalls + 1; return true, "fame_checker" end,
    { session = session }, nil, 363, nil, session.bag)
  assert(passthrough == true and vanillaCalls == 1,
    "numeric item 363 was hijacked without a live Poké Rider identity")
  skillItems[363].name = "Poké Rider"
end

-- RR can repurpose trainer IDs/classes; the live trainer name must drive the
-- Elite Four VS portrait instead of falling through to Blue/Gary.
assert(BattleTransition.pickTrainer({ trainerId = 999, trainerClass = 1 })
    == BattleTransition.ID.LANCE,
  "repurposed RR Lance did not resolve the Lance VS intro")

-- Guarded fanfare recovery restarts the same field BGM only when Android has
-- actually left the queue silent after the fanfare.
Audio._currentSong = { id = 321 }
Audio._mapSong, Audio._bgmGen = 321, 321
Audio._bgmSource.playing = false
Audio._fanfareActive, Audio._finishFanfare = true, true
Audio.update(1 / 60)
Audio.update(1 / 60)
Audio.update(1 / 60)
Audio.update(1 / 60)
local recovered = Audio._played[#Audio._played]
assert(recovered and recovered.id == 321 and recovered.restart == true,
  "silent BGM did not recover after a fanfare")

-- League/trainer battle music must restore the map song captured before the
-- battle BGM replaces it.
Audio._mapSong = 444
wrappers["trainer.party"](function(_, _, party) return party end, 1, 999, {})
Audio._mapSong = 9999
events["battle.ended"]({ result = "win" })
assert(Audio._setMapSong == 444 and Audio._mapSong == 444,
  "battle-end music recovery did not restore the pre-battle map song")

local rows = Qol.buildDexRows(nil, session)
assert(#rows == 4 and rows[1].name == "Pikachu"
    and rows[2].name == "??????????" and rows[3].name == "??????????"
    and rows[4].name == "??????????",
  "DexNav revealed unseen data without DexAll")

local lockedMenu = wrappers["ui.start_menu.items"](
  function(_, items) return items end, {}, {
    { id = "pokedex", label = "POKEDEX" }, { id = "save", label = "SAVE" },
  })
assert(#lockedMenu == 2,
  "DexNav appeared before Radical Red set its story unlock flag")
store.flags[Qol.FLAG.DEX_NAV] = true

store.flags[Qol.FLAG.DEX_ALL] = true
rows = Qol.buildDexRows(nil, session)
assert(rows[2].name == "Combee" and rows[2].minLevel == 4
    and rows[2].maxLevel == 6 and rows[2].method == "WALK"
    and rows[3].name == "Squirtle" and rows[3].method == "SURF"
    and rows[4].name == "Chinchou" and rows[4].method == "OLD ROD",
  "DexAll did not reveal complete current-area encounter info")

local menu = wrappers["ui.start_menu.items"](function(_, items) return items end,
  {}, { { id = "pokedex", label = "POKEDEX" }, { id = "save", label = "SAVE" } })
assert(#menu == 3 and menu[2].id == "rr_dexnav")
menu[2].onSelect(nil, session)
assert(Stack.pushed[#Stack.pushed].id == "rr_dexnav")
local DexNav = Stack.pushed[#Stack.pushed].screen

-- SELECT is the Android fallback for CFRU's R-button registration. The
-- registration and search levels live in session.modData so save/reload keeps
-- them without changing the stock save schema.
local pressed = { select = true }
local input = { wasPressed = function(_, key) return pressed[key] == true end }
assert(DexNav.handleInput(input) == true)
local dexState = Qol.ensureDexNavState(session)
assert(dexState.registeredSpecies == 25 and dexState.registeredArea == "land",
  "DexNav did not persist the registered species")

pressed = { a = true }
DexNav.handleInput(input)
assert(DexNav.mode == "context" and DexNav.contextCursor == 1,
  "DexNav A button did not open Register/Scan/Cancel")
pressed = { down = true }
DexNav.handleInput(input)
assert(DexNav.contextCursor == 2, "DexNav context menu could not select Scan")
pressed = { a = true }
DexNav.handleInput(input)
assert(#startedBattles == 1 and startedBattles[1].encounter.species == 25
    and startedBattles[1].encounter.level >= 3
    and #startedBattles[1].encounter.moves > 0
    and startedBattles[1].encounter.rrDexNav == true,
  "DexNav Scan did not launch a generated wild encounter")
assert(dexState.searchLevels["25"] == 1 and dexState.pendingSpecies == 25,
  "DexNav did not increment and persist the search level at encounter start")
startedBattles[1].done("win")
assert(dexState.chain == 1 and dexState.pendingSpecies == nil,
  "DexNav did not advance its chain after a won search battle")

DexNav.show({}, session)
assert(DexNav.rows[1].searchLevel == 1,
  "DexNav search level did not survive reopening the menu")

-- A fishing-only result must not be searchable until its matching rod is in
-- the bag. Once obtained, the exact same row starts normally.
DexNav.cursor = 4
local started, rodErr = DexNav.scanSelected()
assert(started == false and tostring(rodErr):find("OLD ROD", 1, true)
    and #startedBattles == 1,
  "DexNav ignored the fishing-rod requirement")
session.bag.items[262] = true
assert(DexNav.scanSelected() == true and #startedBattles == 2
    and startedBattles[2].encounter.species == 170,
  "DexNav did not scan a fishing encounter after obtaining the rod")
startedBattles[2].done("run")
assert(dexState.chain == 0, "running from a DexNav battle did not reset the chain")

-- At search level 100, the CFRU probability tables can generate an egg move,
-- hidden ability, and guaranteed-perfect IV potential. Force their low-roll
-- branch and assert the generated encounter carries all three into battle.
dexState.searchLevels["25"] = 100
session.dex.caught[25] = true
session.dex.owned[25] = true
rngValue = 0
rows = Qol.buildDexRows(nil, session)
local boosted = assert(Qol.generateDexNavEncounter(nil, session, rows[1]))
assert(boosted.moves[1] == 999 and boosted.ability == 55
    and boosted.dexNavHiddenAbility == true
    and boosted.dexNavPotential >= 1,
  "DexNav search-level bonuses did not generate RR egg move/HA/potential data")
local perfect = 0
for _, value in pairs(boosted.ivs) do if value == 31 then perfect = perfect + 1 end end
assert(perfect >= boosted.dexNavPotential,
  "DexNav IV potential was not applied to the generated encounter")
rngValue = 50

-- A registered species can be scanned from the field with R, matching CFRU's
-- registered-DexNav shortcut. Exercise the raw queue path used when turbo or
-- catch-up performs multiple fixed steps before core.update returns.
pressed = {}
input.pressQueue = { "r" }
local fieldGame = { phase = "field", session = session, input = input }
assert(wrappers["core.update"](function() return "updated" end,
    fieldGame, 1 / 60) == "updated")
assert(#startedBattles == 3 and startedBattles[3].encounter.species == 25,
  "registered DexNav R shortcut did not start the selected encounter")
wrappers["core.update"](function() return "updated" end, fieldGame, 1 / 60)
assert(#startedBattles == 3,
  "held/queued DexNav shortcut launched the same search twice")
input.pressQueue = {}
startedBattles[3].done("run")
assert(dexState.chain == 0,
  "running from the registered DexNav shortcut did not reset the chain")

-- The default Android overlay exposes SELECT but not R. With no registered
-- key item it must run the same field shortcut, while an assigned key item
-- keeps FireRed's original SELECT action.
wrappers["core.update"](function() return "updated" end, fieldGame, 1 / 60)
pressed = { select = true }
assert(wrappers["core.update"](function() return "updated" end,
    fieldGame, 1 / 60) == "updated")
assert(#startedBattles == 4 and startedBattles[4].encounter.species == 25,
  "Android SELECT did not start the registered DexNav encounter")
startedBattles[4].done("run")
pressed = {}
wrappers["core.update"](function() return "updated" end, fieldGame, 1 / 60)
session.registeredItem = 262
pressed = { select = true }
wrappers["core.update"](function() return "updated" end, fieldGame, 1 / 60)
assert(#startedBattles == 4,
  "DexNav stole SELECT from FireRed's registered key item")
session.registeredItem = nil

-- Any ordinary battle and any map transition break a CFRU DexNav chain.
dexState.chain, dexState.chainMap = 3, session.map
events["battle.ended"]({ result = "win" })
assert(dexState.chain == 0, "a non-DexNav battle did not reset the chain")
dexState.chain, dexState.chainMap = 3, session.map
session.map = "FR_ROUTE_1"
events["map.entered"]()
assert(dexState.chain == 0, "leaving the map did not reset the DexNav chain")
session.map = "FR_VIRIDIAN_CITY"

local caught, shakes = wrappers["catch.rate"](
  function() return false, 0 end, "POKE_BALL", {}, {}, {})
assert(caught == false and shakes == 0)
store.flags[Qol.FLAG.EZ_CATCH] = true
caught, shakes = wrappers["catch.rate"](
  function() return false, 0 end, "POKE_BALL", {}, {}, {})
assert(caught == true and shakes == 4,
  "EZCatch did not force a four-shake catch")

pressed = {}
store.flags[Qol.FLAG.TEAM_PREVIEW] = true
pressed.select = true
assert(BattleUi.handleInput(input) == true and BattleUi._rrTeamPreview == true,
  "TeamPreview did not open from the Android SELECT fallback")
pressed.select, pressed.b = false, true
assert(BattleUi.handleInput(input) == true and BattleUi._rrTeamPreview == false,
  "TeamPreview did not close")

print("PASS rr_qol_test: running shoes and all console-code host effects")
