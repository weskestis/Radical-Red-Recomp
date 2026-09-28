-- Radical Red v4.1 visual compatibility fixes.
--
-- RR expands FireRed's object-event palette table from 18 entries to 451.
-- The stock extractor intentionally scans only a small vanilla-sized window,
-- so RR-only palette tags otherwise fall back to an all-black palette.  This
-- module teaches the existing extractor to honor an explicit profile count.
-- It also isolates both Game3's regular OPTIONS screen and the ROM-driven
-- Choice windows used by Radical Red's Game Modes setup from number-only
-- setColor shims used by some Android builds.  The affected renderer can leave
-- a responsive but completely black screen after the first table-color call.

local Visuals = {}

local EXPECTED_GRAPHICS = {
  { selector = 0, index = 0, encoded = 0,
    palette = 0x1100, width = 16, height = 32 }, -- Red
  { selector = 0, index = 7, encoded = 7,
    palette = 0x1110, width = 16, height = 32 }, -- Leaf
  { selector = 0, index = 88, encoded = 88,
    palette = 0x1168, width = 16, height = 32 }, -- Mom
  { selector = 0, index = 152, encoded = 152,
    palette = 0x11D5, width = 32, height = 32 },
  -- Pallet Town's Route 21 blocker. Its map record stores low byte 110 and
  -- selector 1; dropping the selector drew ordinary-table graphic 110 while
  -- its script correctly said and cried Stufful.
  { selector = 1, index = 110, encoded = 0x016E,
    palette = 0x1281, width = 32, height = 32 },
  { selector = 2, index = 0, encoded = 0x0200,
    palette = 0x12F3, width = 16, height = 32 },
}

-- RR's Black/White-style party screen replaces FireRed's one large card plus
-- five narrow rows with a two-column 14x5-tile grid. These records are read
-- directly from the v4.1 ROM's sPartyMenu* tables (0x459EC4..0x45A03F).
local RR_PARTY_WINDOWS = {
  { left = 1,  top = 0,  w = 14, h = 5, kind = "main" },
  { left = 15, top = 1,  w = 14, h = 5, kind = "wide" },
  { left = 1,  top = 5,  w = 14, h = 5, kind = "wide" },
  { left = 15, top = 6,  w = 14, h = 5, kind = "wide" },
  { left = 1,  top = 10, w = 14, h = 5, kind = "wide" },
  { left = 15, top = 11, w = 14, h = 5, kind = "wide" },
}

local RR_PARTY_SPRITES = {
  { 34,  12,  34,  24,  26,  33,  24,  16 },
  { 146, 20, 146,  32, 138,  41, 136,  24 },
  { 34,  52,  34,  64,  26,  73,  24,  56 },
  { 146, 60, 146,  72, 138,  81, 136,  64 },
  { 34,  92,  34, 104,  26, 113,  24,  96 },
  { 146,100, 146, 112, 138, 121, 136, 104 },
}

local RR_PARTY_INFO_LEFT = {
  nick = { 30, 3 }, level = { 80, 3 }, gender = { 30, 12 },
  hp = { 56, 19 }, hpMax = { 80, 19 }, hpBar = { 64, 18 },
  desc = { 56, 17 },
}

local RR_PARTY_INFO_RIGHT = {
  nick = { 40, 5 }, level = { 5, 25 }, gender = { 98, 5 },
  hp = { 59, 25 }, hpMax = { 74, 25 }, hpBar = { 56, 22 },
  desc = { 40, 25 },
}

local function copyRecord(source)
  local out = {}
  for key, value in pairs(source or {}) do out[key] = value end
  return out
end

local FR_PARTY_WINDOWS = {
  single = {
    { left = 1, top = 3 }, { left = 12, top = 1 },
    { left = 12, top = 4 }, { left = 12, top = 7 },
    { left = 12, top = 10 }, { left = 12, top = 13 },
  },
  double = {
    { left = 1, top = 1 }, { left = 1, top = 8 },
    { left = 12, top = 1 }, { left = 12, top = 5 },
    { left = 12, top = 9 }, { left = 12, top = 13 },
  },
}

local FR_PARTY_SPRITES = {
  single = {
    { 16, 40, 20, 50, 56, 52, 16, 34 },
    { 104, 18, 108, 28, 144, 27, 102, 25 },
    { 104, 42, 108, 52, 144, 51, 102, 49 },
    { 104, 66, 108, 76, 144, 75, 102, 73 },
    { 104, 90, 108, 100, 144, 99, 102, 97 },
    { 104, 114, 108, 124, 144, 123, 102, 121 },
  },
  double = {
    { 16, 24, 20, 34, 56, 36, 16, 18 },
    { 16, 80, 20, 90, 56, 92, 16, 74 },
    { 104, 18, 108, 28, 144, 27, 102, 25 },
    { 104, 50, 108, 60, 144, 59, 102, 57 },
    { 104, 82, 108, 92, 144, 91, 102, 89 },
    { 104, 114, 108, 124, 144, 123, 102, 121 },
  },
}

local FR_PARTY_INFO_LEFT = {
  nick = { 24, 11 }, level = { 32, 20 }, gender = { 64, 20 },
  hp = { 38, 36 }, hpMax = { 53, 36 }, hpBar = { 24, 35 },
  desc = { 12, 34 },
}

local FR_PARTY_INFO_RIGHT = {
  nick = { 22, 3 }, level = { 32, 12 }, gender = { 64, 12 },
  hp = { 102, 12 }, hpMax = { 117, 12 }, hpBar = { 88, 10 },
  desc = { 77, 4 },
}

local PARTY_INFO_KEYS = {
  "nick", "level", "gender", "hp", "hpMax", "hpBar", "desc",
}

local function bufferLength(buffer)
  if type(buffer) == "string" then return #buffer end
  if type(buffer) == "table" then return buffer._len or #buffer end
  return 0
end

local function bufferByte(buffer, index)
  if type(buffer) == "string" then return buffer:byte(index) or 0 end
  return (buffer and buffer[index]) or 0
end

local function bgr555Rgb(color)
  color = (tonumber(color) or 0) % 0x8000
  local r = color % 32
  local g = math.floor(color / 32) % 32
  local b = math.floor(color / 1024) % 32
  return math.floor(r * 255 / 31 + 0.5),
    math.floor(g * 255 / 31 + 0.5),
    math.floor(b * 255 / 31 + 0.5)
end

local function partyPaletteBanks(bytes)
  local banks = {}
  for bank = 0, math.floor(bufferLength(bytes) / 32) - 1 do
    local colors = {}
    for color = 0, 15 do
      local index = bank * 32 + color * 2 + 1
      colors[color] = bufferByte(bytes, index)
        + bufferByte(bytes, index + 1) * 0x100
    end
    banks[bank] = colors
  end
  return banks
end


local function rrPartyPalette(palBytes, selected, multi)
  local banks = partyPaletteBanks(palBytes)
  local base = banks[3] or banks[0] or {}
  local palette = {}
  for index = 0, 15 do palette[index] = base[index] or 0 end
  local function color(id)
    local bank, index = math.floor(id / 16), id % 16
    return (banks[bank] and banks[bank][index]) or 0
  end
  if multi and selected then
    palette[4], palette[5], palette[6] = color(132), color(133), color(134)
    palette[1], palette[7], palette[8] = color(97), color(103), color(104)
  elseif multi then
    palette[4], palette[5], palette[6] = color(68), color(69), color(70)
    palette[1], palette[7], palette[8] = color(65), color(71), color(72)
  elseif selected then
    palette[4], palette[5], palette[6] = color(116), color(117), color(118)
    palette[1], palette[7], palette[8] = color(97), color(103), color(104)
  else
    palette[4], palette[5], palette[6] = color(52), color(53), color(54)
    palette[1], palette[7], palette[8] = color(49), color(55), color(56)
  end
  return palette
end

local function rrBakePartySlot(gfx, tilemap, palette)
  local width, height = 112, 40
  local pixels = {}
  for index = 1, width * height do pixels[index] = 0 end
  local tileCount = math.floor(bufferLength(gfx) / 32)
  for tileY = 0, 4 do
    for tileX = 0, 13 do
      local tileId = tilemap:byte(tileY * 14 + tileX + 1) or 0
      if tileId >= tileCount then tileId = 0 end
      local base = tileId * 32
      for row = 0, 7 do
        for pair = 0, 3 do
          local byte = bufferByte(gfx, base + row * 4 + pair + 1)
          local x = tileX * 8 + pair * 2
          local y = tileY * 8 + row
          pixels[y * width + x + 1] = byte % 16
          pixels[y * width + x + 2] = math.floor(byte / 16) % 16
        end
      end
    end
  end
  local rgba = {}
  for index = 1, width * height do
    local colorIndex = pixels[index] or 0
    if colorIndex == 0 then
      rgba[index] = string.char(0, 0, 0, 0)
    else
      local r, g, b = bgr555Rgb(palette[colorIndex] or 0)
      rgba[index] = string.char(r, g, b, 255)
    end
  end
  return table.concat(rgba)
end


-- CFRU extends FireRed's gMoveMenuInfoIcons table with the Fairy badge at
-- tile 0x100. The stock host reads/bakes only 16x16 tiles (128x128), ending at
-- 0xFF, so type 23 is physically truncated and the renderer falls back to
-- NORMAL. RR needs 16x18 tiles: Fairy starts at (0,128) and is 32x12.
local RR_MENU_INFO_W, RR_MENU_INFO_H = 128, 144
local RR_FAIRY_TYPE, RR_FAIRY_X, RR_FAIRY_Y = 23, 0, 128

local function rrMenuInfoRgba(rom, Versions)
  local gfxBytes = {}
  local gfxLen = RR_MENU_INFO_W * RR_MENU_INFO_H / 2
  for index = 0, gfxLen - 1 do
    gfxBytes[index + 1] = rom:get(Versions.MENU_INFO_GFX + index)
  end
  local palBytes = {}
  for index = 0, 63 do
    palBytes[index + 1] = rom:get(Versions.MENU_INFO_PAL + index)
  end
  local palettes = partyPaletteBanks(palBytes)
  local out = {}
  local tilesWide, tilesHigh = 16, 18
  for tileY = 0, tilesHigh - 1 do
    local palette = palettes[tileY < 2 and 0 or 1] or palettes[0] or {}
    for row = 0, 7 do
      for tileX = 0, tilesWide - 1 do
        local tile = tileY * tilesWide + tileX
        local base = tile * 32 + row * 4
        for pair = 0, 3 do
          local byte = gfxBytes[base + pair + 1] or 0
          local lo, hi = byte % 16, math.floor(byte / 16) % 16
          for sub = 0, 1 do
            local colorIndex = (sub == 0) and lo or hi
            if colorIndex == 0 then
              out[#out + 1] = string.char(0, 0, 0, 0)
            else
              local r, g, b = bgr555Rgb(palette[colorIndex] or 0)
              out[#out + 1] = string.char(r, g, b, 255)
            end
          end
        end
      end
    end
  end
  local rgba = table.concat(out)
  assert(#rgba == RR_MENU_INFO_W * RR_MENU_INFO_H * 4,
    "Radical Red expanded menu-info sheet has the wrong dimensions")
  return rgba
end

local function writeExpandedMenuInfo(rom, cache, Profile)
  local Versions = require("src.import.gba.versions")
  Profile.apply(Versions)
  local root = Profile.extractRoot() .. "/pokemon/summary/menu_info.rgba"
  local rgba = rrMenuInfoRgba(rom, Versions)
  local ok, err = cache:write(root, rgba)
  assert(ok ~= false and ok ~= nil,
    "could not write Radical Red Fairy type badge sheet: " .. tostring(err))
  return {
    width = RR_MENU_INFO_W, height = RR_MENU_INFO_H,
    fairyType = RR_FAIRY_TYPE, fairyX = RR_FAIRY_X, fairyY = RR_FAIRY_Y,
    bytes = #rgba,
  }
end

local function installSummaryChromeExtraction(Profile)
  local SummaryExtract = require("src.import.gba.summary_chrome_extract")
  if SummaryExtract.__rrFairyBadgePatch then return end
  local original = assert(SummaryExtract.run)
  SummaryExtract.run = function(rom, cache, opts)
    local report = original(rom, cache, opts)
    local fairy = writeExpandedMenuInfo(rom, cache, Profile)
    report = report or {}
    report.rrMenuInfoWidth = fairy.width
    report.rrMenuInfoHeight = fairy.height
    report.rrFairyTypeBadge = true
    return report
  end
  SummaryExtract.__rrFairyBadgeOriginal = original
  SummaryExtract.__rrFairyBadgePatch = true
end

local function rrImageFromRgba(raw, width, height)
  if not (love and love.image and love.graphics and raw
      and #raw >= width * height * 4) then return nil end
  local ok, imageData = pcall(love.image.newImageData,
    width, height, "rgba8", raw)
  if not ok or not imageData then
    imageData = love.image.newImageData(width, height)
    local at = 1
    for y = 0, height - 1 do
      for x = 0, width - 1 do
        imageData:setPixel(x, y,
          (raw:byte(at) or 0) / 255,
          (raw:byte(at + 1) or 0) / 255,
          (raw:byte(at + 2) or 0) / 255,
          (raw:byte(at + 3) or 0) / 255)
        at = at + 4
      end
    end
  end
  local image = love.graphics.newImage(imageData)
  if image and image.setFilter then image:setFilter("nearest", "nearest") end
  return image
end

local function installFairyTypeBadgeRuntime(Profile)
  local SummaryChrome = require("src.ui.game3.summary_chrome")
  if SummaryChrome.__rrFairyBadgePatch then return true end
  local originalImage = assert(SummaryChrome.menuInfoImage)
  local originalDraw = assert(SummaryChrome.drawTypeBadge)

  local function expandedImage()
    if SummaryChrome.__rrFairyMenuInfo then return SummaryChrome.__rrFairyMenuInfo end
    local Dataset = require("src.core.game3.dataset")
    local cache = Dataset.cache and Dataset.cache()
    local root = Profile.extractRoot() .. "/pokemon/summary/menu_info.rgba"
    local raw = cache and cache.read and cache:read(root)
    if type(raw) == "string" and #raw >= RR_MENU_INFO_W * RR_MENU_INFO_H * 4 then
      local image = rrImageFromRgba(raw, RR_MENU_INFO_W, RR_MENU_INFO_H)
      if image then
        SummaryChrome.__rrFairyMenuInfo = image
        SummaryChrome._menuInfo = image
        return image
      end
    end
    return originalImage()
  end

  SummaryChrome.menuInfoImage = expandedImage
  SummaryChrome.drawTypeBadge = function(typeId, x, y)
    if type(typeId) == "string" then
      if typeId:upper() == "FAIRY" then typeId = RR_FAIRY_TYPE end
    end
    typeId = tonumber(typeId) or 0
    if typeId ~= RR_FAIRY_TYPE then return originalDraw(typeId, x, y) end
    if not (love and love.graphics) then return end
    local image = expandedImage()
    if not image then return originalDraw(0, x, y) end
    local quad = SummaryChrome.__rrFairyQuad
    if not quad then
      quad = love.graphics.newQuad(RR_FAIRY_X, RR_FAIRY_Y, 32, 12,
        RR_MENU_INFO_W, RR_MENU_INFO_H)
      SummaryChrome.__rrFairyQuad = quad
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, quad, x, y)
  end
  SummaryChrome.__rrFairyBadgeOriginalImage = originalImage
  SummaryChrome.__rrFairyBadgeOriginalDraw = originalDraw
  SummaryChrome.__rrFairyBadgePatch = true

  -- Pokédex owns a second hardcoded vanilla 0..17 badge table. Keep it on the
  -- same expanded RR sheet so every UI surface agrees with Summary/TM Case.
  local okDex, PokedexChrome = pcall(require, "src.ui.game3.pokedex_chrome")
  if okDex and PokedexChrome and PokedexChrome.drawTypeBadge
      and not PokedexChrome.__rrFairyBadgePatch then
    local dexOriginal = PokedexChrome.drawTypeBadge
    PokedexChrome.drawTypeBadge = function(typeId, x, y)
      if type(typeId) == "string" and typeId:upper() == "FAIRY" then
        typeId = RR_FAIRY_TYPE
      end
      if tonumber(typeId) ~= RR_FAIRY_TYPE then
        return dexOriginal(typeId, x, y)
      end
      return SummaryChrome.drawTypeBadge(RR_FAIRY_TYPE, x, y)
    end
    PokedexChrome.__rrFairyBadgeOriginal = dexOriginal
    PokedexChrome.__rrFairyBadgePatch = true
  end
  return true
end

local function graphicsTables(Profile)
  return {
    [0] = {
      pointers = Profile.OFFSET.overworldGraphicsPointers,
      count = Profile.OW_RUNTIME_PRIMARY_COUNT,
      physicalCount = Profile.OW_COUNT,
    },
    [1] = {
      pointers = Profile.OFFSET.overworldPokemonGraphicsPointers,
      count = Profile.OW_POKEMON_COUNT,
    },
    [2] = {
      pointers = Profile.OFFSET.overworldPlayerGraphicsPointers,
      count = Profile.OW_PLAYER_COUNT,
    },
  }
end

local function validateGraphicsInfo(rom, pointers, graphicsId, expected)
  local infoOff = rom:ptrOffset(rom:u32(pointers + graphicsId * 4))
  assert(infoOff,
    ("invalid Radical Red overworld graphics pointer 0x%04X")
      :format(expected.encoded or graphicsId))
  local palette = rom:u16(infoOff + 2)
  local width = rom:u16(infoOff + 8)
  local height = rom:u16(infoOff + 10)
  assert(palette == expected.palette and width == expected.width
      and height == expected.height,
    ("Radical Red overworld table sentinel 0x%04X is wrong "
      .. "(palette 0x%04X, %dx%d)")
      :format(expected.encoded or graphicsId, palette, width, height))
  return infoOff
end

local function expandedPaletteTable(rom, version, count)
  local tableOff = assert(version.ow_sprite_palettes,
    "Radical Red overworld palette table is missing")
  local palsByTag = {}

  for i = 0, count - 1 do
    local off = tableOff + i * 8
    local dataPtr = rom:u32(off)
    local tag = rom:u16(off + 4)
    local dataOff = rom:ptrOffset(dataPtr)
    assert(dataOff and tag ~= 0,
      ("invalid Radical Red overworld palette entry %d"):format(i))
    assert(not palsByTag[tag],
      ("duplicate Radical Red overworld palette tag 0x%04X"):format(tag))

    local colors, hasColor = {}, false
    for c = 0, 15 do
      local color = rom:u16(dataOff + c * 2)
      colors[c] = color
      if c > 0 and color ~= 0 then hasColor = true end
    end
    assert(hasColor,
      ("empty Radical Red overworld palette tag 0x%04X"):format(tag))
    palsByTag[tag] = colors
  end

  -- Validate all three tables used by RR's 16-bit object-graphics resolver.
  -- Missing tags used to be silently replaced with sixteen black colors by
  -- ow_extract.extractOne; ignoring the selector byte instead produced a
  -- perfectly valid but unrelated ordinary-table sprite.
  local tables = assert(version.rr_ow_tables,
    "Radical Red overworld graphics tables are missing")
  local spriteCount, physicalCount = 0, 0
  local used, usedCount = {}, 0
  for selector = 0, 2 do
    local desc = assert(tables[selector],
      ("Radical Red overworld table %d is missing"):format(selector))
    local tableCount = assert(tonumber(desc.count),
      ("Radical Red overworld table %d count is missing"):format(selector))
    local validateCount = tonumber(desc.physicalCount) or tableCount
    spriteCount = spriteCount + tableCount
    physicalCount = physicalCount + validateCount
    for graphicsId = 0, validateCount - 1 do
      local encoded = selector * 0x100 + graphicsId
      local infoOff = rom:ptrOffset(rom:u32(desc.pointers + graphicsId * 4))
      assert(infoOff,
        ("invalid Radical Red overworld graphics pointer 0x%04X")
          :format(encoded))
      local tag = rom:u16(infoOff + 2)
      assert(palsByTag[tag],
        ("Radical Red overworld graphic 0x%04X needs missing palette 0x%04X")
          :format(encoded, tag))
      if graphicsId < tableCount and not used[tag] then
        used[tag], usedCount = true, usedCount + 1
      end
    end
  end

  -- These IDs deliberately span ordinary NPCs, Pokemon, and custom players.
  for _, expected in ipairs(EXPECTED_GRAPHICS) do
    local desc = assert(tables[expected.selector])
    assert(expected.index < desc.count,
      ("Radical Red overworld graphics tables omit sentinel 0x%04X")
        :format(expected.encoded))
    validateGraphicsInfo(rom, desc.pointers, expected.index, expected)
  end

  Visuals._paletteReport = {
    paletteCount = count,
    spriteCount = spriteCount,
    physicalSpriteCount = physicalCount,
    graphicsTableCount = 3,
    usedPaletteCount = usedCount,
    playerPaletteTag = 0x1100,
    momPaletteTag = 0x1168,
    stuffulGraphicsId = 0x016E,
  }
  return palsByTag
end

local function installExpandedMapGraphics(Profile)
  local ExtractMapEvents = require("src.import.gba.extract_map_events")
  if ExtractMapEvents.__rrExpandedGraphicsIdPatch then return end
  local original = assert(ExtractMapEvents.parseMapEvents)
  local tables = graphicsTables(Profile)

  ExtractMapEvents.parseMapEvents = function(rom, eventsPtr)
    local parsed = original(rom, eventsPtr)
    local digest = type(rom and rom.md5) == "string" and rom.md5:lower() or nil
    if not parsed or (digest ~= Profile.MD5 and digest ~= Profile.SHA1) then
      return parsed
    end
    local eventsOff = rom:ptrOffset(eventsPtr)
    local objectCount = eventsOff and rom:get(eventsOff) or 0
    local objectsOff = eventsOff and rom:ptrOffset(rom:u32(eventsOff + 4))
    assert(objectCount == #(parsed.objects or {}),
      "Radical Red object-event count changed during extraction")
    if objectCount > 0 then
      assert(objectsOff, "Radical Red object-event table pointer is invalid")
    end
    for index, obj in ipairs(parsed.objects or {}) do
      local base = objectsOff + (index - 1) * 24
      local low = rom:get(base + 1)
      -- CFRU uses the formerly-padding byte at +3 as the high-byte selector.
      local selector = rom:get(base + 3)
      local desc = tables[selector]
      local indirect = selector == 0xFF and low <= 0x0F
      assert(indirect or (desc and low < desc.count),
        ("invalid Radical Red object graphics id %d:0x%02X (kind %s)")
          :format(selector, low, tostring(obj.kind)))
      local encoded = selector * 0x100 + low
      obj.graphicsBaseId = low
      obj.graphicsTable = selector
      obj.graphicsId = encoded
      obj.graphics = encoded
      if selector ~= 0 then
        obj.sprite = ("RR_GFX_%d_%03d"):format(selector, low)
      end
    end
    return parsed
  end
  ExtractMapEvents.__rrExpandedGraphicsIdPatch = true
end

local function installExpandedOwExtraction(Profile)
  local OwExtract = require("src.import.gba.ow_extract")
  if OwExtract.__rrExpandedGraphicsTablesPatch then return end
  local originalExtractOne = assert(OwExtract.extractOne)
  local originalCollectAllIds = assert(OwExtract.collectAllIds)

  OwExtract.extractOne = function(rom, graphicsId, palsByTag, version)
    local tables = version and version.rr_ow_tables
    if not tables then
      return originalExtractOne(rom, graphicsId, palsByTag, version)
    end
    graphicsId = math.floor(tonumber(graphicsId) or -1)
    local selector = math.floor(graphicsId / 0x100)
    local index = graphicsId % 0x100
    local desc = tables[selector]
    if graphicsId < 0 or not desc or index >= desc.count then
      return nil, "graphicsId out of Radical Red table range"
    end
    local scoped = {}
    for key, value in pairs(version) do scoped[key] = value end
    scoped.ow_gfx_pointers = desc.pointers
    scoped.num_obj_event_gfx = desc.count
    scoped.rr_ow_tables = nil
    local sprite, err = originalExtractOne(
      rom, index, palsByTag, scoped)
    if sprite then sprite.graphicsId = graphicsId end
    return sprite, err
  end

  OwExtract.collectAllIds = function(version)
    local tables = version and version.rr_ow_tables
    if not tables then return originalCollectAllIds(version) end
    local ids = {}
    for selector = 0, 2 do
      local desc = assert(tables[selector])
      for index = 0, desc.count - 1 do
        ids[#ids + 1] = selector * 0x100 + index
      end
    end
    return ids
  end
  OwExtract.__rrExpandedGraphicsTablesPatch = true
end

local function installPartyChromeExtraction(Profile)
  local PartyExtract = require("src.import.gba.party_chrome_extract")
  if PartyExtract.__rrBwGridPatch then return end

  local original = assert(PartyExtract.run)
  local Lz77 = require("src.import.gba.lz77")
  local Versions = require("src.import.gba.versions")

  PartyExtract.run = function(rom, cache, opts)
    local report = original(rom, cache, opts)
    local root = assert(report and report.root,
      "Radical Red party chrome extraction root is missing")
    local function get(offset) return rom:get(offset) end
    local gfx = assert(Lz77.decompress(get, Versions.PARTY_MENU_BG_GFX),
      "Radical Red party chrome graphics failed to decompress")
    local pal = assert(Lz77.decompress(get, Versions.PARTY_MENU_BG_PAL),
      "Radical Red party chrome palette failed to decompress")

    local function raw(offset, length)
      local bytes = {}
      for index = 0, length - 1 do
        bytes[index + 1] = string.char(get(offset + index))
      end
      return table.concat(bytes)
    end

    -- Both filled shapes use the same 14x5 RR tilemap. The separate filenames
    -- are retained because PartyChrome's public contract distinguishes the
    -- first slot from later/empty slots.
    local filled = raw(Profile.OFFSET.partyMenuSlotTilemap, 14 * 5)
    local empty = raw(Profile.OFFSET.partyMenuSlotEmptyTilemap, 14 * 5)
    local palettes = {
      normal = rrPartyPalette(pal, false),
      selected = rrPartyPalette(pal, true),
      multi = rrPartyPalette(pal, false, true),
      multiSelected = rrPartyPalette(pal, true, true),
    }
    local function writeSlot(filename, tilemap, palette)
      local rgba = rrBakePartySlot(gfx, tilemap, palette)
      assert(type(rgba) == "string" and #rgba == 112 * 40 * 4,
        "Radical Red party slot chrome has the wrong dimensions")
      local ok, err = cache:write(root .. "/" .. filename, rgba)
      assert(ok ~= false and ok ~= nil,
        "could not write Radical Red party chrome: " .. tostring(err))
    end

    for _, kind in ipairs({ "main", "wide" }) do
      writeSlot("slot_" .. kind .. ".rgba", filled, palettes.normal)
      writeSlot("slot_" .. kind .. "_selected.rgba", filled,
        palettes.selected)
      writeSlot("slot_" .. kind .. "_multi.rgba", filled,
        palettes.multi)
      writeSlot("slot_" .. kind .. "_multi_selected.rgba", filled,
        palettes.multiSelected)
    end
    writeSlot("slot_wide_empty.rgba", empty, palettes.normal)

    local manifest = string.format([[
return {
  width = %d, height = %d,
  ballW = %d, ballSheetH = %d, ballFrames = %d,
  slotMainW = 112, slotMainH = 40,
  slotWideW = 112, slotWideH = 40,
  cancelButtonW = 56, cancelButtonH = 16,
  holdIconW = %d, holdIconSheetH = %d, holdIconFrames = %d,
  pokemonVersion = %d,
}
]], report.width, report.height, report.ballW, report.ballSheetH,
      report.ballFrames or 2, report.holdIconW, report.holdIconSheetH,
      report.holdIconFrames, Versions.POKEMON_VERSION or 1)
    local ok, err = cache:write(root .. "/manifest.lua", manifest)
    assert(ok ~= false and ok ~= nil,
      "could not write Radical Red party manifest: " .. tostring(err))

    report.slotMainW, report.slotMainH = 112, 40
    report.slotWideW, report.slotWideH = 112, 40
    report.rrGrid = true
    return report
  end

  PartyExtract.__rrBwGridOriginal = original
  PartyExtract.__rrBwGridPatch = true
end

function Visuals.installExtraction(Profile)
  installExpandedMapGraphics(Profile)
  installExpandedOwExtraction(Profile)
  installPartyChromeExtraction(Profile)
  installSummaryChromeExtraction(Profile)
  local OwExtract = require("src.import.gba.ow_extract")
  if not OwExtract.__rrPaletteCountPatch then
    local original = assert(OwExtract.loadPaletteTable)
    OwExtract.loadPaletteTable = function(rom, version)
      local count = version and tonumber(version.ow_sprite_palette_count)
      if count and count > 0 then
        return expandedPaletteTable(rom, version, count)
      end
      return original(rom, version)
    end
    OwExtract.__rrPaletteCountPatch = true
  end
  return {
    paletteTable = Profile.OFFSET.overworldSpritePalettes,
    paletteCount = Profile.OW_PALETTE_COUNT,
    spriteCount = Profile.OW_TOTAL_COUNT,
    physicalSpriteCount = Profile.OW_COUNT + Profile.OW_POKEMON_COUNT
      + Profile.OW_PLAYER_COUNT,
    graphicsTableCount = 3,
    usedPaletteCount = Profile.OW_USED_PALETTE_COUNT,
    playerPaletteTag = 0x1100,
    momPaletteTag = 0x1168,
    stuffulGraphicsId = 0x016E,
    fairyTypeBadgeExtract = true,
    fairyTypeBadgeSheetHeight = RR_MENU_INFO_H,
  }
end

local function ascii(value)
  return tostring(value or ""):gsub("[%z\1-\31\127-\255]", "?")
end

local function fallbackOptionsDraw(OptionMenu)
  local graphics = love and love.graphics
  assert(graphics and graphics.setColor and graphics.rectangle,
    "Radical Red OPTIONS fallback needs LÖVE graphics")

  local pages = OptionMenu._pages
  local page = pages and pages[#pages]
  if not OptionMenu.open or not page then return end

  local rows = page.rows or {}
  local total = #rows + 1
  local visible = 7
  local index = tonumber(page.index) or tonumber(OptionMenu.cursor) or 1
  if index < 1 then index = 1 end
  if index > total then index = total end
  local scroll = tonumber(page.scroll) or 0
  if index - 1 < scroll then scroll = index - 1 end
  if index > scroll + visible then scroll = index - visible end
  if scroll < 0 then scroll = 0 end
  if scroll > math.max(0, total - visible) then
    scroll = math.max(0, total - visible)
  end
  page.scroll = scroll

  -- This path intentionally uses only numeric colors and LÖVE primitives. It
  -- stays visible even when ROM chrome, the FRLG font, or a table-color shim
  -- is the thing that failed in the normal renderer.
  graphics.setColor(18 / 255, 38 / 255, 72 / 255, 1)
  graphics.rectangle("fill", 0, 0, 240, 160)
  graphics.setColor(0 / 255, 123 / 255, 197 / 255, 1)
  graphics.rectangle("fill", 0, 0, 240, 20)
  graphics.setColor(238 / 255, 242 / 255, 248 / 255, 1)
  graphics.rectangle("fill", 8, 26, 224, 126)

  local function printSafe(value, x, y)
    if not graphics.print then return end
    pcall(graphics.print, ascii(value), x, y)
  end

  graphics.setColor(1, 1, 1, 1)
  printSafe("GAME OPTIONS", 10, 4)
  for slot = 1, visible do
    local rowIndex = scroll + slot
    if rowIndex <= total then
      local y = 31 + (slot - 1) * 17
      if rowIndex == index then
        graphics.setColor(82 / 255, 156 / 255, 209 / 255, 1)
        graphics.rectangle("fill", 11, y - 2, 218, 16)
        graphics.setColor(1, 1, 1, 1)
      else
        graphics.setColor(20 / 255, 31 / 255, 48 / 255, 1)
      end

      if rowIndex > #rows then
        printSafe("BACK", 17, y)
      else
        local row = rows[rowIndex] or {}
        printSafe(row.label or "?", 17, y)
        if row.value then
          local ok, value = pcall(row.value, OptionMenu._ctx)
          printSafe(ok and value or "----", 142, y)
        end
      end
    end
  end
  graphics.setColor(1, 1, 1, 1)
end

local function fallbackChoiceDraw(Choice)
  local graphics = love and love.graphics
  assert(graphics and graphics.setColor and graphics.rectangle,
    "Radical Red choice fallback needs LÖVE graphics")
  if not Choice.active or type(Choice.options) ~= "table"
      or #Choice.options < 1 then return end

  local options = Choice.options
  local cols = math.max(1, math.floor(tonumber(Choice.cols) or 1))
  if cols > #options then cols = #options end
  local rows = math.ceil(#options / cols)
  local widths, totalWidth = {}, 0
  for col = 1, cols do
    local chars = 4
    for row = 1, rows do
      local index = (row - 1) * cols + col
      if index <= #options then
        chars = math.max(chars, #ascii(options[index]))
      end
    end
    widths[col] = math.max(52, math.min(210, chars * 6 + 22))
    totalWidth = totalWidth + widths[col]
  end
  if totalWidth > 224 then
    local available = math.floor(224 / cols)
    totalWidth = 0
    for col = 1, cols do
      widths[col] = available
      totalWidth = totalWidth + available
    end
  end

  local panelHeight = math.min(148, rows * 18 + 12)
  local x = math.floor((tonumber(Choice.left) or 2) * 8 - 6)
  local y = math.floor((tonumber(Choice.top) or 5) * 8 - 6)
  x = math.max(6, math.min(234 - totalWidth, x))
  y = math.max(6, math.min(154 - panelHeight, y))

  -- Numeric colors and primitive shapes are deliberate.  This final pass is
  -- independent of ROM chrome, extracted font atlases, and table-color APIs.
  graphics.setColor(8 / 255, 15 / 255, 28 / 255, 0.72)
  graphics.rectangle("fill", x + 3, y + 3, totalWidth, panelHeight)
  graphics.setColor(67 / 255, 91 / 255, 119 / 255, 1)
  graphics.rectangle("fill", x, y, totalWidth, panelHeight)
  graphics.setColor(238 / 255, 242 / 255, 232 / 255, 1)
  graphics.rectangle("fill", x + 3, y + 3, totalWidth - 6, panelHeight - 6)

  local function printSafe(value, px, py)
    if graphics.print then pcall(graphics.print, ascii(value), px, py) end
  end

  local offsetX = 0
  for col = 1, cols do
    for row = 1, rows do
      local index = (row - 1) * cols + col
      if index <= #options then
        local rowX = x + offsetX + 6
        local rowY = y + 7 + (row - 1) * 18
        if index == Choice.cursor then
          graphics.setColor(52 / 255, 123 / 255, 181 / 255, 1)
          graphics.rectangle("fill", rowX - 2, rowY - 2,
            widths[col] - 8, 16)
          graphics.setColor(1, 1, 1, 1)
          printSafe(">", rowX, rowY)
          printSafe(options[index], rowX + 10, rowY)
        else
          graphics.setColor(25 / 255, 31 / 255, 38 / 255, 1)
          printSafe(options[index], rowX + 10, rowY)
        end
      end
    end
    offsetX = offsetX + widths[col]
  end
  graphics.setColor(1, 1, 1, 1)
end

local function installExpandedGraphicsResolver(Profile)
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Ctx = require("src.core.game3.scripting.ctx")
  if Space.__rrGraphicsResolverCount == Profile.OW_TOTAL_COUNT
      and Space.resolveObjectGraphicsId == Space.__rrGraphicsResolver then
    return
  end

  local tables = graphicsTables(Profile)
  local function validGraphics(graphics)
    if type(graphics) ~= "number" or graphics < 0 then return false end
    graphics = math.floor(graphics)
    local selector = math.floor(graphics / 0x100)
    local index = graphics % 0x100
    local desc = tables[selector]
    return desc ~= nil and index < desc.count
  end

  local original = Space.__rrGraphicsResolverOriginal
    or assert(Space.resolveObjectGraphicsId)
  local function resolveObjectGraphicsId(obj, neighbor)
    if not obj then return nil end
    local graphics = tonumber(obj.graphics or obj.graphicsId)
    local store = (neighbor and neighbor.store) or Space.store
      or Flags.newStore()
    local ctx = (Space.vm and Space.vm.ctx) or Ctx.new()
    if obj.graphicsVar then
      local value = Flags.getVar(store, ctx, obj.graphicsVar)
      if type(value) == "number" and value ~= 0 then graphics = value end
    end
    if graphics and graphics >= 0xFF00 and graphics <= 0xFF0F then
      local varId = 0x5028 + (graphics - 0xFF00)
      if neighbor and store.vars[varId] == nil then return nil end
      -- RR's expanded resolver uses 0xFF00..0xFF0F as indirect slots whose
      -- variables hold a complete selector:index graphics value.
      graphics = (tonumber(Flags.getVar(store, ctx, varId)) or 0) % 65536
    end
    if graphics and graphics >= 240 and graphics <= 255 then
      local varId = Ctx.GFX_VAR_LO + (graphics - 240)
      if neighbor and store.vars[varId] == nil then return nil end
      -- CFRU variables carry the complete 16-bit graphics value. Reducing it
      -- to one byte discards the Pokemon/player table selector.
      graphics = (tonumber(Flags.getVar(store, ctx, varId)) or 0) % 65536
    end
    if graphics then
      graphics = math.floor(graphics)
      if not validGraphics(graphics) then graphics = 16 end
    end
    return graphics
  end
  Space.__rrGraphicsResolverOriginal = original
  Space.__rrGraphicsResolver = resolveObjectGraphicsId
  Space.__rrGraphicsResolverCount = Profile.OW_TOTAL_COUNT
  Space.resolveObjectGraphicsId = resolveObjectGraphicsId
end

local function clearStaleBlackVeil(owner)
  local okFade, Fade = pcall(require, "src.ui.game3.fade")
  if not (okFade and Fade
      and tonumber(Fade.mode) == tonumber(Fade.MODE and Fade.MODE.TO_BLACK)
      and ((Fade.isActive and Fade.isActive())
        or (tonumber(Fade.t) or 0) > 0)) then
    return false
  end
  local cleared = pcall(Fade.clear)
  if cleared then
    owner.__rrStaleFadeClearCount =
      (owner.__rrStaleFadeClearCount or 0) + 1
  end
  return cleared
end

local function shiftedCoord(source, dx, dy)
  local out = copyRecord(source)
  out.x = (tonumber(out.x) or 0) + (dx or 0)
  out.y = (tonumber(out.y) or 0) + (dy or 0)
  return out
end

local function installSummaryDetailLayout()
  local SummaryMenu = require("src.ui.game3.summary_menu")
  local SummaryChrome = require("src.ui.game3.summary_chrome")
  if SummaryChrome.__rrBwDetailPatch then return end

  local originalManifest = assert(SummaryChrome.manifest)
  local function rrManifest()
    local base = originalManifest()
    if SummaryMenu._page ~= SummaryMenu.PAGE_MOVES_INFO or not base then
      return base
    end
    if SummaryChrome.__rrBwDetailBase == base
        and SummaryChrome.__rrBwDetailManifest then
      return SummaryChrome.__rrBwDetailManifest
    end

    local derived = copyRecord(base)
    derived.coords = copyRecord(base.coords)
    for _, key in ipairs({
      "level", "name", "gender", "statusMovesInfo",
      "shinyStarMovesInfo", "pokerus", "monIcon",
      "movesInfoType1", "movesInfoType2",
    }) do
      if base.coords and base.coords[key] then
        derived.coords[key] = shiftedCoord(base.coords[key], 120, 0)
      end
    end

    derived.moveSlots = {}
    for index = 1, 4 do
      local source = base.moveSlots and base.moveSlots[index] or {
        nameX = 163, nameY = 21 + (index - 1) * 28,
        typeX = 123, typeY = 21 + (index - 1) * 28,
        ppX = 196, ppY = 32 + (index - 1) * 28,
      }
      local slot = copyRecord(source)
      slot.nameX = (tonumber(slot.nameX) or 163) - 120
      slot.typeX = (tonumber(slot.typeX) or 123) - 120
      slot.ppX = (tonumber(slot.ppX) or 196) - 120
      derived.moveSlots[index] = slot
    end
    derived.moveSlots[5] = {
      nameX = 43, nameY = 133,
      typeX = 3, typeY = 133,
      ppX = 76, ppY = 144,
    }

    derived.movesInfo = copyRecord(base.movesInfo)
    for _, key in ipairs({ "power", "accuracy", "desc" }) do
      if base.movesInfo and base.movesInfo[key] then
        derived.movesInfo[key] = shiftedCoord(base.movesInfo[key], 120, 0)
      end
    end

    SummaryChrome.__rrBwDetailBase = base
    SummaryChrome.__rrBwDetailManifest = derived
    return derived
  end
  SummaryChrome.__rrBwDetailManifestOriginal = originalManifest
  SummaryChrome.manifest = rrManifest

  local originalCursor = assert(SummaryChrome.drawMoveSelectionCursor)
  SummaryChrome.drawMoveSelectionCursor = function(x, y, w, h, isBlue)
    if SummaryMenu._page == SummaryMenu.PAGE_MOVES_INFO and x == 120 then
      x = 0
    end
    return originalCursor(x, y, w, h, isBlue)
  end
  SummaryChrome.__rrBwDetailCursorOriginal = originalCursor
  SummaryChrome.__rrBwDetailPatch = true
end

local function installPartyGridLayout()
  local PartyMenu = require("src.ui.game3.party_menu")
  if PartyMenu.__rrBwGridPatch then return end

  local PartyChrome = require("src.ui.game3.party_chrome")
  local FrlgFont = require("src.ui.game3.frlg_font")
  local Window = require("src.ui.game3.window")
  local Oam = require("src.core.game3.oam")
  local originalDraw = assert(PartyMenu.draw)

  local function layoutName()
    return PartyMenu._layout == "double" and "double" or "single"
  end

  local function sourceInfo(layout, index)
    if index == 1 or (layout == "double" and index == 2) then
      return FR_PARTY_INFO_LEFT
    end
    return FR_PARTY_INFO_RIGHT
  end

  local function targetInfo(index)
    return index % 2 == 1 and RR_PARTY_INFO_LEFT or RR_PARTY_INFO_RIGHT
  end

  local function windowIndex(layout, left, top)
    for index, win in ipairs(FR_PARTY_WINDOWS[layout]) do
      if win.left == left and win.top == top then return index end
    end
    return nil
  end

  local function remapSprite(layout, x, y)
    local source = FR_PARTY_SPRITES[layout]
    for index = 1, 6 do
      for pair = 1, 7, 2 do
        if source[index][pair] == x and source[index][pair + 1] == y then
          return RR_PARTY_SPRITES[index][pair],
            RR_PARTY_SPRITES[index][pair + 1]
        end
      end
    end
    return x, y
  end

  local function remapText(layout, index, x, y)
    local sourceWin = FR_PARTY_WINDOWS[layout][index]
    local targetWin = RR_PARTY_WINDOWS[index]
    local from, to = sourceInfo(layout, index), targetInfo(index)
    for _, key in ipairs(PARTY_INFO_KEYS) do
      local source, target = from[key], to[key]
      local sourceX = sourceWin.left * 8 + source[1]
      local sourceY = sourceWin.top * 8 + source[2]
      if x == sourceX and y == sourceY then
        return targetWin.left * 8 + target[1],
          targetWin.top * 8 + target[2]
      end
    end
    return x, y
  end

  local function drawParty(...)
    local layout = layoutName()
    local currentSlot
    local originalDrawSlot = PartyChrome.drawSlot
    local originalFontDraw = FrlgFont.draw
    local originalStdFrame = Window.stdFrame
    local originalCreateSprite = Oam.createSprite
    local originalSetPos = Oam.setPos
    local graphics = love and love.graphics
    local originalRectangle = graphics and graphics.rectangle

    PartyChrome.drawSlot = function(kind, left, top, selected, hideHp, multi)
      local index = windowIndex(layout, left, top)
      currentSlot = index
      if index then
        local target = RR_PARTY_WINDOWS[index]
        left, top = target.left, target.top
      end
      return originalDrawSlot(kind, left, top, selected, hideHp, multi)
    end

    FrlgFont.draw = function(text, x, y, opts)
      if currentSlot then x, y = remapText(layout, currentSlot, x, y) end
      return originalFontDraw(text, x, y, opts)
    end

    Window.stdFrame = function(...)
      -- Slot drawing is complete once a normal framed overlay/prompt begins.
      currentSlot = nil
      return originalStdFrame(...)
    end

    Oam.createSprite = function(template, x, y, subpriority)
      x, y = remapSprite(layout, x, y)
      return originalCreateSprite(template, x, y, subpriority)
    end
    Oam.setPos = function(id, x, y)
      x, y = remapSprite(layout, x, y)
      return originalSetPos(id, x, y)
    end

    if originalRectangle then
      graphics.rectangle = function(mode, x, y, w, h, ...)
        if currentSlot and mode == "fill" and h == 3 then
          x, y = remapText(layout, currentSlot, x, y)
        end
        return originalRectangle(mode, x, y, w, h, ...)
      end
    end

    local result = { pcall(originalDraw, ...) }
    PartyChrome.drawSlot = originalDrawSlot
    FrlgFont.draw = originalFontDraw
    Window.stdFrame = originalStdFrame
    Oam.createSprite = originalCreateSprite
    Oam.setPos = originalSetPos
    if originalRectangle then graphics.rectangle = originalRectangle end
    if not result[1] then error(result[2], 0) end
    return unpack(result, 2)
  end

  PartyMenu.__rrBwGridOriginal = originalDraw
  PartyMenu.__rrBwGridWrapper = drawParty
  PartyMenu.draw = drawParty
  PartyMenu.__rrBwGridWindows = RR_PARTY_WINDOWS
  PartyMenu.__rrBwGridSprites = RR_PARTY_SPRITES
  PartyMenu.__rrBwGridText = function(index, key)
    local win = assert(RR_PARTY_WINDOWS[index])
    local info = assert(targetInfo(index)[key])
    return win.left * 8 + info[1], win.top * 8 + info[2]
  end
  PartyMenu.__rrBwGridPatch = true
end

local function installBattleSpriteLayout(Profile)
  local Dataset = require("src.core.game3.dataset")
  local cache = assert(Dataset.cache(),
    "Radical Red battle coordinates need the mounted dataset")
  local rel = Profile.extractRoot() .. "/pokemon/pic_coords.lua"
  local source = assert(cache:read(rel),
    "Radical Red battle sprite coordinates are missing")
  local chunk = assert(load(source, "@" .. rel, "t", {}))
  local coords = assert(chunk())
  assert(coords.species == Profile.SPECIES_COUNT
      and type(coords.front) == "table"
      and type(coords.back) == "table"
      and type(coords.elev) == "table",
    "Radical Red battle sprite coordinates are incomplete")
  assert(coords.back[155] == 3,
    "Radical Red Cyndaquil back-sprite baseline is stale")

  -- battle.ui and animation ports all retain this module table, so mutating
  -- its three registries updates normal drawing and move animations together.
  local PicCoords = require("src.core.game3.battle.pic_coords")
  for species = 0, Profile.SPECIES_COUNT - 1 do
    assert(coords.front[species] ~= nil and coords.back[species] ~= nil
        and coords.elev[species] ~= nil,
      "missing Radical Red sprite coordinate for species " .. species)
    PicCoords.front[species] = coords.front[species]
    PicCoords.back[species] = coords.back[species]
    PicCoords.elev[species] = coords.elev[species]
  end

  local Ui = require("src.core.game3.battle.ui")
  if not (Ui.__rrFixedHealthboxBounceWrapper
      and Ui.bounceOffset == Ui.__rrFixedHealthboxBounceWrapper) then
    local original = Ui.__rrFixedHealthboxBounceOriginal
      or assert(Ui.bounceOffset)
    local function fixedHealthboxBounce(kind, ...)
      -- The battler's subtle menu bounce belongs on the Pokémon sprite. The
      -- stock host also applied it to the status tile, making both visibly
      -- travel together at Android scale.
      if kind == "hb" then return 0 end
      return original(kind, ...)
    end
    Ui.__rrFixedHealthboxBounceOriginal = original
    Ui.__rrFixedHealthboxBounceWrapper = fixedHealthboxBounce
    Ui.bounceOffset = fixedHealthboxBounce
  end
  Ui.__rrExpandedPicCoords = true
  return coords
end

function Visuals.installRuntime(Profile)
  installSummaryDetailLayout()
  local fairyBadge = installFairyTypeBadgeRuntime(Profile)
  installPartyGridLayout()
  local battleCoords = installBattleSpriteLayout(Profile)
  local OptionMenu = require("src.ui.game3.option_menu")
  if not (OptionMenu.__rrOptionsDrawWrapper
      and OptionMenu.draw == OptionMenu.__rrOptionsDrawWrapper) then
    local originalDraw = OptionMenu.__rrOptionsDrawOriginal
      or assert(OptionMenu.draw)
    local function drawOptions(...)
      local graphics = love and love.graphics
      local originalSetColor = graphics and graphics.setColor
      if not originalSetColor then return originalDraw(...) end

      -- LÖVE accepts setColor({r,g,b,a}), but number-only graphics shims in
      -- some Android packages reject that overload.  Keep the workaround
      -- scoped to OPTIONS and restore the graphics API even if drawing fails.
      graphics.setColor = function(r, g, b, a)
        if type(r) == "table" then
          return originalSetColor(r[1] or 1, r[2] or 1, r[3] or 1,
            r[4] == nil and 1 or r[4])
        end
        return originalSetColor(r, g, b, a)
      end
      local originalState = false
      if graphics.push and graphics.pop then
        originalState = pcall(graphics.push, "all")
      end
      local result = { pcall(originalDraw, ...) }
      if originalState then pcall(graphics.pop) end
      if not result[1] then
        OptionMenu.__rrLastOptionsDrawError = tostring(result[2])
      end
      -- Preserve the ROM-authentic OPTIONS renderer whenever it succeeds.
      -- The primitive panel is only an emergency recovery path after a real
      -- chrome/font exception; drawing it unconditionally changes the menu's
      -- frame, font, spacing, and colours.
      if not result[1] then
        local portableState = false
        if graphics.push and graphics.pop then
          portableState = pcall(graphics.push, "all")
        end
        if portableState then
          if graphics.setScissor then pcall(graphics.setScissor) end
          if graphics.setShader then pcall(graphics.setShader) end
          if graphics.setBlendMode then pcall(graphics.setBlendMode, "alpha") end
        end
        local portable = { pcall(fallbackOptionsDraw, OptionMenu) }
        if portableState then pcall(graphics.pop) end
        if portable[1] then
          OptionMenu.__rrOptionsFallbackCount =
            (OptionMenu.__rrOptionsFallbackCount or 0) + 1
          result = { true }
        else
          result = { false, tostring(result[2])
            .. "; OPTIONS portable draw failed: " .. tostring(portable[2]) }
        end
      end
      graphics.setColor = originalSetColor
      if not result[1] then error(result[2], 0) end
      return unpack(result, 2)
    end
    OptionMenu.__rrOptionsDrawOriginal = originalDraw
    OptionMenu.__rrOptionsDrawWrapper = drawOptions
    OptionMenu.draw = drawOptions
    OptionMenu.__rrSetColorCompat = true
  end

  local Message = require("src.ui.game3.message")
  if not (Message.__rrMessageDrawWrapper
      and Message.draw == Message.__rrMessageDrawWrapper) then
    local originalDraw = Message.__rrMessageDrawOriginal or assert(Message.draw)
    local function drawMessage(...)
      -- RR's new-game script fades fully to black, then immediately opens its
      -- "stop mashing A" warning without a matching fade-from-black. Clear
      -- only that known stale veil; unrelated story fades remain untouched.
      local page = Message.currentPage and tostring(Message.currentPage()) or ""
      if Message.isOpen and Message.isOpen()
          and page:find("properly", 1, true)
          and page:find("incoming questions", 1, true) then
        clearStaleBlackVeil(Message)
      end
      return originalDraw(...)
    end
    Message.__rrMessageDrawOriginal = originalDraw
    Message.__rrMessageDrawWrapper = drawMessage
    Message.draw = drawMessage
  end

  local Choice = require("src.ui.game3.choice")
  if not (Choice.__rrChoiceDrawWrapper
      and Choice.draw == Choice.__rrChoiceDrawWrapper) then
    local originalDraw = Choice.__rrChoiceDrawOriginal or assert(Choice.draw)
    local function drawChoice(...)
      local graphics = love and love.graphics
      local originalSetColor = graphics and graphics.setColor
      if not originalSetColor then return originalDraw(...) end

      -- The RR bedroom script can open Game Modes while FADE_TO_BLACK is still
      -- running, or after its t=16 veil has completed without a matching
      -- FADE_FROM_BLACK. UiPass draws that veil after Choice, so waiting for
      -- the fade to finish leaves several seconds of black on slower Android
      -- devices. Clear the black cover before the first interactive frame.
      if Choice.active then clearStaleBlackVeil(Choice) end

      graphics.setColor = function(r, g, b, a)
        if type(r) == "table" then
          return originalSetColor(r[1] or 1, r[2] or 1, r[3] or 1,
            r[4] == nil and 1 or r[4])
        end
        return originalSetColor(r, g, b, a)
      end

      local originalState = false
      if graphics.push and graphics.pop then
        originalState = pcall(graphics.push, "all")
      end
      local result = { pcall(originalDraw, ...) }
      if originalState then pcall(graphics.pop) end
      if not result[1] then
        Choice.__rrLastChoiceDrawError = tostring(result[2])
      end

      -- A successful Choice.draw already is the authentic FRLG/Radical Red
      -- menu. Only replace it if that renderer actually throws.
      if not result[1] then
        local portableState = false
        if graphics.push and graphics.pop then
          portableState = pcall(graphics.push, "all")
        end
        if portableState then
          if graphics.setScissor then pcall(graphics.setScissor) end
          if graphics.setShader then pcall(graphics.setShader) end
          if graphics.setBlendMode then pcall(graphics.setBlendMode, "alpha") end
        end
        local portable = { pcall(fallbackChoiceDraw, Choice) }
        if portableState then pcall(graphics.pop) end
        if portable[1] then
          Choice.__rrPortableChoiceCount =
            (Choice.__rrPortableChoiceCount or 0) + 1
          result = { true }
        else
          result = { false, tostring(result[2])
            .. "; choice portable draw failed: " .. tostring(portable[2]) }
        end
      end
      graphics.setColor = originalSetColor
      if not result[1] then error(result[2], 0) end
      return unpack(result, 2)
    end
    Choice.__rrChoiceDrawOriginal = originalDraw
    Choice.__rrChoiceDrawWrapper = drawChoice
    Choice.draw = drawChoice
    Choice.__rrSetColorCompat = true
  end
  installExpandedGraphicsResolver(Profile)
  return {
    optionsDraw = true,
    optionsFallbackGuard = true,
    portableOptionsDraw = true,
    gameModesChoiceDraw = true,
    portableChoiceDraw = true,
    gameModesFadeGuard = true,
    setupMessageFadeGuard = true,
    summaryDetailLayout = true,
    partyGridLayout = true,
    expandedGraphicsIds = true,
    expandedGraphicsTables = true,
    objectGraphicsSelector = true,
    battleSpriteCoords = true,
    battleSpriteCoordSpecies = battleCoords.species,
    cyndaquilBackYOffset = battleCoords.back[155],
    fixedHealthbox = true,
    fairyTypeBadge = fairyBadge == true,
    fairyTypeBadgeId = RR_FAIRY_TYPE,
    fairyTypeBadgeY = RR_FAIRY_Y,
  }
end

Visuals.rebuildMenuInfo = writeExpandedMenuInfo
Visuals.RR_MENU_INFO = {
  width = RR_MENU_INFO_W, height = RR_MENU_INFO_H,
  fairyType = RR_FAIRY_TYPE, fairyX = RR_FAIRY_X, fairyY = RR_FAIRY_Y,
}

function Visuals.report()
  return Visuals._paletteReport
end

return Visuals
