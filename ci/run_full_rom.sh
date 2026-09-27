#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mod_root="$repo_root/mod"
engine_dir="${1:?usage: ci/run_full_rom.sh ENGINE_DIR RR_ROM FIRERED_ROM}"
rr_rom="${2:?missing Radical Red v4.1 ROM}"
firered_rom="${3:?missing FireRed v1.0 ROM}"
luajit_bin="${LUAJIT_BIN:-$(command -v luajit)}"

rr_md5="8529f3a45d32bce4da637976fcf269d4"
firered_sha1="41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc"

test -x "$luajit_bin"
test "$(stat -c '%s' "$rr_rom")" = "33554432"
test "$(md5sum "$rr_rom" | awk '{print $1}')" = "$rr_md5"
test "$(stat -c '%s' "$firered_rom")" = "16777216"
test "$(sha1sum "$firered_rom" | awk '{print $1}')" = "$firered_sha1"

echo "== Exact source audit =="
python3 "$mod_root/tools/verify_sources.py" \
  --firered "$firered_rom" --radical-red "$rr_rom"

echo "== Exact-ROM table and battle tests =="
(
  cd "$mod_root"
  "$luajit_bin" tests/rr_rom_test.lua "$rr_rom"
  "$luajit_bin" tests/rr_battle_test.lua "$rr_rom"
)
(
  cd "$engine_dir"
  "$luajit_bin" mods/radical_red_experience/tests/rr_facilities_test.lua "$rr_rom"
  "$luajit_bin" mods/radical_red_experience/tests/battle_damage_test.lua "$rr_rom"
)

cache_root="$(mktemp -d "${RUNNER_TEMP:-/tmp}/rr-full-rom.XXXXXX")"
trap 'rm -rf -- "$cache_root"' EXIT
modern_cache="$cache_root/modern"
legacy_cache="$cache_root/legacy"
mkdir -p "$modern_cache" "$legacy_cache"

run_loader() {
  local cache_dir="$1"
  local legacy="$2"
  local label="$3"
  echo "== $label =="
  (
    ulimit -v 262144
    cd "$engine_dir"
    RR_TEST_CACHE_DIR="$cache_dir" \
    RR_TEST_LEGACY_ANDROID_READER="$legacy" \
      "$luajit_bin" \
      mods/radical_red_experience/tests/engine_loader_test.lua "$rr_rom"
  )
}

run_loader "$modern_cache" 0 "Modern Android reader cold launch"
run_loader "$modern_cache" 0 "Modern Android reader cached relaunch"
run_loader "$legacy_cache" 1 "Legacy/readBytes Android reader cold launch"
run_loader "$legacy_cache" 1 "Legacy/readBytes Android reader cached relaunch"

generated_root="$modern_cache/mod_cache/radical_red_experience/data/generated/gba"
python3 "$mod_root/tools/audit_generated_sprites.py" "$rr_rom" "$generated_root"

echo "PASS full-ROM certification gate"
