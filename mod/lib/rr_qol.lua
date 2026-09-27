-- Radical Red v4.1 quality-of-life flags whose effects normally live in
-- CFRU's ARM code.  The ROM scripts still own the flags; this module only
-- supplies the matching host behavior after those scripts set them.

local Qol = {}

Qol.FLAG = {
  RUNNING_SHOES = 0x082F,
  SO2_TOXIC = 0x103F,
  WOYAOPP = 0x1040,
  DEX_ALL = 0x1056,
  TEAM_PREVIEW = 0x1083,
  EZ_CATCH = 0x109D,
}

local METHODS = {
  { key = "land", label = "GRASS" },
  { key = "water", label = "WATER" },
  { key = "rocks", label = "ROCK" },
  { key = "fishing", label = "FISH" },
}

local function mergeDefaults(overrides)
  local deps = {}
  for key, value in pairs(overrides or {}) do deps[key] = value end
  local modules = {
    Flags = "src.core.game3.scripting.flags",
    Encounters = "src.core.game3.encounters",
    Pokemon = "src.core.game3.pokemon",
    Dex = "src.core.game3.dex",
  }
  for key, moduleName in pairs(modules) do
    if deps[key] == nil then deps[key] = require(moduleName) end
  end
  return deps
end

local function storeOf(deps)
  if deps.getStore then return deps.getStore() end
  -- Mods run with a capability-scoped package table.  Resolve the live engine
  -- module through require so we do not read the sandbox's stale shadow copy.
  local ok, Space = pcall(require, "src.core.game3.scripting.space")
  if not ok then Space = package.loaded["src.core.game3.scripting.space"] end
  return Space and Space.store or nil
end

local function sessionOf(deps)
  if deps.getSession then return deps.getSession() end
  local ok, Runtime = pcall(require, "src.core.game3.runtime")
  if not ok then Runtime = package.loaded["src.core.game3.runtime"] end
  return Runtime and Runtime.getSession and Runtime.getSession() or nil
end

local function flagOn(deps, id)
  local store = storeOf(deps)
  return store ~= nil and deps.Flags.getFlag(store, nil, id) == true
end

local function playSelect()
  pcall(function() require("src.core.game3.audio").playSe(5) end)
end

function Qol.ensureRunningShoes(deps)
  deps = deps or Qol._deps
  if not deps then return false end
  local store = storeOf(deps)
  if not store then return false end
  if deps.Flags.getFlag(store, nil, Qol.FLAG.RUNNING_SHOES) ~= true then
    deps.Flags.setFlag(store, nil, Qol.FLAG.RUNNING_SHOES, true)
  end
  return true
end

function Qol.dexAllEnabled(deps)
  return flagOn(deps or Qol._deps, Qol.FLAG.DEX_ALL)
end

function Qol.teamPreviewEnabled(deps)
  return flagOn(deps or Qol._deps, Qol.FLAG.TEAM_PREVIEW)
end

function Qol.ezCatchEnabled(deps)
  return flagOn(deps or Qol._deps, Qol.FLAG.EZ_CATCH)
end

local function speciesOf(mon)
  return tonumber(mon and (mon.species or mon.speciesId or mon.id))
end

local function buildDexRows(deps, session)
  local entry = session and deps.Encounters.tableFor(session.map)
  local order, bySpecies = {}, {}
  for _, method in ipairs(METHODS) do
    local area = entry and entry[method.key]
    for _, slot in ipairs((area and (area.slots or area.mons)) or {}) do
      local species = tonumber(slot.species or slot.speciesId or slot[1])
      if species and species > 0 then
        local row = bySpecies[species]
        if not row then
          row = {
            species = species,
            minLevel = tonumber(slot.minLevel or slot.level or slot[2]) or 1,
            maxLevel = tonumber(slot.maxLevel or slot.level or slot[2]) or 1,
            methods = {}, methodSet = {},
          }
          bySpecies[species] = row
          order[#order + 1] = row
        end
        row.minLevel = math.min(row.minLevel,
          tonumber(slot.minLevel or slot.level or slot[2]) or row.minLevel)
        row.maxLevel = math.max(row.maxLevel,
          tonumber(slot.maxLevel or slot.level or slot[2]) or row.maxLevel)
        if not row.methodSet[method.label] then
          row.methodSet[method.label] = true
          row.methods[#row.methods + 1] = method.label
        end
      end
    end
  end
  local all = Qol.dexAllEnabled(deps)
  local dex = (session and session.dex) or {}
  for _, row in ipairs(order) do
    row.revealed = all or deps.Dex.isSeen(dex, row.species) == true
    if row.revealed then
      local ok, name = pcall(deps.Pokemon.name, row.species)
      row.name = ok and name or "?????"
    else
      row.name = "??????????"
    end
    row.method = table.concat(row.methods, "/")
    row.methodSet = nil
  end
  return order
end

function Qol.buildDexRows(deps, session)
  deps = deps or Qol._deps
  return buildDexRows(deps, session or (deps and sessionOf(deps)))
end

local function installDexNav(mod, deps)
  if Qol._dexNav then return Qol._dexNav end
  local okStack, Stack = pcall(require, "src.ui.game3.stack")
  if not okStack then return nil end

  local DexNav = {
    open = false,
    cursor = 1,
    scroll = 1,
    rows = {},
    session = nil,
  }

  function DexNav.show(session)
    DexNav.open = true
    DexNav.session = session
    DexNav.rows = buildDexRows(deps, session)
    DexNav.cursor, DexNav.scroll = 1, 1
    Stack.push("rr_dexnav", DexNav, { hideBelow = true, fullscreen = true })
    playSelect()
  end

  function DexNav.close()
    if not DexNav.open then return end
    DexNav.open = false
    Stack.pop("rr_dexnav")
    playSelect()
  end

  function DexNav.isOpen() return DexNav.open end

  function DexNav.handleInput(input)
    if not DexNav.open or not input then return false end
    local n = #DexNav.rows
    local old = DexNav.cursor
    if input:wasPressed("up") and n > 0 then
      DexNav.cursor = ((DexNav.cursor - 2) % n) + 1
    elseif input:wasPressed("down") and n > 0 then
      DexNav.cursor = (DexNav.cursor % n) + 1
    elseif input:wasPressed("b") or input:wasPressed("start") then
      DexNav.close()
      return true
    else
      return true
    end
    if DexNav.cursor ~= old then
      if DexNav.cursor < DexNav.scroll then DexNav.scroll = DexNav.cursor end
      if DexNav.cursor > DexNav.scroll + 6 then DexNav.scroll = DexNav.cursor - 6 end
      playSelect()
    end
    return true
  end

  function DexNav.draw()
    if not DexNav.open or not (love and love.graphics) then return end
    local g = love.graphics
    local okFont, FrlgFont = pcall(require, "src.ui.game3.frlg_font")
    g.setColor(0.94, 0.95, 0.86, 1)
    g.rectangle("fill", 0, 0, 240, 160)
    g.setColor(0.10, 0.34, 0.58, 1)
    g.rectangle("fill", 0, 0, 240, 20)
    g.setColor(1, 1, 1, 1)
    local function text(value, x, y, color)
      if okFont and FrlgFont and FrlgFont.draw then
        FrlgFont.draw(tostring(value), x, y, {
          small = true,
          colors = color or FrlgFont.COLOR.NORMAL,
        })
      else
        g.setColor(0.08, 0.08, 0.1, 1)
        g.print(tostring(value), x, y)
      end
    end
    text("DEXNAV  " .. tostring((DexNav.session and DexNav.session.map) or "AREA"), 6, 4)
    if #DexNav.rows == 0 then
      text("No wild Pokemon in this area.", 16, 64)
    else
      for visible = 0, 6 do
        local index = DexNav.scroll + visible
        local row = DexNav.rows[index]
        if not row then break end
        local y = 25 + visible * 17
        if index == DexNav.cursor then
          g.setColor(0.72, 0.84, 0.94, 1)
          g.rectangle("fill", 3, y - 2, 234, 16)
        end
        text(index == DexNav.cursor and ">" or " ", 6, y)
        text(row.name, 17, y)
        if row.revealed then
          text(("Lv%d-%d"):format(row.minLevel, row.maxLevel), 112, y)
          text(row.method, 164, y)
        end
      end
    end
    text(Qol.dexAllEnabled(deps) and "DexAll: all info unlocked" or "B: Back", 7, 145)
    g.setColor(1, 1, 1, 1)
  end

  Qol._dexNav = DexNav
  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local base = next(game, items)
    if type(base) ~= "table" then base = items end
    local out, inserted, already = {}, false, false
    for _, item in ipairs(base or {}) do
      if item.id == "rr_dexnav" then already = true end
    end
    for _, item in ipairs(base or {}) do
      out[#out + 1] = item
      if not already and not inserted and item.id == "pokedex" then
        out[#out + 1] = {
          id = "rr_dexnav",
          label = "DEXNAV",
          onSelect = function(_, session) DexNav.show(session) end,
        }
        inserted = true
      end
    end
    return out
  end, 900)
  return DexNav
end

local function drawMonIcon(Pokemon, mon, cx, cy)
  local ok, icon = pcall(Pokemon.monIcon, mon)
  if not ok or not icon or not icon.image then return false end
  local quad = icon.quads and (icon.quads[0] or icon.quads[1])
  local w, h = tonumber(icon.w) or 32, tonumber(icon.h) or 32
  if quad then love.graphics.draw(icon.image, quad, cx, cy, 0, 1, 1, w / 2, h / 2)
  else love.graphics.draw(icon.image, cx, cy, 0, 1, 1, w / 2, h / 2) end
  return true
end

local function installTeamPreview(deps)
  local ok, Ui = pcall(require, "src.core.game3.battle.ui")
  if not ok or Ui.__rrTeamPreviewInstalled then return ok end
  Ui.__rrTeamPreviewInstalled = true
  local originalReset = Ui.reset
  local originalHandle = Ui.handleInput
  local originalDraw = Ui.draw

  local function allowed()
    local st = Ui._st
    return st ~= nil and not st.wild and not st.oldManTutorial
      and not st.pokedude and Qol.teamPreviewEnabled(deps)
  end

  local function pressed(input, names)
    for _, name in ipairs(names) do
      if input:wasPressed(name) then return true end
    end
    return false
  end

  Ui.reset = function(...)
    Ui._rrTeamPreview = false
    return originalReset(...)
  end

  Ui.handleInput = function(input)
    if Ui._rrTeamPreview then
      if input and pressed(input, { "a", "b", "l", "select", "up", "down", "left", "right" }) then
        Ui._rrTeamPreview = false
        playSelect()
      end
      return true
    end
    if input and Ui._mode == "menu" and allowed()
        and pressed(input, { "l", "select" }) then
      Ui._rrTeamPreview = true
      playSelect()
      return true
    end
    return originalHandle(input)
  end

  local function drawPreview()
    local g = love and love.graphics
    if not g then return end
    local Pokemon = deps.Pokemon
    local FrlgFont = require("src.ui.game3.frlg_font")
    local Window = require("src.ui.game3.window")
    g.setColor(0.18, 0.24, 0.36, 1)
    g.rectangle("fill", 0, 0, 240, 160)
    g.setColor(1, 1, 1, 1)
    Window.stdFrame(Window.template(5, 1, 20, 12))
    FrlgFont.draw("OPPONENT'S TEAM", 65, 8, { small = true, colors = FrlgFont.COLOR.NORMAL })
    local party = (Ui._st and (Ui._st.foeParty or Ui._st.enemyParty)) or {}
    for i = 1, math.min(6, #party) do
      local mon = party[i]
      local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
      local cx, cy = 80 + col * 40, 36 + row * 40
      drawMonIcon(Pokemon, mon, cx, cy)
      local species = speciesOf(mon)
      local okName, name = pcall(Pokemon.name, species)
      name = okName and tostring(name) or "?????"
      if #name > 10 then name = name:sub(1, 10) end
      FrlgFont.draw(name, cx - 18, cy + 15, {
        small = true, colors = FrlgFont.COLOR.NORMAL,
      })
      if (tonumber(mon and (mon.hp or mon.currentHp)) or 1) <= 0 then
        g.setColor(0.82, 0.82, 0.82, 0.45)
        g.rectangle("fill", cx - 16, cy - 16, 32, 32)
        g.setColor(1, 1, 1, 1)
      end
    end
    FrlgFont.draw("A/B/L/D-PAD: BACK", 54, 139, {
      small = true, colors = FrlgFont.COLOR.NORMAL,
    })
    g.setColor(1, 1, 1, 1)
  end

  Ui.draw = function(...)
    originalDraw(...)
    if Ui._rrTeamPreview then
      local okDraw, err = pcall(drawPreview)
      if not okDraw then
        Ui._rrTeamPreview = false
        print("[radical-red] team preview draw failed: " .. tostring(err))
      end
    elseif allowed() and Ui._mode == "menu" and love and love.graphics then
      local FrlgFont = require("src.ui.game3.frlg_font")
      FrlgFont.draw("L/SELECT: TEAM", 4, 108, {
        small = true, colors = FrlgFont.COLOR.NORMAL,
      })
    end
  end
  return true
end

function Qol.install(mod, overrides)
  local deps = mergeDefaults(overrides)
  Qol._deps = deps

  -- New games can reload the already-selected start map, which emits
  -- save.created/map.reloaded rather than map.entered.  Cover every adoption
  -- path so the flag is present before the player takes their first step.
  for _, event in ipairs({ "save.created", "save.loaded", "map.entered", "map.reloaded" }) do
    mod.events:on(event, function() Qol.ensureRunningShoes(deps) end)
  end
  mod.hooks:wrap("core.update", function(next, game, dt)
    Qol.ensureRunningShoes(deps)
    return next(game, dt)
  end, 950)

  mod.hooks:wrap("catch.rate", function(next, ball, mon, species, opts)
    if Qol.ezCatchEnabled(deps) then return true, 4 end
    return next(ball, mon, species, opts)
  end, 950)

  local dexNav = installDexNav(mod, deps)
  local teamPreview = installTeamPreview(deps)
  Qol.ensureRunningShoes(deps)
  return {
    runningShoes = true,
    dexAll = dexNav ~= nil,
    teamPreview = teamPreview == true,
    ezCatch = true,
    consoleFlags = {
      SO2Toxic = Qol.FLAG.SO2_TOXIC,
      Woyaopp = Qol.FLAG.WOYAOPP,
      DexAll = Qol.FLAG.DEX_ALL,
      TeamPreview = Qol.FLAG.TEAM_PREVIEW,
      EZCatch = Qol.FLAG.EZ_CATCH,
    },
  }
end

return Qol
