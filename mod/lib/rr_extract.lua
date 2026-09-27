-- Radical Red v4.1 private-ROM extraction pipeline.
--
-- Nothing generated here is shipped in the mod.  On first launch the stock
-- mod API reads the launcher-validated ROM and writes a versioned cache owned
-- by this mod.  Later launches only rebuild the in-memory map catalogue and
-- reuse that cache.

local Extractor = {}

local function copy(t)
  local out = {}
  for k, v in pairs(t or {}) do out[k] = v end
  return out
end

local function importAdapter(mod, Profile)
  local source = assert(mod.imports, "Radical Red import access is unavailable")
  local adapter = {}

  function adapter:info(id)
    if id ~= "firered" and id ~= "leafgreen" then return nil end
    local info, err = source:info(Profile.IMPORT_ID)
    if not info then return nil, err end
    local out = copy(info)
    out.id = "firered"
    return out
  end

  function adapter:read(id, offset, length)
    if id ~= "firered" and id ~= "leafgreen" then
      return nil, "unsupported adapted import " .. tostring(id)
    end
    return source:read(Profile.IMPORT_ID, offset, length)
  end

  return adapter
end

local function loadLua(cache, rel)
  local source = cache:read(rel)
  if type(source) ~= "string" then return nil end
  local chunk = load(source, "@" .. rel, "t", {})
  if not chunk then return nil end
  local ok, value = pcall(chunk)
  if ok then return value end
  return nil
end

local function requireFiles(cache, files)
  for _, rel in ipairs(files) do
    local data = cache:read(rel)
    if type(data) ~= "string" or #data == 0 then
      return false, rel
    end
  end
  return true
end

local function markerReady(cache, Profile)
  local root = Profile.extractRoot()
  local marker = loadLua(cache, root .. "/rr_complete.lua")
  if type(marker) ~= "table"
      or marker.schema ~= Profile.CACHE_SCHEMA
      or marker.md5 ~= Profile.MD5
      or marker.species ~= Profile.SPECIES_COUNT
      or marker.moves ~= Profile.MOVE_COUNT
      or marker.maps ~= Profile.MAP_COUNT then
    return false
  end
  local essentialsOk = requireFiles(cache, {
    root .. "/meta.json",
    root .. "/native/manifest.lua",
    root .. "/warps.lua",
    root .. "/connections.lua",
    root .. "/world_audit.lua",
    root .. "/scripts/scripts.lua",
    root .. "/scripts/events.lua",
    root .. "/scripts/text.lua",
    root .. "/scripts/multichoice.lua",
    root .. "/scripts/rr_listmenus.lua",
    root .. "/scripts/rr_shards/manifest.lua",
    root .. "/encounters.lua",
    root .. "/trainers.lua",
    root .. "/pokemon/manifest.lua",
    root .. "/pokemon/names.lua",
    root .. "/pokemon/stats.lua",
    root .. "/pokemon/abilities.lua",
    root .. "/pokemon/learnsets.lua",
    root .. "/pokemon/evolutions.lua",
    root .. "/pokemon/tmhm.lua",
    root .. "/pokemon/tutor.lua",
    root .. "/pokemon/battle_moves.lua",
    root .. "/pokemon/pic_coords.lua",
    root .. "/pokemon/front/1.rgba",
    root .. "/pokemon/back/1.rgba",
    root .. "/pokemon/icons/1.rgba",
    root .. "/pokemon/front/" .. tostring(Profile.SPECIES_COUNT - 1) .. ".rgba",
    root .. "/pokemon/back/" .. tostring(Profile.SPECIES_COUNT - 1) .. ".rgba",
    root .. "/pokemon/icons/" .. tostring(Profile.SPECIES_COUNT - 1) .. ".rgba",
    root .. "/items/pack.lua",
    root .. "/intro/title_screen.png",
    root .. "/intro/title_logo.png",
    Profile.introIndex(),
    root .. "/audio/index.lua",
    root .. "/audio/samples.bin",
    root .. "/naming/manifest.lua",
  })
  if not essentialsOk then return false end
  local shards = loadLua(cache, root .. "/scripts/rr_shards/manifest.lua")
  if type(shards) ~= "table" or shards.version ~= 1
      or type(shards.parts) ~= "table" then return false end
  for _, name in ipairs({ "scripts", "text", "movements", "events" }) do
    local paths = shards.parts[name]
    if type(paths) ~= "table" or #paths == 0 then return false end
    local ok = requireFiles(cache, paths)
    if not ok then return false end
  end
  local lists = loadLua(cache, root .. "/scripts/rr_listmenus.lua")
  local audit = loadLua(cache, root .. "/world_audit.lua")
  if type(lists) ~= "table" or lists.version ~= 1 or lists.count ~= 16
      or type(lists.lists) ~= "table"
      or type(audit) ~= "table" or audit.version ~= 1
      or audit.maps ~= Profile.MAP_COUNT or audit.layouts ~= Profile.MAP_COUNT
      or audit.connections ~= 116 or audit.warps ~= 1324
      or audit.customListMenus ~= 16 or audit.encounterMaps ~= 134
      or audit.encounterBaseHeaders ~= Profile.RR_WILD_BASE_HEADER_COUNT
      or audit.encounterDayHeaders ~= Profile.RR_WILD_DAY_HEADER_COUNT
      or audit.encounterNightHeaders ~= Profile.RR_WILD_NIGHT_HEADER_COUNT
      or audit.encounterUsableSlots ~= 4866
      or audit.encounterPlaceholderSlotsRemoved ~= 177 then
    return false
  end
  return true
end

-- Versions.MAPS/TILESETS are process-local.  Reconstruct them even when all
-- cache files already exist, otherwise a second launch sees the RR files but
-- only knows the small built-in FireRed map set.
local function rebuildCatalog(adapter, Profile, StreamRom)
  local Versions = require("src.import.gba.versions")
  local MapTree = require("src.import.gba.map_tree")
  local MapCatalog = require("src.import.gba.map_catalog")
  local info = assert(adapter:info("firered"))
  local version = assert(Versions.lookup(info.md5))
  assert(StreamRom and StreamRom.open,
    "Radical Red bounded ROM reader was not loaded")
  local rom = assert(StreamRom.open(adapter, "firered"))
  MapCatalog.rebuildIndex()
  local census = assert(MapTree.walk(rom, version))
  local order, byEngine = MapCatalog.allOrder(census, {})
  local registered = MapCatalog.registerOrder(rom, version, order, byEngine)
  rom:clearCache()
  assert(#order == Profile.MAP_COUNT,
    ("Radical Red map census changed: expected %d, got %d")
      :format(Profile.MAP_COUNT, #order))
  assert(#registered == Profile.MAP_COUNT,
    ("Radical Red map registration incomplete: expected %d, got %d")
      :format(Profile.MAP_COUNT, #registered))
  return #registered
end

local function put(cache, rel, bytes)
  local ok, err = cache:write(rel, bytes)
  assert(ok ~= false and ok ~= nil,
    "could not write Radical Red cache " .. rel .. ": " .. tostring(err))
end

local function writeAbilities(rom, cache, Profile)
  local lines = {
    "-- Generated from the player's Radical Red v4.1 ROM.",
    "-- [1]/[2] are normal abilities; [3]/hidden is the hidden ability.",
    "return {",
  }
  for species = 0, Profile.SPECIES_COUNT - 1 do
    local off = Profile.OFFSET.baseStats + species * 28
    local a1, a2, hidden = rom:get(off + 22), rom:get(off + 23), rom:get(off + 26)
    lines[#lines + 1] = ("  [%d] = { %d, %d, %d, hidden = %d },")
      :format(species, a1, a2, hidden, hidden)
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  put(cache, Profile.extractRoot() .. "/pokemon/abilities.lua", table.concat(lines, "\n"))
end

local function writeLearnsets(rom, cache, Profile)
  local lines = {
    "-- Generated from Radical Red's 3-byte level-up learnset entries.",
    "return {",
  }
  local entries, nonempty = 0, 0
  for species = 0, Profile.SPECIES_COUNT - 1 do
    local ptr = rom:u32(Profile.OFFSET.levelUpLearnsets + species * 4)
    local off = rom:ptrOffset(ptr)
    local parts = {}
    if off then
      local terminated = false
      for i = 0, 255 do
        local move = rom:u16(off + i * 3)
        local level = rom:get(off + i * 3 + 2)
        if move == 0 and level == 0xFF then
          terminated = true
          break
        end
        assert(move < Profile.MOVE_COUNT,
          ("invalid RR learnset move %d for species %d"):format(move, species))
        assert(level <= 100,
          ("invalid RR learnset level %d for species %d"):format(level, species))
        if move > 0 then
          parts[#parts + 1] = ("{%d,%d}"):format(level, move)
          entries = entries + 1
        end
      end
      assert(terminated, "unterminated RR learnset for species " .. species)
    end
    if #parts > 0 then nonempty = nonempty + 1 end
    lines[#lines + 1] = ("  [%d] = { %s },"):format(species, table.concat(parts, ", "))
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  put(cache, Profile.extractRoot() .. "/pokemon/learnsets.lua", table.concat(lines, "\n"))
  return entries, nonempty
end

local function wordsFor(rom, off, count)
  local words = {}
  for i = 0, count - 1 do words[i + 1] = rom:u32(off + i * 4) end
  return words
end

local function wordsNonzero(words)
  for _, value in ipairs(words) do
    if value ~= 0 then return true end
  end
  return false
end

local function wordsLiteral(words)
  local out = {}
  for i, value in ipairs(words) do out[i] = tostring(value) end
  return table.concat(out, ", ")
end

local function writeTmhm(rom, cache, Profile)
  local lines = {
    "-- Generated from Radical Red's 128-machine tables.",
    "local M = { machines = {}, learnsets = {} }",
  }
  for i = 0, Profile.MACHINE_COUNT - 1 do
    lines[#lines + 1] = ("M.machines[%d] = %d")
      :format(i, rom:u16(Profile.OFFSET.tmhmMoves + i * 2))
  end
  local compatible = 0
  for species = 0, Profile.SPECIES_COUNT - 1 do
    local words = wordsFor(rom,
      Profile.OFFSET.tmhmLearnsets + species * Profile.TMHM_WORDS * 4,
      Profile.TMHM_WORDS)
    if wordsNonzero(words) then
      compatible = compatible + 1
      lines[#lines + 1] = ("M.learnsets[%d] = { lo=%u, hi=%u, words={%s} }")
        :format(species, words[1], words[2], wordsLiteral(words))
    end
  end
  lines[#lines + 1] = "return M"
  lines[#lines + 1] = ""
  put(cache, Profile.extractRoot() .. "/pokemon/tmhm.lua", table.concat(lines, "\n"))
  return compatible
end

local function writeTutors(rom, cache, Profile)
  local lines = {
    "-- Generated from Radical Red's 128-tutor tables.",
    "local M = { format_version = 2, moves = {}, learnsets = {} }",
  }
  for i = 0, Profile.TUTOR_COUNT - 1 do
    lines[#lines + 1] = ("M.moves[%d] = %d")
      :format(i, rom:u16(Profile.OFFSET.tutorMoves + i * 2))
  end
  local compatible = 0
  for species = 0, Profile.SPECIES_COUNT - 1 do
    local words = wordsFor(rom,
      Profile.OFFSET.tutorLearnsets + species * Profile.TUTOR_WORDS * 4,
      Profile.TUTOR_WORDS)
    if wordsNonzero(words) then
      compatible = compatible + 1
      lines[#lines + 1] = ("M.learnsets[%d] = { %s, words={%s} }")
        :format(species, wordsLiteral(words), wordsLiteral(words))
    end
  end
  lines[#lines + 1] = "return M"
  lines[#lines + 1] = ""
  put(cache, Profile.extractRoot() .. "/pokemon/tutor.lua", table.concat(lines, "\n"))
  return compatible
end

local SPLIT = { [0] = "physical", [1] = "special", [2] = "status" }
local function writeBattleMoves(rom, cache, Profile)
  local lines = {
    "-- Generated from Radical Red's expanded gBattleMoves.",
    "return { version=2, count=" .. Profile.MOVE_COUNT .. ", moves={",
  }
  local counts = { physical = 0, special = 0, status = 0 }
  for id = 0, Profile.MOVE_COUNT - 1 do
    local off = Profile.OFFSET.battleMoves + id * 12
    local priority = rom:get(off + 7)
    if priority >= 128 then priority = priority - 256 end
    local splitId = rom:get(off + 10)
    local category = assert(SPLIT[splitId], "invalid RR move split " .. splitId)
    counts[category] = counts[category] + 1
    lines[#lines + 1] = ("  [%d]={ effect=%d, power=%d, type=%d, accuracy=%d, pp=%d, secondaryChance=%d, target=%d, priority=%d, flags=%d, zMovePower=%d, splitId=%d, category=%q, zMoveEffect=%d },")
      :format(id, rom:get(off), rom:get(off + 1), rom:get(off + 2),
        rom:get(off + 3), rom:get(off + 4), rom:get(off + 5), rom:get(off + 6),
        priority, rom:get(off + 8), rom:get(off + 9), splitId, category,
        rom:get(off + 11))
  end
  assert(counts.physical == 435 and counts.special == 305 and counts.status == 264,
    "Radical Red move split registry failed validation")
  lines[#lines + 1] = "} }"
  lines[#lines + 1] = ""
  put(cache, Profile.extractRoot() .. "/pokemon/battle_moves.lua", table.concat(lines, "\n"))
  return counts
end

local function writePicCoords(rom, cache, Profile)
  local front, back, elev = {}, {}, {}
  local cyndaquilBack
  for species = 0, Profile.SPECIES_COUNT - 1 do
    -- DPE's struct MonCoords is size, y_offset, then two padding bytes.
    local frontY = rom:get(Profile.OFFSET.frontPicCoords + species * 4 + 1)
    local backY = rom:get(Profile.OFFSET.backPicCoords + species * 4 + 1)
    -- RR uses -3 (stored as 0xFD) for Galarian Weezing's tall front sprite.
    -- Preserve that intended signed displacement in the host renderer.
    if frontY >= 128 then frontY = frontY - 256 end
    if backY >= 128 then backY = backY - 256 end
    local elevation = rom:get(Profile.OFFSET.enemyMonElevation + species)
    assert(frontY >= -64 and frontY <= 64
        and backY >= -64 and backY <= 64 and elevation <= 64,
      "invalid Radical Red sprite coordinate for species " .. species)
    front[#front + 1] = ("[%d]=%d"):format(species, frontY)
    back[#back + 1] = ("[%d]=%d"):format(species, backY)
    elev[#elev + 1] = ("[%d]=%d"):format(species, elevation)
    if species == 155 then cyndaquilBack = backY end
  end
  -- A relocated-table typo can still produce syntactically valid Lua. Pin a
  -- changed RR sentinel so FireRed's stale 9-pixel Cyndaquil baseline cannot
  -- silently return.
  assert(cyndaquilBack == 3,
    "Radical Red Cyndaquil back-sprite coordinate moved")
  local source = table.concat({
    "-- Generated from Radical Red's expanded DPE sprite-coordinate tables.",
    "return {",
    ("  species = %d,"):format(Profile.SPECIES_COUNT),
    "  front = { " .. table.concat(front, ",") .. " },",
    "  back = { " .. table.concat(back, ",") .. " },",
    "  elev = { " .. table.concat(elev, ",") .. " },",
    "}", "",
  }, "\n")
  put(cache, Profile.extractRoot() .. "/pokemon/pic_coords.lua", source)
  return { species = Profile.SPECIES_COUNT, cyndaquilBack = cyndaquilBack }
end

local function corePokemonReady(cache, Profile)
  local root = Profile.extractRoot() .. "/pokemon"
  return requireFiles(cache, {
    root .. "/manifest.lua", root .. "/names.lua", root .. "/stats.lua",
    root .. "/types.lua", root .. "/national.lua", root .. "/evolutions.lua",
    root .. "/egg_moves.lua", root .. "/front/1.rgba", root .. "/back/1.rgba",
    root .. "/icons/1.rgba",
    root .. "/front/" .. tostring(Profile.SPECIES_COUNT - 1) .. ".rgba",
    root .. "/back/" .. tostring(Profile.SPECIES_COUNT - 1) .. ".rgba",
    root .. "/icons/" .. tostring(Profile.SPECIES_COUNT - 1) .. ".rgba",
  })
end

-- The stock species extractor writes several thousand small sprite files.
-- LÖVE's Android allocator can otherwise retain their temporary strings until
-- the end of the pass and cross the process memory ceiling.  Delegate every
-- cache operation to the real mod cache, but force a bounded collection after
-- each small batch of completed writes.
local function collectingCache(cache)
  local writes = 0
  local proxy = {}
  function proxy:write(path, bytes)
    local ok, err = cache:write(path, bytes)
    writes = writes + 1
    if writes % 32 == 0 then collectgarbage("collect") end
    return ok, err
  end
  return setmetatable(proxy, {
    __index = function(_, key)
      local value = cache[key]
      if type(value) ~= "function" then return value end
      return function(_, ...)
        return value(cache, ...)
      end
    end,
  })
end

local function readFullRom(adapter, Profile, progress)
  local parts = {}
  local chunk = 4 * 1024 * 1024
  for offset = 0, Profile.ROM_SIZE - 1, chunk do
    local length = math.min(chunk, Profile.ROM_SIZE - offset)
    parts[#parts + 1] = assert(adapter:read("firered", offset, length))
    if progress then progress("rom_assets", math.floor(offset / chunk) + 1,
      math.ceil(Profile.ROM_SIZE / chunk)) end
  end
  return table.concat(parts)
end

local function runGraphicalAssets(adapter, cache, Profile, progress)
  assert(love and love.image and love.image.newImageData,
    "Radical Red's first launch needs the normal LÖVE graphics runtime")
  local root = Profile.extractRoot()
  local introReady = requireFiles(cache, {
    root .. "/intro/title_screen.png",
    root .. "/intro/title_logo.png",
    Profile.introIndex(),
  })
  local namingReady = requireFiles(cache, {
    root .. "/naming/manifest.lua",
  })
  local audioReady = requireFiles(cache, {
    root .. "/audio/index.lua",
    root .. "/audio/samples.bin",
  })
  if introReady and namingReady and audioReady then
    progress("rom_assets", 3, 3)
    return
  end

  local data = readFullRom(adapter, Profile, progress)
  local source = { data = data }
  collectgarbage("collect")

  progress("rom_assets", 0, 3)
  if not introReady then
    local okIntro, introOrErr = require("src.import.gba.extract_intro").run(source, cache, {
      sha1 = Profile.SHA1,
      root = root .. "/intro",
      introIndex = Profile.introIndex(),
    })
    assert(okIntro, "Radical Red title extraction failed: " .. tostring(introOrErr))
  end
  collectgarbage("collect")
  progress("rom_assets", 1, 3)

  if not namingReady then
    local okNaming, namingErr = require("src.import.gba.extract_naming").run(source, cache, {
      root = root .. "/naming",
    })
    assert(okNaming, "Radical Red naming-screen extraction failed: " .. tostring(namingErr))
  end
  collectgarbage("collect")
  progress("rom_assets", 2, 3)

  if not audioReady then
    local okAudio, audioErr = require("src.import.gba.extract_audio").run(source, cache, {
      sha1 = Profile.SHA1,
      root = root .. "/audio",
    })
    assert(okAudio, "Radical Red audio extraction failed: " .. tostring(audioErr))
  end
  progress("rom_assets", 3, 3)

  source.data, data = nil, nil
  collectgarbage()
end

local OPTIONAL_EXTRACTORS = {
  "src.import.gba.party_chrome_extract",
  "src.import.gba.battle_chrome_extract",
  "src.import.gba.battle_transition_extract",
  "src.import.gba.summary_chrome_extract",
  "src.import.gba.bag_chrome_extract",
  "src.import.gba.shop_chrome_extract",
  "src.import.gba.pokedex_chrome_extract",
  "src.import.gba.storage_chrome_extract",
  "src.import.gba.trainer_card_extract",
  "src.import.gba.tm_case_extract",
  "src.import.gba.berry_pouch_extract",
  "src.import.gba.text_chrome_extract",
  "src.import.gba.ball_open_extract",
}

local function runOptionalExtractors(rom, cache, Profile, log, progress)
  local okCount, failures = 0, {}
  for index, name in ipairs(OPTIONAL_EXTRACTORS) do
    if progress then progress("interface", index - 1, #OPTIONAL_EXTRACTORS) end
    local okRequire, module = pcall(require, name)
    local ok, detail
    if okRequire and module and module.run then
      ok, detail = pcall(module.run, rom, cache, {
        cacheRoot = Profile.extractRoot(), force = true,
      })
    end
    if okRequire and ok then
      okCount = okCount + 1
    else
      failures[#failures + 1] = name .. ": " .. tostring(detail or module)
    end
    collectgarbage("collect")
  end
  if progress then progress("interface", #OPTIONAL_EXTRACTORS, #OPTIONAL_EXTRACTORS) end
  if #failures > 0 and log and log.warn then
    log:warn("Radical Red reused vanilla chrome for " .. #failures
      .. " incompatible auxiliary UI extractor(s)")
  end
  return okCount, failures
end

local function writeMarker(cache, Profile, report)
  local root = Profile.extractRoot()
  local lines = {
    "-- Radical Red private extraction completion marker.",
    "return {",
    ("  schema = %d,"):format(Profile.CACHE_SCHEMA),
    ("  md5 = %q,"):format(Profile.MD5),
    ("  sha1 = %q,"):format(Profile.SHA1),
    ("  maps = %d,"):format(report.maps),
    ("  species = %d,"):format(Profile.SPECIES_COUNT),
    ("  moves = %d,"):format(Profile.MOVE_COUNT),
    ("  abilities = %d,"):format(Profile.ABILITY_COUNT),
    ("  items = %d,"):format(Profile.ITEM_COUNT),
    ("  machines = %d,"):format(Profile.MACHINE_COUNT),
    ("  tutors = %d,"):format(Profile.TUTOR_COUNT),
    "}", "",
  }
  put(cache, root .. "/rr_complete.lua", table.concat(lines, "\n"))
end

function Extractor.ensure(mod, Profile, opts)
  opts = opts or {}
  assert(mod and mod.cache and mod.imports,
    "Radical Red requires mod.cache and mod.imports")

  -- Cold conversion may be driven by a coroutine from the mod's core.update
  -- hook.  Reporting a checkpoint lets Android present a frame between the
  -- expensive extraction passes instead of spending the entire first launch
  -- inside Loader:load (which some devices kill as an unresponsive activity).
  -- Cached launches leave this unset and retain the direct, synchronous path.
  local function progress(stage, cur, total)
    if mod.log and mod.log.info then
      mod.log:info(("Radical Red first-launch extraction: %s %d/%d")
        :format(tostring(stage), tonumber(cur) or 0, tonumber(total) or 1))
    end
    if opts.onProgress then opts.onProgress(stage, cur, total) end
  end

  local Versions = require("src.import.gba.versions")
  Profile.apply(Versions)
  local CachePaths = require("src.core.game3.cache_paths")
  CachePaths.setRoot(Profile.extractRoot())
  local Extract = require("src.import.gba.extract_island1")
  Extract.CACHE_ROOT = Profile.extractRoot()
  Extract.NATIVE_ROOT = Profile.extractRoot() .. "/native"

  local adapter = importAdapter(mod, Profile)
  local StreamRom = assert(opts.streamRom,
    "Radical Red bounded ROM reader was not loaded")
  progress("catalog", 0, 1)
  local maps = rebuildCatalog(adapter, Profile, StreamRom)
  progress("catalog", 1, 1)
  local ready = markerReady(mod.cache, Profile)
  if ready then
    local shardManifest = assert(loadLua(mod.cache,
      Profile.extractRoot() .. "/scripts/rr_shards/manifest.lua"))
    local multichoice = assert(loadLua(mod.cache,
      Profile.extractRoot() .. "/scripts/multichoice.lua"))
    local customLists = assert(loadLua(mod.cache,
      Profile.extractRoot() .. "/scripts/rr_listmenus.lua"))
    local worldAudit = assert(loadLua(mod.cache,
      Profile.extractRoot() .. "/world_audit.lua"))
    local multichoiceLists = 0
    for _, entry in pairs(multichoice) do
      if entry and tonumber(entry.count) and entry.count > 0 then
        multichoiceLists = multichoiceLists + 1
      end
    end
    return {
      cached = true, maps = maps, species = Profile.SPECIES_COUNT,
      moves = Profile.MOVE_COUNT, root = Profile.extractRoot(),
      scriptEntries = shardManifest.entries,
      scriptShards = shardManifest.parts,
      multichoiceLists = multichoiceLists,
      customListMenus = customLists.count,
      worldAudit = worldAudit,
    }
  end

  local World = assert(opts.world,
    "Radical Red low-memory world extractor was not loaded")
  local Encounters = assert(opts.encounters,
    "Radical Red encounter extractor was not loaded")
  local ListMenus = assert(opts.listMenus,
    "Radical Red custom list-menu extractor was not loaded")
  local worldOk, world = pcall(
    World.run, adapter, mod.cache, Profile, progress, StreamRom, ListMenus,
      Encounters)
  assert(worldOk, "Radical Red world extraction failed: " .. tostring(world))
  assert(world and world.maps == Profile.MAP_COUNT,
    "Radical Red world cache omitted maps")
  local scriptEntries = assert(world.scriptEntries,
    "Radical Red script shard counts are missing")
  local scriptParts = assert(world.scriptShards,
    "Radical Red script shard paths are missing")
  collectgarbage()
  progress("world", 1, 1)

  local rom = assert(StreamRom.open(adapter, "firered"))
  local pokemonExtractError = nil
  if not corePokemonReady(mod.cache, Profile) then
    collectgarbage("collect")
    local okPokemon, pokemon = pcall(
      require("src.import.gba.pokemon_extract").run,
      rom, collectingCache(mod.cache), {
        cacheRoot = Profile.extractRoot(),
        numSpecies = Profile.SPECIES_COUNT,
        progress = progress,
      })
    if not okPokemon then pokemonExtractError = tostring(pokemon) end
  end
  local pokemonOk, missingPokemon = corePokemonReady(mod.cache, Profile)
  assert(pokemonOk,
    "Radical Red Pokemon extraction failed before core assets were complete ("
      .. tostring(pokemonExtractError or missingPokemon) .. ")")

  progress("expanded_tables", 0, 8)
  writeAbilities(rom, mod.cache, Profile)
  progress("expanded_tables", 1, 8)
  local learnEntries, learnSpecies = writeLearnsets(rom, mod.cache, Profile)
  progress("expanded_tables", 2, 8)
  local tmSpecies = writeTmhm(rom, mod.cache, Profile)
  progress("expanded_tables", 3, 8)
  local tutorSpecies = writeTutors(rom, mod.cache, Profile)
  progress("expanded_tables", 4, 8)
  local categoryCounts = writeBattleMoves(rom, mod.cache, Profile)
  progress("expanded_tables", 5, 8)
  local picCoords = writePicCoords(rom, mod.cache, Profile)
  progress("expanded_tables", 6, 8)
  local multichoiceReport = require("src.import.gba.multichoice_extract").run(
    rom, mod.cache, { cacheRoot = Profile.extractRoot() })
  progress("expanded_tables", 7, 8)
  require("src.import.gba.items_extract").run(rom, mod.cache, {
    cacheRoot = Profile.extractRoot(), force = true,
  })
  progress("expanded_tables", 8, 8)
  local optionalOk, optionalFailures = runOptionalExtractors(
    rom, mod.cache, Profile, mod.log, progress)
  rom:clearCache()

  if not opts.skipGraphicalAssets then
    runGraphicalAssets(adapter, mod.cache, Profile, progress)
  end

  local essentialsOk, missing = requireFiles(mod.cache, {
    Profile.extractRoot() .. "/native/manifest.lua",
    Profile.extractRoot() .. "/warps.lua",
    Profile.extractRoot() .. "/connections.lua",
    Profile.extractRoot() .. "/world_audit.lua",
    Profile.extractRoot() .. "/scripts/scripts.lua",
    Profile.extractRoot() .. "/scripts/multichoice.lua",
    Profile.extractRoot() .. "/scripts/rr_listmenus.lua",
    Profile.extractRoot() .. "/scripts/rr_shards/manifest.lua",
    Profile.extractRoot() .. "/pokemon/manifest.lua",
    Profile.extractRoot() .. "/pokemon/learnsets.lua",
    Profile.extractRoot() .. "/pokemon/tmhm.lua",
    Profile.extractRoot() .. "/pokemon/tutor.lua",
    Profile.extractRoot() .. "/pokemon/pic_coords.lua",
    Profile.extractRoot() .. "/items/pack.lua",
  })
  assert(essentialsOk, "Radical Red cache is incomplete: missing " .. tostring(missing))

  if not opts.skipGraphicalAssets then
    local graphicalOk, graphicalMissing = requireFiles(mod.cache, {
      Profile.extractRoot() .. "/intro/title_screen.png",
      Profile.extractRoot() .. "/intro/title_logo.png",
      Profile.introIndex(),
      Profile.extractRoot() .. "/audio/index.lua",
      Profile.extractRoot() .. "/naming/manifest.lua",
    })
    assert(graphicalOk,
      "Radical Red graphical/audio cache is incomplete: missing "
        .. tostring(graphicalMissing))
  end

  local report = {
    cached = false,
    maps = maps,
    species = Profile.SPECIES_COUNT,
    moves = Profile.MOVE_COUNT,
    learnsetEntries = learnEntries,
    learnsetSpecies = learnSpecies,
    tmSpecies = tmSpecies,
    tutorSpecies = tutorSpecies,
    categoryCounts = categoryCounts,
    picCoords = picCoords,
    multichoiceLists = multichoiceReport.listCount,
    customListMenus = world.worldAudit.customListMenus,
    worldAudit = world.worldAudit,
    optionalExtractors = optionalOk,
    optionalFailures = optionalFailures,
    scriptEntries = scriptEntries,
    scriptShards = scriptParts,
    pokemonAuxiliaryError = pokemonExtractError,
    root = Profile.extractRoot(),
  }
  if not opts.skipGraphicalAssets then writeMarker(mod.cache, Profile, report) end
  collectgarbage()
  return report
end

Extractor.importAdapter = importAdapter
Extractor.rebuildCatalog = rebuildCatalog
Extractor.markerReady = markerReady

return Extractor
