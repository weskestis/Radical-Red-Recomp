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

function Visuals.installExtraction(Profile)
  installExpandedMapGraphics(Profile)
  installExpandedOwExtraction(Profile)
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

function Visuals.installRuntime(Profile)
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
    expandedGraphicsIds = true,
    expandedGraphicsTables = true,
    objectGraphicsSelector = true,
  }
end

function Visuals.report()
  return Visuals._paletteReport
end

return Visuals
