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

print("PASS stream_rom_compat_test: strings, byte arrays, get-only, Android tilesets")
