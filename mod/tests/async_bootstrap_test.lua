package.path = "./?.lua;./?/init.lua;" .. package.path

-- The first launch must return from Loader immediately, present a setup frame,
-- and advance conversion from core.update.  This is the Android path that
-- prevents the Play transition from becoming an unresponsive Activity.

local installed = {}
_G.__rrAsyncInstalled = installed

local moduleSources = {
  ["lib/rr_profile.lua"] = [[return {
    ID="radical_red_4_1", SPECIES_COUNT=1376, MOVE_COUNT=1004,
    MAP_COUNT=425, ABILITY_COUNT=282, ITEM_COUNT=750, OW_COUNT=257,
    OW_TOTAL_COUNT=545, OW_PALETTE_COUNT=451, OW_USED_PALETTE_COUNT=397,
  }]],
  ["lib/rr_rom.lua"] = [[return {
    IMPORT_ID="radical_red_v4_1", SOURCE_VERSION="v4.1",
    open=function()
      return { verify=function() _G.__rrAsyncInstalled.source=true; return {} end }
    end,
  }]],
  ["lib/rr_stream_rom.lua"] = [[return { open=function() end }]],
  ["lib/rr_visuals.lua"] = [[return {
    installExtraction=function()
      _G.__rrAsyncInstalled.visualExtraction=true
      return { paletteCount=451, spriteCount=545, usedPaletteCount=397 }
    end,
    installRuntime=function()
      _G.__rrAsyncInstalled.visuals=true
      return { optionsDraw=true, optionsFallbackGuard=true,
        portableOptionsDraw=true, gameModesChoiceDraw=true,
        portableChoiceDraw=true, gameModesFadeGuard=true,
        setupMessageFadeGuard=true,
        expandedGraphicsIds=true, expandedGraphicsTables=true,
        objectGraphicsSelector=true, battleSpriteCoords=true,
        battleSpriteCoordSpecies=1376, cyndaquilBackYOffset=3,
        fixedHealthbox=true }
    end,
    report=function() return nil end,
  }]],
  ["lib/rr_world.lua"] = [[return { run=function() end }]],
  ["lib/rr_encounters.lua"] = [[return {}]],
  ["lib/rr_listmenus.lua"] = [[return { write=function() end }]],
  ["lib/rr_extract.lua"] = [[return {
    markerReady=function() return false end,
    ensure=function(mod, profile, opts)
      _G.__rrAsyncInstalled.extract=true
      opts.onProgress("world_tilesets", 0, 2)
      opts.onProgress("world_tilesets", 1, 2)
      opts.onProgress("world_tilesets", 2, 2)
      return { cached=false, maps=profile.MAP_COUNT }
    end,
  }]],
  ["lib/rr_runtime.lua"] = [[return { install=function(mod, profile)
    _G.__rrAsyncInstalled.runtime=true
    mod.game.data = { radicalRed=true }
    return { saveScope=profile.ID }
  end }]],
  ["lib/rr_battle.lua"] = [[return { install=function()
    _G.__rrAsyncInstalled.battle=true; return {}
  end }]],
  ["lib/rr_natives.lua"] = [[return {
    _state={ follower={} },
    install=function() _G.__rrAsyncInstalled.natives=true; return {} end,
  }]],
  ["lib/rr_mechanics.lua"] = [[return { install=function()
    _G.__rrAsyncInstalled.mechanics=true; return {}
  end }]],
  ["lib/rr_randomizer.lua"] = [[return { install=function()
    _G.__rrAsyncInstalled.randomizer=true; return {}
  end }]],
  ["lib/rr_facilities.lua"] = [[return { install=function()
    _G.__rrAsyncInstalled.facilities=true; return {}
  end }]],
  ["lib/rr_raids.lua"] = [[return { install=function()
    _G.__rrAsyncInstalled.raids=true; return {}
  end }]],
  ["lib/rr_story.lua"] = [[return { install=function()
    _G.__rrAsyncInstalled.story=true; return {}
  end }]],
  ["lib/rr_qol.lua"] = [[return { install=function()
    _G.__rrAsyncInstalled.qol=true
    return { runningShoes=true, dexAll=true, teamPreview=true, ezCatch=true,
      dexNavReliableFieldEdge=true, dexNavFieldSelect=true }
  end }]],
}

local bootCalls = {}
package.preload["src.core.SaveData"] = function()
  return {
    load = function() return nil, false end,
    loadOptions = function() return { textSpeed=2 } end,
  }
end
package.preload["src.ui.game3.boot"] = function()
  return {
    setHasContinue = function(_, value) bootCalls.hasContinue=value end,
    setContinueInfo = function(_, value) bootCalls.continueInfo=value end,
    setSaveStatus = function(_, value) bootCalls.saveStatus=value end,
    setTextSpeed = function(_, value) bootCalls.textSpeed=value end,
  }
end
package.preload["src.core.game3.options"] = function()
  return { block=function(value) return value end }
end
package.preload["src.core.Strings"] = function()
  return { load=function(data) assert(data.radicalRed); installed.strings=true end }
end
package.preload["src.mods.Gen3Compat"] = function()
  return { applyMerged=function(game)
    assert(game.data.radicalRed); installed.compat=true
  end }
end

local drawText = {}
_G.love = {
  graphics = {
    rectangle=function() installed.drew=true end,
    printf=function(value) drawText[#drawText + 1]=tostring(value) end,
    getWidth=function() return 1080 end,
    getHeight=function() return 1920 end,
    origin=function() end,
    newFont=function(size) return { size=size } end,
    setFont=function() end,
    setColor=function() end,
  },
}

local events, hooks = {}, {}
local cacheWrites = {}
local game = {
  boot={}, data={ vanilla=true },
  _hasContinueSave=function() return false end,
  applyOptions=function(self, value) self.options=value end,
  returnToTitle=function(self) self.returned=(self.returned or 0)+1; self.boot={} end,
}
local mod = {
  generation=3, imports={}, cache={}, game=game, exports={},
  events={ on=function(_, name, callback) events[name]=callback end },
  hooks={ wrap=function(_, name, callback) hooks[name]=callback end },
  log={
    info=function(_, value) installed.log=tostring(value) end,
    error=function(_, value) error(value) end,
  },
}
function mod.cache:write(path, value) cacheWrites[path]=value; return true end
function mod.cache:delete(path) cacheWrites[path]=nil; return true end
function mod:read(path)
  return assert(moduleSources[path], "unexpected module read: " .. tostring(path))
end

local entry = assert(loadfile("mods/radical_red_experience/main.lua"))()
entry(mod)

assert(mod.exports.phase == "RR_PREPARING")
assert(not installed.extract and not installed.runtime,
  "cold extraction ran inside Loader instead of returning to the frame loop")
assert(type(events["game.ready"]) == "function")
assert(type(hooks["core.update"]) == "function")
assert(type(hooks["render.hud"]) == "function")

hooks["render.hud"](function() installed.drewDownstream=true end, game,
  { width=1080, height=1920 })
assert(installed.drew and installed.drewDownstream)
assert(table.concat(drawText, "\n"):find("Preparing Radical Red", 1, true))

events["game.ready"]({ game=game })
local vanillaUpdates = 0
for _ = 1, 100 do
  hooks["core.update"](function() vanillaUpdates=vanillaUpdates+1 end, game, 1/60)
  if mod.exports.phase == "RR_RUNTIME_DATASET" then break end
end

assert(mod.exports.phase == "RR_RUNTIME_DATASET",
  mod.exports.bootstrap and mod.exports.bootstrap.error or "async setup did not finish")
for _, name in ipairs({ "source", "extract", "runtime", "battle", "natives",
    "mechanics", "randomizer", "facilities", "raids", "story", "qol", "visualExtraction",
    "visuals", "strings", "compat" }) do
  assert(installed[name], "async bootstrap omitted " .. name)
end
assert(vanillaUpdates == 0, "vanilla simulation advanced while RR cache was mutating")
assert(game.returned == 1 and game.options.textSpeed == 2)
assert(bootCalls.hasContinue == false and bootCalls.saveStatus == "ok")
assert(mod.exports.bootstrap.state == "ready")

hooks["core.update"](function() vanillaUpdates=vanillaUpdates+1 end, game, 1/60)
assert(vanillaUpdates == 1, "core.update did not return to vanilla after setup")

_G.__rrAsyncInstalled = nil
_G.love = nil
print("PASS async_bootstrap_test: cold conversion yields, draws progress, and activates automatically")
