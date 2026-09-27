-- Bounded, string-backed ROM reader for Radical Red's first launch.
--
-- The stock extractor's reader expands each cached 4 MiB ROM page into a Lua
-- number table.  Several pages can therefore consume hundreds of megabytes on
-- 64-bit Android.  This reader keeps at most sixteen 256 KiB strings instead,
-- while exposing the same methods used by the stock extraction modules.

local StreamRom = {}

local PAGE_SIZE = 256 * 1024
local MAX_PAGES = 16

local Rom = {}
Rom.__index = Rom

-- Engine releases disagree about the binary-slice method available on a ROM
-- handle.  Newer importers call readString, older Android payloads expose
-- readBytes, and a few vendor builds provide only get.  Keep the conversion
-- here, inside the mod, so the same package can feed every supported tileset
-- importer without modifying the installed engine.
local function normalizeBinary(data, length)
  if type(data) == "string" then
    assert(#data == length,
      ("short binary ROM read: expected %d, got %d"):format(length, #data))
    return data
  end

  local kind = type(data)
  assert(kind == "table" or kind == "userdata" or kind == "cdata",
    "ROM reader returned unsupported binary data type " .. kind)
  local zeroBased = false
  local okZero, zero = pcall(function() return data[0] end)
  if okZero and zero ~= nil then zeroBased = true end

  local chunks, chars = {}, {}
  for i = 0, length - 1 do
    local index = zeroBased and i or (i + 1)
    local value
    if kind == "table" then
      value = data[index]
    else
      local ok
      ok, value = pcall(function() return data[index] end)
      assert(ok,
        ("failed byte-array ROM read at byte %d of %d"):format(i, length))
    end
    assert(value ~= nil,
      ("short byte-array ROM read at byte %d of %d"):format(i, length))
    value = tonumber(value)
    assert(value and value >= 0 and value <= 255,
      ("invalid ROM byte at %d: %s"):format(i, tostring(value)))
    chars[#chars + 1] = string.char(math.floor(value))
    if #chars == 4096 then
      chunks[#chunks + 1] = table.concat(chars)
      chars = {}
    end
  end
  if #chars > 0 then chunks[#chunks + 1] = table.concat(chars) end
  return table.concat(chunks)
end

local function readBinary(reader, offset, length)
  offset, length = tonumber(offset), tonumber(length)
  assert(offset and length and offset >= 0 and length >= 0,
    "invalid ROM binary read range")
  if length == 0 then return "" end

  local errors = {}
  for _, name in ipairs({ "readString", "readBytes" }) do
    local method = reader and reader[name]
    if type(method) == "function" then
      local ok, value = pcall(method, reader, offset, length)
      if ok and value ~= nil then
        local normalized, result = pcall(normalizeBinary, value, length)
        if normalized then return result end
        errors[#errors + 1] = name .. ": " .. tostring(result)
      else
        errors[#errors + 1] = name .. ": " .. tostring(value)
      end
    end
  end

  local get = reader and reader.get
  if type(get) == "function" then
    local chars, chunks = {}, {}
    for i = 0, length - 1 do
      local value = assert(tonumber(get(reader, offset + i)),
        "ROM get returned a non-byte value")
      assert(value >= 0 and value <= 255,
        ("invalid ROM byte at 0x%X: %s"):format(offset + i, tostring(value)))
      chars[#chars + 1] = string.char(math.floor(value))
      if #chars == 4096 then
        chunks[#chunks + 1] = table.concat(chars)
        chars = {}
      end
    end
    if #chars > 0 then chunks[#chunks + 1] = table.concat(chars) end
    return table.concat(chunks)
  end

  error("ROM reader has no usable readString, readBytes, or get method"
    .. (#errors > 0 and (" (" .. table.concat(errors, "; ") .. ")") or ""))
end

local function pageIndex(offset)
  return math.floor(offset / PAGE_SIZE)
end

function Rom:_page(index)
  local cached = self._pages[index]
  if cached then
    self._clock = self._clock + 1
    self._used[index] = self._clock
    return cached
  end

  local offset = index * PAGE_SIZE
  local length = math.min(PAGE_SIZE, self.size - offset)
  if length <= 0 then return nil end
  local bytes, err = self.imports:read(self.id, offset, length)
  assert(bytes, err or "Radical Red ROM read failed")
  assert(#bytes == length,
    ("short Radical Red ROM read at 0x%X: expected %d, got %d")
      :format(offset, length, #bytes))

  if self._count >= MAX_PAGES then
    local oldest, oldestTick
    for page, tick in pairs(self._used) do
      if not oldestTick or tick < oldestTick then
        oldest, oldestTick = page, tick
      end
    end
    if oldest ~= nil then
      self._pages[oldest] = nil
      self._used[oldest] = nil
      self._count = self._count - 1
    end
  end

  self._clock = self._clock + 1
  self._pages[index] = bytes
  self._used[index] = self._clock
  self._count = self._count + 1
  return bytes
end

function Rom:get(offset)
  if offset < 0 or offset >= self.size then
    error(("ROM OOB 0x%X"):format(offset))
  end
  local page = pageIndex(offset)
  return assert(self:_page(page):byte((offset % PAGE_SIZE) + 1))
end

function Rom:readBytes(offset, length)
  if offset < 0 or length < 0 or offset + length > self.size then
    error(("ROM OOB readBytes 0x%X + %d"):format(offset, length))
  end
  local out, count = {}, 0
  local cursor, remaining = offset, length
  -- Older Android importers require a numeric byte array. Copy directly from
  -- each cached string page instead of calling get(), which updates the LRU
  -- tables for every single byte and made script extraction spend several
  -- seconds in one frame on affected devices.
  while remaining > 0 do
    local page = pageIndex(cursor)
    local localOffset = cursor % PAGE_SIZE
    local bytes = assert(self:_page(page))
    local take = math.min(remaining, #bytes - localOffset)
    assert(take > 0, ("short Radical Red ROM page at 0x%X"):format(cursor))
    local first = localOffset + 1
    local last = first + take - 1
    while first <= last do
      -- Keep vararg expansion comfortably below LuaJIT's stack limit.
      local stop = math.min(first + 4095, last)
      local values = { bytes:byte(first, stop) }
      for i = 1, #values do
        count = count + 1
        out[count] = values[i]
      end
      first = stop + 1
    end
    cursor = cursor + take
    remaining = remaining - take
  end
  return out
end

-- gen1recomp 0.3.20 switched the Gen III map/tileset importer from numeric
-- byte arrays to binary strings.  Keep this reader as the bounded Android
-- implementation while exposing the newer API as well, so one mod package
-- runs on both 0.3.5 and 0.3.20.
function Rom:readString(offset, length)
  if offset < 0 or length < 0 or offset + length > self.size then
    error(("ROM OOB readString 0x%X + %d"):format(offset, length))
  end
  if length == 0 then return "" end

  local out = {}
  local cursor = offset
  local remaining = length
  while remaining > 0 do
    local page = pageIndex(cursor)
    local localOffset = cursor % PAGE_SIZE
    local bytes = assert(self:_page(page))
    local take = math.min(remaining, #bytes - localOffset)
    assert(take > 0, ("short Radical Red ROM page at 0x%X"):format(cursor))
    out[#out + 1] = bytes:sub(localOffset + 1, localOffset + take)
    cursor = cursor + take
    remaining = remaining - take
  end
  return table.concat(out)
end

function Rom:u16(offset)
  return self:get(offset) + self:get(offset + 1) * 256
end

function Rom:u32(offset)
  return self:get(offset)
    + self:get(offset + 1) * 256
    + self:get(offset + 2) * 65536
    + self:get(offset + 3) * 16777216
end

function Rom:ptrOffset(pointer)
  if pointer < 0x08000000 or pointer >= 0x0A000000 then return nil end
  return pointer - 0x08000000
end

function Rom:clearCache()
  self._pages, self._used, self._count = {}, {}, 0
end

-- Patch only the three stock tileset helpers that require binary slices.  The
-- public shapes and return values stay identical; only the reader negotiation
-- changes.  This directly covers the Android failure at tileset.lua:105.
function StreamRom.installTilesetCompat(Tileset)
  assert(type(Tileset) == "table", "missing GBA tileset module")
  if Tileset.__rrPortableBinaryReader then return true end

  Tileset.loadTiles4bppRaw = function(rom, offset, nbytes)
    nbytes = tonumber(nbytes) or 0
    if nbytes < 32 then return { count = 0, raw = "" } end
    local raw = readBinary(rom, offset, nbytes)
    return { count = math.floor(nbytes / 32), raw = raw }
  end

  Tileset.loadMetatiles = function(rom, offset, nbytes)
    nbytes = assert(tonumber(nbytes), "missing metatile byte count")
    local data = readBinary(rom, offset, nbytes)
    return { data = data, count = math.floor(nbytes / 16) }
  end

  Tileset.loadAttributes = function(rom, offset, nbytes)
    nbytes = assert(tonumber(nbytes), "missing attribute byte count")
    local data = readBinary(rom, offset, nbytes)
    return { data = data, count = math.floor(nbytes / 4) }
  end

  Tileset.__rrPortableBinaryReader = true
  return true
end

StreamRom.readBinary = readBinary

function StreamRom.open(imports, id)
  local info, err = imports:info(id)
  if not info then return nil, err end
  local reader = setmetatable({
    imports = imports,
    id = id,
    size = assert(info.size),
    md5 = info.md5,
    _pages = {},
    _used = {},
    _count = 0,
    _clock = 0,
  }, Rom)
  -- Store both binary methods directly as well as through __index.  This
  -- survives host wrappers that copy instance fields but do not preserve a
  -- Lua metatable, which occurs in some Android importer builds.
  reader.readBytes = Rom.readBytes
  reader.readString = Rom.readString
  return reader
end

return StreamRom
