package.path = "./?.lua;./?/init.lua;" .. package.path

local StreamRom = assert(loadfile(
  "mods/radical_red_experience/lib/rr_stream_rom.lua"))()

local page = 256 * 1024
local size = page + 64
local chunks = {}
for i = 0, size - 1 do
  chunks[#chunks + 1] = string.char(i % 251)
end
local source = table.concat(chunks)

local imports = {}
function imports:info(id)
  assert(id == "radical_red_v4_1")
  return { size = #source, md5 = "fixture" }
end
function imports:read(id, offset, length)
  assert(id == "radical_red_v4_1")
  return source:sub(offset + 1, offset + length)
end

local rom = assert(StreamRom.open(imports, "radical_red_v4_1"))
assert(type(rawget(rom, "readString")) == "function",
  "Android ROM handles must carry readString as a direct method")
assert(rom:readString(0, 0) == "")
assert(rom:readString(37, 513) == source:sub(38, 550))
assert(rom:readString(page - 17, 49) == source:sub(page - 16, page + 32),
  "readString must preserve bytes across a bounded-page boundary")

local bytes = rom:readBytes(page - 3, 6)
for i = 1, #bytes do
  assert(bytes[i] == source:byte(page - 3 + i))
end

local ok = pcall(rom.readString, rom, size - 2, 3)
assert(not ok, "readString must reject reads beyond the declared ROM")

-- Reproduce the Redmagic/Android 16 failure exactly: its tileset importer
-- calls readString while the supplied ROM handle exposes only readBytes.
local legacyArray = { size = #source }
function legacyArray:readBytes(offset, length)
  local out = {}
  for i = 1, length do out[i] = source:byte(offset + i) end
  return out
end

local Tileset = require("src.import.gba.tileset")
assert(StreamRom.installTilesetCompat(Tileset))
local metatiles = Tileset.loadMetatiles(legacyArray, 37, 32)
assert(metatiles.count == 2)
assert(metatiles.data == source:sub(38, 69),
  "legacy byte-array metatiles were not normalized")
local attributes = Tileset.loadAttributes(legacyArray, 91, 20)
assert(attributes.count == 5)
assert(attributes.data == source:sub(92, 111),
  "legacy byte-array attributes were not normalized")
local rawTiles = Tileset.loadTiles4bppRaw(legacyArray, 123, 64)
assert(rawTiles.count == 2)
assert(rawTiles.raw == source:sub(124, 187),
  "legacy byte-array tiles were not normalized")

-- Also cover minimal readers used by older/vendor payloads that expose only
-- byte-at-a-time access.
local getOnly = { size = #source }
function getOnly:get(offset) return source:byte(offset + 1) end
assert(StreamRom.readBinary(getOnly, page - 9, 27)
    == source:sub(page - 8, page + 18),
  "get-only ROM reader compatibility failed")

-- Schema 19 must validate the expanded audio tables themselves, not trust
-- headline counts left behind by a partial/stale cache write.
local Extractor = assert(loadfile(
  "mods/radical_red_experience/lib/rr_extract.lua"))()
local AudioProfile = {
  SPECIES_COUNT = 1376,
  AUDIO_SONG_COUNT = 526,
  SHA1 = "rr-v4.1-fixture",
}
local fullSongs, fullCries = {}, {}
for song = 0, AudioProfile.AUDIO_SONG_COUNT - 1 do
  fullSongs[song] = { id = song }
end
for cry = 0, AudioProfile.SPECIES_COUNT - 1 do
  fullCries[cry] = { sampleId = 1 }
end
local fullAudio = {
  cryCount = 1376,
  songCount = 526,
  romSha1 = AudioProfile.SHA1,
  songs = fullSongs,
  cries = fullCries,
  samples = { [1] = { id = 1 } },
}
assert(Extractor.expandedAudioIndexReady(fullAudio, AudioProfile),
  "complete schema-19 audio index was rejected")

local function copyIndex()
  local out = {}
  for k, v in pairs(fullAudio) do out[k] = v end
  return out
end

local bad = copyIndex()
bad.songs = {}
assert(not Extractor.expandedAudioIndexReady(bad, AudioProfile),
  "schema-19 audio accepted correct counts with an empty song table")

bad = copyIndex()
bad.songs = { [0] = {} }
assert(not Extractor.expandedAudioIndexReady(bad, AudioProfile),
  "schema-19 audio accepted a truncated song table")

bad = copyIndex()
bad.cries = { [0] = {} }
assert(not Extractor.expandedAudioIndexReady(bad, AudioProfile),
  "schema-19 audio accepted a truncated cry table")

bad = copyIndex()
bad.samples = {}
assert(not Extractor.expandedAudioIndexReady(bad, AudioProfile),
  "schema-19 audio accepted an empty sample index")

bad = copyIndex()
bad.romSha1 = "firered"
assert(not Extractor.expandedAudioIndexReady(bad, AudioProfile),
  "schema-19 audio accepted an index from the wrong ROM")

local expectedPlans = {
  [15] = { picCoords = true,  menuInfo = true,  battleAnims = true,  audio = true },
  [16] = { picCoords = false, menuInfo = true,  battleAnims = true,  audio = true },
  [17] = { picCoords = false, menuInfo = false, battleAnims = true,  audio = true },
  [18] = { picCoords = false, menuInfo = false, battleAnims = false, audio = true },
}
for schema, expected in pairs(expectedPlans) do
  local plan = assert(Extractor.cacheUpgradePlan(schema),
    "missing targeted upgrade plan for schema " .. schema)
  for key, value in pairs(expected) do
    assert(plan[key] == value,
      ("schema %d upgrade plan changed %s"):format(schema, key))
  end
end
assert(Extractor.cacheUpgradePlan(14) == nil
    and Extractor.cacheUpgradePlan(19) == nil,
  "targeted cache upgrader accepted an unsupported source schema")

local AnimProfile = {
  MOVE_COUNT = 1004,
  BATTLE_ANIM_TAG_COUNT = 371,
  BATTLE_ANIM_BG_COUNT = 77,
}
local fullAnim = {
  moves = {},
  labels = { sentinel = { { op = "end" } } },
  tagPals = {},
  animBgs = {},
}
for i = 0, AnimProfile.MOVE_COUNT - 1 do
  fullAnim.moves[i] = { { op = "end" } }
end
for i = 0, 370 do fullAnim.tagPals["TAG_" .. i] = {} end
for i = 0, 76 do fullAnim.animBgs[i] = { file = tostring(i) .. ".png" } end
assert(Extractor.expandedBattleAnimPackReady(fullAnim, AnimProfile),
  "complete expanded battle-animation pack was rejected")

local badAnim = {
  moves = { [0] = fullAnim.moves[0] },
  labels = fullAnim.labels,
  tagPals = fullAnim.tagPals,
  animBgs = fullAnim.animBgs,
}
assert(not Extractor.expandedBattleAnimPackReady(badAnim, AnimProfile),
  "animation cache accepted a missing final move row")

badAnim = {
  moves = fullAnim.moves, labels = {},
  tagPals = fullAnim.tagPals, animBgs = fullAnim.animBgs,
}
assert(not Extractor.expandedBattleAnimPackReady(badAnim, AnimProfile),
  "animation cache accepted an empty callback/label table")

badAnim = {
  moves = fullAnim.moves, labels = fullAnim.labels,
  tagPals = {}, animBgs = fullAnim.animBgs,
}
assert(not Extractor.expandedBattleAnimPackReady(badAnim, AnimProfile),
  "animation cache accepted missing particle palette rows")

badAnim = {
  moves = fullAnim.moves, labels = fullAnim.labels,
  tagPals = fullAnim.tagPals, animBgs = { [0] = fullAnim.animBgs[0] },
}
assert(not Extractor.expandedBattleAnimPackReady(badAnim, AnimProfile),
  "animation cache accepted truncated background rows")

-- Expanded RR animation packs can exceed LuaJIT's per-function 65,536
-- constant ceiling when serialized as one giant literal. The chunker must
-- preserve the exact pack shape while moving move/label constants into small
-- local filler functions that also work in an empty environment.
local sourceLines = {
  "return {",
  "  labels = {",
}
for i = 1, 96 do
  sourceLines[#sourceLines + 1] = ('    ["L%d"] = {'):format(i)
  sourceLines[#sourceLines + 1] = '      {'
  sourceLines[#sourceLines + 1] = '        op = "end"'
  sourceLines[#sourceLines + 1] = '      }'
  sourceLines[#sourceLines + 1] = i < 96 and '    },' or '    }'
end
sourceLines[#sourceLines + 1] = "  },"
sourceLines[#sourceLines + 1] = "  moves = {"
for i = 0, 95 do
  sourceLines[#sourceLines + 1] = ("    [%d] = {"):format(i)
  sourceLines[#sourceLines + 1] = '      {'
  sourceLines[#sourceLines + 1] = '        op = "end"'
  sourceLines[#sourceLines + 1] = '      }'
  sourceLines[#sourceLines + 1] = i < 95 and '    },' or '    }'
end
sourceLines[#sourceLines + 1] = "  },"
sourceLines[#sourceLines + 1] = "  version = 5"
sourceLines[#sourceLines + 1] = "}"
sourceLines[#sourceLines + 1] = ""

local chunked = Extractor.chunkBattleAnimPackSource(
  table.concat(sourceLines, "\n"), 8)
assert(chunked:find("RR chunked battle%-animation pack", 1, false),
  "battle-animation pack chunker did not rewrite the monolith")
local loader = loadstring or load
local chunk, chunkErr = loader(chunked, "@rr_chunked_anim_fixture")
assert(chunk, "chunked battle-animation fixture would not compile: "
  .. tostring(chunkErr))
if setfenv then setfenv(chunk, {}) end
local okChunk, chunkPack = pcall(chunk)
assert(okChunk and type(chunkPack) == "table"
    and chunkPack.version == 5
    and chunkPack.moves[0][1].op == "end"
    and chunkPack.moves[95][1].op == "end"
    and chunkPack.labels.L1[1].op == "end"
    and chunkPack.labels.L96[1].op == "end",
  "chunked battle-animation pack changed the reconstructed table")

print("PASS stream_rom_compat_test: strings, byte arrays, get-only, Android tilesets, schema15-19 cache, chunked anim pack")
