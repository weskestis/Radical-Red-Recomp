-- Runs the real gen1recomp Loader and Gen 3 registry merge against a synthetic
-- 386-species FireRed dataset while streaming table bytes from the exact RR ROM.
package.path = "./?.lua;./?/init.lua;" .. package.path
local sdk = require("tests.modkit").sdk

local rrPath = assert(arg[1],
  "usage: luajit mods/radical_red_experience/tests/engine_loader_test.lua <rr-v4.1.gba>")
local modRoot = "mods/radical_red_experience"
local digest = "8529f3a45d32bce4da637976fcf269d4"
local romSize, romModtime = 33554432, 123
local diskCache = os.getenv("RR_TEST_CACHE_DIR")
local legacyAndroidReader = os.getenv("RR_TEST_LEGACY_ANDROID_READER") == "1"
local madeParents = {}

local function cacheDiskPath(path)
  if not diskCache or path:sub(1, 10) ~= "mod_cache/" then return nil end
  return diskCache .. "/" .. path
end

local function makeParents(path)
  local parent = path:match("^(.*)/[^/]+$")
  if not parent or madeParents[parent] then return end
  local ok = os.execute("mkdir -p " .. string.format("%q", parent))
  assert(ok == true or ok == 0, "could not create cache path " .. parent)
  madeParents[parent] = true
end

local function diskRead(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local body = file:read("*a")
  file:close()
  return body
end

local receiptPath = modRoot
  .. "/baseroms/.required-import-radical_red_v4_1.validated"
local overlay = {
  [receiptPath] = ("v1\n%s\n%d\n%d\n"):format(digest, romSize, romModtime),
  ["options.lua"] = [[return {
    mods = { radical_red_experience = true },
    modsByVersionMigrated = true,
  }]],
}

local function actualPath(path)
  if path == modRoot .. "/baseroms/radical_red_v4_1.gba" then return rrPath end
  if path:sub(1, #modRoot + 1) == modRoot .. "/" then return path end
  return nil
end

local fs = {}
function fs.read(path)
  if overlay[path] then return overlay[path] end
  local cached = cacheDiskPath(path)
  if cached then return diskRead(cached) end
  local actual = actualPath(path)
  local body = actual and diskRead(actual) or nil
  if body and legacyAndroidReader
      and path == modRoot .. "/lib/rr_stream_rom.lua" then
    local replaced
    body, replaced = body:gsub("return StreamRom%s*$",
      "Rom.readString = nil\nreturn StreamRom\n")
    assert(replaced == 1,
      "could not construct legacy Android ROM-reader fixture")
  end
  return body
end
function fs.readRange(path, offset, length)
  local actual = actualPath(path)
  if not actual then return nil, "missing file" end
  local file = assert(io.open(actual, "rb"))
  assert(file:seek("set", offset))
  local body = assert(file:read(length))
  file:close()
  return body
end
function fs.write(path, body)
  local cached = cacheDiskPath(path)
  if cached then
    makeParents(cached)
    local file = assert(io.open(cached, "wb"))
    assert(file:write(body))
    file:close()
    return true
  end
  overlay[path] = body
  return true
end
function fs.remove(path)
  local cached = cacheDiskPath(path)
  if cached then return os.remove(cached) end
  overlay[path] = nil
  return true
end
function fs.createDirectory(path)
  local cached = cacheDiskPath((path or "") .. "/.dir")
  if cached then makeParents(cached) end
  return true
end
function fs.getInfo(path)
  if path == "mods" or path == modRoot or path == modRoot .. "/baseroms" then
    return { type = "directory" }
  end
  if path == modRoot .. "/baseroms/radical_red_v4_1.gba" then
    return { type = "file", size = romSize, modtime = romModtime }
  end
  if overlay[path] then
    return { type = "file", size = #overlay[path], modtime = romModtime }
  end
  local cached = cacheDiskPath(path)
  if cached then
    local file = io.open(cached, "rb")
    if file then
      local size = file:seek("end")
      file:close()
      return { type = "file", size = size, modtime = romModtime }
    end
  end
  local actual = actualPath(path)
  if actual then
    local file = io.open(actual, "rb")
    if file then
      local size = file:seek("end")
      file:close()
      return { type = "file", size = size, modtime = 1 }
    end
  end
  return nil
end
function fs.getDirectoryItems(path)
  if path == "mods" then return { "radical_red_experience" } end
  return {}
end
function fs.load(path)
  local body = fs.read(path)
  if not body then return nil, "missing file: " .. path end
  return assert(loadstring(body, "@" .. path))
end

local data = sdk.gen3Data()
local P = data.gen3Pokemon
P._names, P._types, P._stats, P._speciesMeta = {}, {}, {}, {}
P._abilities, P._learnsets, P._eggMoves, P._evolutions = {}, {}, {}, {}
for index = 1, 411 do
  if index < 252 or index > 276 then
    P._names[index] = ("MON%03d"):format(index)
    P._types[index] = { 0, 0 }
    P._stats[index] = { hp = 50, atk = 50, def = 50, spe = 50, spa = 50, spd = 50 }
    P._speciesMeta[index] = {
      catchRate = 100, expYield = 50, genderRatio = 127, eggCycles = 20,
      friendship = 70, growthRate = 0, eggGroup1 = 1, eggGroup2 = 1,
      itemCommon = 0, itemRare = 0,
    }
    P._abilities[index], P._learnsets[index], P._evolutions[index] = { 0, 0 }, {}, {}
  end
end

-- This total conversion mounts its extracted dataset into the live Game3
-- service while the entry chunk runs.  The generic SDK helper deliberately
-- has no live game, so construct the same Loader with a minimal Game3 owner.
local Loader = require("src.mods.Loader")
sdk.captureRuntime()
local loader = Loader.new({ fs = fs, generation = 3 })
loader.game = { data = data }
local okLoad, loadErr = pcall(loader.load, loader, data)
if not okLoad then
  sdk.restoreRuntime()
  error(loadErr, 0)
end
local run = {
  loader = loader,
  release = function() sdk.restoreRuntime() end,
}
assert(#(loader.errors or {}) == 0, table.concat(loader.errors, " | "))

-- A cold Android-safe launch deliberately returns from Loader:load before
-- converting the ROM. Drive the same game.ready/core.update sequence the real
-- LÖVE loop uses until the one-time converter has mounted the RR dataset.
local pendingExports = loader.exports.radical_red_experience
if pendingExports and pendingExports.phase == "RR_PREPARING" then
  loader.events:emit("game.ready", { game = loader.game })
  local frames = 0
  local maxChunk, maxStage = 0, ""
  while pendingExports.phase == "RR_PREPARING" and frames < 10000 do
    local started = os.clock()
    loader.hooks:call("core.update", function() end, loader.game, 1 / 60)
    local elapsed = os.clock() - started
    if elapsed > maxChunk then
      maxChunk = elapsed
      maxStage = pendingExports.bootstrap
        and tostring(pendingExports.bootstrap.stage) or "unknown"
    end
    frames = frames + 1
  end
  local bootstrap = pendingExports.bootstrap or {}
  assert(pendingExports.phase == "RR_RUNTIME_DATASET",
    bootstrap.error
      and (("deferred Radical Red setup failed during %s: %s")
        :format(tostring(bootstrap.stage or "unknown"), tostring(bootstrap.error)))
      or ("deferred Radical Red setup did not finish after " .. frames .. " frames"))
  print("DEFERRED_SETUP_FRAMES " .. frames)
  print(("DEFERRED_MAX_CHUNK %.3fs %s"):format(maxChunk, maxStage))
  if maxChunk >= 3 then
    print(("DEFERRED_PERF_WARNING %.3fs %s (non-blocking)")
      :format(maxChunk, maxStage))
  end
end

if not loader.mods.radical_red_experience then
  local found = {}
  for id in pairs(loader.mods) do found[#found + 1] = id end
  error("mod discovery failed; discovered: " .. table.concat(found, ", "))
end

local status
for _, row in ipairs(loader:status().available) do
  if row.id == "radical_red_experience" then status = row end
end
assert(status and status.state == "loaded", status and status.error or "mod not found")

local exports = assert(loader.exports.radical_red_experience)
for _, failure in ipairs(exports.extractReport.optionalFailures or {}) do
  print("OPTIONAL_EXTRACTOR_FAILURE " .. failure)
end
assert(exports.phase == "RR_RUNTIME_DATASET")
if legacyAndroidReader then
  print("LEGACY_ANDROID_READER_PASS readBytes-only cold extraction")
end
assert(exports.sourceVersion == "v4.1")
assert(exports.species == 1376 and exports.moves == 1004 and exports.maps == 425)
assert(exports.abilities == 282 and exports.items == 750)
assert(exports.battleReport.moveCategories == 1004)
assert(exports.battleReport.categoryCounts.physical == 435)
assert(exports.battleReport.categoryCounts.special == 305)
assert(exports.battleReport.categoryCounts.status == 264)
assert(exports.battleReport.expandedBattlePlaceholders == 3)
assert(exports.battleReport.expTextPlaceholder == true)
assert(exports.sourceReport.speciesCount == 1376)
assert(exports.sourceReport.moveCount == 1004)
assert(exports.extractReport.species == 1376)
assert(exports.extractReport.battleAnims
    and exports.extractReport.battleAnims.moveCount == 1004,
  "RR battle-animation extraction did not cover all 1004 moves")
assert(exports.extractReport.battleAnims.tables
    and exports.extractReport.battleAnims.tables.uTurnScript,
  "RR expanded animation table sentinels were not preserved")
assert(type(exports.extractReport.scriptEntries) == "table")
assert(exports.extractReport.scriptEntries.events == 425)
assert(exports.extractReport.scriptEntries.scripts > 0)
assert(exports.extractReport.multichoiceLists == 59)
assert(exports.extractReport.customListMenus == 16)
local worldAudit = assert(exports.extractReport.worldAudit)
assert(worldAudit.maps == 425 and worldAudit.layouts == 425)
assert(worldAudit.oddSizedLayouts == 306)
assert(worldAudit.warps == 1324 and worldAudit.resolvedWarps == 1297
  and worldAudit.dynamicWarps == 27)
assert(worldAudit.connections == 116
  and worldAudit.duplicateDirectionConnections == 2)
assert(worldAudit.connectionDirections.north == 32
  and worldAudit.connectionDirections.south == 30
  and worldAudit.connectionDirections.west == 27
  and worldAudit.connectionDirections.east == 27)
assert(worldAudit.customListMenus == 16 and worldAudit.customListMenuCalls == 16)
assert(worldAudit.encounterMaps == 134)
assert(worldAudit.encounterBaseHeaders == 142
  and worldAudit.encounterDayHeaders == 83
  and worldAudit.encounterNightHeaders == 83)
assert(worldAudit.encounterUsableSlots == 4866
  and worldAudit.encounterPlaceholderSlotsRemoved == 177)
assert(exports.runtimeReport.saveScope == "radical_red_4_1")
assert(exports.runtimeReport.expandedScriptVars == true)
assert(exports.runtimeReport.trueMapBounds == true)
assert(exports.runtimeReport.mapLayoutsAudited == 425)
assert(exports.runtimeReport.paddedLayoutsCropped == 306)
assert(exports.runtimeReport.encounters.dayHeaders == 83)
assert(exports.runtimeReport.encounters.nightHeaders == 83)
assert(exports.runtimeReport.encounters.speciesZeroGuard == true)
assert(exports.runtimeReport.encounters.tablesAudited == 134)
assert(exports.nativeReport.specials == 27)
assert(exports.nativeReport.nativeCallbacks == 21)
assert(exports.nativeReport.starterRegionMenu == true)
assert(exports.nativeReport.cartridgeListMenus == true
  and exports.nativeReport.customListMenus == 16)
assert(exports.nativeReport.partySelectionCommit == true)
assert(exports.mechanicsReport.nativeCallbacks == 22)
assert(exports.randomizerReport.cartridgeSetup == true)
assert(exports.randomizerReport.speciesPool == 1032)
assert(exports.randomizerReport.scaledPool == 330)
assert(exports.randomizerReport.abilityPool == 236)
assert(exports.randomizerReport.movePool == 806)
assert(exports.randomizerReport.regionalStarterPreserved == true)
assert(exports.randomizerReport.fixedRivals == true)
assert(exports.randomizerReport.fixedRivalClasses == 2)
assert(exports.randomizerReport.fixedRivalIds == 12)
assert(exports.randomizerReport.fixedBosses == true)
assert(exports.facilityReport.nativeCallbacks == 10)
assert(exports.facilityReport.dynamicTrainerIds == true)
assert(exports.raidReport.specialCallbacks == 8)
assert(exports.raidReport.battleHooks == true)
assert(exports.raidReport.wishingPieceRespawn == true)
assert(exports.qolReport.runningShoes == true)
assert(exports.qolReport.dexAll == true)
assert(exports.qolReport.teamPreview == true)
assert(exports.qolReport.ezCatch == true)
assert(exports.qolReport.dexNavReliableFieldEdge == true)
assert(exports.qolReport.dexNavFieldSelect == true)
assert(exports.qolReport.skillsMenu == true)
assert(exports.qolReport.autoRunSkill == true)
assert(exports.qolReport.timeChangerSkill == true)
assert(exports.qolReport.infiniteRepelSkill == true)
assert(exports.qolReport.pokeVialSkill == true)
assert(exports.qolReport.pokeRider == true)
assert(exports.qolReport.pokeRiderItemId == 363)
assert(exports.qolReport.fanfareBgmRecovery == true)
assert(exports.qolReport.eliteFourVsIntroFix == true)
assert(exports.qolReport.battleMusicReturn == true)
assert(exports.runtimeReport.saveTransferBridge == true)
assert(exports.runtimeReport.battleAnimPackReset == true)
assert(exports.runtimeReport.expandedCries == true)
assert(exports.runtimeReport.cryCount == 1376)
assert(exports.runtimeReport.cryMappedSpecies == 1348)
assert(exports.runtimeReport.cryReservedSpecies == 27)
assert((exports.runtimeReport.cryAliasedSpecies or 0) > 0)
assert(exports.runtimeReport.expandedSongs == true)
assert(exports.runtimeReport.songCount == 526)
assert(exports.visualReport.optionsDraw == true)
assert(exports.visualReport.optionsFallbackGuard == true)
assert(exports.visualReport.portableOptionsDraw == true)
assert(exports.visualReport.gameModesChoiceDraw == true)
assert(exports.visualReport.portableChoiceDraw == true)
assert(exports.visualReport.gameModesFadeGuard == true)
assert(exports.visualReport.setupMessageFadeGuard == true)
assert(exports.visualReport.summaryDetailLayout == true)
assert(exports.visualReport.partyGridLayout == true)
assert(exports.visualReport.expandedGraphicsIds == true)
assert(exports.visualReport.expandedGraphicsTables == true)
assert(exports.visualReport.objectGraphicsSelector == true)
assert(exports.visualReport.battleSpriteCoords == true)
assert(exports.visualReport.battleSpriteCoordSpecies == 1376)
assert(exports.visualReport.cyndaquilBackYOffset == 3)
assert(exports.visualReport.fixedHealthbox == true)
assert(exports.visualReport.fairyTypeBadgeExtract == true)
assert(exports.visualReport.fairyTypeBadgeSheetHeight == 144)
assert(exports.visualReport.fairyTypeBadge == true)
assert(exports.visualReport.fairyTypeBadgeId == 23)
assert(exports.visualReport.fairyTypeBadgeY == 128)
assert(exports.visualReport.paletteTable == 0x035CCC8)
assert(exports.visualReport.paletteCount == 451)
assert(exports.visualReport.spriteCount == 545)
assert(exports.visualReport.physicalSpriteCount == 546)
assert(exports.visualReport.graphicsTableCount == 3)
assert(exports.visualReport.usedPaletteCount == 397)
assert(exports.visualReport.stuffulGraphicsId == 0x016E)
assert(exports.visualReport.playerPaletteTag == 0x1100)
assert(exports.visualReport.momPaletteTag == 0x1168)

-- Post-Gen-III moves must use RR/CFRU's real animation and sound scripts,
-- never the host's generic IMPACT fallback. Follow calls/gotos into the
-- generated label table because many move rows are only a tiny dispatcher.
do
  local Dataset = require("src.core.game3.dataset")
  local cache = Dataset.cache()
  local path = "data/" .. "generated/gba/pokemon/battle_anims/pack.lua"
  local source = assert(cache:read(path), "RR battle animation pack is missing")
  local chunk, loadErr = load(source, "@" .. path, "t", {})
  assert(chunk, "RR battle animation pack would not load: " .. tostring(loadErr))
  local okPack, pack = pcall(chunk)
  assert(okPack and type(pack) == "table"
      and type(pack.moves) == "table" and type(pack.labels) == "table",
    "RR battle animation pack is invalid")

  local SOUND_OP = {
    playse = true, playsewithpan = true, panse = true,
    loopsewithpan = true, waitplaysewithpan = true,
    createsoundtask = true,
  }
  local VISUAL_OP = {
    createsprite = true, createvisualtask = true, loadspritegfx = true,
    fadetobg = true, fadetobgfromset = true, changebg = true,
    monbg = true, monbg_static = true, setalpha = true,
  }

  local function auditScript(script, seen, out)
    if type(script) ~= "table" then return end
    seen = seen or {}
    out = out or {
      sound = false, visual = false, ops = 0, soundIds = {}, unresolved = {},
    }
    if seen[script] then return out end
    seen[script] = true
    for _, op in ipairs(script) do
      out.ops = out.ops + 1
      if SOUND_OP[op.op] then
        out.sound = true
        local id = tonumber(op.se)
        if id ~= nil then out.soundIds[id] = true end
      end
      if VISUAL_OP[op.op] then out.visual = true end
      if (op.op == "createvisualtask" or op.op == "createsoundtask")
          and type(op.task) == "string" and op.task:match("^0x") then
        out.unresolved[#out.unresolved + 1] = op.op .. ":" .. op.task
      elseif op.op == "createsprite"
          and op.template == nil and op.callback == nil
          and op.tag == nil and not op.noGfx then
        out.unresolved[#out.unresolved + 1] =
          "createsprite:<no template/callback/tag>"
      end
      if (op.op == "loadspritegfx" or op.op == "unloadspritegfx")
          and op.tag and not (pack.tags and pack.tags[op.tag]) then
        out.unresolved[#out.unresolved + 1] = "missing tag:" .. tostring(op.tag)
      elseif op.op == "createsprite" and op.tag and not op.noGfx
          and not (pack.tags and pack.tags[op.tag]) then
        out.unresolved[#out.unresolved + 1] =
          "createsprite missing tag:" .. tostring(op.tag)
      end
      for _, key in ipairs({ "label", "label1", "label2" }) do
        local label = op[key]
        if label ~= nil then
          if pack.labels[label] then
            auditScript(pack.labels[label], seen, out)
          else
            out.unresolved[#out.unresolved + 1] =
              tostring(op.op) .. " missing " .. key .. ":" .. tostring(label)
          end
        end
      end
    end
    return out
  end

  local sentinels = {
    [0x1BA] = "U-turn",
    [0x1CD] = "Fairy Wind",
    [0x1CF] = "Play Rough",
    [0x1D2] = "Dazzling Gleam",
  }
  for id, name in pairs(sentinels) do
    local script = assert(pack.moves[id],
      name .. " has no RR/CFRU move-animation row")
    local audit = auditScript(script)
    assert(audit.ops > 1 and audit.visual,
      name .. " still resolves to no real visual animation")
    assert(audit.sound,
      name .. " still resolves to an animation with no sound command")
    assert(#audit.unresolved == 0,
      name .. " still depends on unresolved CFRU animation callbacks/tasks: "
        .. table.concat(audit.unresolved, ", "))
    local Audio = require("src.core.game3.audio")
    local songs = assert(Audio._pack and Audio._pack.index
        and Audio._pack.index.songs,
      "RR audio pack is unavailable while auditing move SFX")
    local referenced = 0
    for se in pairs(audit.soundIds) do
      referenced = referenced + 1
      local row = songs[se] or songs[tostring(se)]
      assert(row and row.missing ~= true,
        ("%s animation references uncached SFX/song id %d")
          :format(name, se))
    end
    assert(referenced > 0,
      name .. " animation had no concrete SFX id to validate")
    local first = script[1]
    local ops = {}
    for i, op in ipairs(script) do ops[i] = tostring(op.op or "") end
    local signature = table.concat(ops, ",")
    local generic = first and first.op == "loadspritegfx"
      and first.tag == "IMPACT" and first.tag_idx == 135
      and (signature ==
          "loadspritegfx,monbg,createsprite,createsprite,createvisualtask,waitforvisualfinish,clearmonbg,blendoff,end"
        or signature ==
          "loadspritegfx,monbg,createsprite,delay,createsprite,createvisualtask,waitforvisualfinish,clearmonbg,end")
    assert(not generic,
      name .. " still resolves to a known generic IMPACT fallback sequence")
  end

  -- Audit the complete 1,004-row RR/CFRU move-animation table. The private
  -- ROM itself must contain a valid script pointer for every move, and every
  -- decoded dependency must resolve to a host-supported task/callback/tag.
  local tables = assert(exports.extractReport.battleAnims
      and exports.extractReport.battleAnims.tables,
    "RR expanded animation table report is missing")
  local movesTable = assert(tonumber(tables.movesTable),
    "RR move-animation table offset is missing")
  local romFile = assert(io.open(rrPath, "rb"))
  local function readU32(offset)
    assert(romFile:seek("set", offset))
    local raw = assert(romFile:read(4))
    assert(#raw == 4)
    local b1, b2, b3, b4 = raw:byte(1, 4)
    return b1 + b2 * 0x100 + b3 * 0x10000 + b4 * 0x1000000
  end
  local Audio = require("src.core.game3.audio")
  local songs = assert(Audio._pack and Audio._pack.index
      and Audio._pack.index.songs,
    "RR audio pack is unavailable for the expanded move audit")
  local animationRows, referencedSfx = 0, 0
  for id = 0, 1003 do
    local ptr = readU32(movesTable + id * 4)
    assert(ptr >= 0x08000000 and ptr < 0x0A000000,
      ("RR move %d has invalid animation pointer 0x%08X"):format(id, ptr))
    local script = assert(pack.moves[id],
      ("RR move %d has no decoded animation row"):format(id))
    local audit = auditScript(script)
    assert(audit.ops > 0,
      ("RR move %d decoded to an empty animation"):format(id))
    assert(#audit.unresolved == 0,
      ("RR move %d has unresolved animation dependencies: %s")
        :format(id, table.concat(audit.unresolved, ", ")))
    for se in pairs(audit.soundIds) do
      referencedSfx = referencedSfx + 1
      local row = songs[se] or songs[tostring(se)]
      assert(row and row.missing ~= true,
        ("RR move %d references uncached SFX/song id %d")
          :format(id, se))
    end
    animationRows = animationRows + 1
  end
  romFile:close()
  assert(animationRows == 1004,
    ("complete animation audit covered %d/1004 move rows"):format(animationRows))
  assert(referencedSfx > 0,
    "complete animation audit found no concrete sound-effect references")
end

-- Expanded DPE cries must be addressed by live internal species id. The
-- previous stock FireRed extractor stopped its cry map at species 411, which
-- made modern encounters fall through to wrong/missing ToneData rows.
do
  local Pokemon = require("src.core.game3.pokemon")
  local Audio = require("src.core.game3.audio")
  local function norm(value)
    local text = tostring(value or "")
    text = text:gsub("é", "e"):gsub("É", "E")
    return text:upper():gsub("[^A-Z0-9]", "")
  end
  local function findSpecies(want)
    for id = 1, 1375 do
      local ok, name = pcall(Pokemon.name, id)
      if ok and norm(name) == want then return id end
    end
    return nil
  end

  local mapped, reserved, aliases = 0, 0, 0
  local distinctSamples = {}
  for species = 1, 1375 do
    local stats = Pokemon.stats(species)
    local populated = type(stats) == "table" and (tonumber(stats.hp) or 0) > 0
    local cryIndex = Audio._pack.index.cryIds[species]
    if populated then
      assert(type(cryIndex) == "number" and cryIndex >= 1 and cryIndex <= 1375,
        ("species %d has invalid resolved cry row %s"):format(species, tostring(cryIndex)))
      if cryIndex ~= species then
        local national = Pokemon.national(species)
        local cryNational = Pokemon.national(cryIndex)
        assert(national and cryNational == national,
          ("species %d cry alias %d left National Dex family %s -> %s")
            :format(species, cryIndex, tostring(national), tostring(cryNational)))
        aliases = aliases + 1
      end
      local cry = Audio._pack.index.cries[cryIndex]
      assert(type(cry) == "table" and cry.sampleId ~= nil,
        ("species %d resolved cry row %d has no extracted sample")
          :format(species, cryIndex))
      local meta = Audio._pack.samples[cry.sampleId]
        or Audio._pack.samples[tostring(cry.sampleId)]
      assert(type(meta) == "table"
          and (tonumber(meta.freq) or 0) > 0
          and (tonumber(meta.size) or 0) > 0,
        ("species %d resolved cry sample metadata is corrupt"):format(species))
      distinctSamples[tostring(cry.sampleId)] = true
      mapped = mapped + 1
    else
      assert(cryIndex == species,
        ("reserved species %d unexpectedly remapped to cry row %s")
          :format(species, tostring(cryIndex)))
      reserved = reserved + 1
    end
  end
  assert(mapped == 1348 and reserved == 27,
    ("complete RR cry census covered %d populated / %d reserved species")
      :format(mapped, reserved))
  assert(aliases == exports.runtimeReport.cryAliasedSpecies and aliases > 0,
    ("complete RR cry census reported %d form aliases vs runtime %s")
      :format(aliases, tostring(exports.runtimeReport.cryAliasedSpecies)))
  assert(next(distinctSamples) ~= nil,
    "complete RR cry census resolved no samples")

  -- Representative modern species still exercise the actual host voice path.
  for _, want in ipairs({ "TURTWIG", "LUCARIO", "TINKATINK" }) do
    local species = assert(findSpecies(want),
      "exact RR species table did not contain " .. want)
    assert(species > 411,
      want .. " unexpectedly landed inside FireRed's old cry-map range")
    assert(Audio.playCry(species) == true,
      want .. " cry would not start")
    assert(Audio._crySlot and Audio._crySlot.info
        and Audio._crySlot.info.cryIndex == species,
      want .. " played another species' cry row")
    Audio.stopCry()
  end
end

-- Radical Red repurposes FireRed's Fame Checker slot as Poké Rider.
do
  local ItemsData = require("src.core.game3.items_data")
  local rider = tostring(ItemsData.displayName(363) or "")
    :gsub("é", "e"):gsub("É", "E"):upper():gsub("[^A-Z0-9]", "")
  assert(rider == "POKERIDER",
    "RR item 363 is no longer the Poké Rider expected by the field-use bridge")
end

-- Fairy lives below the vanilla type-icon sheet in the source ROM.
-- Verify both the extracted pixels and the actual runtime renderer so the
-- sheet cannot exist while Summary/TM/Pokedex silently fall back to NORMAL.
do
  local Dataset = require("src.core.game3.dataset")
  local bytes = Dataset.cache():read(
    "data/" .. "generated/gba/pokemon/summary/menu_info_rr.rgba")
  assert(type(bytes) == "string" and #bytes == 128 * 144 * 4,
    "expanded Fairy type sheet was not preserved")

  local SummaryChrome = require("src.ui.game3.summary_chrome")
  local PokedexChrome = require("src.ui.game3.pokedex_chrome")
  assert(SummaryChrome.__rrFairyBadgePatch == true
      and PokedexChrome.__rrFairyBadgePatch == true,
    "Fairy badge runtime patches were not installed on every UI surface")

  local oldNewQuad = love.graphics.newQuad
  local oldDraw = love.graphics.draw
  local oldQuad = SummaryChrome.__rrFairyQuad
  local quadArgs, draws = nil, {}
  SummaryChrome.__rrFairyQuad = nil
  love.graphics.newQuad = function(x, y, w, h, sw, sh)
    quadArgs = { x, y, w, h, sw, sh }
    return { __rrFairyTestQuad = true }
  end
  love.graphics.draw = function(image, quad, x, y, ...)
    draws[#draws + 1] = { image = image, quad = quad, x = x, y = y }
  end

  local okDraw, drawErr = pcall(function()
    SummaryChrome.drawTypeBadge(23, 17, 29)
    PokedexChrome.drawTypeBadge("FAIRY", 31, 43)
  end)
  love.graphics.newQuad = oldNewQuad
  love.graphics.draw = oldDraw
  SummaryChrome.__rrFairyQuad = oldQuad
  assert(okDraw, "Fairy type badge renderer crashed: " .. tostring(drawErr))
  assert(quadArgs
      and quadArgs[1] == 0 and quadArgs[2] == 128
      and quadArgs[3] == 32 and quadArgs[4] == 12
      and quadArgs[5] == 128 and quadArgs[6] == 144,
    "Fairy badge renderer used the wrong RR sheet crop")
  assert(#draws == 2
      and draws[1].quad and draws[1].quad.__rrFairyTestQuad
      and draws[1].x == 17 and draws[1].y == 29
      and draws[2].quad and draws[2].quad.__rrFairyTestQuad
      and draws[2].x == 31 and draws[2].y == 43,
    "Fairy badge did not render through Summary and Pokedex surfaces")
end

-- Battle sprites must use RR's expanded DPE coordinates rather than the
-- still-linked FireRed table. The status tile remains fixed while the active
-- battler keeps its menu bounce.
do
  local PicCoords = require("src.core.game3.battle.pic_coords")
  assert(PicCoords.back[155] == 3 and PicCoords.front[155] == 14,
    "Cyndaquil retained FireRed's cropped back-sprite baseline")
  assert(PicCoords.back[1375] == 7 and PicCoords.front[1375] == 0,
    "expanded-species battle coordinates were not installed")
  local BattleUi = require("src.core.game3.battle.ui")
  local _, cyndaquilY = BattleUi.battlerSpriteCenter(
    "player", 155, { x = 72, y = 80 })
  assert(cyndaquilY == 87,
    "Cyndaquil back sprite was not raised to Radical Red's baseline")
  local savedBounce = BattleUi._bounce
  BattleUi._bounce = {
    hb = { [0] = { y = 2 } }, mon = { [0] = { y = 2 } },
  }
  assert(BattleUi.bounceOffset("hb", 0) == 0,
    "player status tile still follows the Pokemon bounce")
  assert(BattleUi.bounceOffset("mon", 0) == 2,
    "battle sprite bounce was disabled with the status tile")
  BattleUi._bounce = savedBounce
end

-- RR swaps the two halves of FireRed's move-detail screen and replaces the
-- stock party list with a two-column grid. Verify the live engine functions,
-- not just the report booleans, so stale FireRed coordinates cannot pass.
do
  local SummaryMenu = require("src.ui.game3.summary_menu")
  local SummaryChrome = require("src.ui.game3.summary_chrome")
  local oldPage = SummaryMenu._page
  SummaryMenu._page = SummaryMenu.PAGE_MOVES
  local ordinary = assert(SummaryChrome.manifest())
  assert(ordinary.coords.name.x == 40
      and ordinary.moveSlots[1].nameX == 163,
    "ordinary summary-page coordinates were unexpectedly changed")
  SummaryMenu._page = SummaryMenu.PAGE_MOVES_INFO
  local detail = assert(SummaryChrome.manifest())
  assert(detail.coords.name.x == 160 and detail.coords.gender.x == 225
      and detail.coords.monIcon.x == 128,
    "RR move-detail Pokemon header did not move to the right pane")
  assert(detail.moveSlots[1].typeX == 3
      and detail.moveSlots[1].nameX == 43
      and detail.moveSlots[1].ppX == 76
      and detail.moveSlots[5].nameY == 133,
    "RR move-detail move rows did not move to the left pane")
  assert(detail.movesInfo.power.x == 177
      and detail.movesInfo.accuracy.x == 177
      and detail.movesInfo.desc.x == 127,
    "RR move-detail stats did not move to the right pane")

  local cursorWrapper = SummaryChrome.drawMoveSelectionCursor
  local originalCursor, originalCursorIndex
  for index = 1, 32 do
    local name, value = debug.getupvalue(cursorWrapper, index)
    if not name then break end
    if name == "originalCursor" then
      originalCursor, originalCursorIndex = value, index
      break
    end
  end
  assert(originalCursorIndex, "RR move-detail cursor wrapper is missing")
  local cursorX
  debug.setupvalue(cursorWrapper, originalCursorIndex, function(x)
    cursorX = x
  end)
  SummaryChrome.drawMoveSelectionCursor(120, 18, false)
  debug.setupvalue(cursorWrapper, originalCursorIndex, originalCursor)
  assert(cursorX == 0, "RR move-detail cursor stayed on the right pane")
  SummaryMenu._page = oldPage

  local PartyChrome = require("src.ui.game3.party_chrome")
  PartyChrome.install(nil)
  assert(PartyChrome._manifest.slotMainW == 112
      and PartyChrome._manifest.slotMainH == 40
      and PartyChrome._manifest.slotWideW == 112
      and PartyChrome._manifest.slotWideH == 40,
    "RR party-card chrome retained FireRed dimensions")

  local PartyMenu = require("src.ui.game3.party_menu")
  local windows = assert(PartyMenu.__rrBwGridWindows)
  assert(windows[1].left == 1 and windows[1].top == 0
      and windows[1].w == 14 and windows[1].h == 5
      and windows[2].left == 15 and windows[2].top == 1
      and windows[5].left == 1 and windows[5].top == 10,
    "RR party windows retained FireRed geometry")
  local sprites = assert(PartyMenu.__rrBwGridSprites)
  assert(sprites[1][1] == 34 and sprites[1][2] == 12
      and sprites[6][1] == 146 and sprites[6][2] == 100,
    "RR party icons retained FireRed positions")
  local textX1, textY1 = PartyMenu.__rrBwGridText(1, "nick")
  local textX2, textY2 = PartyMenu.__rrBwGridText(2, "nick")
  local textX3, textY3 = PartyMenu.__rrBwGridText(3, "nick")
  assert(textX1 == 38 and textY1 == 3
      and textX2 == 160 and textY2 == 13
      and textX3 == 38 and textY3 == 43,
    "RR party text did not alternate between left/right card layouts")

  -- Exercise the sandbox-safe public-function remapper that surrounds the
  -- stock renderer. This catches a release that reports the right constants
  -- but still sends FireRed positions to the actual chrome/font/OAM APIs.
  local partyWrapper = PartyMenu.draw
  local stockDraw, stockDrawIndex
  for index = 1, 32 do
    local name, value = debug.getupvalue(partyWrapper, index)
    if not name then break end
    if name == "originalDraw" then
      stockDraw, stockDrawIndex = value, index
      break
    end
  end
  assert(stockDrawIndex, "RR party-grid draw wrapper is missing")
  local TestPartyChrome = require("src.ui.game3.party_chrome")
  local TestFont = require("src.ui.game3.frlg_font")
  local TestOam = require("src.core.game3.oam")
  local realSlotDraw, realFontDraw = TestPartyChrome.drawSlot, TestFont.draw
  local realSetPos, realRectangle = TestOam.setPos, love.graphics.rectangle
  local seen = {}
  TestPartyChrome.drawSlot = function(_, left, top)
    seen.slot = { left, top }
  end
  TestFont.draw = function(_, x, y) seen.text = { x, y } end
  TestOam.setPos = function(_, x, y) seen.sprite = { x, y } end
  love.graphics.rectangle = function(_, x, y) seen.bar = { x, y } end
  debug.setupvalue(partyWrapper, stockDrawIndex, function()
    TestPartyChrome.drawSlot("main", 1, 3, false, false, false)
    TestFont.draw("NAME", 32, 35, {})
    TestOam.setPos(1, 16, 40)
    love.graphics.rectangle("fill", 32, 59, 24, 3)
  end)
  local oldLayout = PartyMenu._layout
  PartyMenu._layout = "single"
  local okPartyDraw, partyDrawErr = pcall(partyWrapper)
  PartyMenu._layout = oldLayout
  debug.setupvalue(partyWrapper, stockDrawIndex, stockDraw)
  TestPartyChrome.drawSlot, TestFont.draw = realSlotDraw, realFontDraw
  TestOam.setPos, love.graphics.rectangle = realSetPos, realRectangle
  assert(okPartyDraw, "RR party-grid remapper failed: " .. tostring(partyDrawErr))
  assert(seen.slot[1] == 1 and seen.slot[2] == 0
      and seen.text[1] == 38 and seen.text[2] == 3
      and seen.sprite[1] == 34 and seen.sprite[2] == 12
      and seen.bar[1] == 72 and seen.bar[2] == 18,
    "RR party-grid remapper still emitted FireRed draw coordinates")
end

-- RR's live wild resolver uses relocated day/night tables. The FireRed
-- fallback has intentional SPECIES_NONE placeholders for city grass; those
-- must be represented as no encounter, never as a level-1 species-zero foe.
do
  local Encounters = require("src.core.game3.encounters")
  local WildPokemon = require("src.core.game3.pokemon")
  local viridian = assert(Encounters.tableFor("FR_VIRIDIAN_CITY"))
  assert(viridian.__rrBase and viridian.__rrBase.land == nil,
    "Viridian's species-zero fallback grass table remained active")
  assert(viridian.rrDay and viridian.rrDay.land
      and viridian.rrDay.land.slots[1].species == 456,
    "Viridian's RR day encounters were not extracted")
  assert(viridian.rrNight and viridian.rrNight.land
      and viridian.rrNight.land.slots[1].species == 843,
    "Viridian's RR night encounters were not extracted")

  local seen, maps, slots = {}, 0, 0
  for key, entry in pairs(Encounters._tables) do
    if type(key) == "string" and key:match("^%d+:%d+$") then
      maps = maps + 1
      assert(not seen[entry], "numeric encounter tables unexpectedly alias")
      seen[entry] = true
      for _, bucket in ipairs({ entry.__rrBase, entry.rrDay, entry.rrNight }) do
        for _, method in ipairs({ "land", "water", "rocks", "fishing" }) do
          local area = bucket and bucket[method]
          if area then
            for _, slot in ipairs(area.slots or {}) do
              assert(slot.species >= 1 and slot.species < 1376,
                "invalid wild species survived extraction on " .. key)
              assert(slot.minLevel >= 1 and slot.minLevel <= 100
                and slot.maxLevel >= 1 and slot.maxLevel <= 100,
                "invalid wild level survived extraction on " .. key)
              local lowMoves = WildPokemon.movesAtLevel(slot.species, slot.minLevel)
              local highMoves = WildPokemon.movesAtLevel(slot.species, slot.maxLevel)
              assert(type(lowMoves) == "table" and #lowMoves > 0
                  and type(highMoves) == "table" and #highMoves > 0,
                ("wild species %d has no battle moves at levels %d-%d on %s")
                  :format(slot.species, slot.minLevel, slot.maxLevel, key))
              slots = slots + 1
            end
          end
        end
      end
    end
  end
  assert(maps == 134 and slots == 4866,
    ("RR encounter census changed: %d maps/%d slots"):format(maps, slots))
end

do
  local OwSprites = require("src.core.game3.ow_sprites")
  local player = assert(OwSprites.get(0))
  local mom = assert(OwSprites.get(88))
  local stufful = assert(OwSprites.get(0x016E))
  local manifest = assert(OwSprites._manifest)
  assert(player.width == 16 and player.height == 32
      and player.frameCount == 20
      and manifest.sprites[0].paletteTag == 0x1100,
    "generated player sheet is not Radical Red's Red sprite")
  assert(mom.width == 16 and mom.height == 32
      and mom.frameCount == 9
      and manifest.sprites[88].paletteTag == 0x1168,
    "generated Mom sheet came from the Pokemon/follower table")
  assert(stufful.width == 32 and stufful.height == 32
      and stufful.frameCount == 9
      and manifest.sprites[0x016E].paletteTag == 0x1281,
    "Pallet Town's selector-qualified Stufful sheet was not extracted")
  local Versions = require("src.import.gba.versions")
  assert(Versions.NAMING.rival_gfx == 0x0EE82B0,
    "naming screen still points at Radical Red's erased FireRed rival sheet")
end

-- Every ROM map, edge, and padded layout must be navigable as cartridge
-- geometry. This catches both a malformed connection registry and the fake
-- collision row/column that even-sized native storage used to expose.
do
  local maps = assert(loader.game.data.maps)
  local Connections = require("src.core.game3.connections")
  local Collision = require("src.core.game3.collision")
  local mapCount, edgeCount, croppedCount = 0, 0, 0
  local function destination(id) return maps[id] end
  for mapId, def in pairs(maps) do
    local layout = assert(def.midLayout, "missing live layout for " .. mapId)
    assert(layout.width == def.width and layout.height == def.height)
    assert(layout.width == layout.trueWidth and layout.height == layout.trueHeight,
      "storage padding remained live on " .. mapId)
    if not def._plazaSource then
      mapCount = mapCount + 1
      if layout.__rrHadStoragePadding then croppedCount = croppedCount + 1 end
      local sourceW, sourceH = Connections.sizeOf(def)
      assert(sourceW == def.width and sourceH == def.height)
      for _, connection in ipairs(Connections.each(def)) do
        edgeCount = edgeCount + 1
        local dest = assert(maps[connection.map],
          "missing connection destination " .. tostring(connection.map))
        local destW, destH = Connections.sizeOf(dest)
        local offset = tonumber(connection.offset) or 0
        local vertical = connection.dir == "north" or connection.dir == "south"
        local sourceSpan = vertical and sourceW or sourceH
        local destSpan = vertical and destW or destH
        local low = math.max(0, offset)
        local high = math.min(sourceSpan - 1, offset + destSpan - 1)
        assert(low <= high, "non-overlapping live connection on " .. mapId)
        local along = math.floor((low + high) / 2)
        local found = Connections.incoming(def, connection.dir,
          vertical and along or 0, vertical and 0 or along, destination)
        assert(found, "live connection lookup failed on " .. mapId)
        local playerDir, fromX, fromY
        if connection.dir == "north" then
          playerDir, fromX, fromY = "up", along, 0
        elseif connection.dir == "south" then
          playerDir, fromX, fromY = "down", along, sourceH - 1
        elseif connection.dir == "west" then
          playerDir, fromX, fromY = "left", 0, along
        else
          playerDir, fromX, fromY = "right", sourceW - 1, along
        end
        local x, y = Collision.connectionLanding(
          dest, connection, playerDir, fromX, fromY)
        assert(x and y and x >= 0 and y >= 0 and x < destW and y < destH,
          "connection landing failed on " .. mapId)
      end
    end
  end
  assert(mapCount == 425 and edgeCount == 116 and croppedCount == 306)

  local sixWest = 0
  for _, connection in ipairs(Connections.each(
      assert(maps.FR_SIX_ISLAND_WATER_PATH))) do
    if connection.dir == "west" then sixWest = sixWest + 1 end
  end
  assert(sixWest == 3,
    "duplicate west edges on Six Island Water Path were collapsed")
  local function hasEdge(mapId, dir, dest)
    for _, connection in ipairs(Connections.each(assert(maps[mapId]))) do
      if connection.dir == dir and connection.map == dest then return true end
    end
    return false
  end
  assert(hasEdge("FR_ROUTE_23", "north", "FR_INDIGO_PLATEAU_EXTERIOR"))
  assert(hasEdge("FR_INDIGO_PLATEAU_EXTERIOR", "south", "FR_ROUTE_23"))
end

-- A Radical Red new game owns its setup through the ROM's original
-- FR_PLAYERS_HOUSE_2F onFrame script.  Loading the registries is not enough:
-- prove the live field VM actually starts g3:0904edd0 and reaches its first
-- prompt instead of silently behaving like vanilla FireRed.
do
  local Game3 = require("src.core.Game3")
  local game = Game3.new()
  game.data = loader.game.data
  game.mods = loader
  game.modStatus = loader:status()
  game.options = {}
  game.input:init()
  loader.game = game

  game:_handleBootAction({
    action = "new_game", name = "RED", rivalName = "BLUE", gender = 0,
  })
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")

  do
    local pallet = assert(Space.bundle.events.FR_PALLET_TOWN)
    local blocker
    for _, obj in ipairs(pallet.objects or {}) do
      if obj.localId == 5 then blocker = obj break end
    end
    assert(blocker and blocker.graphicsTable == 1
        and blocker.graphicsBaseId == 110
        and blocker.graphicsId == 0x016E,
      "Pallet Town Stufful lost its Radical Red graphics-table selector")
    local cry
    for _, row in ipairs(assert(Space.bundle.scripts[blocker.scriptKey])) do
      if row.op == "playmoncry" then cry = row[1] break end
    end
    assert(cry == 976,
      "Pallet Town Stufful interaction lost its matching species cry")
  end
  local Fade = require("src.ui.game3.fade")
  local Game3Runtime = require("src.core.game3.runtime")
  local function frame(button)
    if button then
      game.input.pressQueue[#game.input.pressQueue + 1] = button
    end
    game.input:step()
    Game3Runtime.update(1 / 60)
    if button then game.input.state[button] = false end
  end
  local function reachChoice(kind, label)
    for _ = 1, 240 do
      if Message.isTyping() then Message.skipReveal() end
      frame()
      if Choice.isOpen() and Choice.kind == kind then return end
      -- RR's first warning spans normal message pages and ends in
      -- waitbuttonpress.  Advance only after an idle VM tick has had the
      -- opportunity to open a choice, so the injected A cannot select it.
      if Message.isOpen() and Message.isWaiting() then
        frame("a")
        if Choice.isOpen() and Choice.kind == kind then return end
      end
    end
    error("Radical Red setup did not open " .. label)
  end
  local function assertOptions(expected, label)
    assert(#(Choice.options or {}) == #expected,
      label .. " option count changed")
    for i, value in ipairs(expected) do
      assert(Choice.options[i] == value,
        ("%s option %d changed: expected %q, got %q")
          :format(label, i, value, tostring(Choice.options[i])))
    end
  end
  for _ = 1, 180 do
    frame()
  end
  assert(game.session and game.session.map == "FR_PLAYERS_HOUSE_2F")
  assert(Space.mapId == "FR_PLAYERS_HOUSE_2F")
  assert(Flags.getVar(Space.store, Space.vm and Space.vm.ctx, 0x5100) == 2,
    "Radical Red setup onFrame script did not start")
  assert(Flags.getFlag(Space.store, Space.vm and Space.vm.ctx, 0x91D),
    "Radical Red setup guard flag was not applied")
  assert(Flags.getFlag(Space.store, Space.vm and Space.vm.ctx, 0x82F),
    "Radical Red did not grant running shoes at the start of a new game")
  assert(Message.isOpen(), "Radical Red setup did not reach its first prompt")
  assert((Message.currentPage() or ""):find("properly", 1, true),
    "Radical Red setup opened the wrong first prompt")

  -- No input is required to reveal the first setup message. The ROM script
  -- intentionally reached FADE_TO_BLACK without a matching FROM_BLACK, so
  -- the message renderer must remove that stale veil on its first frame.
  assert(tonumber(Fade.t) and Fade.t > 0,
    "clean setup boot did not reproduce Radical Red's stale black veil")
  local beforeMessageFadeClear = Message.__rrStaleFadeClearCount or 0
  local drewFirstMessage, firstMessageErr = pcall(Message.draw)
  assert(drewFirstMessage,
    "Radical Red first setup message failed to draw: " .. tostring(firstMessageErr))
  assert(not Fade.isActive() and (tonumber(Fade.t) or 0) == 0,
    "first setup message remained hidden behind the black fade")
  assert((Message.__rrStaleFadeClearCount or 0) == beforeMessageFadeClear + 1,
    "first setup message fade guard did not run")

  -- Continue through the cartridge's prompt, choose "No" at "play without
  -- custom options", and prove RR's shared dynamic multichoice array is
  -- exposed with its original labels and counts.  This catches a deceptively
  -- playable build where the scripts run but lists 32..37 are blank/generic.
  reachChoice("yesno", "the original custom-options question")
  assert((Message.currentPage() or ""):find("without any custom options", 1, true),
    "Radical Red setup skipped its original custom-options question")
  assertOptions({ "Yes", "No" }, "custom-options question")
  Choice.autoPick(false)

  reachChoice("multi", "the original setup menu")
  assertOptions({
    "Difficulty Options",
    "Minimal Grinding Mode",
    "Randomizer Options",
    "Done",
  }, "Radical Red setup")

  -- Game Modes is a ROM multichoice, not the engine's regular OPTIONS page.
  -- The successful path must retain its real FRLG frame/font; the primitive
  -- panel is only for an actual renderer failure. Also begin an in-progress
  -- TO_BLACK to prove the very first menu frame clears it immediately.
  local originalSetColor = love.graphics.setColor
  local originalRectangle = love.graphics.rectangle
  local originalPrint = love.graphics.print
  local Window = require("src.ui.game3.window")
  local originalStdFrame = Window.stdFrame
  local originalPrintPx = Window.printPx
  local function assertSetupChoiceDraw(forceFailure)
    local painted, fallbackText, romText, frames = 0, {}, {}, 0
    love.graphics.setColor = function(r, g, b, a)
      assert(type(r) == "number", "choice passed a table color")
      return originalSetColor(r, g, b, a)
    end
    love.graphics.rectangle = function(...)
      painted = painted + 1
      return originalRectangle(...)
    end
    love.graphics.print = function(value, ...)
      fallbackText[#fallbackText + 1] = tostring(value)
      return originalPrint(value, ...)
    end
    if forceFailure then
      Window.stdFrame = function()
        error("forced Game Modes chrome failure")
      end
    else
      Window.stdFrame = function(...)
        frames = frames + 1
        return originalStdFrame(...)
      end
      Window.printPx = function(value, ...)
        romText[#romText + 1] = tostring(value)
        return originalPrintPx(value, ...)
      end
      Fade.begin(Fade.MODE.TO_BLACK, 8)
      Fade.t = 6
    end
    local before = Choice.__rrPortableChoiceCount or 0
    local ok, err = pcall(Choice.draw)
    Window.stdFrame = originalStdFrame
    Window.printPx = originalPrintPx
    love.graphics.setColor = originalSetColor
    love.graphics.rectangle = originalRectangle
    love.graphics.print = originalPrint
    assert(ok, "Radical Red Game Modes draw failed: " .. tostring(err))
    local portableDelta = (Choice.__rrPortableChoiceCount or 0) - before
    if forceFailure then
      assert(portableDelta == 1,
        "Radical Red Game Modes emergency fallback did not run")
      assert(painted >= 4,
        "Radical Red Game Modes fallback did not paint a visible panel")
    else
      assert(portableDelta == 0,
        "portable overlay replaced the authentic Radical Red menu")
      assert(frames >= 1, "authentic Radical Red menu frame was not drawn")
    end
    local text = table.concat(forceFailure and fallbackText or romText, "\n")
    for _, label in ipairs({
      "Difficulty Options", "Minimal Grinding Mode", "Randomizer Options", "Done",
    }) do
      assert(text:find(label, 1, true),
        "Radical Red Game Modes renderer omitted " .. label)
    end
  end
  assertSetupChoiceDraw(false)
  assert(not Fade.isActive() and (tonumber(Fade.t) or 0) == 0,
    ("Radical Red Game Modes draw did not clear its stale fade veil "
      .. "(active=%s mode=%s t=%s)")
      :format(tostring(Fade.isActive()), tostring(Fade.mode), tostring(Fade.t)))
  assert((Choice.__rrStaleFadeClearCount or 0) >= 1,
    "Radical Red Game Modes stale-fade guard did not run")
  assertSetupChoiceDraw(true)

  Choice.autoPick(0)
  reachChoice("multi", "the original difficulty menu")
  assertOptions({ "Default", "Restricted", "Hardcore", "Easy", "Done" },
    "Radical Red difficulty")

  Choice.autoPick(4)
  reachChoice("multi", "the setup menu after leaving difficulty options")
  assertOptions({
    "Difficulty Options",
    "Minimal Grinding Mode",
    "Randomizer Options",
    "Done",
  }, "Radical Red setup return")

  Choice.autoPick(2)
  reachChoice("multi", "the original randomizer menu")
  assertOptions({ "Species", "Ability", "Learnset", "Done" },
    "Radical Red randomizer")

  Choice.autoPick(0)
  reachChoice("multi", "the original species-randomizer menu")
  assertOptions({ "Normal Species", "Scaled Species", "Done" },
    "Radical Red species randomizer")

  -- Reproduce the exact Turtwig path from Oak's Lab. RR stores the selected
  -- species in expanded variable 0x5124, then passes that variable to both
  -- showmonpic and givemon. Treating it as the literal species 20772 produced
  -- the empty preview and the party.lua crash reported on device.
  do
    local Ctx = require("src.core.game3.scripting.ctx")
    local Ops = require("src.core.game3.scripting.ops_a")
    local MonPic = require("src.ui.game3.mon_pic")
    local StarterParty = require("src.core.game3.party")
    local starterStore = Flags.newStore()
    local starterCtx = Ctx.new({ playerName = "RED", rivalName = "BLUE" })
    local starterSession = setmetatable({
      party = {}, dex = { seen = {}, owned = {}, caught = {} },
    }, { __index = assert(game.session) })
    local gifted
    local starterVm = {
      store = starterStore,
      ctx = starterCtx,
      adapters = {
        showMonPic = function(species, x, y) MonPic.show(species, x, y) end,
        giveMonToPlayer = function(species, level, _, nickname)
          local code, mon = StarterParty.giveMonToPlayer(
            starterSession, species, level, nickname)
          gifted = mon
          return code
        end,
        log = function() end,
      },
    }
    local function scriptRow(key, op)
      local rows = assert(Space.bundle.scripts[key], "missing RR script " .. key)
      for _, row in ipairs(rows) do
        if row.op == op then return row end
      end
      error(("RR script %s omitted %s"):format(key, op))
    end
    assert(Ops.dispatch(starterVm, scriptRow("g3:0904fcfe", "setvar")) == false)
    assert(Flags.getVar(starterStore, starterCtx, 0x5124) == 440,
      "Turtwig selector did not populate RR variable 0x5124")
    assert(Ops.dispatch(starterVm, scriptRow("g3:0904fb0f", "showmonpic")) == false)
    assert(MonPic.active and MonPic.species == 440 and MonPic._img,
      "Turtwig preview did not resolve/render expanded variable 0x5124")
    Flags.setFlag(Space.store, nil, 0x940, true)
    assert(Ops.dispatch(starterVm, scriptRow("g3:0904fe57", "givemon")) == false)
    Flags.setFlag(Space.store, nil, 0x940, false)
    assert(gifted and gifted.species == 440 and gifted.name == "Turtwig",
      "regional Turtwig starter was randomized a second time")
    MonPic.hide()
  end


  -- RR replaces FireRed special 0x158 with 16 ROM-defined lists. Exercise
  -- every one so no nature/tutor/fossil/type/elevator menu can fall through
  -- to the stock badge labels.
  do
    local Ctx = require("src.core.game3.scripting.ctx")
    local Natives = require("src.core.game3.scripting.natives")
    local ListMenu = require("src.core.game3.scripting.natives_listmenu")
    local Dataset = require("src.core.game3.dataset")
    local rel = "data/" .. "generated/gba/scripts/rr_listmenus.lua"
    local source = assert(Dataset.cache():read(rel), "missing custom-list cache")
    local registry = assert(load(source, "@" .. rel, "t", {}))()
    local signatures = {
      [0] = { 12, "Give Pokémon", "Reset Giovanni 3" },
      [1] = { 1, "Dratini", "Dratini" },
      [2] = { 15, "Dratini", "Frigibax" },
      [3] = { 16, "Drill Run", "Psychic Fangs" },
      [4] = { 12, "Power Whip", "Solar Blade" },
      [5] = { 11, "1F", "11F" },
      [6] = { 21, "Adamant +Atk -SpA", "Gentle   +SpD -Def" },
      [7] = { 9, "Kabuto   2 Blue Shards", "Amaura    2 Yellow Shard" },
      [8] = { 9, "Omanyte   2 Blue Shards", "Amaura    2 Yellow Shard" },
      [9] = { 27, "Master Ball", "Hisuian Ball" },
      [10] = { 16, "Fighting", "Dark" },
      [11] = { 4, "Brock Rematch", "Giovanni" },
      [12] = { 8, "Johto", "Paldea" },
      [13] = { 4, "Normal", "Info" },
      [14] = { 3, "Fire Fang", "Thunder Fang" },
      [15] = { 8, "Power Whip", "Solar Blade" },
    }
    for id = 0, 15 do
      local entry = assert(registry.lists[id])
      local signature = signatures[id]
      assert(entry.count == signature[1] and #entry.labels == signature[1])
      assert(entry.labels[1] == signature[2]
        and entry.labels[#entry.labels] == signature[3])
      local ctx = Ctx.new({ playerName = "RED", rivalName = "BLUE" })
      Flags.setVar(Space.store, ctx, 0x8004, 0)
      Flags.setVar(Space.store, ctx, 0x8000, id)
      Flags.setVar(Space.store, ctx, 0x8001, 6)
      assert(Natives.ALLOW["special:344"](ctx) == false)
      assert(ListMenu.Menu.isOpen(), "custom list did not open for id " .. id)
      assert(ListMenu.Menu.kind == "rr_custom_list_" .. id)
      assert(table.concat(ListMenu.Menu.labels or {}, "\0")
        == table.concat(entry.labels, "\0"))
      assert(ListMenu.Menu.left == 1 and ListMenu.Menu.top == 1)
      if id == 12 then
        for _ = 1, 7 do ListMenu.Menu.move(1) end
      end
      local expectedResult = id == 12 and 7 or 0
      ListMenu.Menu.confirm()
      assert(Flags.getVar(Space.store, ctx, 0x800D) == expectedResult,
        "custom list result was wrong for id " .. id)
    end
  end

  -- The bedroom console owns these five exact, case-sensitive codes. Verify
  -- the extracted text, comparison special, branch flags, and every host
  -- effect that otherwise lived in CFRU's ARM code.
  do
    local Ctx = require("src.core.game3.scripting.ctx")
    local Natives = require("src.core.game3.scripting.natives")
    local Party = require("src.core.game3.party")
    local Stack = require("src.ui.game3.stack")
    local codes = {
      { code = "Woyaopp",     text = "g3:0910d4ff", branch = "g3:090500f3", flag = 0x1040 },
      { code = "DexAll",      text = "g3:0910d90a", branch = "g3:0905011f", flag = 0x1056 },
      { code = "SO2Toxic",    text = "g3:0910d50e", branch = "g3:0905013f", flag = 0x103F },
      { code = "TeamPreview", text = "g3:0910d517", branch = "g3:090507fb", flag = 0x1083 },
      { code = "EZCatch",     text = "g3:0910d523", branch = "g3:09050109", flag = 0x109D },
    }
    local prompt = assert(Space.bundle.scripts["g3:09050086"])
    local function contains(rows, op, field, value)
      for _, row in ipairs(rows or {}) do
        if row.op == op and row[field] == value then return true end
      end
      return false
    end
    for _, spec in ipairs(codes) do
      local ctx = Ctx.new({ playerName = "RED", rivalName = "BLUE" })
      ctx.data[0] = spec.text
      ctx.stringVars[1] = spec.code
      assert(Natives.ALLOW["special:301"](ctx) == false)
      assert(Flags.getVar(Space.store, ctx, 0x800D) == 0,
        spec.code .. " was not accepted by the console")
      ctx.stringVars[1] = spec.code:lower()
      Natives.ALLOW["special:301"](ctx)
      assert(Flags.getVar(Space.store, ctx, 0x800D) ~= 0,
        spec.code .. " unexpectedly lost cartridge case sensitivity")
      assert(contains(prompt, "loadword", "value", spec.text),
        "console prompt omitted " .. spec.code)
      local branch = assert(Space.bundle.scripts[spec.branch],
        "missing console branch for " .. spec.code)
      assert(contains(branch, "setflag", "flag", spec.flag),
        spec.code .. " did not persist its cartridge flag")
    end

    -- SO2Toxic's branch must still reach cartridge item-grant subroutines.
    local grants, visited = 0, {}
    local function auditItemGrants(key)
      if visited[key] then return end
      visited[key] = true
      for _, row in ipairs(Space.bundle.scripts[key] or {}) do
        if row.op == "callstd" and row.std == 0 then grants = grants + 1 end
        if (row.op == "call" or row.op == "call_if") and row.target then
          auditItemGrants(row.target)
        end
      end
    end
    auditItemGrants("g3:0905013f")
    assert(grants >= 1, "SO2Toxic no longer reaches any early-item grants")

    -- Woyaopp exposes the Viridian kid's Rare Candy/level-cap service.
    local candyRows = assert(Space.bundle.scripts["g3:0904dd1b"])
    assert(contains(candyRows, "special", "id", 159)
        and contains(candyRows, "callnative", "fn", 0x090950A5)
        and contains(candyRows, "callnative", "fn", 0x090772D1),
      "Woyaopp's Viridian Rare Candy/level-cap service is incomplete")

    -- Reproduce the tester's exact second-slot Combee selection through the
    -- live party menu. Its callback runs after close, so the chosen slot must
    -- be committed before the gender-check native resumes.
    local session = assert(game.session)
    local oldParty = session.party
    local scratch = setmetatable({
      party = {}, dex = { seen = {}, owned = {}, caught = {} },
    }, { __index = session })
    Flags.setFlag(Space.store, nil, 0x940, false)
    assert(Party.giveMon(scratch, 1, 5))
    assert(Party.giveMon(scratch, 468, 5))
    session.party = scratch.party
    local pickCtx = Ctx.new({ playerName = "RED", rivalName = "BLUE" })
    assert(Natives.choosePartyMon(pickCtx, nil, "choose_single") == true)
    local PartyMenu = require("src.ui.game3.party_menu")
    assert(PartyMenu.open and type(PartyMenu._onSelect) == "function")
    local selected = PartyMenu._onSelect
    PartyMenu.close()
    selected(2, session.party[2])
    assert(Flags.getVar(Space.store, pickCtx, 0x8004) == 1,
      "party picker resumed with slot one after selecting slot two")
    local beforeGender = session.party[2].gender
    assert(Natives.ALLOW["native:" .. 0x09077B59](pickCtx) == false)
    assert(Flags.getVar(Space.store, pickCtx, 0x800D) == 1,
      "second-slot Combee was rejected by the live gender changer")
    assert(Natives.ALLOW["native:" .. 0x09077C45](pickCtx) == false)
    assert(session.party[2].gender ~= beforeGender,
      "second-slot Combee gender did not change")
    session.party = oldParty

    -- DexAll adds a current-area DexNav and reveals every encounter row.
    Flags.setFlag(Space.store, nil, 0x1056, true)
    local items = loader.hooks:call("ui.start_menu.items",
      function(_, value) return value end, game, {
        { id = "pokedex", label = "POKEDEX" },
        { id = "save", label = "SAVE" },
      })
    local dexNav
    for _, item in ipairs(items) do
      if item.id == "rr_dexnav" then dexNav = item break end
    end
    assert(dexNav and type(dexNav.onSelect) == "function",
      "DexAll did not expose the DexNav menu")
    local oldMap = session.map
    session.map = "FR_VIRIDIAN_CITY"
    dexNav.onSelect(game, session)
    local dexLayer = Stack.top()
    assert(dexLayer and dexLayer.id == "rr_dexnav"
        and #dexLayer.mod.rows > 0,
      "DexNav did not load Viridian encounter rows")
    for index, row in ipairs(dexLayer.mod.rows) do
      assert(row.revealed and row.name ~= "??????????",
        "DexAll left hidden encounter data in DexNav")
      -- Every current-area slot that does not require a fishing rod must be
      -- capable of producing a complete battle payload.  This catches the
      -- old display-only DexNav as well as species-zero/no-moves regressions.
      local needsRod = true
      for _, slot in ipairs(row.scanSlots or {}) do
        if not slot.requiredItem then needsRod = false break end
      end
      if not needsRod then
        dexLayer.mod.cursor = index
        local encounter, encounterErr = dexLayer.mod.generateSelected()
        assert(encounter, "DexNav could not generate " .. tostring(row.name)
          .. ": " .. tostring(encounterErr))
        assert(encounter.rrDexNav == true and encounter.species == row.species
            and encounter.level >= 1 and encounter.level <= 100,
          "DexNav generated an invalid species/level payload")
        assert(type(encounter.moves) == "table" and #encounter.moves > 0,
          "DexNav generated a species with no usable moves")
        assert(type(encounter.ivs) == "table"
            and encounter.ivs.hp ~= nil and encounter.ivs.atk ~= nil
            and encounter.ivs.def ~= nil and encounter.ivs.spe ~= nil
            and encounter.ivs.spa ~= nil and encounter.ivs.spd ~= nil,
          "DexNav did not generate a complete IV payload")
      end
    end
    dexLayer.mod.cursor = 1
    assert(dexLayer.mod.registerSelected() == true,
      "DexNav could not register its selected species")
    local dexState = assert(session.modData.radical_red_experience.dexNav)
    assert(dexState.registeredSpecies == dexLayer.mod.rows[1].species,
      "DexNav registration was not persisted in the save session")
    dexLayer.mod.close()
    session.map = oldMap

    -- EZCatch forces four shakes, while TeamPreview accepts SELECT on Android
    -- overlays that do not expose an L button.
    Flags.setFlag(Space.store, nil, 0x109D, true)
    local caught, shakes = loader.hooks:call("catch.rate",
      function() return false, 0 end, "POKE_BALL", {}, {}, {})
    assert(caught == true and shakes == 4,
      "EZCatch did not force a successful catch")

    Flags.setFlag(Space.store, nil, 0x1083, true)
    local BattleUi = require("src.core.game3.battle.ui")
    local oldState, oldMode, oldPreview =
      BattleUi._st, BattleUi._mode, BattleUi._rrTeamPreview
    BattleUi._st = { wild = false, foeParty = { { species = 25, hp = 10 } } }
    BattleUi._mode = "menu"
    local pressed = { select = true }
    local input = { wasPressed = function(_, key) return pressed[key] == true end }
    assert(BattleUi.handleInput(input) == true and BattleUi._rrTeamPreview == true,
      "TeamPreview did not open with Android SELECT")
    pressed.select, pressed.b = false, true
    assert(BattleUi.handleInput(input) == true and BattleUi._rrTeamPreview == false,
      "TeamPreview did not close with B")
    BattleUi._st, BattleUi._mode, BattleUi._rrTeamPreview =
      oldState, oldMode, oldPreview
  end

  -- The labels alone are not enough. Exercise the live CFRU replacement
  -- paths against the player's full trainer id and the exact pools embedded
  -- in this ROM. This proves the original options affect created Pokemon,
  -- abilities, and level-up learnsets after their flags are selected.
  local function romU16(offset)
    local file = assert(io.open(rrPath, "rb"))
    assert(file:seek("set", offset))
    local bytes = assert(file:read(2))
    file:close()
    local lo, hi = bytes:byte(1, 2)
    return lo + hi * 0x100
  end
  local function poolU16(offset, index)
    return romU16(offset + 2 + index * 2)
  end
  local function poolU8(offset, index)
    local file = assert(io.open(rrPath, "rb"))
    assert(file:seek("set", offset + 1 + index))
    local value = assert(file:read(1)):byte(1)
    file:close()
    return value
  end
  local Rng = require("src.core.game3.rng")
  local Pokemon = require("src.core.game3.pokemon")
  local Party = require("src.core.game3.party")
  local session = assert(game.session)
  local fullId = ((tonumber(session.secretId) or 0) % 0x10000) * 0x10000
    + ((tonumber(session.trainerId) or 0) % 0x10000)
  if fullId == 0 then fullId = 1 end

  Flags.setFlag(Space.store, nil, 0x940, true)
  local expectedSpecies = poolU16(0x1163B98,
    Rng.mulU32(fullId, 1) % exports.randomizerReport.speciesPool)

  -- The ROM script has already selected each of these party records from the
  -- player's starter/region branch. The randomizer hook must pass the exact
  -- table through, including explicit competitive moves and held items.
  for _, identity in ipairs({
    { 81, 326 }, -- opening Kanto rival
    { 89, 332 }, -- later Kanto rival branch
    { 1, 44 },   -- Brendan
    { 90, 438 }, -- Champion rival branch
  }) do
    local rivalParty = { {
      species = 7, speciesId = 7, level = 5, heldItem = 13,
      moves = { "TACKLE" }, moveIds = { 33 },
    } }
    local passed = loader.hooks:call("trainer.party",
      function(_, _, party) return party end,
      identity[1], identity[2], rivalParty)
    assert(passed == rivalParty and passed[1].speciesId == 7
        and passed[1].moveIds[1] == 33 and passed[1].heldItem == 13,
      "starter/region rival party was randomized after ROM branch selection")
  end
  -- The three earned overworld Skills must resolve from the exact RR item
  -- table, not from synthetic ids baked into the mod.
  local ItemsData = require("src.core.game3.items_data")
  local function normalizedItemName(value)
    local text = tostring(value or "")
    text = text:gsub("é", "e"):gsub("É", "E")
    return text:upper():gsub("[^A-Z0-9]", "")
  end
  local skillIds = assert(exports.qolReport.skillItemIds)
  assert(skillIds.timeChanger and skillIds.infiniteRepel and skillIds.pokeVial,
    "one or more Radical Red Skill key items were not found in the exact ROM")
  assert(normalizedItemName(ItemsData.displayName(skillIds.timeChanger)) == "TIMECHANGER")
  assert(normalizedItemName(ItemsData.displayName(skillIds.infiniteRepel)) == "INFINITEREPEL")
  assert(normalizedItemName(ItemsData.displayName(skillIds.pokeVial)) == "POKEVIAL")

  -- Exercise the actual pinned controller path for the original device report:
  -- LOVE leftshoulder -> Input logical "l" -> queued edge -> core.update ->
  -- rr_skills stack layer. Also prove a held shoulder cannot reopen the menu
  -- until a real release re-arms the edge.
  do
    local Stack = require("src.ui.game3.stack")
    local Field = require("src.core.game3.field")
    local Battle = require("src.core.game3.battle")
    local input = game.input
    local savedVm = Space.vm
    local savedLocked = Field.locked
    local savedBattleActive = Battle.isActive

    Stack.clear()
    Space.vm = nil
    Field.locked = false
    Battle.isActive = function() return false end
    input:reset()

    local skillGame = { phase = "field", session = session, input = input }
    local function skillTick()
      return loader.hooks:call("core.update", function(g)
        -- core.update wraps the real Game:update path. Advance Input here so
        -- queued edges/pressed state have the same lifetime as the pinned host.
        g.input:step()
        return "updated"
      end, skillGame, 1 / 60)
    end

    input:gamepadpressed(nil, "leftshoulder")
    local sawQueuedL = false
    for _, key in ipairs(input.pressQueue or {}) do
      if key == "l" then sawQueuedL = true break end
    end
    assert(sawQueuedL and input:isDown("l"),
      "pinned leftshoulder input did not emit the logical L edge")
    assert(skillTick() == "updated")
    local firstSkillLayer = Stack.top()
    assert(firstSkillLayer and firstSkillLayer.id == "rr_skills",
      "physical left shoulder did not open the live Radical Red Skills menu")
    firstSkillLayer.mod.close(true)

    -- Still physically held: no second open.
    assert(skillTick() == "updated")
    assert(Stack.top() == nil,
      "held L reopened the Skills menu without a release edge")

    input:gamepadreleased(nil, "leftshoulder")
    assert(skillTick() == "updated")
    input:gamepadpressed(nil, "leftshoulder")
    assert(skillTick() == "updated")
    local secondSkillLayer = Stack.top()
    assert(secondSkillLayer and secondSkillLayer.id == "rr_skills",
      "Skills menu did not re-arm after releasing and pressing L again")
    secondSkillLayer.mod.close(true)

    input:gamepadreleased(nil, "leftshoulder")
    input:reset()
    Space.vm = savedVm
    Field.locked = savedLocked
    Battle.isActive = savedBattleActive
  end

  -- Census the live extracted trainer table, not just one convenient boss.
  -- Every identity the runtime classifies as authored must preserve its exact
  -- party under the enabled species randomizer. This covers recurring bosses
  -- whose trainer class is shared with ordinary opponents as well as leaders,
  -- admins, Elite Four/Champion records, and every protected rival branch.
  local Trainers = require("src.core.game3.scripting.trainers")
  local RRRandomizer = assert(loadfile(
    "mods/radical_red_experience/lib/rr_randomizer.lua"))()
  local requiredBossNames = {
    GIOVANNI = false, ARCHER = false, ARIANA = false,
    CLAIR = false, BRENDAN = false, MAY = false,
  }
  local protectedBosses = 0
  local trainerPack = assert(Trainers.pack(), "exact RR trainer pack is missing")
  for rawId in pairs(assert(trainerPack.trainers,
      "exact RR trainer pack has no trainer table")) do
    local id = tonumber(rawId)
    local row = id and Trainers.get(id) or nil
    if row and RRRandomizer.isFixedBoss(tonumber(row.class) or 1, id) then
      protectedBosses = protectedBosses + 1
      local name = tostring(row.name or row.trainerName or ""):upper()
      if requiredBossNames[name] ~= nil then requiredBossNames[name] = true end

      local bossParty = { {
        species = 25, speciesId = 25, level = 50, heldItem = 13,
        moves = { "THUNDERBOLT" }, moveIds = { 85 },
      } }
      local bossPassed = loader.hooks:call("trainer.party",
        function(_, _, party) return party end,
        tonumber(row.class) or 1, id, bossParty)
      assert(bossPassed == bossParty
          and bossPassed[1].speciesId == 25
          and bossPassed[1].heldItem == 13
          and bossPassed[1].moveIds[1] == 85,
        ("authored boss/rival %d (%s) was randomized in the exact RR runtime")
          :format(id, name))
    end
  end
  assert(protectedBosses >= 20,
    "exact RR boss census was unexpectedly small: " .. protectedBosses)
  for name, found in pairs(requiredBossNames) do
    assert(found, "exact RR boss census did not protect documented " .. name)
  end

  local ordinaryParty = { { species = 1, speciesId = 1, level = 5 } }
  local randomizedTrainer = loader.hooks:call("trainer.party",
    function(_, _, party) return party end, 1, 19, ordinaryParty)
  assert(randomizedTrainer ~= ordinaryParty
      and randomizedTrainer[1].speciesId == expectedSpecies,
    "ordinary trainer stopped using the enabled species randomizer")

  local scratch = setmetatable({ party = {}, dex = { seen = {}, owned = {}, caught = {} } },
    { __index = session })
  local gave, _, generated = Party.giveMon(scratch, 1, 5)
  assert(gave and generated and generated.species == expectedSpecies,
    "normal species randomizer did not use RR v4.1's deterministic pool")

  Flags.setFlag(Space.store, nil, 0x940, false)
  Flags.setFlag(Space.store, nil, 0x93A, true)
  local firstScaledCount = exports.randomizerReport.scaledPool
  local expectedScaled = poolU16(0x1165E18,
    Rng.mulU32(fullId, 1) % firstScaledCount)
  local scaledScratch = setmetatable({ party = {}, dex = { seen = {}, owned = {}, caught = {} } },
    { __index = session })
  local gaveScaled, _, scaledMon = Party.giveMon(scaledScratch, 1, 5)
  assert(gaveScaled and scaledMon and scaledMon.species == expectedScaled,
    "scaled species randomizer did not use RR v4.1's opening pool")
  Flags.setFlag(Space.store, nil, 0x93A, false)
  Flags.setFlag(Space.store, nil, 0x940, true)

  Flags.setFlag(Space.store, nil, 0x942, true)
  local baseAbility = Pokemon.abilities(1)[1]
  local abilityCount = exports.randomizerReport.abilityPool
  local startAt = (fullId % 0x10000) % abilityCount
  local xorVal = math.floor(fullId / 0x10000) % 0xFF
  local abilityIndex = baseAbility + 1 + startAt
  if abilityIndex >= abilityCount then
    abilityIndex = abilityIndex - abilityCount + 2
  end
  abilityIndex = require("bit").bxor(abilityIndex, xorVal) % abilityCount
  assert(Pokemon.abilityId(1, 0) == poolU8(0x1162ED6, abilityIndex),
    "ability randomizer did not use RR v4.1's deterministic pool")

  Flags.setFlag(Space.store, nil, 0x941, true)
  local rawLearnset = Pokemon._learnsets[1]
  local rawMove = tonumber(rawLearnset[1][2] or rawLearnset[1].move)
  local moveIndex = Rng.mulU32(Rng.mulU32(rawMove, 1), fullId)
    % exports.randomizerReport.movePool
  local randomizedLearnset = Pokemon.learnset(1)
  assert((randomizedLearnset[1][2] or randomizedLearnset[1].move)
      == poolU16(0x11627B8, moveIndex),
    "learnset randomizer did not use RR v4.1's deterministic pool")

  -- Opening OPTIONS paints an opaque black backdrop before any of its chrome.
  -- A draw error therefore looks like a responsive, entirely black screen.
  -- Exercise the real menu once so that missing ROM text/chrome is caught.
  local OptionMenu = require("src.ui.game3.option_menu")
  OptionMenu.show({ session = session, game = game })
  local originalSetColor = love.graphics.setColor
  local originalRectangle = love.graphics.rectangle
  local originalPrint = love.graphics.print
  local Chrome = require("src.ui.game3.chrome")
  local originalFrame = Chrome.fixedStdFrame
  local originalWindowPrint = Window.printPx
  local painted, normalText, authenticFrames = 0, {}, 0
  -- Model the number-only graphics shim used by the affected Android build.
  -- The mod wrapper must translate table colors without touching the engine.
  love.graphics.setColor = function(r, g, b, a)
    assert(type(r) == "number", "number-only setColor received a table")
    return originalSetColor(r, g, b, a)
  end
  love.graphics.rectangle = function(...)
    painted = painted + 1
    return originalRectangle(...)
  end
  Chrome.fixedStdFrame = function(...)
    authenticFrames = authenticFrames + 1
    return originalFrame(...)
  end
  Window.printPx = function(value, ...)
    normalText[#normalText + 1] = tostring(value)
    return originalWindowPrint(value, ...)
  end
  local beforeNormalFallback = OptionMenu.__rrOptionsFallbackCount or 0
  local drewOptions, optionsErr = pcall(OptionMenu.draw)
  Chrome.fixedStdFrame = originalFrame
  Window.printPx = originalWindowPrint
  love.graphics.setColor = originalSetColor
  love.graphics.rectangle = originalRectangle
  assert(drewOptions, "Radical Red OPTIONS draw failed: " .. tostring(optionsErr))
  assert((OptionMenu.__rrOptionsFallbackCount or 0) == beforeNormalFallback,
    "portable overlay replaced the authentic OPTIONS screen")
  assert(authenticFrames >= 1 and painted >= 1 and #normalText >= 2,
    "authentic OPTIONS chrome/font did not render")

  -- If any downstream chrome/font renderer still fails on a device, the
  -- wrapper must replace the already-painted black frame with a usable menu.
  local printed, fallbackPainted = {}, 0
  local beforeFallback = OptionMenu.__rrOptionsFallbackCount or 0
  Chrome.fixedStdFrame = function() error("forced OPTIONS chrome failure") end
  love.graphics.setColor = function(r, g, b, a)
    assert(type(r) == "number", "fallback passed a table color")
    return originalSetColor(r, g, b, a)
  end
  love.graphics.rectangle = function(...)
    fallbackPainted = fallbackPainted + 1
    return originalRectangle(...)
  end
  love.graphics.print = function(value, ...)
    printed[#printed + 1] = tostring(value)
    return originalPrint(value, ...)
  end
  local drewFallback, fallbackErr = pcall(OptionMenu.draw)
  Chrome.fixedStdFrame = originalFrame
  love.graphics.setColor = originalSetColor
  love.graphics.rectangle = originalRectangle
  love.graphics.print = originalPrint
  assert(drewFallback,
    "Radical Red OPTIONS fallback failed: " .. tostring(fallbackErr))
  assert((OptionMenu.__rrOptionsFallbackCount or 0) == beforeFallback + 1)
  assert(fallbackPainted >= 4,
    "Radical Red OPTIONS fallback did not repaint the black screen")
  assert(table.concat(printed, "\n"):find("GAME OPTIONS", 1, true),
    "Radical Red OPTIONS fallback did not draw its title")
  OptionMenu.close()
end

local Versions = require("src.import.gba.versions")
assert(Versions.ITEM_ICON_TABLE == 0x13C8100,
  "Radical Red expanded item-icon table was not selected")
assert(Versions.OW_GFX_POINTERS == 0x0EB1000)
assert(Versions.NUM_OBJ_EVENT_GFX == 257)
assert(Versions.NAMING.rival_gfx == 0x0EE82B0)

local Space = require("src.core.game3.scripting.space")
assert(Space.resolveObjectGraphicsId({ graphics=0 }) == 0)
assert(Space.resolveObjectGraphicsId({ graphics=88 }) == 88)
assert(Space.resolveObjectGraphicsId({ graphics=152 }) == 152)
assert(Space.resolveObjectGraphicsId({ graphics=239 }) == 239)
assert(Space.resolveObjectGraphicsId({ graphics=256 }) == 256)
assert(Space.resolveObjectGraphicsId({ graphics=0x016E }) == 0x016E)
assert(Space.resolveObjectGraphicsId({ graphics=495 }) == 495)
assert(Space.resolveObjectGraphicsId({ graphics=496 }) == 16)
assert(Space.resolveObjectGraphicsId({ graphics=512 }) == 512)
assert(Space.resolveObjectGraphicsId({ graphics=560 }) == 560)
assert(Space.resolveObjectGraphicsId({ graphics=561 }) == 16)
do
  local ResolverFlags = require("src.core.game3.scripting.flags")
  local prior = Space.store.vars[0x5028]
  ResolverFlags.setVar(Space.store, nil, 0x5028, 0x016E)
  assert(Space.resolveObjectGraphicsId({ graphics=0xFF00 }) == 0x016E,
    "RR's expanded indirect graphics slot discarded its table selector")
  Space.store.vars[0x5028] = prior
end

local Types = require("src.core.game3.battle.types")
assert(Types.ID.FAIRY == 23 and Types.name(23) == "FAIRY")
assert(Types.effectiveness(16, 23) == 0)   -- Dragon -> Fairy
assert(Types.effectiveness(23, 16) == 2)   -- Fairy -> Dragon
assert(Types.effectiveness(17, 8) == 1)    -- Dark -> Steel is neutral
assert(Types.effectiveness(7, 8) == 1)     -- Ghost -> Steel is neutral
local _, foresightOff = Types.typeCalc(0, 7, 7, 100, false)
local foresightDamage = Types.typeCalc(0, 7, 7, 100, true)
assert(foresightOff.immune and foresightDamage == 100)

-- Reproduce the post-rival faint path that previously crashed on CFRU's
-- expanded B_BUFF3 code 0x34. Also cover every other expanded placeholder
-- present in this ROM so the next screen/catch message cannot fail later.
do
  local BattleText = require("src.core.game3.battle.battle_text")
  local exp = BattleText.get("STRINGID_PKMNGAINEDEXP", {
    buff1 = "BULBY", buff2 = "", buff3 = "69",
  })
  assert(exp:find("BULBY", 1, true) and exp:find("69", 1, true)
      and exp:find("Exp. Points", 1, true),
    "Radical Red B_BUFF3 did not expand the rival-battle EXP message")
  local veil = BattleText.get("STRINGID_PKMNCOVEREDBYVEIL", { atk = "player" })
  assert(veil:find("Your team", 1, true),
    "Radical Red B_ATK_TEAM2 did not expand the player's team")
  local caught = BattleText.get("STRINGID_GOTCHAPKMNCAUGHT", {
    opponentMon1 = "RATTATA",
  })
  assert(caught:find("RATTATA was caught", 1, true),
    "Radical Red B_DEF_TEAM1 did not expand a caught Pokemon name")

  local ExpSeq = require("src.core.game3.battle.exp_seq")
  assert(ExpSeq.begin({ {
    mon = { species = 1, nickname = "BULBY" },
    partyIndex = 1,
    result = { gained = 69, steps = {} },
  } }, nil, nil, { headless = true }),
    "post-rival EXP sequence did not begin")
  assert(ExpSeq._steps and ExpSeq._steps[1]
      and ExpSeq._steps[1].data.text:find("69", 1, true),
    "post-rival EXP sequence did not build its gained-EXP message")
  ExpSeq.reset()
end

-- Exercise the installed raid resolver against the real stock battle modules,
-- not only the isolated threshold helpers.  Five-star damaging moves become
-- v4.1 Max moves, status moves can trigger a repeat, and barriers reject
-- player status moves while counting Brick Break as two shield segments.
local Pokemon = require("src.core.game3.pokemon")
local State = require("src.core.game3.battle.state")
local Adapter = require("src.core.game3.battle.adapter")
local Engine = require("src.core.game3.battle.engine")
local Battle = require("src.core.game3.battle")
local function battleMon(species, level, moves)
  local mon = {
    species = species, level = level, personality = 0,
    ivs = { hp = 31, atk = 31, def = 31, spe = 31, spa = 31, spd = 31 },
    evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 },
    moves = moves, pp = {}, maxPp = {},
  }
  for i, move in ipairs(moves) do
    mon.pp[i] = Pokemon.movePp(move)
    mon.maxPp[i] = mon.pp[i]
  end
  Pokemon.applyStats(mon)
  mon.hp = mon.maxHp
  return mon
end

-- RR's Roost uses the ordinary recover effect but its extracted battle text
-- names the battler through B_DEF_NAME_WITH_PREFIX. Exercise the live engine
-- path so a missing placeholder fill cannot escape the text-only tests above.
do
  local roostMon = battleMon(16, 50, { 395 })
  local foeMon = battleMon(19, 50, { 33 })
  local roostState = State.new({
    wild = true, playerParty = { roostMon }, foeMon = foeMon,
    foeParty = { foeMon }, rng = function(lo) return lo or 0 end,
  })
  roostState.player.mon.hp = math.max(1, roostState.player.mon.maxHp - 20)
  local before = roostState.player.mon.hp
  local roostOut = {}
  local roostAdapter = Adapter.new(roostState, function() end)
  Engine.resolveMove(roostState.player, roostState.enemy, 395, 1,
    roostAdapter, roostState, roostOut)
  assert(roostState.player.mon.hp > before,
    "Roost did not restore the user's HP")
  assert(table.concat(roostOut, " | "):find("regained", 1, true),
    "Roost did not render its recovered-health battle text")

  -- CFRU move scripts can request the same text without an explicit fill.def;
  -- the live effect globals still identify the user.  Reproduce the tester's
  -- exact failure instead of relying only on the normal healing helper, which
  -- currently passes def itself.
  local EffectCtx = require("src.core.game3.battle.effect_ctx")
  local BattleText = require("src.core.game3.battle.battle_text")
  EffectCtx.push(roostAdapter, roostState.player, roostState.player,
    { target = 16 }, 395, function(lo) return lo or 0 end, {})
  local okText, sparseRoostText = pcall(BattleText.get,
    "STRINGID_PKMNREGAINEDHEALTH", {})
  EffectCtx.pop()
  assert(okText and sparseRoostText:find("regained", 1, true),
    "Roost's sparse CFRU text context still requires fill.def: "
      .. tostring(sparseRoostText))
end

-- RR's damaging pivot family deliberately shares CFRU's Baton Pass effect id,
-- but only the party-picker/presentation contract.  The actual switch must
-- clear Baton Pass state.  Exercise the live v0.3.20 engine so a future host
-- change cannot silently turn U-turn/Volt Switch/Flip Turn into an instant
-- data swap or start inheriting stages/Substitute.
do
  local AnimSeq = require("src.core.game3.battle.anim_seq")
  local pivots = {
    { 0x1BA, "U-turn" },
    { 0x1BB, "Volt Switch" },
    { 0x2D8, "Flip Turn" },
  }
  for _, pivot in ipairs(pivots) do
    local moveId, label = pivot[1], pivot[2]
    local lead = battleMon(1, 60, { moveId })
    local bench2 = battleMon(4, 60, { 33 })
    local bench3 = battleMon(7, 60, { 33 })
    local foe = battleMon(19, 60, { 33 })
    local pivotState = State.new({
      wild = true,
      playerParty = { lead, bench2, bench3 },
      foeMon = foe,
      foeParty = { foe },
      rng = function(lo) return lo or 0 end,
    })
    pivotState.interactiveChoices = true
    pivotState.player.stages.attack = 4
    pivotState.player.substituteHP = 20
    pivotState.enemy.mon.maxHp, pivotState.enemy.mon.hp = 10000, 10000

    local pivotAdapter = Adapter.new(pivotState, function() end)
    local first = {}
    Engine.resolveMove(
      pivotState.player, pivotState.enemy, moveId, 1,
      pivotAdapter, pivotState, first)

    assert(first.pendingChoice
        and first.pendingChoice.kind == "baton_pass"
        and first.pendingChoice.rrPivot == true,
      label .. " did not pause on the live forced-switch party picker")
    assert(pivotState.player.partyIndex == 1,
      label .. " switched before the player selected a replacement")

    local resumed = assert(Engine.resumeChoice(pivotState, pivotAdapter, 3),
      label .. " did not resume after selecting a replacement")
    assert(pivotState.player.partyIndex == 3,
      label .. " did not switch to the selected party slot")
    assert((tonumber(pivotState.player.stages.attack) or 0) == 0
        and not pivotState.player.substituteHP,
      label .. " incorrectly inherited Baton Pass stages/Substitute")

    local switchEvent
    for _, ev in ipairs(resumed._anim and resumed._anim.events or {}) do
      if ev.kind == "switch" then
        switchEvent = ev
        break
      end
    end
    assert(switchEvent
        and switchEvent.reason == "baton_pass"
        and switchEvent.from == 1
        and switchEvent.to == 3,
      label .. " did not emit the presentation switch event 1 -> 3")

    local steps = AnimSeq.buildSteps(
      resumed._anim and resumed._anim.events or {},
      resumed._anim or {})
    local switchOutAt, goAt, switchInAt
    for i, step in ipairs(steps) do
      if step.kind == "switch_out" and not switchOutAt then
        switchOutAt = i
      elseif switchOutAt and step.kind == "msg" and not goAt then
        -- BattleText.key() resolves STRINGID_SWITCHINMON to a concrete
        -- sText_* key (for example sText_GoPkmn2) before this reaches AnimSeq.
        goAt = i
      elseif switchOutAt and step.kind == "switch_in" and not switchInAt then
        switchInAt = i
      end
    end
    assert(switchOutAt and goAt and switchInAt
        and switchOutAt < goAt and goAt < switchInAt,
      label .. " presentation is not switch-out -> Go! -> switch-in")
  end
end

local p1 = battleMon(1, 60, { 33, 45, 280 })
local p2 = battleMon(4, 60, { 33 })
local bossMon = battleMon(127, 60, { 33, 45 })
bossMon.rrRaid, bossMon.raidStars = true, 5
local raidState = State.new({
  wild = true, double = true, playerParty = { p1, p2 }, partnerIndex = 2,
  foeMon = bossMon, foeParty = { bossMon },
  rng = function(lo) return lo or 0 end,
})
raidState.raid = {
  stars = 5, shieldsUp = false, shieldsDestroyed = 0,
  faints = 0, repeatedAttacks = 0,
}
raidState.enemy.isFirstTurn = 0
raidState.turn, raidState.randomTurnNumber = 2, 0
raidState.player.mon.maxHp, raidState.player.mon.hp = 10000, 10000
raidState.battlers[2].mon.maxHp, raidState.battlers[2].mon.hp = 10000, 10000
local raidAdapter = Adapter.new(raidState, function() end)
Battle._actions, Battle._actionI = {}, 1
local maxOut = Engine.resolveMove(1, 0, 33, 1, raidAdapter, raidState, {})
assert(maxOut._anim and maxOut._anim.moveId == 902,
  "five-star raid Tackle did not become Max Strike")
assert(raidState.player.stages.speed == -1,
  "Max Strike did not apply its RR raid secondary (speed="
    .. tostring(raidState.player.stages.speed) .. ", missed="
    .. tostring(maxOut._anim and maxOut._anim.missed) .. ", type="
    .. tostring(require("src.core.game3.battle.moves").get(33).type)
    .. ", over=" .. tostring(raidState.over) .. ", messages="
    .. table.concat(maxOut, " | ") .. ")")

Battle._actions, Battle._actionI = {}, 1
raidState.raid.repeatedAttacks, raidState.raid.attackAgain = 0, false
local statusOut = Engine.resolveMove(1, 0, 45, 2, raidAdapter, raidState, {})
assert(statusOut._anim and #Battle._actions == 1
  and Battle._actions[1]._rrRaidRepeat,
  "raid status move did not schedule a repeated attack")

Battle._actions, Battle._actionI = {}, 1
raidState.raid.shieldsUp = true
raidState.raid.shieldCount = 4
raidState.raid.shieldsDestroyed = 0
local blockedOut = Engine.resolveMove(0, 1, 45, 2, raidAdapter, raidState, {})
assert(blockedOut._anim and blockedOut._anim.cancelled,
  "raid barrier did not reject a player status move")
Engine.resolveMove(0, 1, 280, 3, raidAdapter, raidState, {})
assert(raidState.raid.shieldsDestroyed == 2,
  "Brick Break did not remove two raid shield segments")

-- Draw TeamPreview over a fully formed battle state, including real icon and
-- FRLG-window rendering. Input-only coverage would miss an Android-visible
-- overlay failure after the button was accepted.
do
  local PreviewUi = require("src.core.game3.battle.ui")
  PreviewUi.reset({ headless = false })
  PreviewUi.bindState(raidState)
  PreviewUi._mode = "menu"
  PreviewUi._rrTeamPreview = true
  local okPreview, previewErr = pcall(PreviewUi.draw)
  assert(okPreview and PreviewUi._rrTeamPreview == true,
    "TeamPreview draw failed: " .. tostring(previewErr))
  PreviewUi._rrTeamPreview = false
end

run.release()
print("PASS engine_loader_test: stock loader mounted RR data and raid battle rules")
