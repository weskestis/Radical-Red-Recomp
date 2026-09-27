#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
engine_dir="${1:-$repo_root/.ci/engine}"
engine_repo="https://github.com/bryanthaboi/gen1recomp.git"
engine_tag="v0.3.20"
engine_commit="64dd9cb3a377b398b6132d223a121878f68b4b07"

if [[ -e "$engine_dir" ]]; then
  echo "Engine destination already exists: $engine_dir" >&2
  exit 1
fi

mkdir -p "$(dirname "$engine_dir")"
git clone --branch "$engine_tag" --depth 1 "$engine_repo" "$engine_dir"

actual_commit="$(git -C "$engine_dir" rev-parse HEAD)"
if [[ "$actual_commit" != "$engine_commit" ]]; then
  echo "Engine pin mismatch: expected $engine_commit, got $actual_commit" >&2
  exit 1
fi

mod_link="$engine_dir/mods/radical_red_experience"
if [[ -e "$mod_link" || -L "$mod_link" ]]; then
  echo "Engine already contains $mod_link" >&2
  exit 1
fi
ln -s "$repo_root/mod" "$mod_link"

printf '%s\n' "$engine_dir"

