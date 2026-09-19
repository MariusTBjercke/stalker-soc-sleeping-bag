# Changelog

All notable changes to this project are documented here.

## 0.1.0 - 2026-09-19

First manual-install release candidate for S.T.A.L.K.E.R.: Shadow of
Chornobyl Enhanced Edition (`1.10.3+68-42`, Steam build `24067120`).

- Added the reusable `soc_sleeping_bag` inventory item with automatic
  provisioning after spawn, load, and use.
- Added the sleep menu with 1, 3, and 9 hour sleeps, a bounded
  "Sleep until healed" action, cancel, Escape, and EE controller
  navigation.
- Added the sleeping state machine with single-capture time factor,
  damage/death aborts without healing, idempotent cleanup, and recovery
  from interrupted sessions. Elapsed sleep time is measured with the
  engine's CTime `diffSec`. The sleep also aborts when health drops below
  its starting value (hunger, radiation, bleeding), so fast-forwarding cannot
  starve or irradiate the actor to death. A 60 s real-time timeout and
  guarded start and time reads make sure the fast time factor cannot leak.
- Added the sleep menu layout following EE's own dialog pattern (full-screen
  window, absolute coordinates, vanilla button size).
- Added a custom 2x2 inventory icon. EE draws inventory icons from one shared
  atlas, so the deployer reads the game's own `ui_icon_equipment.dds` from
  `resources.db10` at a pinned, hash-verified offset, replaces only the icon's
  DXT5 blocks, and installs the result as a mod-owned loose file. The
  uninstaller removes it again; a foreign loose atlas is never overwritten.
- Added `INSTALL.txt` and a `.sha256` checksum file to the release package.
- Added localized refusal reasons (English content shipped in every EE
  locale folder as explicit fallback until native review).
- Added the merge-aware, dry-run-first deployer with timestamped backups,
  encoding-preserving shared-file patching, and an ownership-aware
  uninstaller. It needs no external tools: shared files that have no loose
  copy are read from the game's own archive at hash-pinned offsets.
- Added the aggregate checker (`tools/check.ps1`) covering patch,
  deployment, uninstall, gameplay, UI, static, and repository-policy
  suites.
- Runtime acceptance evidence is tracked in `docs/RUNTIME-TESTS.md`.
