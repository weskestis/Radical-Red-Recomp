-- Exercises the mod against gen1recomp's real FireRed damage module.
package.path = "./?.lua;./?/init.lua;" .. package.path

local rrPath = assert(arg[1],
  "usage: luajit mods/radical_red_experience/tests/battle_damage_test.lua <rr-v4.1.gba>")
local handle = assert(io.open(rrPath, "rb"))
local size = assert(handle:seek("end"))
local imports = {}
function imports:info(id)
  return { id = id, size = size, md5 = "8529f3a45d32bce4da637976fcf269d4" }
end
function imports:read(_, offset, length)
  assert(handle:seek("set", offset))
  return assert(handle:read(length))
end

local RR = assert(loadfile("mods/radical_red_experience/lib/rr_rom.lua"))()
local Battle = assert(loadfile("mods/radical_red_experience/lib/rr_battle.lua"))()
local rom = RR.open(imports, RR.IMPORT_ID)
rom:verify()
Battle.install(rom)

local Damage = require("src.core.game3.battle.damage")
local Types = require("src.core.game3.battle.types")

local attacker = {
  side = "player", item = 0, type1 = 17,
  stages = { attack = 0, defense = 0, spAtk = 0, spDef = 0 },
  mon = {
    level = 50, hp = 150, maxHp = 150,
    attack = 200, defense = 100, spAtk = 50, spDef = 100,
  },
}
local defender = {
  side = "enemy", item = 0, type1 = 0,
  stages = { attack = 0, defense = 0, spAtk = 0, spDef = 0 },
  mon = {
    level = 50, hp = 200, maxHp = 200,
    attack = 100, defense = 50, spAtk = 100, spDef = 200,
  },
}

local physicalDark = {
  id = "BITE", numId = 44, effect = 0, power = 60, type = 17,
  category = "physical",
}
local specialDark = {
  id = "TEST_SPECIAL", numId = 999, effect = 0, power = 60, type = 17,
  category = "special",
}
local physicalDamage = Damage.base(attacker, defender, physicalDark, {})
local specialDamage = Damage.base(attacker, defender, specialDark, {})
assert(physicalDamage > specialDamage * 5,
  "per-move category must select Attack/Defense instead of Dark's Gen III class")

local shadowBall = {
  id = "SHADOW_BALL", numId = 247, effect = 0, power = 80, type = 7,
  accuracy = 100, category = "special",
}
local _, shadowInfo = Damage.calc(attacker, defender, shadowBall, {
  noRandom = true, forceCrit = false,
})
assert(shadowInfo.physical == false,
  "Shadow Ball must be special even though Ghost was physical in Gen III")

local fairyMove = {
  id = "FAIRY_TEST", numId = 999, effect = 0, power = 80, type = 23,
  accuracy = 100, category = "special",
}
attacker.type1 = 23
defender.type1 = 16
local fairyDamage, fairyInfo = Damage.calc(attacker, defender, fairyMove, {
  noRandom = true, forceCrit = false,
})
assert(fairyDamage > 0 and fairyInfo.effectiveness == 2)
assert(Types.effectiveness(16, 23) == 0)

handle:close()
print("PASS battle_damage_test: real stock damage code honors RR move split and Fairy chart")
