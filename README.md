# Radical Red Recomp

Private hardening and certification workspace for the Radical Red v4.1
total-conversion mod on gen1recomp.

## Current baseline

- Mod release: `0.5.13`
- Engine: gen1recomp `v0.3.20`
- Engine commit: `64dd9cb3a377b398b6132d223a121878f68b4b07`
- Release ZIP SHA-256:
  `9af718654f33c55f95948f6f48d5010457e1b58cc6028df94375ef537f2d03d9`
- Radical Red v4.1 MD5: `8529f3a45d32bce4da637976fcf269d4`

The installable mod source is under [`mod/`](mod/). It remains ROM-free and
must pass its own `SHA256SUMS.txt` manifest before packaging.

## Branches

- `main`: locked, tester-approved release baselines.
- `hardening/v0.6.0`: certification work and regression fixes.
- `private-test-inputs`: temporary private ROM inputs used only by CI. This
  branch is intentionally excluded from workflow triggers and releases.

## Certification

`.github/workflows/certification.yml` runs two independent gates:

1. The ROM-free gate validates every source checksum, runs the complete
   synthetic/unit suite, performs strict Gen 3 compatibility checks, and
   produces the release package twice to prove byte-for-byte reproducibility.
2. The private full-ROM gate verifies both ROM identities, executes exact-ROM
   table and battle tests, performs modern and legacy Android cold/cached
   launches under a 256 MiB address-space ceiling, and audits every generated
   sprite asset.

No ROM, generated cache, or extracted asset is uploaded as a workflow artifact
or included in a release package.

## Local run

```bash
ci/prepare_engine.sh .ci/engine
ci/run_rom_free.sh .ci/engine
ci/run_full_rom.sh .ci/engine /path/to/radical_red_v4_1.gba /path/to/firered_v1_0.gba
```

