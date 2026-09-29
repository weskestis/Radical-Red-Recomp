# Verification report — Radical Red 0.5.19 release candidate

The table below preserves the last fully executed exact-ROM release gate from
0.5.16. Private ROM bytes and generated assets are not part of the mod package.

The 0.5.19 delta has source-level regressions and package checks committed, but
the current GitHub Actions service has not assigned either certification job a
runner: every recent run ends with `runner_id: 0` and zero executed steps.
Therefore the new 0.5.19 rows below are **PENDING**, not PASS, until the exact-ROM
and ROM-free jobs can actually execute.

| Area | Result |
|---|---|
| ROM size, digest, header, version marker, and table sentinels | PASS |
| Private extraction and cache schema | PASS |
| Cold first launch under 256 MiB address-space ceiling | PASS |
| Frame-by-frame cold bootstrap and setup overlay | PASS |
| Cached relaunch under 256 MiB address-space ceiling | PASS |
| Original setup prompts and all nested v4.1 choice lists | PASS |
| First setup warning visible before any button input | PASS |
| All 16 custom lists use ROM labels rather than badge names | PASS |
| Running shoes active before the first playable step | PASS |
| All five bedroom-console codes and persistent flags | PASS |
| DexAll, TeamPreview, and EZCatch host behavior | PASS |
| DexNav registration, scanning, search levels, chains, rods, and latched R/SELECT shortcuts | PASS |
| DexNav encounter bonuses and complete battle payloads | PASS |
| Woyaopp Viridian service and SO2Toxic item branches | PASS |
| Live party-menu slot-two Combee gender change | PASS |
| Region-selected starter is preserved with species randomization active | PASS |
| Kanto rival, Brendan/May, and Champion branch parties stay fixed | PASS |
| Normal/scaled species, ability, and learnset mappings | PASS |
| Stock gen1recomp 0.3.5 and 0.3.20 loaders | PASS |
| Android ROM readers using strings, numeric byte arrays, or `get` | PASS |
| Full cold extraction with `readString` deliberately unavailable | PASS |
| 425/425 native map layouts and script shard loading | PASS |
| 1,324 warp records and 116 outdoor connection records | PASS |
| 306 odd-sized maps normalized to true ROM bounds | PASS |
| 134 wild maps and 4,866 valid base/day/night encounter slots | PASS |
| 177 species-zero placeholders removed; final battle guard active | PASS |
| All 4,866 wild slots have moves at minimum and maximum levels | PASS |
| Route 23–Indigo Plateau reciprocal path | PASS |
| Three west edges on Six Island Water Path retained | PASS |
| 1,376 species / 1,004 moves / 282 abilities / 750 items | PASS |
| Radical Red title data and expanded item icons | PASS |
| All three RR object-graphics tables and 546 physical ROM mappings | PASS |
| 545 addressable sheets and selector-qualified map object IDs | PASS |
| Exact 451-entry object palette table and all 397 used tags | PASS |
| Expanded and indirect 16-bit graphics IDs at runtime | PASS |
| Pallet Town Stufful sprite, text species, and cry identity | PASS |
| Pokémon, trainer, item, interface, field-effect, and all RGBA assets | PASS — 9,530 audited |
| Rock Smash field effect sourced from live RR graphics ID 96 | PASS |
| Relocated rival naming sheet and all nine live frame-table entries | PASS |
| RR six-card party chrome, icon, text, and HP-bar geometry | PASS |
| RR Known Moves detail panes and selection cursor geometry | PASS |
| All 1,376 RR battle sprite offsets/elevations installed | PASS |
| Cyndaquil back-sprite baseline and signed form offset sentinels | PASS |
| Fixed status tile with independent Pokémon bounce | PASS |
| Seviian Ursaring species/form identity preserved | PASS |
| Actual Game Modes list clears active and completed black fade veils | PASS |
| Authentic Game Modes renderer on normal frames | PASS |
| Portable Game Modes fallback after forced chrome failure | PASS |
| Normal Options draw past its black backdrop on the Android color shim | PASS |
| Authentic Options renderer on normal frames | PASS |
| Portable Options fallback after forced renderer failure | PASS |
| Extended CFRU variables in preview/gift/egg/cry commands | PASS |
| Exact Turtwig `showmonpic` and `givemon` path through variable `0x5124` | PASS |
| Post-rival gained-EXP sequence and CFRU `B_BUFF3` expansion | PASS |
| All expanded battle placeholders, including sparse Roost defender text | PASS |
| Modern category split, Fairy, and type effectiveness | PASS |
| 72/72 real script-native targets handled | PASS |
| Facilities and rental-party behavior | PASS |
| Raid battle behavior | PASS |
| Story and follower behavior | PASS |
| Separate save scope and automatic activation | PASS |
| Disabled-mod vanilla isolation | PASS |
| No ROM, patch, cache, executable, or extracted asset in package | PASS |
| Modkit lint / Gen 3 check / strict validation | PASS |
| Manual graphical device run | NOT RUN |

## 0.5.19 delta gate

| Area | Current status |
|---|---|
| Early RR save scope binding; schema-15/16/17/18 targeted upgrades; truncated/wrong-ROM schema-19 audio and schema-18/19 animation cache rejection | PENDING — runner unavailable |
| FireRed launcher context preserved for RR save import/export, legacy-stamp/ITEM_NONE normalization, and failed-slot rollback | PENDING — runner unavailable |
| Physical left-shoulder Skills path plus Auto Run / Time Changer / Infinite Repel / PokéVial | PENDING — runner unavailable |
| DexNav R/SELECT field shortcuts repair serialized ITEM_NONE=0 while preserving real registered key items | PENDING — runner unavailable |
| Complete extracted trainer-table census preserves every authored boss/rival while ordinary trainers still randomize | PENDING — runner unavailable |
| Wishing Piece transactionally reactivates a cleared den, validates the reroll before spending, and advances/wraps raid sequence | PENDING — runner unavailable |
| Fairy type badge extracted from CFRU tile `0x100` and rendered through Summary/TM-style and Pokédex surfaces | PENDING — runner unavailable |
| Poké Rider item 363 bypasses Fame Checker in Bag/direct use and releases the field lock on map-open failure | PENDING — runner unavailable |
| Field BGM fanfare recovery / pre-battle map-song return / live Elite Four VS intro identity | PENDING — runner unavailable |
| U-turn / Volt Switch / Flip Turn perform normal post-hit pivot switching | PENDING — runner unavailable |
| Full 1,376-row Radical Red cry table and modern-species cry mapping | PENDING — runner unavailable |
| CFRU/RR 526-row song/SFX table and expanded-move sound references | PENDING — runner unavailable |
| Full 1,004-move CFRU animation pack / 371 particle rows / 77 backgrounds | PENDING — runner unavailable |
| U-turn / Fairy Wind / Play Rough / Dazzling Gleam real visual+SFX scripts | PENDING — runner unavailable |
| Reported modern move scripts contain no unresolved CFRU callback/task pointers | PENDING — runner unavailable |
| Package manifest / SHA-256 cross-reference / private-content policy | PASS — source-level audit |

The exact loader integration test executes discovery, required-import
validation, permission setup, extraction, cache mounting, data hydration,
runtime hooks, original setup navigation, randomizer mapping, battle rules,
the distinct authentic and emergency Game Modes/Options render paths, the
expanded-variable Turtwig sequence with species randomization enabled,
selector-qualified Stufful mapping, all 16 custom list-menu IDs, every live map
connection/landing, and teardown using the stock engine modules. Modern and
readBytes-only empty-cache conversions plus cached relaunches complete under a
256 MiB limit. The cold path yields at 194 checkpoints and does not expose the
vanilla game loop before Radical Red is fully active.
