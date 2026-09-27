-- Low-memory Radical Red world extractor.
--
-- The stock full-world extractor keeps every tileset bundle and all 425 map
-- grids alive until the native pack is finished.  That is convenient on a
-- desktop, but it pushes a first Android boot beyond the process memory limit.
-- This equivalent path writes scripts first, then handles one tileset pair at
-- a time and collects only the small aggregate manifests in memory.

local World = {}

local function put(cache, rel, bytes)
  local ok, err = cache:write(rel, bytes)
  assert(ok ~= false and ok ~= nil,
    "could not write Radical Red world cache " .. rel .. ": " .. tostring(err))
end

local function sortedKeys(t)
  local keys = {}
  for key in pairs(t or {}) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

local function writeTableShards(cache, base, name, value, serialize)
  local keys = sortedKeys(value)
  local paths, entries = {}, 0

  local function writeRange(first, last)
    local part = {}
    for i = first, last do
      local key = keys[i]
      part[key] = value[key]
    end
    local source = "return " .. serialize(part) .. "\n"
    local loader, compileError = load(source,
      "@" .. base .. "/" .. name .. "_probe.lua", "t", {})
    if not loader and first < last then
      local middle = math.floor((first + last) / 2)
      writeRange(first, middle)
      writeRange(middle + 1, last)
      return
    end
    assert(loader, "Radical Red " .. name .. " shard did not compile: "
      .. tostring(compileError))
    local path = ("%s/%s_%03d.lua"):format(base, name, #paths + 1)
    put(cache, path, source)
    paths[#paths + 1] = path
    entries = entries + last - first + 1
  end

  local perShard = name == "events" and 16 or 64
  for first = 1, #keys, perShard do
    writeRange(first, math.min(#keys, first + perShard - 1))
  end
  return paths, entries
end

local function writeScriptShards(cache, root, bundle, serialize)
  local base = root .. "/scripts/rr_shards"
  local kinds = { "scripts", "text", "movements", "events" }
  local parts, entries = {}, {}
  for _, name in ipairs(kinds) do
    parts[name], entries[name] = writeTableShards(
      cache, base, name, bundle[name] or {}, serialize)
  end
  local lines = {
    "-- Compile-safe Radical Red script registry shards.",
    "return { version = 1, parts = {",
  }
  for _, name in ipairs(kinds) do
    lines[#lines + 1] = ("  %s = {"):format(name)
    for _, path in ipairs(parts[name]) do
      lines[#lines + 1] = ("    %q,"):format(path)
    end
    lines[#lines + 1] = "  },"
  end
  lines[#lines + 1] = "}, entries = {"
  for _, name in ipairs(kinds) do
    lines[#lines + 1] = ("  %s = %d,"):format(name, entries[name])
  end
  lines[#lines + 1] = "} }"
  lines[#lines + 1] = ""
  put(cache, base .. "/manifest.lua", table.concat(lines, "\n"))
  return entries, parts
end

local function writeScriptSupport(rom, cache, root, bundle, serialize)
  local base = root .. "/scripts"
  -- The RR runtime reads the compile-safe shards.  Keep tiny stock-contract
  -- files so the engine can install object interactions, marts and text table
  -- metadata without compiling the monolithic RR registries a second time.
  for _, name in ipairs({ "scripts", "text", "movements", "events" }) do
    put(cache, base .. "/" .. name .. ".lua", "return {}\n")
  end
  put(cache, base .. "/text_tables.lua",
    "return " .. serialize(bundle.textTables or {}) .. "\n")

  local mapIds = sortedKeys(bundle.events)
  local meta = {
    '{"cache_version":',
    tostring(require("src.import.gba.versions").CACHE_VERSION),
    ',"kind":"game3","source":"rom","maps":[',
  }
  for i, mapId in ipairs(mapIds) do
    if i > 1 then meta[#meta + 1] = "," end
    meta[#meta + 1] = string.format("%q", mapId)
  end
  meta[#meta + 1] = "]}\n"
  put(cache, base .. "/meta.json", table.concat(meta))

  local MartsExtract = require("src.import.gba.marts_extract")
  local marts = bundle.marts
  if not marts or not next(marts) then
    marts = select(1, MartsExtract.build(rom, bundle.scripts))
  end
  local count, seen = 0, {}
  for key, entry in pairs(marts or {}) do
    if type(key) == "number" and entry and not seen[entry.ptr] then
      seen[entry.ptr] = true
      count = count + 1
    end
  end
  MartsExtract.write(cache, root, marts, { count = count })
  require("src.import.gba.flags_extract").write(cache, root)
end

local function writeWarps(cache, root, mapOrder, warps)
  local MapCatalog = require("src.import.gba.map_catalog")
  local lines = { "return {" }
  for _, mapId in ipairs(mapOrder) do
    lines[#lines + 1] = ("  %s = {"):format(mapId)
    for _, warp in ipairs(warps[mapId] or {}) do
      local dest = warp.destMap
        or MapCatalog.mapIdFor(warp.mapGroup, warp.mapNum)
      if dest then
        lines[#lines + 1] =
          ("    { x=%d, y=%d, destMap=%q, destWarp=%d },")
            :format(warp.x, warp.y, dest, warp.destWarp or 1)
      else
        lines[#lines + 1] =
          ("    { x=%d, y=%d, destMap=nil, destWarp=%d, mapGroup=%d, mapNum=%d },")
            :format(warp.x, warp.y, warp.destWarp or 1,
              warp.mapGroup or 0, warp.mapNum or 0)
      end
    end
    lines[#lines + 1] = "  },"
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  put(cache, root .. "/warps.lua", table.concat(lines, "\n"))
end

local function writeConnections(cache, root, mapOrder, connections)
  local lines = { "return {" }
  for _, mapId in ipairs(mapOrder) do
    lines[#lines + 1] = ("  %s = {"):format(mapId)
    -- Connections are an ordered array, not a table keyed by direction.
    -- Six Island Water Path legitimately has three west edges; keying by
    -- direction would discard two of them.
    for _, connection in ipairs(connections[mapId] or {}) do
      lines[#lines + 1] =
        ("    { dir=%q, map=%q, offset=%d },")
          :format(connection.dir, connection.map,
            tonumber(connection.offset) or 0)
    end
    lines[#lines + 1] = "  },"
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  local source = table.concat(lines, "\n")
  local chunk, err = load(source, "@" .. root .. "/connections.lua", "t", {})
  assert(chunk, "Radical Red connection registry did not compile: " .. tostring(err))
  put(cache, root .. "/connections.lua", source)
end

local function countSpecialCalls(scripts, specialId)
  local count = 0
  for _, rows in pairs(scripts or {}) do
    for _, row in ipairs(rows or {}) do
      if row.op == "special" and tonumber(row.id or row[1]) == specialId then
        count = count + 1
      end
    end
  end
  return count
end

local CARDINAL = { north = true, south = true, west = true, east = true }

local function connectionOverlaps(source, dest, dir, offset)
  local sourceSpan, destSpan
  if dir == "north" or dir == "south" then
    sourceSpan, destSpan = source.width, dest.width
  else
    sourceSpan, destSpan = source.height, dest.height
  end
  local low = math.max(0, offset)
  local high = math.min(sourceSpan - 1, offset + destSpan - 1)
  return low <= high
end

local function auditTopology(Profile, mapOrder, mapDims, warps, connections)
  local audit = {
    version = 1,
    maps = #mapOrder,
    warps = 0,
    resolvedWarps = 0,
    dynamicWarps = 0,
    connections = 0,
    duplicateDirectionConnections = 0,
    connectionDirections = { north = 0, south = 0, west = 0, east = 0 },
  }

  for _, mapId in ipairs(mapOrder) do
    local dim = assert(mapDims[mapId], "missing Radical Red dimensions for " .. mapId)
    for index, warp in ipairs(warps[mapId] or {}) do
      audit.warps = audit.warps + 1
      local x, y = tonumber(warp.x), tonumber(warp.y)
      assert(x and y and x >= 0 and y >= 0 and x < dim.width and y < dim.height,
        ("Radical Red warp %s#%d is outside its %dx%d map"):format(
          mapId, index, dim.width, dim.height))
      local dest = warp.destMap
      local destWarp = tonumber(warp.destWarp)
      if dest and mapDims[dest] and destWarp and destWarp >= 1
          and destWarp <= #(warps[dest] or {}) then
        audit.resolvedWarps = audit.resolvedWarps + 1
      else
        -- Link rooms, elevators and a handful of cartridge-controlled holes
        -- deliberately use dynamic/sentinel destinations.
        audit.dynamicWarps = audit.dynamicWarps + 1
      end
    end

    local seenDirections = {}
    for index, connection in ipairs(connections[mapId] or {}) do
      local dir = connection.dir
      local dest = connection.map
      local destDim = mapDims[dest]
      local offset = tonumber(connection.offset) or 0
      assert(CARDINAL[dir],
        ("Radical Red connection %s#%d has invalid direction %s")
          :format(mapId, index, tostring(dir)))
      assert(destDim,
        ("Radical Red connection %s#%d has missing destination %s")
          :format(mapId, index, tostring(dest)))
      assert(connectionOverlaps(dim, destDim, dir, offset),
        ("Radical Red connection %s#%d cannot overlap %s")
          :format(mapId, index, dest))
      audit.connections = audit.connections + 1
      audit.connectionDirections[dir] = audit.connectionDirections[dir] + 1
      if seenDirections[dir] then
        audit.duplicateDirectionConnections =
          audit.duplicateDirectionConnections + 1
      end
      seenDirections[dir] = true
    end
  end

  assert(audit.maps == Profile.MAP_COUNT, "Radical Red topology omitted maps")
  assert(audit.warps == 1324 and audit.resolvedWarps == 1297
      and audit.dynamicWarps == 27,
    ("Radical Red warp census changed: total=%d resolved=%d dynamic=%d")
      :format(audit.warps, audit.resolvedWarps, audit.dynamicWarps))
  assert(audit.connections == 116,
    "Radical Red connection census changed: " .. tostring(audit.connections))
  assert(audit.duplicateDirectionConnections == 2,
    "Radical Red duplicate-direction connection census changed")
  return audit
end

local function auditLayouts(cache, root, mapOrder, mapDims, manifest, audit)
  local NativePack = require("src.import.gba.native_pack")
  local count, odd = 0, 0
  for _, mapId in ipairs(mapOrder) do
    local expected = assert(mapDims[mapId], "missing dimensions for " .. mapId)
    local info = assert(manifest.layouts[mapId],
      "missing native layout manifest entry for " .. mapId)
    local blob = assert(cache:read(root .. "/native/" .. info.file),
      "missing native layout file for " .. mapId)
    local decoded, err = NativePack.decodeMidLayout(blob)
    assert(decoded, "invalid native layout for " .. mapId .. ": " .. tostring(err))
    local paddedWidth = expected.width + expected.width % 2
    local paddedHeight = expected.height + expected.height % 2
    assert(decoded.trueWidth == expected.width
        and decoded.trueHeight == expected.height,
      ("native layout %s lost true dimensions: %dx%d, expected %dx%d")
        :format(mapId, decoded.trueWidth, decoded.trueHeight,
          expected.width, expected.height))
    assert(decoded.width == paddedWidth and decoded.height == paddedHeight,
      ("native layout %s has wrong padded dimensions: %dx%d, expected %dx%d")
        :format(mapId, decoded.width, decoded.height,
          paddedWidth, paddedHeight))
    if expected.width % 2 ~= 0 or expected.height % 2 ~= 0 then odd = odd + 1 end
    count = count + 1
  end
  assert(count == #mapOrder, "Radical Red native layout audit omitted maps")
  assert(odd == 306, "Radical Red odd-sized map census changed: " .. tostring(odd))
  audit.layouts = count
  audit.oddSizedLayouts = odd
  return audit
end

local function writeWorldAudit(cache, root, audit)
  local d = audit.connectionDirections
  local source = table.concat({
    "-- Exact Radical Red v4.1 full-world extraction audit.",
    "return {",
    ("  version = %d,"):format(audit.version or 1),
    ("  maps = %d,"):format(audit.maps),
    ("  layouts = %d,"):format(audit.layouts),
    ("  oddSizedLayouts = %d,"):format(audit.oddSizedLayouts),
    ("  warps = %d,"):format(audit.warps),
    ("  resolvedWarps = %d,"):format(audit.resolvedWarps),
    ("  dynamicWarps = %d,"):format(audit.dynamicWarps),
    ("  connections = %d,"):format(audit.connections),
    ("  duplicateDirectionConnections = %d,")
      :format(audit.duplicateDirectionConnections),
    ("  connectionDirections = { north=%d, south=%d, west=%d, east=%d },")
      :format(d.north, d.south, d.west, d.east),
    ("  customListMenus = %d,"):format(audit.customListMenus),
    ("  customListMenuCalls = %d,"):format(audit.customListMenuCalls),
    ("  encounterMaps = %d,"):format(audit.encounterMaps),
    ("  encounterBaseHeaders = %d,"):format(audit.encounterBaseHeaders),
    ("  encounterDayHeaders = %d,"):format(audit.encounterDayHeaders),
    ("  encounterNightHeaders = %d,"):format(audit.encounterNightHeaders),
    ("  encounterUsableSlots = %d,"):format(audit.encounterUsableSlots),
    ("  encounterPlaceholderSlotsRemoved = %d,")
      :format(audit.encounterPlaceholderSlotsRemoved),
    "}", "",
  }, "\n")
  local chunk, err = load(source, "@" .. root .. "/world_audit.lua", "t", {})
  assert(chunk, "Radical Red world audit did not compile: " .. tostring(err))
  put(cache, root .. "/world_audit.lua", source)
end

local function writeNativeManifest(cache, root, manifest, pairNames)
  local Versions = require("src.import.gba.versions")
  local lines = {
    "return {",
    ("  native_version = %d,"):format(Versions.NATIVE_VERSION or 1),
    "  pairs = {",
  }
  for _, pairName in ipairs(pairNames) do
    local pair = manifest.pairs[pairName]
    if pair then
      lines[#lines + 1] =
        ("    [%q] = { midCount=%d, atlasCols=%d, atlasRows=%d, layered=true },")
          :format(pairName, pair.midCount, pair.atlasCols, pair.atlasRows)
    end
  end
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "  layouts = {"
  for _, mapId in ipairs(sortedKeys(manifest.layouts)) do
    local layout = manifest.layouts[mapId]
    lines[#lines + 1] =
      ("    [%q] = { pair=%q, width=%d, height=%d, file=%q },")
        :format(mapId, layout.pair, layout.width, layout.height, layout.file)
  end
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  put(cache, root .. "/native/manifest.lua", table.concat(lines, "\n"))
end

local function writeMeta(cache, root, Profile, version, importId, mapOrder, midCount)
  local Versions = require("src.import.gba.versions")
  local Canon = require("src.import.canonical_json")
  put(cache, root .. "/meta.json", Canon.encode({
    cache_version = Versions.CACHE_VERSION,
    native_version = Versions.NATIVE_VERSION or 1,
    md5 = Profile.MD5,
    version_id = version.id,
    import_id = importId,
    mid_count = midCount,
    tile_count = 0,
    block_count = 0,
    imageWidth = 0,
    imageHeight = 0,
    tilesPerRow = 16,
    maps = mapOrder,
  }) .. "\n")
end

function World.run(adapter, cache, Profile, progress, StreamRom, RRListMenus,
    RR_Encounters)
  local Versions = require("src.import.gba.versions")
  local MapTree = require("src.import.gba.map_tree")
  local MapCatalog = require("src.import.gba.map_catalog")
  local Tileset = require("src.import.gba.tileset")
  assert(StreamRom and StreamRom.installTilesetCompat,
    "Radical Red portable tileset reader was not loaded")
  StreamRom.installTilesetCompat(Tileset)
  local Maps = require("src.import.gba.maps")
  local Collision = require("src.core.game3.scripting.collision")
  local NativePack = require("src.import.gba.native_pack")
  local BaseExtract = require("src.import.gba.extract_island1")
  local ExtractScripts = require("src.import.gba.extract_scripts")
  local root = Profile.extractRoot()
  local importId = "firered"
  local info = assert(adapter:info(importId))
  local version = assert(Versions.lookup(info.md5))
  assert(StreamRom and StreamRom.open,
    "Radical Red bounded ROM reader was not loaded")
  local rom = assert(StreamRom.open(adapter, importId))

  progress("world_census", 0, 1)
  MapCatalog.rebuildIndex()
  local census = assert(MapTree.walk(rom, version))
  local mapOrder, byEngine = MapCatalog.allOrder(census, {})
  MapCatalog.registerOrder(rom, version, mapOrder, byEngine)
  assert(#mapOrder == Profile.MAP_COUNT,
    ("Radical Red map census changed: expected %d, got %d")
      :format(Profile.MAP_COUNT, #mapOrder))
  local mapDims = {}
  for _, mapId in ipairs(mapOrder) do
    local entry = assert(byEngine[mapId], "missing Radical Red census entry " .. mapId)
    mapDims[mapId] = {
      width = assert(entry.layout.width),
      height = assert(entry.layout.height),
    }
  end
  census, byEngine = nil, nil
  rom:clearCache()
  collectgarbage()

  local needed, pairMaps = {}, {}
  for _, mapId in ipairs(mapOrder) do
    local spec = assert(Versions.MAPS[mapId], "missing map spec " .. mapId)
    local pairName = spec.pair or "sevii_outdoor"
    needed[pairName] = true
    pairMaps[pairName] = pairMaps[pairName] or {}
    pairMaps[pairName][#pairMaps[pairName] + 1] = mapId
  end
  local pairNames = sortedKeys(needed)

  progress("world_scripts", 0, 1)
  local bundle = ExtractScripts.extractFromRom(rom, version)
  local scriptMids = NativePack.scriptMidsByPair(
    bundle.scripts, bundle.events, function(mapId)
      local spec = Versions.MAPS[mapId]
      return spec and (spec.pair or "sevii_outdoor") or nil
    end)
  local scriptEntries, scriptParts = writeScriptShards(
    cache, root, bundle, ExtractScripts.serialize_lua)
  writeScriptSupport(rom, cache, root, bundle, ExtractScripts.serialize_lua)
  assert(RRListMenus and RRListMenus.write,
    "Radical Red custom list-menu extractor was not loaded")
  local listMenuData = RRListMenus.write(cache, root, rom)
  local listMenuCalls = countSpecialCalls(bundle.scripts, 0x158)
  assert(listMenuData.count == 16 and listMenuCalls == 16,
    ("Radical Red custom-list census changed: tables=%s calls=%s")
      :format(tostring(listMenuData.count), tostring(listMenuCalls)))
  require("src.import.gba.trainer_extract").run(rom, cache, {
    cacheRoot = root,
    scripts = bundle.scripts,
    text = bundle.text,
  })
  local scriptCount, seedCount = bundle.scriptCount, bundle.seedCount
  bundle = nil
  rom:clearCache()
  collectgarbage()

  progress("world_warps", 0, 1)
  local ExtractMapEvents = require("src.import.gba.extract_map_events")
  local rawWarps, rawConnections =
    ExtractMapEvents.extractWarpsAndConnections(rom, version)
  local warps, connections, warpCells = {}, {}, {}
  for _, mapId in ipairs(mapOrder) do
    local list = rawWarps[mapId] or Versions.WARPS[mapId] or {}
    for _, warp in ipairs(list) do
      if not warp.destMap and warp.mapGroup ~= nil then
        warp.destMap = MapCatalog.mapIdFor(warp.mapGroup, warp.mapNum)
      end
    end
    warps[mapId] = list
    local set = {}
    for _, warp in ipairs(list) do
      if tonumber(warp.x) and tonumber(warp.y) then
        set[NativePack.warpKey(tonumber(warp.x), tonumber(warp.y))] = true
      end
    end
    warpCells[mapId] = set

    local fixed = {}
    local function addConnection(dir, connection)
      local dest = connection.map
      if (not dest or dest:match("^g%d+_m%d+$"))
          and connection.mapGroup ~= nil then
        dest = MapCatalog.mapIdFor(connection.mapGroup, connection.mapNum) or dest
      elseif dest then
        dest = MapCatalog.resolve(dest) or dest
      end
      if dest then
        fixed[#fixed + 1] = {
          dir = assert(dir, "Radical Red connection omitted direction"),
          map = dest,
          offset = tonumber(connection.offset) or 0,
        }
      end
    end
    local raw = rawConnections[mapId] or {}
    for _, connection in ipairs(raw) do
      addConnection(connection.dir or connection.direction, connection)
    end
    -- Compatibility with older engine extractors that returned keyed edges.
    for dir, connection in pairs(raw) do
      if type(dir) == "string" then addConnection(dir, connection) end
    end
    connections[mapId] = fixed
  end
  rawWarps, rawConnections = nil, nil
  local worldAudit = auditTopology(
    Profile, mapOrder, mapDims, warps, connections)
  writeWarps(cache, root, mapOrder, warps)
  writeConnections(cache, root, mapOrder, connections)
  connections = nil
  collectgarbage()

  -- Void-fill needs only these two tiny borders while each tileset pair is
  -- processed.  Keeping them avoids retaining every map grid just for this
  -- cross-pair rule.
  local sharedBorders = {}
  for _, mapId in ipairs({ "FR_PALLET_TOWN", "FR_CINNABAR_ISLAND" }) do
    if Versions.MAPS[mapId] then
      sharedBorders[mapId] = Maps.loadBorder(rom, version, mapId)
    end
  end

  local finalManifest = { pairs = {}, layouts = {} }
  local midIndexLines = { "return {" }
  local totalMids = 0
  local AltLayouts = require("src.import.gba.alt_layouts")
  local AnimPack = require("src.import.gba.tileset_anim_pack")

  for pairIndex, pairName in ipairs(pairNames) do
    progress("world_tilesets", pairIndex - 1, #pairNames)
    local bundleForPair = assert(Tileset.loadPair(rom, version, pairName),
      "could not load Radical Red tileset pair " .. pairName)
    local grids, borders = {}, {}
    for key, value in pairs(sharedBorders) do borders[key] = value end
    for _, mapId in ipairs(pairMaps[pairName]) do
      local spec = Versions.MAPS[mapId]
      local layout = spec.layout and version.layouts[spec.layout]
      assert(layout, "missing Radical Red layout " .. tostring(spec.layout))
      local grid = Maps.loadGrid(rom, layout)
      grid.map_id = mapId
      grid.kind = spec.kind
      grid.pair = pairName
      grid.environment = spec.environment
      grids[mapId] = BaseExtract.padEven(grid)
      borders[mapId] = Maps.loadBorder(rom, version, mapId)
    end
    AltLayouts.build(rom, version, grids, borders, BaseExtract.padEven)

    local midList = NativePack.collectMidsForPair(
      grids, borders, pairName, scriptMids)
    totalMids = totalMids + #midList
    local oneIndex = { [pairName] = {} }
    midIndexLines[#midIndexLines + 1] = ("  [%q] = {"):format(pairName)
    for _, mid in ipairs(midList) do
      local behavior = Tileset.behaviorOf(bundleForPair, mid) or 0
      local coll = select(1,
        Collision.fromCell(mid, 0, behavior, "outdoor")) or 0
      oneIndex[pairName][mid] = {
        tiles = { 0, 0, 0, 0 }, coll = coll,
        behavior = behavior, category = "misc",
      }
      midIndexLines[#midIndexLines + 1] =
        ("    [%d] = { tiles={0,0,0,0}, coll=%d, behavior=%d, category=%q },")
          :format(mid, coll, behavior, "misc")
    end
    midIndexLines[#midIndexLines + 1] = "  },"

    local partial = NativePack.writeExtract(cache, root,
      { [pairName] = bundleForPair }, grids, borders, { pairName }, oneIndex,
      Tileset.behaviorOf, Collision.fromCell, scriptMids, warpCells)
    finalManifest.pairs[pairName] = partial.pairs[pairName]
    for mapId, layout in pairs(partial.layouts or {}) do
      finalManifest.layouts[mapId] = layout
    end
    AnimPack.writeExtract(rom, cache, root,
      { [pairName] = bundleForPair }, { [pairName] = midList }, version)

    bundleForPair, grids, borders, oneIndex, midList, partial =
      nil, nil, nil, nil, nil, nil
    rom:clearCache()
    collectgarbage()
  end
  progress("world_tilesets", #pairNames, #pairNames)

  midIndexLines[#midIndexLines + 1] = "}"
  midIndexLines[#midIndexLines + 1] = ""
  put(cache, root .. "/mid_index.lua", table.concat(midIndexLines, "\n"))
  writeNativeManifest(cache, root, finalManifest, pairNames)
  writeMeta(cache, root, Profile, version, importId, mapOrder, totalMids)
  auditLayouts(cache, root, mapOrder, mapDims, finalManifest, worldAudit)
  worldAudit.customListMenus = listMenuData.count
  worldAudit.customListMenuCalls = listMenuCalls

  -- Independent extractors run only after all tileset/map working sets have
  -- been released.  Each writes immediately to the mod-private disk cache.
  progress("world_aux", 0, 7)
  require("src.import.gba.help_extract").writeExtract(rom, cache)
  progress("world_aux", 1, 7)
  require("src.import.gba.quest_log_extract").writeExtract(rom, cache)
  progress("world_aux", 2, 7)
  require("src.import.gba.object_interactions_extract").writeExtract(
    rom, cache, root, version)
  progress("world_aux", 3, 7)
  require("src.import.gba.ow_extract").writeExtract(rom, cache, root, version)
  progress("world_aux", 4, 7)
  assert(RR_Encounters and RR_Encounters.writeExtract,
    "Radical Red encounter extractor was not loaded")
  local encounterAudit = RR_Encounters.writeExtract(
    rom, cache, root, version, Profile)
  worldAudit.encounterMaps = encounterAudit.maps
  worldAudit.encounterBaseHeaders = encounterAudit.baseHeaders
  worldAudit.encounterDayHeaders = encounterAudit.dayHeaders
  worldAudit.encounterNightHeaders = encounterAudit.nightHeaders
  worldAudit.encounterUsableSlots = encounterAudit.usableSlots
  worldAudit.encounterPlaceholderSlotsRemoved =
    encounterAudit.placeholderSlotsRemoved
  writeWorldAudit(cache, root, worldAudit)
  progress("world_aux", 5, 7)
  require("src.import.gba.field_effect_extract").writeExtract(
    rom, cache, root, version)
  -- RR erases FireRed's old fixed gObjectEventPic_RockSmashRock address, but
  -- the live object-event table still exposes the exact four-frame 16x16 rock
  -- sheet as graphics ID 96.  Reuse that ROM-derived sheet for the field-move
  -- effect instead of accepting 1,024 opaque black pixels from the stale
  -- vanilla offset.
  local rockSmash = cache:read(root .. "/ow/96.rgba")
  assert(type(rockSmash) == "string" and #rockSmash == 16 * 16 * 4 * 4,
    "Radical Red Rock Smash object sheet is missing or malformed")
  put(cache, root .. "/field_effects/rock_smash.rgba", rockSmash)
  progress("world_aux", 6, 7)
  local okTree, treeError = require("src.import.gba.map_tree_extract").run(
    rom, cache, { version = version, root = root .. "/map_tree" })
  assert(okTree, "Radical Red map-tree extraction failed: " .. tostring(treeError))
  progress("world_aux", 7, 7)

  rom:clearCache()
  rom, warps, warpCells, scriptMids = nil, nil, nil, nil
  collectgarbage()
  return {
    maps = #mapOrder,
    mapOrder = mapOrder,
    midCount = totalMids,
    scriptCount = scriptCount,
    scriptSeeds = seedCount,
    scriptEntries = scriptEntries,
    scriptShards = scriptParts,
    worldAudit = worldAudit,
  }
end

return World
