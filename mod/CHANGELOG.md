# Changelog

## 0.5.15 — Rival identity and Black/White-style menu repair

- Preserve every starter/region-dependent rival party after Radical Red's
  cartridge script selects it. Kanto rival classes, Brendan/May encounters,
  and both Champion trios now bypass the host trainer randomizer without
  disabling randomization for ordinary trainers.
- Rebuild the party-card chrome as Radical Red's 14×5-tile panels and remap
  all six windows, Pokémon/item/status/ball sprites, labels, HP values, and HP
  bars to the ROM's two-column Black/White-style grid.
- Swap the Known Moves detail layout to Radical Red's intended arrangement:
  move rows and cursor on the left, Pokémon header/types and selected-move
  stats/description on the right. Ordinary summary pages keep their original
  coordinates.
- Verify species `0x04FF` against the ROM as Ghost/Fighting Seviian Ursaring.
  Its unusual turquoise multi-armed art is intentional, so the extracted
  front/back sprites and palettes remain unchanged.
- Bump the private cache schema to 15 and add exact-loader regressions for the
  party assets, live menu-coordinate transforms, all rival exemptions, and
  the Seviian-form sentinel.

## 0.5.14 — Functional DexNav and Roost text repair

- Replace the display-only current-area DexNav with working Register, Scan,
  and Cancel actions, plus persistent species registration, search levels,
  chains, and the registered R-button field shortcut. SELECT remains the
  registration fallback for Android overlays without a shoulder button.
- Generate complete DexNav wild encounters with the selected area's exact
  level range, chain bonuses, shiny checks, egg-move and hidden-ability odds,
  held-item bonuses, IV potential, and fishing-rod requirements. Failed,
  escaped, ordinary, and cross-map battles reset chains correctly.
- Recover CFRU's live defender from the active move-effect context when battle
  text omits `fill.def`. This fixes Roost's
  `B_DEF_NAME_WITH_PREFIX needs fill.def` crash while preserving explicit
  attacker/defender values on ordinary engine paths.
- Extend the exact-ROM gate to construct real DexNav payloads, persist a
  registration, reproduce Roost's sparse text call, and verify that every one
  of the 4,866 base/day/night wild slots has at least one usable move at both
  ends of its encounter-level range.
- Repeat modern Android cold extraction, cached relaunch, and readBytes-only
  vendor/Redmagic-style cold extraction under the 256 MiB address-space limit.

## 0.5.13 — Running shoes, console codes, and party-selection repair

- Grant Radical Red's running-shoes flag before the first step on a new game,
  and repair the flag automatically when an existing save is loaded.
- Verify the bedroom console's exact case-sensitive `SO2Toxic`, `DexAll`,
  `Woyaopp`, `TeamPreview`, and `EZCatch` strings and their original persistent
  flags. The ROM's early-item and Viridian level-cap service branches remain
  intact.
- Add the missing host behavior behind the CFRU-only flags: a current-area
  DexNav with `DexAll` disclosure, opponent team preview with L/SELECT, and
  guaranteed four-shake captures with `EZCatch`.
- Commit the selected party slot inside the live party-menu callback before
  the field script resumes. Gender change, level-cap, healing, form, and
  ability callbacks no longer operate on slot one after another slot was
  selected.
- Restore the cartridge's full supported gender-change set, with an explicit
  second-slot Combee regression and a name fallback for converted saves.
- Resolve live runtime, script-store, and party-menu modules through the mod
  sandbox instead of stale shadow-package entries.
- Repeat modern and legacy/readBytes-only Android cold and cached launches
  under the 256 MiB address-space ceiling.

## 0.5.12 — Complete time-of-day encounters and species-zero guard

- Extract Radical Red's relocated 83-map day and night wild-encounter tables
  instead of treating FireRed's fallback `gWildMonHeaders` as the live table.
- Match v4.1's exact clock split: day from 04:00 through 16:59, and the shared
  evening/night table from 17:00 through 03:59, with method-by-method fallback.
- Remove all 177 intentional `SPECIES_NONE` placeholder slots across the base,
  day, and night registries. Viridian and the other city fallback tables can
  no longer create a level-1 species-zero battle.
- Add a final runtime guard for walking, surfing, Rock Smash, fishing, pending,
  and modded wild encounters so an invalid species cannot reach battle
  construction even if a future table or hook is malformed.
- Audit all 134 encounter maps and 4,866 usable base/day/night slots through
  the exact stock loader, plus modern and readBytes-only Android cold starts
  and a cached relaunch under the 256 MiB address-space ceiling.
- Bump the private cache schema to 14 so every install rebuilds the corrected
  encounter registry automatically.

## 0.5.11 — Complete map seams and cartridge list menus

- Preserve all 116 ROM map connections as ordered records, including the
  three distinct west exits on Six Island Water Path. The previous writer
  emitted invalid numeric Lua fields, so the host silently fell back to a
  tiny vanilla corridor graph and rendered trees/void at routes such as the
  Route 23–Indigo Plateau boundary.
- Normalize the 306 odd-sized cartridge layouts from even-padded extraction
  storage back to their true ROM width and height before rendering/collision,
  eliminating artificial blocked south/east rows and columns.
- Audit every one of the 425 layouts, all 1,324 warp sources and destinations,
  and all 116 connection overlaps during extraction; an incomplete or
  malformed world can no longer commit a reusable cache.
- Extract Radical Red's complete 16-table custom list-menu registry from the
  player's ROM. Nature, region, fossil, tutor, Poké Ball, type, elevator,
  rematch, debug, and game-mode lists no longer fall through to FireRed badge
  names.
- Add exact-loader regressions for every map connection and landing, all 16
  custom menus, the three same-direction Six Island edges, and the reciprocal
  Route 23–Indigo Plateau path.
- Repeat both modern and readBytes-only Android cold conversions under the
  256 MiB address-space ceiling and re-audit all 9,530 generated RGBA assets.
- Bump the private cache schema to 13 so every install rebuilds the corrected
  connection registry, list tables, and true map bounds automatically.

## 0.5.10 — Regional starters and selector-qualified overworld sprites

- Preserve the exact species already chosen by Radical Red's regional starter
  script when the separate species-randomizer flag is enabled. Ordinary gifts,
  wild encounters, and trainer parties continue to use the selected randomizer.
- Decode CFRU's full 16-bit object graphics value: the formerly-padding map
  byte selects the ordinary, Pokémon/follower, or player-customization table.
  This fixes Stufful and every other selector-qualified overworld Pokémon
  without changing their already-correct text or cry.
- Support RR's expanded `0xFF00..0xFF0F` indirect graphics slots without
  discarding the table selector stored in their variables.
- Extract and validate all 545 addressable overworld sheets across all three
  tables, all 546 physical ROM mappings, and all 397 referenced palette tags.
- Expand the content-aware audit to all 9,530 generated RGBA assets and add
  exact-ROM regressions for Pallet Town's Stufful sprite/cry identity and the
  region-selected Turtwig gift while species randomization is active.
- Bump the private cache schema to 12 so installs rebuild the corrected map
  object records and selector-qualified sprite sheets automatically.

## 0.5.9 — Setup flow and post-rival battle text

- Clear Radical Red's unmatched `FADE_TO_BLACK` on the first rendered setup
  warning, so a clean boot shows the prompt without requiring B or any other
  button press.
- Replace the repurposed FireRed badge list with Radical Red's actual Johto,
  Hoenn, Sinnoh, Unova, Kalos, Alola, Galar, and Paldea starter-region list,
  while retaining the stock handler for every ordinary FireRed list menu.
- Translate every expanded CFRU battle placeholder present in the v4.1 ROM:
  `B_BUFF3`, `B_ATK_TEAM2`, and `B_DEF_TEAM1`. This fixes the gained-EXP crash
  after the opening rival battle and prevents the related team-screen and
  catch/nickname messages from failing later.
- Add exact-ROM regressions for a no-input-visible first setup frame, all eight
  region labels/results, the post-rival EXP sequence, team text, and caught
  Pokémon text.
- Copy legacy Android numeric ROM slices page-by-page instead of touching the
  LRU cache once per byte; the readBytes-only cold-start regression now stays
  below the same three-second frame ceiling as the modern reader.
- Keep private cache schema 11 because these are runtime compatibility fixes;
  existing valid extracted assets do not need rebuilding.

## 0.5.8 — Portable Android ROM-reader compatibility

- Normalize binary ROM slices from `readString`, numeric `readBytes`, or
  byte-at-a-time `get` readers instead of assuming one engine interface.
- Store both binary methods directly on every bounded ROM-reader instance so
  Android host wrappers that do not preserve Lua metatables still retain them.
- Install mod-local portable readers for raw tiles, metatiles, and attributes,
  directly fixing the `tileset.lua:105 readString (a nil value)` cold-start
  failure seen on Android 16/Redmagic OS.
- Add an exact regression for that line using a readBytes-only reader, plus a
  complete cold extraction with the modern method deliberately removed.
- Keep cache schema 11 because generated data is unchanged; incomplete failed
  conversions remain uncommitted and retry safely after installing 0.5.8.

## 0.5.7 — Authentic menus, rival portrait, and expanded script variables

- Restore the exact Radical Red/Game3 choice renderer on successful Game
  Modes frames instead of covering it with the emergency primitive menu.
- Clear an active or completed `FADE_TO_BLACK` as soon as the cartridge opens
  an interactive Game Modes choice, eliminating the multi-second black screen.
- Point the naming screen at Radical Red's relocated nine-frame rival sheet at
  `0x0EE82B0`; the vanilla address is erased in the v4.1 ROM.
- Resolve CFRU's extended `0x5000..0x51FF` variables for Pokémon preview, gift,
  egg, and cry commands. This fixes `showmonpic 0x5124` and `givemon 0x5124`
  receiving the literal invalid species 20772 during the Turtwig sequence.
- Add exact-ROM regressions for all nine rival frames, the live rival frame
  table, the authentic/fail-safe menu split, and Turtwig preview plus gift.
- Re-run the content-aware audit across all 9,242 generated RGBA assets, all
  257 overworld mappings (including Red and Mom), 1,376 Pokémon art/icon sets,
  154 trainer sheets, and 750 item icons.
- Bump the private cache schema to 11 so the corrected naming asset is rebuilt
  automatically instead of reusing an earlier black portrait cache.

## 0.5.6 — Complete sprite audit and visible Game Modes

- Clear the completed `FADE_TO_BLACK` veil that the bedroom script leaves over
  Radical Red's actual Difficulty, Minimal Grinding, and Randomizer setup menu.
- Wrap that ROM multichoice renderer with numeric-color compatibility and a
  primitive-only final pass for affected Android renderers.
- Test that exact live Game Modes list both normally and with its ROM chrome
  deliberately failed, rather than testing only the unrelated engine Options
  screen.
- Audit all 9,242 generated RGBA assets and independently validate all 257
  object-event sheets, 1,376 Pokemon front/back/shiny/icon sets, 154 trainer
  sheets, and 750 item icons against the v4.1 ROM tables and palettes.
- Replace the erased vanilla Rock Smash graphics address with Radical Red's
  exact four-frame rock sheet from live object-event graphics ID 96.
- Bump the private cache schema to 10 so every prior generated asset cache is
  rebuilt on first launch.

## 0.5.5 — Correct characters and fail-safe Options

- Point object events at Radical Red's real 257-entry overworld graphics table
  at `0x0EB1000`, fixing the black replacement player and restoring Mom instead
  of incorrectly reading both IDs from the separate Pokemon/follower table.
- Validate Red, Leaf, Mom, the first expanded graphic, and the final table
  entry directly from the exact ROM before committing generated sprite sheets.
- Preserve Radical Red's expanded graphics IDs 152–256 at runtime instead of
  applying FireRed's old `>= 152` fallback.
- Finish every Options frame with a self-contained numeric/primitives renderer,
  so usable controls replace the black clear even when Android silently drops
  the normal menu chrome without raising an error.
- Bump the private cache schema to 9, forcing every bad 0.5.4 sprite cache to
  regenerate automatically on first launch.

## 0.5.4 — Sprite palettes and visible Options screen

> Superseded by 0.5.5: this release misidentified the 289-entry
> Pokemon/follower table as the object-event table, corrupting ordinary
> characters despite the palette validation below.

- Read Radical Red v4.1's exact 451-entry expanded object-event palette table
  instead of FireRed's old 18-entry table.
- Validate all 289 overworld graphics and all 230 palette tags they use before
  accepting a generated cache, preventing silent all-black sprite fallbacks.
- Keep the stock Game3 Options screen visible on Android graphics shims that
  accept numeric color arguments but reject LÖVE's table-color overload.
- Bump the private cache schema to 8 so installs made by 0.5.3 automatically
  regenerate the corrected overworld graphics on their first 0.5.4 start.
- Audit all 9,274 generated RGBA assets, including every overworld, Pokémon
  front/back/shiny/icon, trainer, interface, and field-effect sprite family.

## 0.5.3 — Original setup flow and current-app compatibility

- Restore Radical Red v4.1's exact new-game setup prompts, labels, nesting,
  and order by exposing all six cartridge-owned dynamic choice lists.
- Keep setup entirely inside the original map script: no substitute mod menu,
  extra options, or launcher integration is added.
- Activate the original normal/scaled species, ability, and learnset
  randomizers from the cartridge flags, full trainer ID, and exact ROM pools.
- Implement the ROM reader interface expected by gen1recomp 0.3.20 while
  retaining compatibility with stock 0.3.5.
- Add exact-ROM regressions that traverse the setup menus and compare all
  randomizer paths with the v4.1 source tables.

## 0.5.2 — Nonblocking Android first launch

- Return from the launcher Play transition before a cold 206 MiB private-cache
  conversion begins, then advance the work between rendered frames.
- Show an opaque **Preparing Radical Red** screen with live stage and item
  progress instead of leaving Android on a grey/transparent activity.
- Pause vanilla simulation until the Radical Red dataset is fully mounted,
  then rebuild the title state and activate the separate RR save scope
  automatically.
- Keep conversion failures on screen with the exact failing stage and message,
  while also recording the error in the mod-private diagnostic cache.
- Reuse already completed title, naming, and audio assets after an interrupted
  first launch instead of rebuilding them unnecessarily.
- Add a deferred-bootstrap regression and make the exact-ROM cold gate verify
  196 resumable checkpoints with no desktop chunk longer than three seconds.

## 0.5.1 — Android launch fix

- Replace the stock 4 MiB numeric-table ROM cache during conversion with a
  bounded, string-backed reader whose working set is capped at 4 MiB.
- Extract scripts first and process each of the 60 tileset pairs separately,
  releasing map, atlas, and animation working data between pairs.
- Bound temporary species-sprite allocations during the 1,376-species pass.
- Preserve identical private-cache outputs and automatic activation without
  changing the launcher, executable, APK, or engine.
- Bump the private cache schema to 7 so failed or partial 0.5.0 conversions are
  rebuilt cleanly.
- Add cold and cached exact-loader release gates under a 256 MiB address-space
  ceiling; both reach the fully hydrated Radical Red runtime.

## 0.5.0 — Runtime total-conversion candidate

- Mount Radical Red's private extracted cache as the active Game3 dataset when
  the mod is enabled; no launcher or engine file changes are required.
- Extract and hydrate 425 maps plus scripts, text, events, encounters,
  trainers, graphics, UI chrome, audio, and the Radical Red title screen.
- Install expanded registries for 1,376 species, 1,004 moves, 282 abilities,
  and 750 items, including the relocated Radical Red item-icon table.
- Add a dedicated Radical Red save scope and automatic title-menu refresh.
- Implement all 72 `callnative` targets used by the v4.1 scripts.
- Add level-cap, starter, egg, follower, roaming, NG+, facility, rental-party,
  simulator, and story utility behavior.
- Add raid generation, capture/reward flow, barriers, Max-move conversion,
  repeated boss turns, stat nullification, KO boosts, and loss rules.
- Add callback coverage, runtime orchestration, raid combat, exact-loader,
  and mod-disabled isolation regressions.
- Bump the private cache schema so older partial caches rebuild automatically.

## 0.2.0 — CP2A Fairy and move split

- Kept the launcher and engine source untouched; all compatibility is mod-local.
- Declared the stock `engine_internals` permission used by runtime wrappers.
- Added exact parsing and validation of RR's 12-byte battle-move records.
- Added exact parsing and validation of RR's dense 24×24 type chart.
- Promoted Fairy type ID 23 for 23 verified FireRed-range species.
- Applied RR physical/special/status categories to all 354 playable FireRed moves.
- Added stack-safe category context for damage, accuracy, AI, nested moves,
  locked/encored moves, and interactive coroutine resume.
- Preserved vanilla type-based category behavior outside an RR move context.
- Added wrapper, real stock damage-module, and upgraded stock Loader tests.
- Added a CP2 source audit and updated the parity/handoff documentation.

## 0.1.0 — CP1 safe species overlay

- Declared the exact Radical Red v4.1 ROM as a private required import.
- Added Dynamic Pokémon Expansion pointer and species-table parsing.
- Added strict header, size, digest-metadata, species-count, and sentinel checks.
- Applied eight FireRed-compatible species field groups across 386 records.
- Detected and skipped internal reserved slots 252–276.
- Added deterministic source audit tooling and standalone Lua tests.
- Added a real headless gen1recomp Gen 3 Loader integration test.
- Passed modkit lint, Gen 3 compatibility checks, and fixture validation.
- Documented the parity contract, current limitations, and staged roadmap.
