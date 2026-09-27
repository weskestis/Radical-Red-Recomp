# Radical Red

Radical Red 0.5.16 is a FireRed-only runtime total conversion for unmodified
gen1recomp 0.3.5 and 0.3.20. It validates the player's own Pokémon Radical Red
v4.1 ROM, builds a private cache on first start, and mounts that data as the
active game. No launcher, executable, APK, or engine file is modified.

When the mod is enabled, starting FireRed activates Radical Red automatically.
There is no second in-game switch. Disabling the mod and restarting restores
vanilla FireRed, and Radical Red uses its own save scope so the two games do
not overwrite each other's saves.

## What is live

- 425 Radical Red maps with their layouts, warps, objects, encounters, text,
  scripts, movements, shops, trainers, and event data;
- the expanded 1,376-species, 1,004-move, 282-ability, and 750-item registries;
- expanded Pokémon front/back sprites, their full 1,376-entry battle
  coordinate/elevation registries, icons, palettes, learnsets, evolutions,
  TM/HM and tutor compatibility, and Pokédex data;
- Radical Red title, menu/battle chrome, item icons, overworld graphics,
  naming assets, field effects, and ROM audio;
- all 545 addressable object-event sprites from Radical Red's ordinary,
  Pokémon/follower, and player-customization tables using its 451-entry
  palette registry, including the correct player, NPCs, trainers, Pokémon,
  and objects;
- Radical Red's physical/special split, Fairy type, and 24×24 type chart;
- Radical Red v4.1's original new-game setup prompts and menus, including its
  exact difficulty, Minimal Grinding Mode, species/ability/learnset randomizer,
  and normal/scaled species choices;
- the original trainer-ID-seeded species, ability, and learnset randomizer
  mappings, using the candidate pools embedded in the player's v4.1 ROM,
  while preserving every starter/region-dependent rival party selected by
  the cartridge;
- all 72 native callbacks referenced by the v4.1 script set, including level
  caps, random starters/eggs, followers, facilities, and story utilities;
- running shoes from the first step, plus the original bedroom-console codes:
  `SO2Toxic`, `DexAll`, `Woyaopp`, `TeamPreview`, and `EZCatch`;
- a functional current-area DexNav with persistent registration, search levels,
  chains, scan encounters, rod requirements, egg moves, hidden abilities,
  held items, IV potential, and reliable registered R/SELECT field shortcuts;
  `DexAll` reveals unseen entries, and an assigned key item keeps SELECT;
- raid encounters, rewards, capture flow, barriers, Max moves, repeated boss
  attacks, stat nullification, and raid loss rules;
- ROM-backed facility trainers, spreads, rentals, and party restoration.

The remaining compatibility boundary is documented in
`docs/PORTING_MATRIX.md`: gen1recomp's host battle engine still does not model
every CFRU-only modern move effect, ability trigger, held-item trigger, or GBA
animation byte-for-byte. The converted world and registries are live, but this
build is not presented as perfect battle-engine parity.

## Required files

| File | Size | MD5 | SHA-1 |
|---|---:|---|---|
| Pokémon FireRed Version (USA), Rev 0 | 16,777,216 | `e26ee0d44e809351c8ce2d73c7400cdd` | `41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc` |
| Pokémon Radical Red v4.1, fully patched ROM | 33,554,432 | `8529f3a45d32bce4da637976fcf269d4` | `964f951a0fdaf209e4ea1344883ef0d557bb3a80` |

The required Radical Red file is the complete 32 MiB patched `.gba`, not the
small `.ups`/`.ips` patch file. A wrong-size message means the selected file is
not the required final ROM image.

## Install

1. In an unmodified supported launcher (gen1recomp 0.3.5 or 0.3.20), import the
   exact FireRed ROM listed above as the base game.
2. Import the Radical Red mod package through the normal Mods screen.
3. When prompted, choose the exact 33,554,432-byte Radical Red v4.1 `.gba`.
4. Enable **Radical Red** and start FireRed.
5. Leave the **Preparing Radical Red** screen open until it reaches the title.
   The one-time private cache is about 216 MiB; later starts reuse it.

On a new save, the setup is not in the launcher or mod menu. Radical Red's own
cartridge script opens it automatically in the upstairs bedroom. Answer **No**
to “play without any custom options” to configure the original choices.

The first start opens the game, displays live conversion progress, and keeps
Android responsive while the bounded ROM reader and staged extractor do their
work. Interrupted cache work is safely resumed. If a conversion step fails,
the exact stage and error remain visible instead of silently returning to the
launcher. Version 0.5.16 negotiates the string, numeric byte-array, and
byte-at-a-time ROM-reader interfaces found across supported Android payloads.
Its legacy numeric-array path copies bounded ROM pages in blocks so conversion
does not stall the Android main thread once per byte.
It also rebuilds older caches automatically, regenerating the corrected
overworld and Rock Smash assets plus Radical Red's relocated rival portrait.
Map objects now retain CFRU's graphics-table selector, so overworld Pokémon
such as Pallet Town's Stufful use the sprite that matches their text and cry.
The regional starter gift is also protected from being randomized a second
time after the cartridge has already chosen it from the selected region.
The same protection now covers every Kanto-rival, Brendan/May, and Champion
party branch, so the opponent roster remains paired with the starter/region
choice made by Radical Red's own scripts.
Radical Red's Black/White-style six-card party layout and reversed Known Moves
detail panes use their v4.1 ROM geometry instead of FireRed's stock window and
text coordinates. The unusual turquoise multi-armed Ursaring at species
`0x04FF` is the intended Ghost/Fighting Seviian form and is not replaced.
The new-game warning clears its unmatched black fade on its first rendered
frame. All 16 cartridge-defined custom lists—including starter region,
nature, tutor, fossil, type, ball, elevator, and game-mode lists—are extracted
from the ROM instead of falling through to FireRed badge names. CFRU's
expanded EXP/team/catch battle-text fields are also translated by the runtime.
The complete 425-map world is checked before its cache is accepted: 425 native
layouts, 1,324 warps, and all 116 outdoor connections must resolve. Odd-sized
maps use their true ROM collision bounds rather than their even-padded storage
dimensions, and duplicate same-direction connections remain intact.
Wild encounters now use Radical Red's relocated day/night registries rather
than FireRed's fallback table. All 134 encounter maps and 4,866 usable slots
are validated, and intentional species-zero placeholders are removed before
they can reach battle construction.
Running shoes are granted on new games and repaired on existing saves. The
five case-sensitive bedroom-console codes retain their original flags and
effects; `TeamPreview` also accepts SELECT for Android overlays without an L
button. Party selection is committed before the next ROM callback, so choosing
Combee or another supported Pokémon outside slot one reaches the correct
gender/form/level operation.
DexNav's former display-only list now executes its Register, Scan, and Cancel
actions and persists search progress in the Radical Red save. Scan encounters
carry CFRU's level, shiny-check, egg-move, ability, held-item, and IV-potential
bonuses into the live battle. Its field control now latches queued/held input
across turbo frames, and Android SELECT scans when it is not reserved for a
registered key item. Battle sprites use Radical Red's own expanded baselines
instead of FireRed's table—fixing Cyndaquil's cropped back sprite—and the
status tile no longer bobs with the active Pokémon. Roost and other CFRU
effect text can recover the active self-target battler when the ROM script
omits an explicit defender, without replacing a defender supplied by the
normal battle engine.

## Verification

The source tree includes deterministic tests for ROM identity, extraction,
runtime mounting, expanded data, battle categories/type rules, all native
callback families, facilities, raids, story/followers, automatic activation,
and mod-disabled vanilla isolation. The exact stock-loader integration test
also verifies Radical Red's title data, expanded 750-item icon table, all 545
addressable overworld sheets and 546 physical ROM mappings, Red, Mom, Stufful,
and custom-player table sentinels, expanded graphics IDs,
all nine relocated rival naming frames, the regular Options renderer, and
Radical Red's separate Game Modes choice renderer. It also verifies a
no-input-visible first setup frame, all 16 ROM-defined custom lists, every map
connection/landing (including Route 23–Indigo Plateau), the post-rival
gained-EXP sequence, and the exact extended-variable Turtwig preview and gift
commands that use `0x5124`. It also enters every bedroom-console code, checks
its cartridge branch and persistent flag, exercises all four host-side QoL
effects, generates complete DexNav battle payloads, validates that all 4,866
wild slots have usable moves at their encounter levels, exercises Roost's
sparse and ordinary battle-text paths, and reproduces a second-slot Combee
gender change through the live party menu.

The release gate is recorded in `docs/CHECKPOINT_STATUS.md`. It includes both
supported stock loaders, the original setup-menu path, live randomizer
mappings, cold and cached launches under a 256 MiB address-space ceiling, and
the nonblocking frame-loop bootstrap. Its 9,530-asset audit checks every
generated RGBA file for truncation and unexpected blank/black output, then
independently checks the core sprite families against the v4.1 ROM mappings
and palettes. A post-fix graphical LÖVE device playthrough was not available
in this build environment; that remaining manual test is reported explicitly
rather than assumed.

## Legal

This package contains integration code and documentation only. It contains no
ROM, patch, or extracted game assets. All game data is derived locally from
the player's launcher-validated private Radical Red v4.1 ROM.
