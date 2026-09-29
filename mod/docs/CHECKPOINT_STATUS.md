# Radical Red 0.5.19 release-candidate status

Targets: unmodified gen1recomp 0.3.5 and 0.3.20, mod API 2, FireRed.

## Inputs

- FireRed US 1.0: 16,777,216 bytes; MD5
  `e26ee0d44e809351c8ce2d73c7400cdd`.
- Radical Red v4.1: 33,554,432 bytes; MD5
  `8529f3a45d32bce4da637976fcf269d4`; SHA-256
  `679d112cdfe699c2793d82c7e7999ac9dfca9e222ad5a85d4f8f1e457cd0283f`.
- Embedded ROM marker: `Radical Red Version v4.1`.

## Runtime invariants

- Phase export: `RR_RUNTIME_DATASET`.
- Registries: 425 maps, 1,376 species, 1,004 moves, 282 abilities,
  750 items, 128 machines, and 128 tutors.
- Script callback coverage: all 72 extracted `callnative` targets.
- Required special handlers: 27 base/QoL, 2 facility, and 8 raid handlers.
- Separate save scope: `radical_red_4_1`.
- Expanded item icon pointer table: `0x13C8100`.
- Radical Red title composite verified from the exact ROM.
- Bounded ROM cache: sixteen 256 KiB string pages (4 MiB maximum).
- Android ROM-reader negotiation: `readString`, numeric `readBytes`, and
  byte-at-a-time `get`; tileset binary reads do not require one host API, and
  numeric slices are copied page-by-page rather than updating LRU state for
  every byte.
- Private cache schema: 19.
- Wild encounters: 134 maps and 4,866 valid slots across the base and
  relocated 83-map day/night tables; all 177 `SPECIES_NONE` placeholders are
  removed, and a final runtime guard rejects invalid wild battles.
- Full-world audit: 425/425 native layouts, 1,324 warp records (1,297
  statically resolved and 27 cartridge-controlled), and 116/116 outdoor
  connections with valid overlap and live landing coordinates.
- True map bounds: all 306 odd-sized cartridge layouts are cropped from their
  even-padded extraction storage before rendering and collision.
- Overworld graphics: 545 addressable sheets across the ordinary table at
  `0x0EB1000`, Pokémon/follower table at `0x134FD7C`, and custom-player table
  at `0x134FCB8`; all 546 physical mappings and 397 referenced palette tags
  are validated. Red, Mom, Pallet Town's Stufful, and a custom player are
  explicit ROM sentinels.
- Map objects retain CFRU's graphics selector byte and the `0xFF00..0xFF0F`
  indirect slots preserve complete 16-bit selector/index values.
- Naming rival graphics: all nine live frame-table entries resolve to the
  relocated sheet at `0x0EE82B0`; no frame is blank or solid black.
- Expanded script variables: CFRU's `0x5000..0x51FF` bank is resolved for
  preview, gift, egg, and cry operands.
- Original setup: cartridge-owned prompt and all six dynamic option lists.
- Setup visibility: the first warning clears the script's unmatched black fade
  during its first draw, before any input is injected.
- Custom list menus: all 16 RR table IDs are ROM-extracted and handled,
  including starter regions, natures, fossils, tutors, balls, types, floors,
  rematches, and game modes; none can fall through to FireRed badge labels.
- Regional starter gift: the exact species selected through `0x5124` is not
  randomized a second time, even when the species-randomizer flag is active.
- Rival parties: all starter/region-selected Kanto rival records, Brendan/May
  encounters, and both Champion trios bypass the host trainer randomizer after
  the cartridge chooses their branch.
- Black/White-style UI: the six 14×5 party cards, icons, labels, HP bars, and
  the reversed Known Moves detail panes use the exact v4.1 ROM geometry.
- Battle sprite geometry: all 1,376 front/back offsets and enemy elevations
  come from RR's expanded DPE tables; Cyndaquil's corrected back offset is 3,
  signed form offsets are retained, and status tiles do not follow battler
  menu bounce.
- Seviian Ursaring: species `0x04FF` is verified as the intentional
  Ghost/Fighting form; its ROM sprite is preserved unchanged.
- Fairy UI: the 128×144 RR menu-info sheet preserves tile `0x100`, and the
  live Summary/TM-style and Pokédex badge renderers crop Fairy from
  `(0,128,32,12)` instead of falling back to NORMAL.
- Running shoes: flag `0x82F` is present before the first playable step and is
  repaired for existing saves on load/map entry.
- Console codes: exact matching and persistent flags for `SO2Toxic`, `DexAll`,
  `Woyaopp`, `TeamPreview`, and `EZCatch`; DexNav disclosure, opponent preview,
  guaranteed catch, early-item, and Viridian level-cap paths are exercised.
- Poké Rider: RR item 363 bypasses Fame Checker in Bag-deferred and direct
  registered-item use, opens the visited-location Fly map, and releases the
  field lock if the region map cannot open or is canceled.
- DexNav: story unlock and DexAll disclosure, Register/Scan/Cancel, saved
  registration and search levels, chain lifecycle, latched R/SELECT controls,
  key-item SELECT preservation, serialized ITEM_NONE=0 repair, fishing rods,
  complete generated battle payloads, and CFRU search bonuses are live.
- Party selection: the live close-before-select callback commits slot two
  before the next native; Combee eligibility and gender mutation are verified.
- Battle text: all expanded CFRU placeholders present in the v4.1 bundle are
  resolved, including the `B_BUFF3` post-rival gained-EXP field; sparse effect
  text recovers the live self-target defender used by Roost.
- Original randomizers: ROM-backed species, scaled-species, ability, and
  learnset mappings seeded by the full trainer ID.
- Cold bootstrap: 194 resumable frame-loop checkpoints; longest measured
  release-gate chunk 1.969 seconds (three-second regression ceiling), with both
  modern and readBytes-only Android fixtures completing under the limit.
- Launcher/engine source modifications: none.
- 0.5.19 additions: FireRed-context RR save transfer with legacy-stamp
  normalization and failed-import rollback, four-skill L menu with pinned
  physical-left-shoulder input coverage,
  authored-boss preservation with a complete extracted-trainer census,
  transactional Wishing Piece den reactivation,
  CFRU Fairy badge,
  guarded field-BGM recovery, pre-battle map-song restoration, live Elite Four
  VS-intro identity, damaging pivot moves, the full 1,376-row cry table,
  CFRU's 526-row song/SFX table, and the full 1,004-move animation pack with
  371 particle rows and 77 animation backgrounds.

## 0.5.19 certification state

The rows in the legacy gate table below are the last fully executed 0.5.16
baseline. New 0.5.19 regression coverage is committed, including exact-ROM
sentinels for Poké Rider, modern cries, U-turn mechanics, Fairy rendering, and
Gen 4+ animation/SFX integrity. Current GitHub Actions runs do not execute:
both jobs terminate with `runner_id: 0` and an empty step list. Those new
0.5.19 checks remain pending until a runner is assigned.

## Last fully executed automated release gate (0.5.16 baseline)

| Test | Result |
|---|---|
| Exact-ROM parser and sentinels | PASS |
| Expanded move/type runtime | PASS |
| Real stock damage module | PASS |
| Field/QoL native callbacks | PASS |
| Immediate running shoes and existing-save repair | PASS |
| All five bedroom-console codes and host effects | PASS |
| DexNav register/scan/search/chain and R/SELECT controls | PASS |
| DexNav level, move, ability, item, shiny, and IV generation | PASS |
| Live second-slot Combee gender change | PASS |
| Facility generation and party restore | PASS |
| Raid selection, rewards, capture, and combat rules | PASS |
| Story/follower utilities | PASS |
| All 72 native addresses covered exactly once | PASS |
| Automatic main-module orchestration | PASS |
| Nonblocking setup screen and deferred activation | PASS |
| Original v4.1 setup prompts and nested option lists | PASS |
| First setup warning visible with no button input | PASS |
| Eight starter-region labels and Paldea result branch | PASS |
| All 16 ROM-defined custom menu tables and result paths | PASS |
| All 425 layouts, 1,324 warps, and 116 map connections | PASS |
| All 134 wild maps / 4,866 day-night slots; no species zero | PASS |
| All 4,866 wild slots have usable moves at min/max level | PASS |
| Route 23–Indigo Plateau and duplicate Six Island edges | PASS |
| True collision/render bounds for 306 odd-sized layouts | PASS |
| ROM-exact species, ability, and learnset randomizers | PASS |
| All regional/starter rival branches bypass trainer randomization | PASS |
| Six-card RR party layout and Known Moves detail geometry | PASS |
| Expanded battle sprite coordinates and Cyndaquil baseline | PASS |
| Fixed status tile with independent battler bounce | PASS |
| Seviian Ursaring identity and Ghost/Fighting form data | PASS |
| Three RR overworld tables; all 545 addressable / 546 physical mappings | PASS |
| Full 16-bit direct and indirect graphics IDs remain addressable | PASS |
| Stufful overworld sheet, interaction species, and cry identity | PASS |
| Generated RGBA audit (9,530 assets; ROM/palette validation for core families) | PASS |
| Relocated rival naming sheet and all nine live frame mappings | PASS |
| Authentic Game Modes multichoice normal draw | PASS |
| Portable Game Modes fallback after a forced chrome failure | PASS |
| Active/completed black fade is cleared before Game Modes compositing | PASS |
| Normal Options draw through the affected Android color-call contract | PASS |
| Portable Options fallback after a forced renderer failure | PASS |
| Exact Turtwig preview/gift through `0x5124` with randomizer active | PASS |
| Post-rival EXP, Roost, and all used expanded battle placeholders | PASS |
| Exact stock Loader with real v4.1 ROM | PASS |
| gen1recomp 0.3.20 ROM importer compatibility | PASS |
| Legacy/vendor Android readBytes-only tileset compatibility | PASS |
| Empty-cache extraction with host `readString` removed | PASS |
| Empty-cache launch with 256 MiB address-space limit | PASS |
| Cached relaunch with 256 MiB address-space limit | PASS |
| Mod-disabled vanilla behavior | PASS |
| Package private-content policy | PASS |
| `modkit lint` | PASS |
| `modkit gen3check --notes` | PASS |
| `modkit validate --base fixture --strict` | PASS |
| Graphical LÖVE/device smoke test | NOT RUN — unavailable in build environment |

## Release boundary

The world/data conversion and every script-native entry point are installed.
The remaining non-parity area is the host battle engine's incomplete coverage
of CFRU-only modern move, ability, item, and animation semantics. See
`PORTING_MATRIX.md` for the precise distinction.
