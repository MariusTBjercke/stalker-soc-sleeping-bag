# STALKER SoC Sleeping Bag

This Lua mod adds a reusable sleeping-bag gameplay feature for manual PC
installations of **S.T.A.L.K.E.R.: Shadow of Chornobyl Enhanced Edition**.

The design takes behavioral inspiration from the 2007 ABC Sleeping Bag Mod.
This repository contains independently authored code and assets only; it does
not contain ABC code, textures, XML, or icon atlases.

## Current status

Version `0.1.0` targets the supported build only: EE executable
`1.10.3+68-42`, Steam build `24067120`. Other builds are not supported until
verified. Automated checks pass; runtime acceptance evidence is collected in
[RUNTIME-TESTS](docs/RUNTIME-TESTS.md).

## Features

- A reusable sleeping bag is provisioned automatically after spawn, load,
  and use, including in existing saves.
- The sleep menu offers 1, 3, and 9 hour sleeps and a bounded
  "Sleep until healed" action, with mouse, keyboard, Escape, and EE
  controller navigation.
- Resting is refused with a localized reason while talking, bleeding,
  heavily irradiated, or within ten seconds of combat damage.
- Damage during sleep aborts immediately without healing; time factor,
  input, weapon, and overlay recover through one idempotent cleanup path.

## Installation

Prerequisite: 7-Zip with the X-Ray database plugin, because the deployer
materializes missing shared files from the game's `resources/configs.db`.
See [Development](docs/DEVELOPMENT.md) for the plugin setup and
`config/local.json` paths.

Review before writing anything. The deployer is dry-run by default:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/deploy.ps1
```

Inspect the printed plan (copies and shared-file patches with origins and
hashes). When it looks right, apply:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/deploy.ps1 -Apply
```

Repeated apply is idempotent. A timestamped backup of pre-existing loose
files is created under `out/backups/`.

## Removal

Review first:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/uninstall.ps1
```

Then apply. Unchanged mod-owned files are deleted; mod-owned files changed
after deployment are reported and kept; shared files lose only the marked
lines:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/uninstall.ps1 -Apply
```

## Documentation

| Document | Contents |
| --- | --- |
| [Architecture](docs/ARCHITECTURE.md) | Verified engine facts and pending probes |
| [Compatibility](docs/COMPATIBILITY.md) | Supported build and coexistence boundary |
| [Development](docs/DEVELOPMENT.md) | Configuration, extraction, checks, and runtime policy |
| [Runtime tests](docs/RUNTIME-TESTS.md) | Disposable-save acceptance evidence |
| [Design specification](docs/superpowers/specs/2026-09-18-sleeping-bag-design.md) | Approved feature behavior and constraints |
| [Implementation plan](docs/superpowers/plans/2026-09-18-sleeping-bag-implementation.md) | Task-by-task delivery plan |

## License

Repository code written for this project is under the MIT license. Game files,
third-party reference material, and ABC material are not covered by that
license. See [LICENSE](LICENSE).
