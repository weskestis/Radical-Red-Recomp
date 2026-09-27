local romPath = assert(arg[1], "usage: texlua tests/rr_rom_test.lua <radical-red-v4.1.gba>")
local handle = assert(io.open(romPath, "rb"))
local size = assert(handle:seek("end"))

local imports = {}
function imports:info(id)
  assert(id == "radical_red_v4_1")
  return { id = id, size = size, md5 = "8529f3a45d32bce4da637976fcf269d4" }
end
function imports:read(id, offset, length)
  assert(id == "radical_red_v4_1")
  assert(handle:seek("set", offset))
  return assert(handle:read(length))
end

local RR = assert(loadfile("lib/rr_rom.lua"))()
local Profile = assert(loadfile("lib/rr_profile.lua"))()
local rom = RR.open(imports, RR.IMPORT_ID)
local report = rom:verify()

assert(Profile.CACHE_SCHEMA == 15)
assert(Profile.OFFSET.wildMonDayHeaders == 0x1166AB8)
assert(Profile.OFFSET.wildMonNightHeaders == 0x1166428)
assert(Profile.OFFSET.overworldGraphicsPointers == 0x0EB1000)
assert(Profile.OFFSET.overworldPokemonGraphicsPointers == 0x134FD7C)
assert(Profile.OFFSET.overworldPlayerGraphicsPointers == 0x134FCB8)
assert(Profile.OFFSET.namingRivalGfx == 0x0EE82B0)
assert(Profile.OFFSET.partyMenuSlotTilemap == 0x045A180)
assert(Profile.OFFSET.partyMenuSlotEmptyTilemap == 0x045A210)
assert(Profile.OW_COUNT == 257)
assert(Profile.OW_RUNTIME_PRIMARY_COUNT == 256)
assert(Profile.OW_POKEMON_COUNT == 240)
assert(Profile.OW_PLAYER_COUNT == 49)
assert(Profile.OW_TOTAL_COUNT == 545)
assert(Profile.OW_USED_PALETTE_COUNT == 397)
local function rawU16(offset)
  local bytes = imports:read(RR.IMPORT_ID, offset, 2)
  return bytes:byte(1) + bytes:byte(2) * 0x100
end

local function rawU32(offset)
  local bytes = imports:read(RR.IMPORT_ID, offset, 4)
  return bytes:byte(1) + bytes:byte(2) * 0x100
    + bytes:byte(3) * 0x10000 + bytes:byte(4) * 0x1000000
end

-- CFRU stores the graphics-table selector in the formerly-padding byte at +3
-- of each object-event record. Pallet's Route 21 blocker is 0x01:0x6E, not
-- ordinary-table 0x6E; selector 1 index 110 is the Stufful sheet.
do
  local object = 0x734230
  assert(imports:read(RR.IMPORT_ID, object, 1):byte() == 5)
  assert(imports:read(RR.IMPORT_ID, object + 1, 1):byte() == 0x6E)
  assert(imports:read(RR.IMPORT_ID, object + 3, 1):byte() == 1)
  local pointer = rawU32(Profile.OFFSET.overworldPokemonGraphicsPointers
    + 0x6E * 4)
  local infoOff = pointer - 0x08000000
  assert(rawU16(infoOff + 2) == 0x1281)
  assert(rawU16(infoOff + 8) == 32 and rawU16(infoOff + 10) == 32)
end
for graphicsId, expected in pairs({
  [0] = { 0x1100, 16, 32 },
  [7] = { 0x1110, 16, 32 },
  [88] = { 0x1168, 16, 32 },
  [152] = { 0x11D5, 32, 32 },
  [256] = { 0x1100, 16, 32 },
}) do
  local pointer = rawU32(
    Profile.OFFSET.overworldGraphicsPointers + graphicsId * 4)
  assert(pointer >= 0x08000000 and pointer < 0x0A000000)
  local infoOff = pointer - 0x08000000
  assert(rawU16(infoOff + 2) == expected[1])
  assert(rawU16(infoOff + 8) == expected[2])
  assert(rawU16(infoOff + 10) == expected[3])
end

-- FireRed's old rival-name sheet is erased in RR; the live nine-frame table
-- points at the relocated copy.  Catching this at the ROM level prevents a
-- syntactically valid but solid-black portrait from passing extraction.
for frame = 0, 8 do
  local pointer = rawU32(0x0EB4E58 + frame * 8)
  assert(pointer == 0x08000000 + Profile.OFFSET.namingRivalGfx + frame * 0x100)
  assert(rawU16(0x0EB4E58 + frame * 8 + 4) == 0x100)
  local bytes = imports:read(RR.IMPORT_ID,
    Profile.OFFSET.namingRivalGfx + frame * 0x100, 0x100)
  local indices = {}
  for i = 1, #bytes do
    local byte = bytes:byte(i)
    indices[byte % 16] = true
    indices[math.floor(byte / 16)] = true
  end
  indices[0] = nil
  local colors = 0
  for _ in pairs(indices) do colors = colors + 1 end
  assert(colors >= 3, "relocated rival naming frame is blank/solid: " .. frame)
end

assert(report.speciesCount == 1376)
assert(report.firstSpecies == "Bulbasaur")
assert(report.lastSpecies == "Chillet")
assert(report.embeddedVersion == "Radical Red Version v4.1")
assert(report.pointers.speciesNames == 0x14042CC)
assert(report.pointers.baseStats == 0x17B98EC)
assert(report.pointers.battleMoves == 0x11521D0)
assert(report.moveCount == 1004)
assert(report.moveCategories.physical == 435)
assert(report.moveCategories.special == 305)
assert(report.moveCategories.status == 264)
assert(report.typeCount == 24)
assert(report.typeChartOffset == 0x1146CE2)

local bulbasaur = rom:species(1)
assert(bulbasaur.baseStats.hp == 45)
assert(bulbasaur.baseStats.attack == 49)
assert(bulbasaur.baseStats.specialAttack == 65)
assert(bulbasaur.types[1] == "GRASS" and bulbasaur.types[2] == "POISON")

local clefairy = rom:species(35)
assert(clefairy.name == "Clefairy")
assert(clefairy.types[1] == "FAIRY" or clefairy.types[2] == "FAIRY")

-- Species 0x04FF is Radical Red's Seviian Ursaring. It intentionally keeps
-- the display name Ursaring while using the Ghost/Fighting regional-form
-- sprite and data; do not "repair" it with ordinary Ursaring's art.
local seviianUrsaring = rom:species(0x04FF)
assert(seviianUrsaring.name == "Ursaring")
assert(seviianUrsaring.types[1] == "GHOST"
  and seviianUrsaring.types[2] == "FIGHTING")

for index = 252, 276 do
  assert(not rom:species(index).populated)
end

local last = rom:species(1375)
assert(last.name == "Chillet")

assert(rom:move(1).category == "physical")       -- Pound
assert(rom:move(14).category == "status")        -- Swords Dance
assert(rom:move(44).category == "physical")      -- Bite (Dark)
assert(rom:move(52).category == "special")       -- Ember
assert(rom:move(247).category == "special")      -- Shadow Ball (Ghost)
assert(rom:typeMultiplier(16, 23) == 0)           -- Dragon -> Fairy
assert(rom:typeMultiplier(23, 16) == 20)          -- Fairy -> Dragon
assert(rom:typeMultiplier(17, 8) == 10)           -- Dark -> Steel
assert(rom:typeMultiplier(7, 8) == 10)            -- Ghost -> Steel

handle:close()
print("PASS rr_rom_test: RR v4.1 species, move splits, and type chart verified")
