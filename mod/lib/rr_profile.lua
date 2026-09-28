-- Exact Radical Red v4.1 extraction profile.
--
-- The hack keeps FireRed's native map/tree and most Gen III structures, but
-- relocates and expands the registries used by CFRU/DPE.  This module teaches
-- gen1recomp's existing extractors where those registries live.  It contains
-- addresses and format metadata only; every byte of game content is read from
-- the player's launcher-validated Radical Red ROM.

local GENERATED_ROOT = "data/" .. "generated"

local Profile = {
  ID = "radical_red_4_1",
  IMPORT_ID = "radical_red_v4_1",
  MD5 = "8529f3a45d32bce4da637976fcf269d4",
  SHA1 = "964f951a0fdaf209e4ea1344883ef0d557bb3a80",
  ROM_SIZE = 33554432,
  -- Bump whenever the private-ROM cache layout or a decoded RR structure
  -- changes.  A mismatched marker makes the mod rebuild from the player's
  -- validated import instead of ever mixing old/vanilla cache data.
  CACHE_SCHEMA = 17,

  SPECIES_COUNT = 1376,
  MOVE_COUNT = 1004,
  ABILITY_COUNT = 282,
  ITEM_COUNT = 750,
  NATIONAL_DEX_COUNT = 1025,
  EVOLUTIONS_PER_SPECIES = 16,
  MACHINE_COUNT = 128,
  TUTOR_COUNT = 128,
  LEARNSET_ENTRY_SIZE = 3,
  TMHM_WORDS = 4,
  TUTOR_WORDS = 4,

  RR_WILD_BASE_HEADER_COUNT = 142,
  RR_WILD_DAY_HEADER_COUNT = 83,
  RR_WILD_NIGHT_HEADER_COUNT = 83,

  MAP_GROUPS = 43,
  MAP_COUNT = 425,
  -- RR keeps FireRed's physical 257-entry table, but its live resolver treats
  -- the high byte of a map object's graphics value as a table selector.  The
  -- three addressable tables contain 256 ordinary objects, 240 Pokemon, and
  -- 49 player-customization sheets.  Physical ordinary entry 256 is an
  -- inaccessible Red alias because encoded value 0x0100 selects Pokemon 0.
  OW_COUNT = 257,
  OW_RUNTIME_PRIMARY_COUNT = 256,
  OW_POKEMON_COUNT = 240,
  OW_PLAYER_COUNT = 49,
  OW_TOTAL_COUNT = 545,
  OW_PALETTE_COUNT = 451,
  OW_USED_PALETTE_COUNT = 397,
  OW_PRIMARY_USED_PALETTE_COUNT = 179,
}

Profile.OFFSET = {
  gMapGroups = 0x03526A8,
  wildMonHeaders = 0x072C984,
  -- RR's live CFRU resolver always checks one of these relocated tables
  -- first. Evening shares the night table; absent methods fall back to the
  -- FireRed-derived table above.
  wildMonDayHeaders = 0x1166AB8,
  wildMonNightHeaders = 0x1166428,
  -- RR's resolver selects one of three tables with the graphics high byte.
  -- 0x134FCB8 begins 49 custom-player entries; the 240-entry Pokemon/follower
  -- table immediately follows at 0x134FD7C. Ordinary NPC IDs still use the
  -- FireRed-derived table at 0x0EB1000.
  overworldGraphicsPointers = 0x0EB1000,
  overworldPokemonGraphicsPointers = 0x134FD7C,
  overworldPlayerGraphicsPointers = 0x134FCB8,
  overworldSpritePalettes = 0x035CCC8,

  speciesNames = 0x14042CC,
  baseStats = 0x17B98EC,
  speciesToNational = 0x18218F0,
  frontPics = 0x17FA1C4,
  backPics = 0x17B6DC4,
  -- DPE stores MonCoords as { size, y_offset, u16 padding }. These expanded
  -- tables are distinct from the sprite-pointer tables above.
  frontPicCoords = 0x17F8C30,
  backPicCoords = 0x17B5830,
  enemyMonElevation = 0x17CD44A,
  normalPalettes = 0x1811208,
  shinyPalettes = 0x181EDC8,
  icons = 0x17FE6CC,
  iconPaletteIndices = 0x17FE164,

  abilityNames = 0x10E32C0,
  abilityDescriptions = 0x1009B84,
  moveNames = 0x10F3188,
  moveDescriptions = 0x103DF74,
  battleMoves = 0x11521D0,
  levelUpLearnsets = 0x180175C,
  eggMoves = 0x17CB0E4,
  evolutions = 0x17CD9B0,
  tmhmLearnsets = 0x13E6DB4,
  tmhmMoves = 0x18224B8,
  tutorLearnsets = 0x13EC404,
  tutorMoves = 0x18223B8,
  pokedexEntries = 0x1814030,

  items = 0x13C0000,

  trainers = 0x023EAC8,
  trainerClassNames = 0x023E558,

  -- RR relocates FireRed's nine-frame naming-screen rival sheet.  The stock
  -- address (0x38A428) is erased to 0xFF in v4.1, which decodes as the solid
  -- black rectangle previously shown on the rival-name screen.
  namingRivalGfx = 0x0EE82B0,

  -- RR's Black/White-style party cards are 14x5 tiles. FireRed's stock
  -- extractor otherwise interprets these bytes as one 10x7 and one 18x3
  -- panel, producing the stretched/overlapping party screen.
  partyMenuSlotTilemap = 0x045A180,
  partyMenuSlotEmptyTilemap = 0x045A210,
}

local function copy(t)
  local out = {}
  for k, v in pairs(t or {}) do out[k] = v end
  return out
end

function Profile.version(Versions)
  return {
    id = Profile.ID,
    game = "firered",
    tilesets = Versions.TILESETS,
    layouts = {},
    map_headers = Versions.MAP_HEADERS,
    g_map_groups = Profile.OFFSET.gMapGroups,
    g_map_layouts = Versions.G_MAP_LAYOUTS,
    num_map_groups = Versions.NUM_MAP_GROUPS,
    ow_gfx_pointers = Profile.OFFSET.overworldGraphicsPointers,
    ow_sprite_palettes = Profile.OFFSET.overworldSpritePalettes,
    ow_sprite_palette_count = Profile.OW_PALETTE_COUNT,
    num_obj_event_gfx = Profile.OW_COUNT,
    rr_ow_tables = {
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
    },
    wild_mon_headers = Profile.OFFSET.wildMonHeaders,
    rr_wild_day_headers = Profile.OFFSET.wildMonDayHeaders,
    rr_wild_night_headers = Profile.OFFSET.wildMonNightHeaders,
    base_wild_header_count = Profile.RR_WILD_BASE_HEADER_COUNT,
    day_wild_header_count = Profile.RR_WILD_DAY_HEADER_COUNT,
    night_wild_header_count = Profile.RR_WILD_NIGHT_HEADER_COUNT,
    wild_mon_header_size = 20,
    land_wild_count = 12,
    water_wild_count = 5,
    rock_wild_count = 5,
    fish_wild_count = 10,
  }
end

-- Apply the profile to the engine's address registry.  The engine process is
-- restarted when mods change, so these overrides exist only while RR is on.
function Profile.apply(Versions)
  assert(type(Versions) == "table", "Radical Red profile needs gba.versions")

  local version = Profile.version(Versions)
  Versions.BY_SHA1[Profile.MD5] = version
  Versions.BY_SHA1[Profile.SHA1] = version
  -- Rom.open calls select().  Select FireRed first, then install the expanded
  -- values so a prior LeafGreen session cannot restore baseline addresses.
  Versions.select(Profile.MD5)

  Versions.ROM_SIZE = Profile.ROM_SIZE
  Versions.POKEMON_VERSION = 410
  Versions.NUM_SPECIES = Profile.SPECIES_COUNT
  Versions.SPECIES_NAMES = Profile.OFFSET.speciesNames
  Versions.SPECIES_NAME_LENGTH = 11
  Versions.SPECIES_INFO = Profile.OFFSET.baseStats
  Versions.SPECIES_INFO_SIZE = 28
  Versions.SPECIES_TO_NATIONAL = Profile.OFFSET.speciesToNational

  Versions.MON_ICON_TABLE = Profile.OFFSET.icons
  Versions.MON_ICON_PAL_INDICES = Profile.OFFSET.iconPaletteIndices
  -- RR retains FireRed's six generic icon palettes at the original address.
  Versions.MON_ICON_PALETTES = 0x03D3740
  Versions.MON_ICON_PAL_COUNT = 6
  Versions.MON_BACK_PIC_TABLE = Profile.OFFSET.backPics
  Versions.MON_SHINY_PALETTE_TABLE = Profile.OFFSET.shinyPalettes

  Versions.ABILITY_NAMES = Profile.OFFSET.abilityNames
  Versions.ABILITY_NAME_LENGTH = 16
  Versions.ABILITIES_COUNT = Profile.ABILITY_COUNT
  Versions.ABILITY_DESCRIPTIONS = Profile.OFFSET.abilityDescriptions

  Versions.MOVE_NAMES = Profile.OFFSET.moveNames
  Versions.MOVE_NAME_LENGTH = 12
  Versions.MOVE_DESCRIPTIONS = Profile.OFFSET.moveDescriptions
  Versions.MOVES_COUNT = Profile.MOVE_COUNT
  Versions.BATTLE_MOVES = Profile.OFFSET.battleMoves
  Versions.BATTLE_MOVE_SIZE = 12
  Versions.LEVEL_UP_LEARNSETS = Profile.OFFSET.levelUpLearnsets
  Versions.EGG_MOVES = Profile.OFFSET.eggMoves
  Versions.EVOLUTION_TABLE = Profile.OFFSET.evolutions
  Versions.EVOS_PER_MON = Profile.EVOLUTIONS_PER_SPECIES
  Versions.EVOLUTION_ENTRY_SIZE = 8
  Versions.TMHM_LEARNSETS = Profile.OFFSET.tmhmLearnsets
  Versions.TMHM_MOVES = Profile.OFFSET.tmhmMoves
  Versions.TMHM_COUNT = Profile.MACHINE_COUNT
  Versions.TUTOR_MOVES = Profile.OFFSET.tutorMoves
  Versions.TUTOR_LEARNSETS = Profile.OFFSET.tutorLearnsets
  Versions.TUTOR_MOVE_COUNT = Profile.TUTOR_COUNT

  Versions.POKEDEX_ENTRIES = Profile.OFFSET.pokedexEntries
  Versions.POKEDEX_ENTRY_SIZE = 36
  Versions.NATIONAL_DEX_COUNT = Profile.NATIONAL_DEX_COUNT

  Versions.ITEMS = Profile.OFFSET.items
  Versions.ITEMS_COUNT = Profile.ITEM_COUNT
  Versions.ITEM_STRIDE = 44
  -- RR relocates the expanded 750-entry item icon/palette pointer table.
  -- Keeping FireRed's stock table makes every post-Gen-III bag icon fail and
  -- leaves the converted menus looking deceptively close to vanilla.
  Versions.ITEM_ICON_TABLE = 0x13C8100

  -- RR 4.1 replaces or expands several menu/battle INCBINs.  Most stay in
  -- FireRed's graphics banks, but the larger payloads are repointed into free
  -- space.  Use the live pointers from the v4.1 image so the host never falls
  -- back to stock FireRed chrome merely because an old fixed offset now sits
  -- in the middle of a larger compressed stream.
  Versions.PARTY_MENU_BG_GFX = 0x0E82700
  Versions.PARTY_MENU_BG_PAL = 0x0E82994
  Versions.PARTY_MENU_BG_TILEMAP = 0x0E82A98
  Versions.PARTY_MENU_BALL_GFX = 0x0E82BE0
  Versions.PARTY_MENU_BALL_PAL = 0x0E82E7C
  Versions.PARTY_MENU_SLOT_MAIN_TILEMAP = Profile.OFFSET.partyMenuSlotTilemap
  Versions.PARTY_MENU_SLOT_WIDE_TILEMAP = Profile.OFFSET.partyMenuSlotTilemap
  Versions.PARTY_MENU_SLOT_WIDE_EMPTY_TILEMAP =
    Profile.OFFSET.partyMenuSlotEmptyTilemap
  Versions.SUMMARY_STATUS_ICONS_GFX = 0x1327888

  Versions.SUMMARY_BG_GFX = 0x0E9A460
  Versions.SUMMARY_BG_PAL = 0x0E9B310
  Versions.SUMMARY_EXP_BAR_GFX = 0x0E9B3F0
  Versions.SUMMARY_HP_BAR_GFX = 0x0E9B4B8
  Versions.SUMMARY_HP_EXP_PAL = 0x0E9B578
  Versions.SUMMARY_PAGE_INFO_TILEMAP = 0x0E9B598
  Versions.SUMMARY_PAGE_SKILLS_TILEMAP = 0x0E9B750
  Versions.SUMMARY_PAGE_MOVES_TILEMAP = 0x0E9B950
  Versions.SUMMARY_PAGE_MOVES_INFO_TILEMAP = 0x0E9BA30
  Versions.SUMMARY_PAGE_EGG_TILEMAP = 0x0E9BBCC
  Versions.SUMMARY_CURSOR_LEFT_GFX = 0x0E9B188
  Versions.SUMMARY_CURSOR_RIGHT_GFX = 0x0463800

  Versions.TM_CASE_BG_GFX = 0x036F098
  Versions.TM_CASE_MENU_TILEMAP = 0x036F648
  Versions.TM_CASE_BG_TILEMAP = 0x0E84B70

  Versions.TRAINER_CARD_BADGES_TILES = 0x0364CB8

  Versions.BATTLE_UI = copy(Versions.BATTLE_UI)
  Versions.BATTLE_UI.textbox_gfx = 0x0370A40
  Versions.BATTLE_UI.healthbox_player = 0x037016C
  Versions.BATTLE_UI.healthbox_enemy = 0x036FED8
  Versions.BATTLE_UI.healthbox_doubles_player = 0x036FC38
  Versions.BATTLE_UI.healthbox_doubles_opponent = 0x036F9A4
  Versions.BATTLE_UI.party_summary_bar = 0x035F92C
  Versions.BATTLE_UI.terrain_grass = copy(Versions.BATTLE_UI.terrain_grass)
  Versions.BATTLE_UI.terrain_grass.tiles = 0x0950000
  Versions.BATTLE_UI.terrain_grass.tilemap = 0x0950C90

  Versions.TRAINERS_TABLE = Profile.OFFSET.trainers
  Versions.TRAINERS_COUNT = 743
  Versions.TRAINER_CLASS_NAMES = Profile.OFFSET.trainerClassNames

  Versions.WILD_MON_HEADERS = Profile.OFFSET.wildMonHeaders
  Versions.WILD_MON_HEADER_SIZE = 20
  Versions.OW_GFX_POINTERS = Profile.OFFSET.overworldGraphicsPointers
  Versions.OW_SPRITE_PALETTES = Profile.OFFSET.overworldSpritePalettes
  Versions.OW_SPRITE_PALETTE_COUNT = Profile.OW_PALETTE_COUNT
  Versions.NUM_OBJ_EVENT_GFX = Profile.OW_COUNT

  Versions.INTRO = copy(Versions.INTRO)
  Versions.INTRO.mon_front_pic_table = Profile.OFFSET.frontPics
  Versions.INTRO.mon_palette_table = Profile.OFFSET.normalPalettes

  Versions.NAMING = copy(Versions.NAMING)
  Versions.NAMING.rival_gfx = Profile.OFFSET.namingRivalGfx

  -- Radical Red deliberately blanks FireRed's pre-title Gengar/Nidorino movie
  -- payload (the stock copyright LZ stream starts with 0xFF in v4.1).  Keeping
  -- FireRed's static INTRO_MOVIE addresses would make the engine try to decode
  -- removed data on the first launch.  The actual RR title, Oak speech and
  -- controls assets remain in place and are still extracted above.
  Versions.INTRO_MOVIE = nil

  return version
end

function Profile.runtimeRoot(modId)
  return "mod_cache/" .. tostring(modId or "radical_red_experience")
    .. "/" .. GENERATED_ROOT .. "/gba"
end

function Profile.extractRoot()
  return GENERATED_ROOT .. "/gba"
end

function Profile.generatedRoot()
  return GENERATED_ROOT
end

function Profile.introIndex()
  return GENERATED_ROOT .. "/intro.lua"
end

return Profile
