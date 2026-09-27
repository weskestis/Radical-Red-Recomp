package.path = "./?.lua;./?/init.lua;" .. package.path

-- Fast orchestration test for the current total-conversion bootstrap.  The
-- real extraction/mount path is exercised by engine_loader_test; this test
-- makes sure main.lua cannot regress to the obsolete CP2 species overlay and
-- that enabling the mod installs every runtime layer automatically.

local loaded, installed = {}, {}
local moduleSources = {
  ["lib/rr_profile.lua"] = [[return {
    ID="radical_red_4_1", SPECIES_COUNT=1376, MOVE_COUNT=1004,
    MAP_COUNT=425, ABILITY_COUNT=282, ITEM_COUNT=750, OW_COUNT=257,
    OW_TOTAL_COUNT=545, OW_PALETTE_COUNT=451, OW_USED_PALETTE_COUNT=397,
  }]],
  ["lib/rr_rom.lua"] = [[return {
    IMPORT_ID="radical_red_v4_1", SOURCE_VERSION="v4.1",
    open=function(imports, id)
      assert(imports and id == "radical_red_v4_1")
      return { verify=function() return { verified=true } end }
    end,
  }]],
  ["lib/rr_world.lua"] = [[return { run=function() end }]],
  ["lib/rr_encounters.lua"] = [[return {}]],
  ["lib/rr_listmenus.lua"] = [[return { write=function() end }]],
  ["lib/rr_stream_rom.lua"] = [[return { open=function() end }]],
  ["lib/rr_visuals.lua"] = [[return {
    installExtraction=function(profile)
      _G.__rrInstalled.visualExtraction=true
      return { paletteCount=profile.OW_PALETTE_COUNT or 451,
        spriteCount=profile.OW_TOTAL_COUNT or 545 }
    end,
    installRuntime=function()
      _G.__rrInstalled.visuals=true
      return { optionsDraw=true, optionsFallbackGuard=true,
        portableOptionsDraw=true, gameModesChoiceDraw=true,
        portableChoiceDraw=true, gameModesFadeGuard=true,
        setupMessageFadeGuard=true,
        summaryDetailLayout=true, partyGridLayout=true,
        expandedGraphicsIds=true, expandedGraphicsTables=true,
        objectGraphicsSelector=true, battleSpriteCoords=true,
        battleSpriteCoordSpecies=1376, cyndaquilBackYOffset=3,
        fixedHealthbox=true }
    end,
    report=function() return { usedPaletteCount=397 } end,
  }]],
  ["lib/rr_extract.lua"] = [[return {
    markerReady=function() return true end,
    ensure=function(mod, profile, opts)
    assert(opts and opts.world and type(opts.world.run) == "function")
    assert(opts.listMenus and type(opts.listMenus.write) == "function")
    assert(opts.streamRom and type(opts.streamRom.open) == "function")
    _G.__rrInstalled.world=true
    _G.__rrInstalled.extract=true
    return { cached=true, maps=profile.MAP_COUNT }
  end }]],
  ["lib/rr_runtime.lua"] = [[return { install=function(mod, profile)
    _G.__rrInstalled.runtime=true
    return { saveScope=profile.ID, maps=profile.MAP_COUNT }
  end }]],
  ["lib/rr_battle.lua"] = [[return { install=function()
    _G.__rrInstalled.battle=true
    return { moveCategories=1004, fairyTypeId=23 }
  end }]],
  ["lib/rr_natives.lua"] = [[return {
    _state={ follower={ active=true } },
    install=function() _G.__rrInstalled.natives=true; return { specials=26 } end,
  }]],
  ["lib/rr_mechanics.lua"] = [[return { install=function()
    _G.__rrInstalled.mechanics=true; return { nativeCallbacks=22 }
  end }]],
  ["lib/rr_randomizer.lua"] = [[return { install=function()
    _G.__rrInstalled.randomizer=true
    return { cartridgeSetup=true, fixedRivals=true }
  end }]],
  ["lib/rr_facilities.lua"] = [[return { install=function()
    _G.__rrInstalled.facilities=true; return { nativeCallbacks=10 }
  end }]],
  ["lib/rr_raids.lua"] = [[return { install=function()
    _G.__rrInstalled.raids=true; return { specialCallbacks=8, battleHooks=true }
  end }]],
  ["lib/rr_story.lua"] = [[return { install=function(mod, deps)
    assert(deps.getFollowerState().active == true)
    _G.__rrInstalled.story=true; return { nativeCallbacks=18 }
  end }]],
  ["lib/rr_qol.lua"] = [[return { install=function()
    _G.__rrInstalled.qol=true
    return { runningShoes=true, dexAll=true, teamPreview=true, ezCatch=true,
      dexNavReliableFieldEdge=true, dexNavFieldSelect=true }
  end }]],
}

_G.__rrInstalled = installed

local bootCalls = {}
package.preload["src.core.SaveData"] = function()
  return {
    load = function() return { playerName = "RED" }, false end,
    loadOptions = function() return { textSpeed = 2 } end,
  }
end
package.preload["src.ui.game3.boot"] = function()
  return {
    setHasContinue = function(_, value) bootCalls.hasContinue = value end,
    continueInfoFromSave = function(save) return save.playerName end,
    setContinueInfo = function(_, value) bootCalls.continueInfo = value end,
    setSaveStatus = function(_, value) bootCalls.saveStatus = value end,
    setTextSpeed = function(_, value) bootCalls.textSpeed = value end,
  }
end
package.preload["src.core.game3.options"] = function()
  return { block = function(options) return options end }
end

local ready
local game = {
  boot = {},
  _hasContinueSave = function() return true end,
  applyOptions = function(self, options) self.appliedOptions = options end,
}
local mod = {
  generation = 3,
  imports = {},
  cache = {},
  game = game,
  exports = {},
  events = { on = function(_, name, callback)
    assert(name == "game.ready")
    ready = callback
  end },
  log = { info = function(_, message) loaded[#loaded + 1] = message end },
}
function mod:read(path)
  return assert(moduleSources[path], "unexpected module read: " .. tostring(path))
end

local entry = assert(loadfile("mods/radical_red_experience/main.lua"))()
entry(mod)

for _, name in ipairs({
  "world", "extract", "runtime", "battle", "natives", "mechanics",
  "randomizer", "facilities", "raids", "story", "qol", "visualExtraction", "visuals",
}) do
  assert(installed[name], "main did not install " .. name)
end
assert(mod.exports.phase == "RR_RUNTIME_DATASET")
assert(mod.exports.sourceVersion == "v4.1")
assert(mod.exports.species == 1376 and mod.exports.moves == 1004)
assert(mod.exports.maps == 425 and mod.exports.abilities == 282
  and mod.exports.items == 750)
assert(mod.exports.storyReport.nativeCallbacks == 18)
assert(mod.exports.qolReport.runningShoes == true)
assert(mod.exports.qolReport.dexAll == true)
assert(mod.exports.qolReport.teamPreview == true)
assert(mod.exports.qolReport.ezCatch == true)
assert(mod.exports.qolReport.dexNavReliableFieldEdge == true)
assert(mod.exports.qolReport.dexNavFieldSelect == true)
assert(mod.exports.visualReport.optionsDraw == true)
assert(mod.exports.visualReport.optionsFallbackGuard == true)
assert(mod.exports.visualReport.portableOptionsDraw == true)
assert(mod.exports.visualReport.gameModesChoiceDraw == true)
assert(mod.exports.visualReport.portableChoiceDraw == true)
assert(mod.exports.visualReport.gameModesFadeGuard == true)
assert(mod.exports.visualReport.setupMessageFadeGuard == true)
assert(mod.exports.visualReport.summaryDetailLayout == true)
assert(mod.exports.visualReport.partyGridLayout == true)
assert(mod.exports.visualReport.expandedGraphicsIds == true)
assert(mod.exports.visualReport.expandedGraphicsTables == true)
assert(mod.exports.visualReport.objectGraphicsSelector == true)
assert(mod.exports.visualReport.battleSpriteCoords == true)
assert(mod.exports.visualReport.battleSpriteCoordSpecies == 1376)
assert(mod.exports.visualReport.cyndaquilBackYOffset == 3)
assert(mod.exports.visualReport.fixedHealthbox == true)
assert(mod.exports.visualReport.paletteCount == 451)
assert(mod.exports.visualReport.spriteCount == 545)
assert(mod.exports.visualReport.usedPaletteCount == 397)
assert(mod.exports.randomizerReport.fixedRivals == true)
assert(type(ready) == "function")

ready({ game = game })
assert(bootCalls.hasContinue == true and bootCalls.continueInfo == "RED")
assert(bootCalls.saveStatus == "ok" and bootCalls.textSpeed == 2)
assert(game.appliedOptions and game.appliedOptions.textSpeed == 2)
assert(#loaded == 1 and loaded[1]:find("Radical Red v4.1 active", 1, true))

_G.__rrInstalled = nil
print("PASS main_overlay_test: enabling the mod installs the complete RR runtime stack")
