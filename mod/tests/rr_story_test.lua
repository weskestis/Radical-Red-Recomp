package.path = "./?.lua;./?/init.lua;" .. package.path

local session = {
  map = "RR_TEST",
  mapGroup = 10,
  mapNum = 16,
  regionMapSectionId = 142,
  party = {
    { species = 25, nickname = "SPARK", hp = 30, friendship = 210, heldItem = 0 },
    { species = 6, nickname = "EMBER", hp = 0, friendship = 80 },
    { species = 150, nickname = "MEWTWO", hp = 80, friendship = 120 },
    { species = 99, nickname = "EGG", hp = 1, friendship = 0, isEgg = true },
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
function Pokemon.speciesOf(mon) return mon and mon.species end
function Pokemon.isEgg(mon) return mon and mon.isEgg == true end
function Pokemon.displayName(mon) return mon.nickname end
function Pokemon.friendshipOf(mon) return mon.friendship end
function Pokemon.setFriendship(mon, value) mon.friendship = value; return value end
function Pokemon.evolutions(species)
  if species == 3 then return { { method = 0xFE, param = 533, target = 869 } } end
  return {}
end
function Pokemon.types(species)
  if species == 25 then return { 13, 13 } end
  if species == 150 then return { 1, 14 } end
  if species == 77 then return { 10, 10 } end
  if species == 78 then return { 5, 11 } end
  if species == 79 then return { 4, 8 } end
  if species == 80 then return { 2, 2 } end
  return { 0, 0 }
end
function Pokemon.currentMapSec(s) return s.regionMapSectionId end

local Natives = { ALLOW = {} }
local npc = { cellX = 2, cellY = 2, px = 32, py = 32, facing = "down" }
local visible
local Follower = {}
function Follower.current() return npc end
function Follower.setVisible(_, value) visible = value; npc.hidden = not value end
function Follower.update() end
function Follower.actor()
  if npc.hidden then return nil end
  return { x = npc.px, y = npc.py, sortY = npc.py }
end

local emotes = {}
local FieldEffects = {}
function FieldEffects.startEmote(target, kind) emotes[#emotes + 1] = { target, kind } end

local sounds = {}
local Audio = {}
function Audio.playSe(id) sounds[#sounds + 1] = id; return true end
function Audio.applyOptions(s) s._audioOptionsApplied = true end

local Options = {}
function Options.set(s, key, value)
  s.options = s.options or {}
  s.options[key] = value
end

local loadedSave
local deps = {
  Natives = Natives,
  Flags = Flags,
  Pokemon = Pokemon,
  Options = Options,
  Audio = Audio,
  Follower = Follower,
  FieldEffects = FieldEffects,
  SaveData = {},
  Player = { cellX = 5, cellY = 2 },
  getSession = function() return session end,
  loadSave = function() return loadedSave end,
}

local followerState = { active = true }
deps.getFollowerState = function() return followerState end

local Story = assert(loadfile("lib/rr_story.lua"))()
local report = Story.install(nil, deps)
assert(report.nativeCallbacks == 18)

local ctx = { specialVars = {}, stringVars = {} }
local function var(id, value)
  if value ~= nil then Flags.setVar(store, ctx, id, value) end
  return Flags.getVar(store, ctx, id)
end
local function call(address, adapters)
  local handler = assert(Natives.ALLOW["native:" .. address],
    ("missing native %08X"):format(address))
  return handler(ctx, adapters)
end

store.vars[0x5130] = 25
call(Story.ADDR.FOLLOWER_AVAILABLE)
assert(var(0x800D) == 1 and ctx.stringVars[2] == "SPARK")
ctx.stringVars[2] = ""
call(Story.ADDR.FOLLOWER_NICKNAME)
assert(ctx.stringVars[2] == "SPARK")
call(Story.ADDR.FOLLOWER_FRIENDSHIP)
assert(var(0x800D) == 1)

call(Story.ADDR.FOLLOWER_HIDE)
assert(followerState.hidden and followerState.delayedState == 1 and visible == false)
call(Story.ADDR.FOLLOWER_DELAY)
assert(followerState.delayedState == 1)
call(Story.ADDR.FOLLOWER_SYNC)
assert(not followerState.hidden and followerState.delayedState == 0 and visible == true)

call(Story.ADDR.FOLLOWER_REACTION)
assert(var(0x800D) == 2, "electric follower reacts in Power Plant section")
store.flags[0x1034] = true
call(Story.ADDR.FOLLOWER_REACTION)
assert(var(0x800D) == 0, "hardcore flag suppresses Power Plant reaction")
store.flags[0x1034] = nil

session.party[1].species = 77
store.vars[0x5130] = 77
followerState.interactionMode = 2
call(Story.ADDR.FOLLOWER_REACTION)
assert(var(0x800D) == 1, "fire follower special reaction")
followerState.interactionMode = nil

call(Story.ADDR.PLAY_SE_154)
call(Story.ADDR.PLAY_SE_194)
assert(sounds[1] == 154 and sounds[2] == 194)
call(Story.ADDR.FOLLOWER_SMILE)
assert(emotes[1][1] == npc and emotes[1][2] == "smile")

session.party[1].friendship = 90
call(Story.ADDR.FOLLOWER_ORAN)
assert(session.party[1].friendship == 160)
call(Story.ADDR.FOLLOWER_ORAN)
assert(session.party[1].friendship == 220)
call(Story.ADDR.FOLLOWER_ORAN)
assert(session.party[1].friendship == 255)

call(Story.ADDR.FOLLOWER_JUMP_RIGHT)
assert(npc.facing == "right" and npc.rrJumpFrames == 16)
deps.Player.cellX, deps.Player.cellY = 2, 0
call(Story.ADDR.FOLLOWER_JUMP_TOWARD)
assert(npc.facing == "up" and followerState.lastMovement == 0x53)

store.vars[0x5130] = 150
session.mapGroup, session.mapNum = 1, 109
call(Story.ADDR.FOLLOWER_MEWTWO_EVENT)
assert(var(0x800D) == 1)
store.flags[0x1074] = true
call(Story.ADDR.FOLLOWER_MEWTWO_EVENT)
assert(var(0x800D) == 0)
store.flags[0x1074] = nil

call(Story.ADDR.FORCE_STEREO)
assert(session.options.sound == 1 and session._audioOptionsApplied)

session.roamer = { species = 245 }
call(Story.ADDR.ACTIVE_ROAMER)
assert(var(0x800D) == 1)
session.roamer = nil
session.roamers = { { species = 0 }, { species = 243 } }
call(Story.ADDR.ACTIVE_ROAMER)
assert(var(0x800D) == 1)
session.roamers = nil

loadedSave = { game_cleared = true, hallOfFameTeams = { { party = {} } } }
call(Story.ADDR.NEW_GAME_PLUS)
assert(var(0x800D) == 1)
loadedSave = {}
call(Story.ADDR.NEW_GAME_PLUS)
assert(var(0x800D) == 0)

var(0x8005, 2)
for input, expected in pairs({
  ["Berry"] = "Berries", ["berry"] = "berries", ["Box"] = "Boxes",
  ["box"] = "boxes", ["Glass"] = "Glass", ["Potion"] = "Potions",
}) do
  ctx.stringVars[2] = input
  call(Story.ADDR.PLURALIZE_ITEM)
  assert(ctx.stringVars[2] == expected, input .. " plural")
end
var(0x8005, 1)
ctx.stringVars[2] = "Berry"
call(Story.ADDR.PLURALIZE_ITEM)
assert(ctx.stringVars[2] == "Berry")

session.party[1] = { species = 3, heldItem = 533, hp = 1, nickname = "MEGA" }
store.vars[0x5130] = 869
call(Story.ADDR.FOLLOWER_AVAILABLE)
assert(var(0x800D) == 1 and ctx.stringVars[2] == "MEGA", "held-item Mega follower match")

print("PASS rr_story_test: all 18 RR story/follower utility callbacks")
