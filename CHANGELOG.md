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
  from interrupted sessions.
- Added localized refusal reasons (English content shipped in every EE
  locale folder as explicit fallback until native review).
- Added the merge-aware, dry-run-first deployer with timestamped backups,
  encoding-preserving shared-file patching, and an ownership-aware
  uninstaller.
- Added the aggregate checker (`tools/check.ps1`) covering patch,
  deployment, uninstall, gameplay, UI, static, and repository-policy
  suites.
- Runtime acceptance evidence is tracked in `docs/RUNTIME-TESTS.md`.
