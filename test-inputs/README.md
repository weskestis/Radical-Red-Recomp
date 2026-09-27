# Private test inputs

The `main` and hardening branches contain no ROM files.

The temporary `private-test-inputs` branch supplies one CI-only archive split
into 44 deterministic chunks:

- `test-inputs/private-rom-inputs.zip.part-000` through `part-043`
- chunks `000` through `042`: 524,288 bytes each
- chunk `043`: 121,797 bytes
- concatenated archive SHA-256:
  `004b334dd312508b284982dffd01e32e7ccfafd42dd4e80ffd0f639c3ce5cb10`

The archive contains these exact inputs:

- `radical_red_v4_1.gba`
  - size: 33,554,432 bytes
  - MD5: `8529f3a45d32bce4da637976fcf269d4`
- `firered_v1_0.gba`
  - size: 16,777,216 bytes
  - SHA-1: `41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc`

Workflows reconstruct and verify the archive inside the runner's temporary
directory. These inputs must never be placed in packages, logs, caches,
releases, or uploaded artifacts.
