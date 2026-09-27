# Private test inputs

The `main` and hardening branches contain no ROM files.

The temporary `private-test-inputs` branch supplies these exact CI-only files:

- `test-inputs/radical_red_v4_1.gba`
  - size: 33,554,432 bytes
  - MD5: `8529f3a45d32bce4da637976fcf269d4`
- `test-inputs/firered_v1_0.gba`
  - size: 16,777,216 bytes
  - SHA-1: `41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc`

Workflows copy these inputs into the runner's temporary directory. They must
never be placed in packages, logs, caches, releases, or uploaded artifacts.

