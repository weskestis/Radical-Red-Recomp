-- Install the private Radical Red cache as the live Game3 dataset.
-- This is deliberately a runtime-only interposition: no launcher or engine
-- file is edited, and restarting with the mod disabled restores stock FR.

local Runtime = {}

local function withNoPrefix(CacheFs, fn, ...)
  local saved = CacheFs.prefix
  CacheFs.prefix = ""
  local result = { pcall(fn, ...) }
  CacheFs.prefix = saved
  if not result[1] then error(result[2], 0) end
  return unpack(result, 2, #result)
end

local function installCacheOverlay(mod, Profile)
  local CacheFs = require("src.import.CacheFs")
  local GameVersion = require("src.core.GameVersion")
  local state = CacheFs.__radicalRedOverlay
  if state then return state end

  local modId = (mod.manifest and mod.manifest.id) or "radical_red_experience"
  local versionId = "radical_red_runtime"
  local cachePrefix = "mod_cache/" .. modId .. "/"
  local dataGenerated = Profile.generatedRoot and Profile.generatedRoot()
    or ("data/" .. "generated")
  local assetsGenerated = "assets/" .. "generated"
  local function redirect(rel)
    if type(rel) ~= "string" then return nil end
    -- Dataset/Extract modules also pass their already-qualified physical
    -- root back through CacheFs (for example
    -- a fully-qualified script-cache path). Treat that as
    -- an exact RR path.  Without this branch CacheFs.prefix could prepend the
    -- base FireRed prefix and silently make scripts/events/UI look absent.
    if rel:sub(1, #cachePrefix) == cachePrefix then return rel end
    if rel:match("^" .. dataGenerated .. "/?")
        or rel:match("^" .. assetsGenerated .. "/?") then
      return cachePrefix .. rel
    end
    return nil
  end
  local function logicalFallback(rel)
    if type(rel) == "string" and rel:sub(1, #cachePrefix) == cachePrefix then
      return rel:sub(#cachePrefix + 1)
    end
    return nil
  end

  -- CacheFs normally sees the same LÖVE save directory as mod.cache.  The
  -- SDK/headless loader intentionally supplies an isolated filesystem,
  -- though, and portable hosts can also expose the scoped cache before its
  -- physical mount is visible.  Keep mod.cache as a second, capability-safe
  -- path to the exact same files rather than treating that timing difference
  -- as a missing RR asset.
  local function readCustom(custom)
    local ok, bytes = pcall(CacheFs.readAt, custom)
    if ok and type(bytes) == "string" then return bytes end
    local logical = logicalFallback(custom)
    if logical and mod.cache and mod.cache.read then
      bytes = mod.cache:read(logical)
      if type(bytes) == "string" then return bytes end
    end
    return nil
  end

  local function customExists(custom)
    local ok, exists = pcall(CacheFs.existsAt, custom)
    if ok and exists then return true end
    local logical = logicalFallback(custom)
    return logical and mod.cache and mod.cache.exists
      and mod.cache:exists(logical) or false
  end

  state = {
    versionId = versionId,
    cachePrefix = cachePrefix,
    originalRead = CacheFs.read,
    originalReadActive = CacheFs.readActive,
    originalExists = CacheFs.exists,
    originalWrite = CacheFs.write,
    originalOpenWrite = CacheFs.openWrite,
    originalUnmount = CacheFs.unmountVersion,
    mounted = false,
  }
  CacheFs.__radicalRedOverlay = state

  -- CacheFs.readActive's original implementation calls CacheFs.read by table
  -- lookup.  Temporarily expose the original read while asking it for a base
  -- FireRed fallback; otherwise it would recurse through this overlay.
  local function readBaseActive(rel)
    local overlayRead = CacheFs.read
    CacheFs.read = state.originalRead
    local result = { pcall(state.originalReadActive, rel) }
    CacheFs.read = overlayRead
    if not result[1] then return nil end
    return result[2]
  end

  CacheFs.readActive = function(rel)
    local custom = redirect(rel)
    if custom then
      local bytes = readCustom(custom)
      if type(bytes) == "string" then return bytes end
      local logical = logicalFallback(custom)
      if logical then
        bytes = readBaseActive(logical)
        if type(bytes) == "string" then return bytes end
      end
    end
    return state.originalReadActive(rel)
  end

  CacheFs.read = function(rel)
    local custom = redirect(rel)
    if custom then
      local bytes = readCustom(custom)
      if type(bytes) == "string" then return bytes end
      local logical = logicalFallback(custom)
      if logical then
        bytes = readBaseActive(logical)
        if type(bytes) == "string" then return bytes end
      end
    end
    return state.originalRead(rel)
  end

  CacheFs.exists = function(rel)
    local custom = redirect(rel)
    if custom and customExists(custom) then return true end
    local logical = custom and logicalFallback(custom)
    if logical and type(readBaseActive(logical)) == "string" then return true end
    return state.originalExists(rel)
  end

  -- Runtime atlas baking must remain inside this mod's cache instead of
  -- polluting the base FireRed generated tree.
  CacheFs.write = function(rel, bytes)
    local custom = redirect(rel)
    if custom then
      local logical = logicalFallback(custom)
      if logical and mod.cache and mod.cache.write then
        return mod.cache:write(logical, bytes)
      end
      return withNoPrefix(CacheFs, state.originalWrite, custom, bytes)
    end
    return state.originalWrite(rel, bytes)
  end

  CacheFs.openWrite = function(rel)
    local custom = redirect(rel)
    if custom then
      return withNoPrefix(CacheFs, state.originalOpenWrite, custom)
    end
    return state.originalOpenWrite(rel)
  end

  GameVersion.VERSIONS[versionId] = {
    id = versionId,
    label = "Radical Red",
    displayName = "Radical Red",
    launcherName = "Radical Red",
    sha1 = Profile.SHA1,
    cachePrefix = cachePrefix,
    saveSuffix = "_radical_red_4_1",
    generation = 3,
    engine = "game3",
    cartShape = "gba",
  }

  CacheFs.unmountVersion = function(version)
    local customDone = false
    if state.mounted and version == versionId then
      local done = state.originalUnmount(versionId)
      state.mounted = false
      return done
    elseif state.mounted then
      customDone = state.originalUnmount(versionId) and true or false
      state.mounted = false
    end
    local baseDone = state.originalUnmount(version)
    return customDone or baseDone
  end

  CacheFs.mountVersion(versionId)
  state.mounted = true
  return state
end

local function invalidateLoadedModules()
  local Space = require("src.core.game3.scripting.space")
  if Space.active and Space.deactivate then pcall(Space.deactivate, nil) end
  Space.bundle = nil
  Space._immediateVm = nil

  local Pokemon = require("src.core.game3.pokemon")
  if Pokemon.invalidate then Pokemon.invalidate() end

  local Moves = require("src.core.game3.battle.moves")
  Moves._romLoaded = false
  Moves._rom = nil
  Moves._numByName = nil

  local Trainers = require("src.core.game3.scripting.trainers")
  Trainers._pack = nil

  local modules = {
    "src.core.game3.tileset_native",
    "src.core.game3.ow_sprites",
    "src.core.game3.field_effects",
    "src.core.game3.tileset_anim",
    "src.core.game3.heal_locations",
    "src.ui.game3.frlg_font",
    "src.ui.game3.chrome",
  }
  for _, name in ipairs(modules) do
    local ok, module = pcall(require, name)
    if ok and module and module.invalidate then pcall(module.invalidate) end
  end

  local MoveLearn = require("src.core.game3.move_learn")
  if MoveLearn.resetTutorPack then MoveLearn.resetTutorPack() end

  local Encounters = require("src.core.game3.encounters")
  Encounters._loaded = false
  Encounters._tables = {}
  Encounters._logged = false
end

local function installScriptShardLoader()
  local ExtractScripts = require("src.import.gba.extract_scripts")
  if ExtractScripts.__radicalRedShardLoader then return end
  ExtractScripts.__radicalRedShardLoader = true
  local original = assert(ExtractScripts.loadBundle)
  ExtractScripts.__radicalRedOriginalLoadBundle = original

  local function loadTable(cache, rel)
    local source = cache and cache.read and cache:read(rel)
    if type(source) ~= "string" then return nil end
    local chunk = load(source, "@" .. rel, "t", {})
    if not chunk then return nil end
    local ok, value = pcall(chunk)
    if ok and type(value) == "table" then return value end
    return nil
  end

  local function merge(dst, src)
    for key, value in pairs(src or {}) do dst[key] = value end
    return dst
  end

  ExtractScripts.loadBundle = function(cache, root, opts)
    root = root or ("data/" .. "generated/gba")
    local manifestPath = root .. "/scripts/rr_shards/manifest.lua"
    local sourceCache = cache
    local manifest = loadTable(sourceCache, manifestPath)
    if not manifest then
      local okDataset, Dataset = pcall(require, "src.core.game3.dataset")
      local fallback = okDataset and Dataset and Dataset.cache and Dataset.cache()
      manifest = loadTable(fallback, manifestPath)
      if manifest then sourceCache = fallback end
    end
    if not (manifest and manifest.version == 1 and manifest.parts) then
      return original(cache, root, opts)
    end

    local registries = {}
    for _, name in ipairs({ "scripts", "text", "movements", "events" }) do
      local registry = {}
      for _, rel in ipairs(manifest.parts[name] or {}) do
        local shard = assert(loadTable(sourceCache, rel),
          "Radical Red script shard is missing or invalid: " .. tostring(rel))
        merge(registry, shard)
      end
      registries[name] = registry
      local expected = manifest.entries and tonumber(manifest.entries[name])
      if expected then
        local actual = 0
        for _ in pairs(registry) do actual = actual + 1 end
        assert(actual == expected,
          ("Radical Red %s shard count mismatch: expected %d, got %d")
            :format(name, expected, actual))
      end
    end

    -- Let the stock loader perform object-interaction, encounter-type, mart,
    -- and text-table setup against tiny placeholders, then merge those
    -- overlays on top of the RR registries.
    local scriptsBase = root .. "/scripts/"
    local proxy = {}
    function proxy:read(rel)
      if rel == scriptsBase .. "scripts.lua"
          or rel == scriptsBase .. "text.lua"
          or rel == scriptsBase .. "movements.lua"
          or rel == scriptsBase .. "events.lua" then
        return "return {}\n"
      end
      return sourceCache:read(rel)
    end
    function proxy:exists(rel)
      if sourceCache.exists then return sourceCache:exists(rel) end
      return self:read(rel) ~= nil
    end
    local stock = assert(original(proxy, root, { allowIncomplete = true }))
    merge(registries.scripts, stock.scripts)
    merge(registries.text, stock.text)
    merge(registries.movements, stock.movements)
    stock.scripts = registries.scripts
    stock.text = registries.text
    stock.movements = registries.movements
    stock.events = registries.events
    stock.fromCache = true
    stock.radicalRedSharded = true
    return stock
  end
end

-- NativePack pads odd FRLG layouts to an even grid for 2x2 atlas packing.
-- That storage padding is not part of the cartridge map: if it remains in
-- LayoutNative.width/height, the renderer and collision system expose a fake
-- solid row/column before south/east connections. Normalize the live handles
-- back to their ROM dimensions while retaining every real cell.
local function installTrueMapBounds()
  local LayoutNative = require("src.core.game3.layout_native")

  local function normalize(layout)
    if type(layout) ~= "table" then return false end
    if layout.__rrTrueBoundsNormalized then
      return layout.__rrHadStoragePadding == true
    end
    local width = tonumber(layout.width) or 0
    local height = tonumber(layout.height) or 0
    local trueWidth = tonumber(layout.trueWidth) or width
    local trueHeight = tonumber(layout.trueHeight) or height
    assert(trueWidth >= 1 and trueHeight >= 1
        and trueWidth <= width and trueHeight <= height,
      "Radical Red native layout has invalid true dimensions")
    local padded = width ~= trueWidth or height ~= trueHeight
    if padded then
      local cropped = {}
      for y = 0, trueHeight - 1 do
        for x = 0, trueWidth - 1 do
          cropped[#cropped + 1] = layout.cells[y * width + x + 1]
        end
      end
      assert(#cropped == trueWidth * trueHeight,
        "Radical Red native layout crop was incomplete")
      layout.cells = cropped
      layout.width = trueWidth
      layout.height = trueHeight
    end
    layout.__rrPhysicalWidth = width
    layout.__rrPhysicalHeight = height
    layout.__rrHadStoragePadding = padded
    layout.__rrTrueBoundsNormalized = true
    return padded
  end

  if not LayoutNative.__radicalRedTrueBounds then
    LayoutNative.__radicalRedTrueBounds = true
    local original = assert(LayoutNative.fromDecoded)
    LayoutNative.__radicalRedOriginalFromDecoded = original
    LayoutNative.fromDecoded = function(...)
      local layout = original(...)
      normalize(layout)
      return layout
    end
  end
  return normalize
end

local function bitSet(words, index)
  local wordIndex = math.floor(index / 32) + 1
  local bitIndex = index % 32
  local word = tonumber(words and words[wordIndex]) or 0
  return math.floor(word / (2 ^ bitIndex)) % 2 == 1
end

local function patchExpandedRegistries(Profile)
  local Pokemon = require("src.core.game3.pokemon")
  if not Pokemon.__radicalRedExpanded then
    Pokemon.__radicalRedExpanded = true
    local originalAbilities = Pokemon.abilities
    Pokemon.abilities = function(species)
      species = tonumber(species)
      if not species then return { 0, 0, 0 } end
      if not Pokemon._abilities then Pokemon.install(Pokemon._cache) end
      local row = Pokemon._abilities and Pokemon._abilities[species]
      if row then
        return { row[1] or 0, row[2] or 0, row[3] or row.hidden or 0 }
      end
      local pair = originalAbilities(species)
      return { pair[1] or 0, pair[2] or 0, 0 }
    end

    local originalAbilityId = Pokemon.abilityId
    Pokemon.abilityId = function(species, personality, abilityNum)
      local abilities = Pokemon.abilities(species)
      abilityNum = tonumber(abilityNum)
      if abilityNum == 2 and (abilities[3] or 0) ~= 0 then return abilities[3] end
      if abilityNum == 1 and (abilities[2] or 0) ~= 0 then return abilities[2] end
      return originalAbilityId(species, personality)
    end

    Pokemon.moveFromTmItem = function(itemId)
      local ItemsData = require("src.core.game3.items_data")
      local info = ItemsData.info(itemId)
      local number = info and tonumber(info.registrability)
      if not info or info.pocket ~= "TM_CASE" or not number
          or number < 1 or number > Profile.MACHINE_COUNT then return nil end
      if not Pokemon._tmhm then Pokemon.install(Pokemon._cache) end
      local machines = Pokemon._tmhm and Pokemon._tmhm.machines
      return machines and tonumber(machines[number - 1]) or nil
    end

    Pokemon.canLearnTmIndex = function(species, tmIndex)
      species, tmIndex = tonumber(species), tonumber(tmIndex)
      if not species or not tmIndex or tmIndex < 0
          or tmIndex >= Profile.MACHINE_COUNT then return false end
      if not Pokemon._tmhm then Pokemon.install(Pokemon._cache) end
      local row = Pokemon._tmhm and Pokemon._tmhm.learnsets
        and Pokemon._tmhm.learnsets[species]
      if not row then return false end
      local words = row.words or { row.lo or row[1] or 0, row.hi or row[2] or 0,
        row[3] or 0, row[4] or 0 }
      return bitSet(words, tmIndex)
    end

    Pokemon.canLearnTmItem = function(species, itemId)
      local ItemsData = require("src.core.game3.items_data")
      local info = ItemsData.info(itemId)
      local number = info and tonumber(info.registrability)
      if not info or info.pocket ~= "TM_CASE" or not number then return false end
      return Pokemon.canLearnTmIndex(species, number - 1)
    end
  end

  local ItemsData = require("src.core.game3.items_data")
  ItemsData.CAPACITY.TM_CASE = Profile.MACHINE_COUNT
  if not ItemsData.__radicalRedExpanded then
    ItemsData.__radicalRedExpanded = true
    local originalIsTm = ItemsData.isTm
    local originalTmNumber = ItemsData.tmNumber
    local originalIsHm = ItemsData.isHm

    ItemsData.tmNumber = function(id)
      local info = ItemsData.info(id)
      local number = info and tonumber(info.registrability)
      if info and info.pocket == "TM_CASE" and number
          and number >= 1 and number <= Profile.MACHINE_COUNT then
        return number
      end
      return originalTmNumber(id)
    end
    ItemsData.isTm = function(id)
      local info = ItemsData.info(id)
      local number = info and tonumber(info.registrability)
      if info and info.pocket == "TM_CASE" and number
          and number >= 1 and number <= Profile.MACHINE_COUNT then return true end
      return originalIsTm(id)
    end
    ItemsData.isHm = function(id)
      local info = ItemsData.info(id)
      local number = info and tonumber(info.registrability)
      if info and info.pocket == "TM_CASE" and number then
        return number > 120 and number <= Profile.MACHINE_COUNT
      end
      return originalIsHm(id)
    end
  end

  local MoveLearn = require("src.core.game3.move_learn")
  MoveLearn.TUTOR_MOVE_COUNT = Profile.TUTOR_COUNT
  if not MoveLearn.__radicalRedExpanded then
    MoveLearn.__radicalRedExpanded = true
    MoveLearn.canLearnTutorMove = function(species, tutor)
      species, tutor = tonumber(species), tonumber(tutor)
      if not species or not tutor or tutor < 0
          or tutor >= Profile.TUTOR_COUNT then return false end
      local sets = MoveLearn.tutorLearnsets()
      local row = sets and sets[species]
      if not row then return false end
      local words = type(row) == "table" and (row.words or row) or { tonumber(row) or 0 }
      return bitSet(words, tutor)
    end
  end

  local Dex = require("src.core.game3.dex")
  Dex.NATIONAL_MAX = Profile.NATIONAL_DEX_COUNT

  local Game3Profile = require("src.core.game3.profile").active()
  if Game3Profile and Game3Profile.species then
    Game3Profile.species.num = Profile.SPECIES_COUNT
    Game3Profile.species.egg = 412
  end
end

local function installChrome(cache)
  local names = {
    "src.ui.game3.party_chrome",
    "src.ui.game3.bag_chrome",
    "src.ui.game3.battle_chrome",
    "src.ui.game3.battle_transition_chrome",
    "src.ui.game3.summary_chrome",
    "src.ui.game3.shop_chrome",
    "src.ui.game3.pokedex_chrome",
    "src.ui.game3.naming_chrome",
  }
  for _, name in ipairs(names) do
    local ok, module = pcall(require, name)
    if ok and module and module.install then pcall(module.install, cache) end
  end
end

-- CFRU extends the save-variable bank into 0x5000..0x51FF.  The stock host's
-- VarGet helper deliberately recognizes only FireRed's 0x4000..0x40FF bank,
-- so a command such as `showmonpic 0x5124` otherwise treats 0x5124 itself as
-- a species.  Resolve the expanded operands at the supported script hook,
-- leaving destinations (`setvar`, comparisons, buffers) untouched.
local function installExpandedScriptVars(mod)
  if not (mod and mod.hooks and mod.hooks.wrap) then return false end
  if mod.__rrExpandedScriptVars then return true end

  local Flags = require("src.core.game3.scripting.flags")
  local operandNames = {
    showmonpic = { [1] = "species" },
    givemon = { [1] = "species", [2] = "level" },
    giveegg = { [1] = "species" },
    playmoncry = { [1] = "species", [2] = "mode" },
  }

  local function isExpandedVar(value)
    value = tonumber(value)
    return value and value >= 0x5000 and value <= 0x51FF
  end

  mod.hooks:wrap("script.command", function(next, ctx, op, row)
    local operands = operandNames[op]
    if not operands or type(row) ~= "table" then
      return next(ctx, op, row)
    end
    local rawSpecies = row[1]
    if rawSpecies == nil then rawSpecies = row.species end
    -- The regional picker has already selected the exact starter in 0x5124.
    -- Species randomization is a separate cartridge option and must not run a
    -- second time when that one gift command reaches Party.giveMon.
    local preserveRegionalStarter = op == "givemon"
      and tonumber(rawSpecies) == 0x5124
    local runner = ctx and ctx.runner
    local store = runner and runner.store
    local scriptCtx = runner and runner.ctx
    local copy
    for index, name in pairs(operands) do
      local raw = row[index]
      if raw == nil then raw = row[name] end
      if isExpandedVar(raw) then
        copy = copy or (function()
          local out = {}
          for key, value in pairs(row) do out[key] = value end
          return out
        end)()
        local resolved = Flags.getVar(store, scriptCtx, raw)
        copy[index] = resolved
        if copy[name] ~= nil then copy[name] = resolved end
      end
    end
    if not preserveRegionalStarter then
      return next(ctx, op, copy or row)
    end
    local prior = mod.__rrPreserveRegionalStarter
    mod.__rrPreserveRegionalStarter = true
    local result = { pcall(next, ctx, op, copy or row) }
    mod.__rrPreserveRegionalStarter = prior
    if not result[1] then error(result[2], 0) end
    return unpack(result, 2, #result)
  end, 9000)
  mod.__rrExpandedScriptVars = true
  return true
end


local function installSaveTransferBridge(Profile)
  local okImporter, RomImporter = pcall(require, "src.import.RomImporter")
  local okIo, SaveFileIO = pcall(require, "src.import.SaveFileIO")
  if not (okImporter and okIo and RomImporter and SaveFileIO) then return false end
  if RomImporter.__radicalRedSaveBridge then return true end

  local SaveData = require("src.core.SaveData")
  local SaveSerializer = require("src.core.SaveSerializer")
  local BASE_VERSION = "firered"
  local MOD_ID = "radical_red_experience"
  local CART_ID = Profile.ID
  local LUA_LIMITS = {
    maxBytes = 16 * 1024 * 1024,
    maxNodes = 262144,
    maxTableEntries = 8192,
    rootName = "save",
  }

  local function rrEnabled(version)
    if version ~= BASE_VERSION then return false end
    local ok, opts = pcall(SaveData.loadOptions)
    if not ok or type(opts) ~= "table" then opts = {} end
    local scope = SaveData.modScope and SaveData.modScope(version) or version
    local chosen = SaveData.modEnabled and SaveData.modEnabled(opts, MOD_ID, scope)
    -- This bridge only exists after Radical Red has loaded once in this
    -- process, so an unanswered toggle means the loader's normal enabled
    -- default. A deliberate disable immediately returns the launcher to its
    -- ordinary FireRed save card without restarting.
    return chosen ~= false
  end

  local function readSource(source)
    local t = type(source)
    if t == "table" or t == "userdata" then
      if type(source.read) ~= "function" then return nil, "that file could not be read" end
      local ok, err = source:open("r")
      if not ok then return nil, "could not open the dropped file: " .. tostring(err) end
      local bytes, readErr = source:read(source:getSize())
      source:close()
      if type(bytes) ~= "string" then
        return nil, "could not read the dropped file: " .. tostring(readErr)
      end
      return bytes
    end
    if t ~= "string" then return nil, "no save file was provided" end
    if source:find("^%s*return[%s{]") then return source end
    local file = io.open(source, "rb")
    if file then
      local bytes = file:read("*a")
      file:close()
      if type(bytes) == "string" then return bytes end
    end
    if love and love.filesystem and love.filesystem.read then
      local ok, bytes = pcall(love.filesystem.read, source)
      if ok and type(bytes) == "string" then return bytes end
    end
    return nil, "could not read the save file"
  end

  local function importOriginalSlot(source)
    local bytes, readErr = readSource(source)
    if not bytes then return false, readErr end
    if not bytes:find("^%s*return[%s{]") then
      return false, "Radical Red imports use Original save (.lua)."
    end
    local save, parseErr = SaveSerializer.decode(bytes, LUA_LIMITS)
    if type(save) ~= "table" then
      return false, "That .lua file is not a readable save (" .. tostring(parseErr) .. ")."
    end

    -- The broken v0.5.18 transfer experiment could stamp the private runtime
    -- overlay id into an otherwise-valid RR save. Accept it once and normalize
    -- back to FireRed, which is the public launcher game the conversion owns.
    if save.version == "radical_red_runtime" then save.version = BASE_VERSION end
    if save.version ~= BASE_VERSION
        or (save.generation ~= nil and tonumber(save.generation) ~= 3)
        or (save.engine ~= nil and save.engine ~= "game3")
        or type(save.party) ~= "table" then
      return false, "That .lua file is not a Radical Red / FireRed save."
    end

    save.meta = type(save.meta) == "table" and save.meta or {}
    save.meta.cartId = CART_ID
    save.meta.cartHash = Profile.SHA1

    local slotId = SaveData.createCartSlot(CART_ID)
    if not slotId then return false, "could not create a Radical Red save slot" end
    local ok, err = SaveData.writeCartSlot(CART_ID, slotId, save)
    if not ok then
      SaveData.deleteCartSlot(CART_ID, slotId)
      return false, "could not write the imported save: " .. tostring(err)
    end
    if not SaveData.readCartSlotSource(CART_ID, slotId) then
      SaveData.deleteCartSlot(CART_ID, slotId)
      return false, "the imported save did not read back; nothing was imported"
    end
    SaveData.setActiveCartSlot(CART_ID, slotId)
    return true, slotId
  end

  -- Keep the FireRed launcher tab selected. The save CARD is redirected to the
  -- private Radical Red namespace only while the mod is enabled; no
  -- GameVersion.set("radical_red_runtime") and no fake cart selection occurs.
  local originalRefreshSlots = RomImporter._refreshSlots
  RomImporter._refreshSlots = function(self, scope)
    if rrEnabled(scope) then
      self.slots[scope] = SaveData.listCartSlots(CART_ID) or {}
      local opts = SaveData.loadOptions()
      local reg = opts.cartSlots and opts.cartSlots[CART_ID]
      self.activeSlot[scope] =
        reg and (reg.active or (reg.list and reg.list[1])) or nil
      return
    end
    return originalRefreshSlots(self, scope)
  end

  local originalSelectSlot = RomImporter._selectSlot
  RomImporter._selectSlot = function(self, scope, id)
    if rrEnabled(scope) then
      SaveData.setActiveCartSlot(CART_ID, id)
      self.activeSlot[scope] = id
      return
    end
    return originalSelectSlot(self, scope, id)
  end

  local originalNewSlot = RomImporter._newSlot
  RomImporter._newSlot = function(self, scope)
    if rrEnabled(scope) then
      local id = SaveData.createCartSlot(CART_ID)
      if id then SaveData.setActiveCartSlot(CART_ID, id) end
      self:_refreshSlots(scope)
      self.activeSlot[scope] = id
      self.slotScroll[scope] = math.huge
      return
    end
    return originalNewSlot(self, scope)
  end

  local originalDeleteSlot = RomImporter._deleteSlot
  RomImporter._deleteSlot = function(self, scope, id)
    if rrEnabled(scope) then
      if self.workState == "working" then return end
      local ok, err = SaveData.deleteCartSlot(CART_ID, id)
      if ok then
        self:_refreshSlots(scope)
        self.saveNotice[scope] = { ok = true, text = "Deleted " .. tostring(id) .. "." }
      else
        self.saveNotice[scope] = { ok = false, text = tostring(err) }
      end
      return
    end
    return originalDeleteSlot(self, scope, id)
  end

  local originalCommitRename = RomImporter._commitRename
  RomImporter._commitRename = function(self)
    local row = self._rename
    if row and rrEnabled(row.version) then
      self._rename = nil
      if self._disarmTextInput then self:_disarmTextInput() end
      SaveData.renameCartSlot(CART_ID, row.id, row.text)
      self:_refreshSlots(row.version)
      return
    end
    return originalCommitRename(self)
  end

  local originalImport = RomImporter._importSave
  RomImporter._importSave = function(self, version, source, force)
    if rrEnabled(version) then
      if self.workState == "working" then return end
      -- Do not mutate self.tab here: importing an RR save is a save operation,
      -- not a game-selection operation.
      local ok, slotOrErr = importOriginalSlot(source)
      if ok then
        self:_refreshSlots(version)
        self.activeSlot[version] = slotOrErr
        self.slotScroll[version] = math.huge
        self.saveNotice[version] = {
          ok = true, text = "Imported Radical Red save into " .. tostring(slotOrErr) .. ".",
        }
      else
        self.saveNotice[version] = { ok = false, text = tostring(slotOrErr) }
      end
      return
    end
    return originalImport(self, version, source, force)
  end

  local originalExportLua = SaveFileIO.exportLuaSlot
  SaveFileIO.exportLuaSlot = function(version, slotId, cartId)
    if cartId == nil and rrEnabled(version) then cartId = CART_ID end
    return originalExportLua(version, slotId, cartId)
  end

  local originalExportActive = SaveFileIO.exportActiveSlot
  SaveFileIO.exportActiveSlot = function(version)
    version = version or require("src.core.GameVersion").get()
    if rrEnabled(version) then
      return false, "Radical Red exports use Original save (.lua)."
    end
    return originalExportActive(version)
  end

  -- The stock editor mounts FireRed's generated dataset. Letting it open a
  -- Radical Red slot would display/validate expanded species against the wrong
  -- tables. Keep the button harmless until the editor can mount this mod cache.
  local originalNew = RomImporter.new
  RomImporter.new = function(onComplete, opts)
    local self = originalNew(onComplete, opts)
    if self and self.onEditSave then
      local edit = self.onEditSave
      self.onEditSave = function(version, slotId)
        if rrEnabled(version) then
          self.saveNotice[version] = {
            ok = false,
            text = "Edit save is disabled for Radical Red saves; Import/Export remain available.",
          }
          return
        end
        return edit(version, slotId)
      end
    end
    return self
  end

  RomImporter.__radicalRedSaveBridge = {
    version = BASE_VERSION,
    cartId = CART_ID,
  }
  return true
end

function Runtime.install(mod, Profile, RR_Encounters)
  assert(mod and mod.game, "Radical Red requires the live Game3 service")
  local Versions = require("src.import.gba.versions")
  Profile.apply(Versions)
  local overlay = installCacheOverlay(mod, Profile)
  local saveTransferBridge = installSaveTransferBridge(Profile)
  local physicalRoot = Profile.runtimeRoot(
    (mod.manifest and mod.manifest.id) or "radical_red_experience")

  local Dataset = require("src.core.game3.dataset")
  local CachePaths = require("src.core.game3.cache_paths")
  local Extract = require("src.import.gba.extract_island1")
  Dataset.cacheRootOverride = physicalRoot
  CachePaths.setRoot(physicalRoot)
  Extract.CACHE_ROOT = physicalRoot
  Extract.NATIVE_ROOT = physicalRoot .. "/native"
  installScriptShardLoader()
  local normalizeMapBounds = installTrueMapBounds()

  local SaveData = require("src.core.SaveData")
  SaveData.setCart(Profile.ID, Profile.SHA1)
  if SaveData.refreshSlotResolution then SaveData.refreshSlotResolution() end

  invalidateLoadedModules()
  Dataset.hydrate(mod.game)
  assert(RR_Encounters and RR_Encounters.install,
    "Radical Red encounter runtime was not loaded")
  local encounterReport = RR_Encounters.install(Profile)
  local layoutCount, croppedLayouts = 0, 0
  for _, def in pairs((mod.game.data and mod.game.data.maps) or {}) do
    if def and def.midLayout then
      local padded = normalizeMapBounds(def.midLayout)
      assert(def.midLayout.width == def.width and def.midLayout.height == def.height,
        "Radical Red live map dimensions diverged after normalization")
      -- The engine derives one 25x25 wireless plaza from Union Room after
      -- hydration. It is not one of the cartridge's 425 layouts.
      if not def._plazaSource then
        layoutCount = layoutCount + 1
        if padded then croppedLayouts = croppedLayouts + 1 end
      end
    end
  end
  assert(layoutCount == Profile.MAP_COUNT,
    ("Radical Red runtime attached %d/%d map layouts")
      :format(layoutCount, Profile.MAP_COUNT))
  assert(croppedLayouts == 306,
    "Radical Red runtime odd-layout census changed: " .. tostring(croppedLayouts))
  local cache = Dataset.cache()

  local ItemsData = require("src.core.game3.items_data")
  ItemsData.install(cache)
  patchExpandedRegistries(Profile)
  local expandedScriptVars = installExpandedScriptVars(mod)

  local Moves = require("src.core.game3.battle.moves")
  Moves._romLoaded = false
  Moves._rom = nil
  Moves.loadRomPack(cache)

  local Audio = require("src.core.game3.audio")
  local okAudio, audioErr = Audio.install(cache, { root = physicalRoot .. "/audio" })
  assert(okAudio, "Radical Red audio pack failed to install: " .. tostring(audioErr))

  -- The stock host's FireRed pack only knows cries for the original species
  -- range. RR's extraction writes a separate map because DPE's expanded
  -- gCryTable is indexed directly by internal species id.
  local cryIdPath = physicalRoot .. "/audio/rr_cry_ids.lua"
  local cryIdSource = assert(cache:read(cryIdPath),
    "Radical Red expanded cry-id map is missing")
  local cryChunk, cryLoadErr = load(cryIdSource, "@" .. cryIdPath, "t", {})
  assert(cryChunk, "Radical Red cry-id map would not load: " .. tostring(cryLoadErr))
  local cryOk, cryIds = pcall(cryChunk)
  assert(cryOk and type(cryIds) == "table",
    "Radical Red cry-id map is invalid")
  assert(cryIds[1] == 1
      and cryIds[Profile.SPECIES_COUNT - 1] == Profile.SPECIES_COUNT - 1,
    "Radical Red cry-id map does not cover the expanded species table")
  assert(Audio._pack and Audio._pack.index and Audio._pack.index.cries,
    "Radical Red expanded cry pack was not installed")
  assert(tonumber(Audio._pack.index.cryCount) == Profile.SPECIES_COUNT,
    ("Radical Red cry pack has %s/%d rows")
      :format(tostring(Audio._pack.index.cryCount), Profile.SPECIES_COUNT))
  Audio._pack.index.cryIds = cryIds

  installChrome(cache)
  local Help = require("src.ui.game3.help_system")
  if Help.reset then Help.reset() end
  if Help.install then Help.install(cache) end
  local QuestLog = require("src.ui.game3.quest_log")
  if QuestLog.install then QuestLog.install(cache) end

  if mod.game._exposeModData then mod.game:_exposeModData() end

  return {
    root = physicalRoot,
    overlay = overlay.versionId,
    maps = mod.game.data and mod.game.data.maps,
    species = Profile.SPECIES_COUNT,
    moves = Profile.MOVE_COUNT,
    saveScope = Profile.ID,
    saveTransferBridge = saveTransferBridge == true,
    expandedCries = true,
    cryCount = Audio._pack.index.cryCount,
    cryMappedSpecies = Profile.SPECIES_COUNT - 1,
    expandedScriptVars = expandedScriptVars,
    trueMapBounds = true,
    mapLayoutsAudited = layoutCount,
    paddedLayoutsCropped = croppedLayouts,
    encounters = encounterReport,
  }
end

Runtime._installSaveTransferBridge = installSaveTransferBridge

return Runtime
