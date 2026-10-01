#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mod_root="$repo_root/mod"
engine_dir="${1:?usage: ci/run_rom_free.sh ENGINE_DIR}"
luajit_bin="${LUAJIT_BIN:-$(command -v luajit)}"

test -x "$luajit_bin"
test -f "$engine_dir/tools/modkit.py"
test -L "$engine_dir/mods/radical_red_experience"

echo "== Source and package policy =="
(cd "$mod_root" && sha256sum -c SHA256SUMS.txt)
python3 "$mod_root/tools/check_package.py" "$mod_root"

echo "== ROM-free regression suite =="
engine_tests=(
  async_bootstrap_test.lua
  callback_coverage_test.lua
  main_overlay_test.lua
  rr_encounters_test.lua
  rr_facilities_test.lua
  rr_raids_test.lua
  stream_rom_compat_test.lua
  vanilla_off_test.lua
)
for test_file in "${engine_tests[@]}"; do
  (cd "$engine_dir" && "$luajit_bin" \
    "mods/radical_red_experience/tests/$test_file")
done

mod_tests=(
  rr_mechanics_test.lua
  rr_natives_test.lua
  rr_qol_test.lua
  rr_randomizer_test.lua
  rr_save_transfer_test.lua
  rr_story_test.lua
)
for test_file in "${mod_tests[@]}"; do
  (cd "$mod_root" && "$luajit_bin" "tests/$test_file")
done

echo "== Strict modkit gates =="
(
  cd "$engine_dir"
  MODKIT_LUAJIT="$luajit_bin" python3 tools/modkit.py lint "$mod_root"
  MODKIT_LUAJIT="$luajit_bin" python3 tools/modkit.py \
    gen3check --strict "$mod_root"
  MODKIT_LUAJIT="$luajit_bin" python3 tools/modkit.py \
    validate --strict --base fixture "$mod_root"
)

echo "== Reproducible package =="
package_tmp="$(mktemp -d "${RUNNER_TEMP:-/tmp}/rr-package.XXXXXX")"
trap 'rm -rf -- "$package_tmp"' EXIT
first="$package_tmp/Radical-Red-0.5.19-a.zip"
second="$package_tmp/Radical-Red-0.5.19-b.zip"
(
  cd "$engine_dir"
  SOURCE_DATE_EPOCH=0 MODKIT_LUAJIT="$luajit_bin" \
    python3 tools/modkit.py pack --base fixture -o "$first" "$mod_root"
  SOURCE_DATE_EPOCH=0 MODKIT_LUAJIT="$luajit_bin" \
    python3 tools/modkit.py pack --base fixture -o "$second" "$mod_root"
)
cmp "$first" "$second"
unzip -t "$first"

extract_dir="$package_tmp/extracted"
mkdir -p "$extract_dir"
unzip -q "$first" -d "$extract_dir"
(cd "$extract_dir" && sha256sum -c SHA256SUMS.txt)
python3 "$mod_root/tools/check_package.py" "$extract_dir"

python3 - "$first" <<'PY'
import pathlib
import sys
import zipfile

archive = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(archive) as package:
    names = package.namelist()
    forbidden = [
        name for name in names
        if pathlib.PurePosixPath(name).suffix.lower() in {".gba", ".gb", ".gbc", ".ips", ".bps", ".ups"}
        or any(part.lower() in {"cache", "mod_cache", "baseroms"}
               for part in pathlib.PurePosixPath(name).parts)
    ]
    if forbidden:
        raise SystemExit("forbidden release payloads: " + ", ".join(forbidden))
print("PASS reproducible ROM-free package")
PY

if [[ -n "${RELEASE_PACKAGE_OUT:-}" ]]; then
  mkdir -p -- "$(dirname -- "$RELEASE_PACKAGE_OUT")"
  cp -- "$first" "$RELEASE_PACKAGE_OUT"
  sha256sum "$RELEASE_PACKAGE_OUT"
  echo "PLAYABLE_PACKAGE $RELEASE_PACKAGE_OUT"
fi
