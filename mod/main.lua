-- Radical Red v4.1 total-conversion bootstrap.
--
-- The launcher validates the player's private ROM. Before Game3 creates its
-- boot screen, this entry extracts (once), mounts, and rehydrates that ROM as
-- the live dataset. No launcher/executable/engine file is modified.

local function loadLocal(mod, path)
  local source = assert(mod:read(path))
  return assert(load(source, "@" .. path))()
end

return function(mod)
  assert(mod.generation == 3,
    "Radical Red requires a Generation III / FireRed session")

  local Profile = loadLocal(mod, "lib/rr_profile.lua")
  local RR = loadLocal(mod, "lib/rr_rom.lua")
  local StreamRom = loadLocal(mod, "lib/rr_stream_rom.lua")
  local Visuals = loadLocal(mod, "lib/rr_visuals.lua")
  local World = loadLocal(mod, "lib/rr_world.lua")
  local Encounters = loadLocal(mod, "lib/rr_encounters.lua")
  local ListMenus = loadLocal(mod, "lib/rr_listmenus.lua")
  local Extractor = loadLocal(mod, "lib/rr_extract.lua")
  local Runtime = loadLocal(mod, "lib/rr_runtime.lua")
  local Battle = loadLocal(mod, "lib/rr_battle.lua")
  local Natives = loadLocal(mod, "lib/rr_natives.lua")
  local Mechanics = loadLocal(mod, "lib/rr_mechanics.lua")
  local Randomizer = loadLocal(mod, "lib/rr_randomizer.lua")
  local Facilities = loadLocal(mod, "lib/rr_facilities.lua")
  local Raids = loadLocal(mod, "lib/rr_raids.lua")
  local Story = loadLocal(mod, "lib/rr_story.lua")
  local Qol = loadLocal(mod, "lib/rr_qol.lua")

  mod.exports.species = Profile.SPECIES_COUNT
  mod.exports.moves = Profile.MOVE_COUNT
  mod.exports.maps = Profile.MAP_COUNT
  mod.exports.abilities = Profile.ABILITY_COUNT
  mod.exports.items = Profile.ITEM_COUNT

  -- Install the RR-expanded object palette reader before either the cached or
  -- cold extraction path can load overworld graphics.
  local visualProfile = Visuals.installExtraction(Profile)

  local function publish(reports)
    mod.exports.phase = "RR_RUNTIME_DATASET"
    mod.exports.sourceVersion = RR.SOURCE_VERSION
    mod.exports.sourceReport = reports.source
    mod.exports.extractReport = reports.extract
    mod.exports.runtimeReport = reports.runtime
    mod.exports.battleReport = reports.battle
    mod.exports.nativeReport = reports.native
    mod.exports.mechanicsReport = reports.mechanics
    mod.exports.randomizerReport = reports.randomizer
    mod.exports.facilityReport = reports.facilities
    mod.exports.raidReport = reports.raids
    mod.exports.storyReport = reports.story
    mod.exports.qolReport = reports.qol
    mod.exports.visualReport = reports.visuals
  end

  local function activate(onProgress)
    local function step(stage, cur, total)
      if onProgress then onProgress(stage, cur, total) end
    end

    step("source", 0, 1)
    local rom = RR.open(mod.imports, RR.IMPORT_ID)
    local reports = { source = rom:verify() }
    step("source", 1, 1)

    reports.extract = Extractor.ensure(mod, Profile, {
      world = World,
      encounters = Encounters,
      listMenus = ListMenus,
      streamRom = StreamRom,
      onProgress = onProgress,
    })

    collectgarbage("collect")
    step("runtime", 0, 9)
    reports.runtime = Runtime.install(mod, Profile, Encounters)
    reports.visuals = Visuals.installRuntime(Profile)
    for key, value in pairs(visualProfile) do reports.visuals[key] = value end
    local paletteReport = Visuals.report()
    if paletteReport then
      for key, value in pairs(paletteReport) do reports.visuals[key] = value end
    end
    step("runtime", 1, 9)
    reports.battle = Battle.install(rom)
    step("runtime", 2, 9)
    reports.native = Natives.install(mod)
    step("runtime", 3, 9)
    reports.mechanics = Mechanics.install(mod, rom)
    reports.randomizer = Randomizer.install(mod, rom)
    step("runtime", 4, 9)
    reports.facilities = Facilities.install(mod, rom)
    step("runtime", 5, 9)
    reports.raids = Raids.install(mod, rom)
    step("runtime", 6, 9)
    reports.story = Story.install(mod, {
      getFollowerState = function() return Natives._state.follower end,
    })
    step("runtime", 7, 9)
    reports.qol = Qol.install(mod)
    step("runtime", 8, 9)
    step("runtime", 9, 9)
    return reports
  end

  local function refreshTitle(game, rebuild)
    if rebuild and game and game.returnToTitle then game:returnToTitle() end
    local SaveData = require("src.core.SaveData")
    local Boot = require("src.ui.game3.boot")
    local Options = require("src.core.game3.options")
    local okSave, save, recovered = pcall(SaveData.load)
    if not okSave then save, recovered = nil, nil end
    local hasContinue = game and game._hasContinueSave
      and game:_hasContinueSave() or false
    if game and game.boot then
      Boot.setHasContinue(game.boot, hasContinue)
      Boot.setContinueInfo(game.boot,
        hasContinue and Boot.continueInfoFromSave(save) or nil)
      Boot.setSaveStatus(game.boot, recovered and "error" or "ok")
      local options = SaveData.loadOptions and SaveData.loadOptions()
      if type(options) == "table" then
        game.options = options
        if game.applyOptions then game:applyOptions(options) end
        Boot.setTextSpeed(game.boot, Options.block(options).textSpeed)
      end
    end
  end

  local function announceActive(game, rebuild)
    refreshTitle(game, rebuild)
    mod.log:info(("Radical Red v4.1 active: %d maps, %d species, %d moves; save scope %s")
      :format(Profile.MAP_COUNT, Profile.SPECIES_COUNT, Profile.MOVE_COUNT,
        Profile.ID))
  end

  -- A completed cache is small enough to mount synchronously.  A cold cache
  -- is intentionally different: Android may kill an Activity that spends the
  -- whole Play transition doing CPU and disk work without presenting frames.
  -- Let Game3 finish creating its window, then advance the extraction
  -- coroutine from core.update while render.hud owns a visible setup screen.
  if Extractor.markerReady(mod.cache, Profile) then
    publish(activate(nil))
    mod.exports.bootstrap = { mode = "cached", state = "ready" }
    mod.events:on("game.ready", function(payload)
      announceActive((payload and payload.game) or mod.game, false)
    end)
    return
  end

  local boot = {
    phase = "waiting",
    stage = "starting",
    current = 0,
    total = 1,
    game = nil,
    co = nil,
    reports = nil,
    err = nil,
  }
  mod.exports.phase = "RR_PREPARING"
  mod.exports.bootstrap = { mode = "nonblocking", state = "waiting" }

  local function checkpoint(stage, cur, total)
    boot.stage = tostring(stage or "working")
    boot.current = tonumber(cur) or 0
    boot.total = math.max(tonumber(total) or 1, 1)
    mod.exports.bootstrap.state = "extracting"
    mod.exports.bootstrap.stage = boot.stage
    mod.exports.bootstrap.current = boot.current
    mod.exports.bootstrap.total = boot.total
    coroutine.yield()
  end

  local function fail(err)
    boot.phase = "failed"
    boot.err = tostring(err or "unknown conversion error")
    mod.exports.phase = "RR_SETUP_ERROR"
    mod.exports.bootstrap.state = "failed"
    mod.exports.bootstrap.error = boot.err
    if mod.log and mod.log.error then
      pcall(mod.log.error, mod.log,
        "Radical Red first-launch setup failed: " .. boot.err)
    end
    pcall(function()
      mod.cache:write("diagnostics/last_boot_error.txt",
        "Radical Red 0.5.15 first-launch setup failed\n"
          .. "stage=" .. tostring(boot.stage) .. "\n"
          .. boot.err .. "\n")
    end)
  end

  local function finish()
    -- Game3 already crossed its normal post-loader merge boundary while the
    -- converter was running, so repeat those two cheap post-merge installs
    -- against the newly hydrated Radical Red dataset.
    require("src.core.Strings").load(boot.game and boot.game.data or {})
    local Gen3Compat = require("src.mods.Gen3Compat")
    if Gen3Compat.applyMerged then Gen3Compat.applyMerged(boot.game) end
    announceActive(boot.game, true)
    publish(assert(boot.reports, "Radical Red setup reports are missing"))
    boot.phase = "ready"
    boot.co = nil
    mod.exports.bootstrap.state = "ready"
    pcall(function() mod.cache:delete("diagnostics/last_boot_error.txt") end)
  end

  mod.events:on("game.ready", function(payload)
    boot.game = (payload and payload.game) or mod.game
    boot.phase = "extracting"
    mod.exports.bootstrap.state = "extracting"
    boot.co = coroutine.create(function()
      boot.reports = activate(checkpoint)
    end)
  end)

  mod.hooks:wrap("core.update", function(next, game, dt)
    if boot.phase == "extracting" then
      local ok, err = coroutine.resume(boot.co)
      if not ok then
        fail(err)
      elseif coroutine.status(boot.co) == "dead" then
        local done, finishErr = pcall(finish)
        if not done then fail(finishErr) end
      end
      -- Keep the vanilla title state still while private data is changing.
      return
    elseif boot.phase == "failed" or boot.phase == "waiting" then
      return
    end
    return next(game, dt)
  end, 10000)

  local labels = {
    source = "Checking the Radical Red v4.1 ROM",
    catalog = "Reading the map catalogue",
    world_census = "Finding Radical Red maps",
    world_scripts = "Converting story scripts and text",
    world_warps = "Converting warps and connections",
    world_tilesets = "Converting maps and tilesets",
    world_aux = "Converting world systems",
    world = "Finishing the world cache",
    pokemon = "Converting Pokemon sprites and data",
    learnsets = "Converting learnsets",
    battle_moves = "Converting battle moves",
    party_chrome = "Converting party graphics",
    battle_chrome = "Converting battle graphics",
    battle_transition = "Converting battle transitions",
    summary_chrome = "Converting summary graphics",
    bag_chrome = "Converting Bag graphics",
    shop_chrome = "Converting shop graphics",
    pokedex_entries = "Converting Pokedex entries",
    pokedex_categories = "Converting Pokedex categories",
    pokedex_orders = "Converting Pokedex order",
    pokedex_done = "Finishing the Pokedex",
    trainers = "Converting trainers",
    battle_ai = "Converting trainer AI",
    expanded_tables = "Building expanded registries",
    interface = "Converting interface graphics",
    rom_assets = "Converting title, naming, and audio assets",
    runtime = "Starting Radical Red",
  }
  local titleFont, bodyFont
  mod.hooks:wrap("render.hud", function(next, game, viewport)
    next(game, viewport)
    if boot.phase == "ready" then return end
    local g = love and love.graphics
    if not (g and g.rectangle and g.printf) then return end
    local w = (viewport and viewport.width) or g.getWidth()
    local h = (viewport and viewport.height) or g.getHeight()
    if g.origin then g.origin() end
    if not titleFont and g.newFont then
      local okTitle, madeTitle = pcall(g.newFont, math.max(22, math.floor(h / 25)))
      local okBody, madeBody = pcall(g.newFont, math.max(14, math.floor(h / 42)))
      if okTitle then titleFont = madeTitle end
      if okBody then bodyFont = madeBody end
    end
    g.setColor(0.025, 0.035, 0.06, 1)
    g.rectangle("fill", 0, 0, w, h)
    if titleFont then g.setFont(titleFont) end
    g.setColor(0.95, 0.18, 0.22, 1)
    local top = math.floor(h * 0.22)
    local heading = boot.phase == "failed"
      and "Radical Red setup stopped" or "Preparing Radical Red"
    g.printf(heading, math.floor(w * 0.08), top, math.floor(w * 0.84), "center")
    if bodyFont then g.setFont(bodyFont) end
    if boot.phase == "failed" then
      g.setColor(1, 0.86, 0.86, 1)
      g.printf("The game is still running. Take a screenshot of this message:\n\n"
        .. tostring(boot.err), math.floor(w * 0.1), top + math.floor(h * 0.12),
        math.floor(w * 0.8), "left")
      return
    end
    local label = labels[boot.stage] or ("Working: " .. tostring(boot.stage))
    local detail = ""
    if boot.total > 1 then
      detail = ("  %d / %d"):format(math.min(boot.current, boot.total), boot.total)
    end
    g.setColor(0.94, 0.96, 1, 1)
    g.printf(label .. detail, math.floor(w * 0.08), top + math.floor(h * 0.13),
      math.floor(w * 0.84), "center")
    local barX, barY = math.floor(w * 0.15), top + math.floor(h * 0.23)
    local barW, barH = math.floor(w * 0.7), math.max(10, math.floor(h * 0.018))
    local ratio = math.max(0, math.min(1, boot.current / boot.total))
    g.setColor(0.16, 0.19, 0.26, 1)
    g.rectangle("fill", barX, barY, barW, barH)
    g.setColor(0.86, 0.12, 0.18, 1)
    g.rectangle("fill", barX, barY, math.floor(barW * ratio), barH)
    g.setColor(0.7, 0.75, 0.84, 1)
    g.printf("First launch only. Keep the app open; this can take several minutes.",
      math.floor(w * 0.1), barY + math.floor(h * 0.06), math.floor(w * 0.8), "center")
  end, 10000)

end
