# Agent guidance

This repository is a pre-release, manual-PC Lua mod for S.T.A.L.K.E.R.:
Shadow of Chornobyl Enhanced Edition (EE). Read the documents in `docs/`
before changing game behavior.

## Verified integration facts

- EE exposes `callback.use_object` through `actor_binder:use_inventory_item`.
- The existing actor binder contains EE-specific achievement, hit, death,
  treasure, and task behavior. Preserve all of it when integrating this mod.
- The normal configured time factor is `10`; the established fast-forward
  value is `10000`.
- The actor hit callback supplies the recent-hit signal.
- Shared-file changes use the deployer's `soc_sleeping_bag` markers. Do not
  replace shared files or edit unmarked integration points.

## Boundaries

- `references/` and the game directory are research and input locations, not
  source trees to copy into this repository.
- Do not commit extracted game files, ABC code or assets, saves, deployment
  backups, or `config/local.json`.
- Do not modify `fsgame_soc.ltx`.
- Agents may run deployment with `-Apply` when testing (authorized by the
  user on 2026-09-19); review the dry-run plan first. Removal stays a dry-run
  unless the user explicitly supplies `-Apply`.
- Use a disposable save for every runtime test that can write game state.

## Reading order and next step

| Need | Read |
| --- | --- |
| Engine facts and pending probes | `docs/ARCHITECTURE.md` |
| Build support and coexistence | `docs/COMPATIBILITY.md` |
| Local setup and test workflow | `docs/DEVELOPMENT.md` |
| Behavior and constraints | `docs/superpowers/specs/2026-09-18-sleeping-bag-design.md` |
| Implementation sequence | `docs/superpowers/plans/2026-09-18-sleeping-bag-implementation.md` |

Version 0.1.0 is deployed for testing and packaged in `dist/`. Playtests so
far are logged in `docs/RUNTIME-TESTS.md`; rows not listed as confirmed there
are still pending. Next: publish the GitHub release (see CONTRIBUTING.md), then
consider Steam Workshop support.
