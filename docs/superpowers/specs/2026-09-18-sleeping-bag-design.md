# STALKER SoC Sleeping Bag Design

## Purpose

Build a new sleeping-bag gameplay mod for **S.T.A.L.K.E.R.: Shadow of
Chornobyl - Enhanced Edition** on Windows PC. The mod takes behavioral
inspiration from the 2007 ABC Sleeping Bag Mod but does not install, patch,
or redistribute ABC as a dependency.

The first release targets the user's current Steam installation:

- Game: S.T.A.L.K.E.R.: Shadow of Chornobyl - Enhanced Edition
- Executable version: `1.10.3+68-42`
- Steam build: `24067120`
- Reference installation date: September 17, 2026
- Distribution: manual PC installation through loose `gamedata` files

Official Workshop distribution is out of scope. GSC's current moderated
mod pipeline rejects scripts and configuration files, both of which this
feature requires.

## Goals

- Give the actor a reusable sleeping bag automatically, including in
  existing saves.
- Open an EE-native sleep menu through the existing inventory item-use
  callback.
- Offer fixed sleep durations of 1, 3, and 9 hours.
- Offer a bounded "Sleep until healed" action.
- Prevent sleeping in clearly unsafe actor states.
- Preserve Enhanced Edition behavior and unrelated manual mods.
- Install through verified, idempotent edits instead of replacing shared
  files blindly.
- Recover the normal time factor, controls, weapon state, and UI after
  completion, interruption, load, or failure.

## Non-goals

- Reproducing ABC source code line for line.
- Redistributing ABC's texture atlas, screenshots, or other assets.
- Supporting the original 32-bit Shadow of Chernobyl release.
- Steam Workshop or console distribution.
- Map-specific beds, safe zones, shelter detection, or indoor detection in
  the first release.
- Curing radiation or bleeding through sleep.
- Adding new dream artwork in the first release.
- Supporting an unverified EE build by forcing a patch.

## Research findings

The installed EE build retains the Lua 5.1 and loose `gamedata` mechanisms
used by the original game. The APIs required for a sleeping feature remain
available: `CUIScriptWnd`, `CScriptXmlInit`, scripted menus, time-factor
control, input control, weapon hiding, camera effects, and actor update
hooks.

EE also adds `callback.use_object` to `bind_stalker.script`. This provides a
direct inventory-use hook and removes the need for ABC's delayed
drop-item/binocular workaround.

The original ABC package cannot be installed directly:

- Its `bind_stalker.script` predates EE achievement callbacks, actor hit and
  death callbacks, task-news changes, and treasure-manager serialization.
- Its full `items.ltx`, `localization.ltx`, and `ui_movies.xml` replacements
  overwrite current EE data.
- Its dream definitions refer to three `textures\sleep` assets that are not
  present in the package or the inspected EE archives.
- Its inventory icon is supplied as a complete 2007 equipment atlas.
- Its "Unlimited" action is unfinished: it derives at most 2.75 hours from
  missing health while its healing code is disabled.

These findings make a clean reimplementation safer than a compatibility
patch around the old package.

## Repository structure

```text
gamedata/
  scripts/                 Mod-owned sleeping-bag modules
  config/ui/               Sleep menu layout
  config/text/<locale>/    Localized strings
  config/misc/             Sleeping-bag item definition

patches/
  bind_stalker/            Marked item-use, hit, spawn, and update hooks
  system/                  Marked include for the item definition
  ui_movies/               Only if the engine probe proves it necessary

tools/
  common.ps1               Paths, hashes, backups, and patch primitives
  check.ps1                Static and repository validation
  deploy.ps1               Dry-run and merge-aware installation
  uninstall.ps1            Ownership-aware removal
  tests/                    Patch and gameplay-module test fixtures

config/
  local.example.json       Documented machine-local configuration shape
  local.json               Ignored local game path

docs/
  ARCHITECTURE.md
  COMPATIBILITY.md
  DEVELOPMENT.md
  superpowers/specs/
  superpowers/plans/

references/                Ignored game and third-party research material
```

Complete extracted GSC files and third-party mods remain under
`references/` and are never committed. Timestamped deployment backups also
remain untracked.

## Component boundaries

### Sleeping-bag gameplay module

The gameplay module owns:

- Provisioning and restoring the sleeping bag.
- Sleep eligibility checks and localized refusal reasons.
- Opening and closing the duration menu.
- Starting, updating, aborting, and completing sleep.
- Remembering the original time factor and transient UI/input state.
- Cleanup during actor spawn/load and after interrupted transitions.

Shared EE scripts contain only marked calls into this module. They do not
contain the sleep implementation.

### Item definition

The sleeping bag is an inventory-usable item following ABC's automatic
ownership pattern. The actor receives it after spawn/load if it is absent.
The initial engine probe must confirm whether EE consumes the chosen item
class before the module finalizes the restoration timing.

The item definition lives in a mod-owned `.ltx` file. `system.ltx` receives
one marked include rather than an embedded item section.

### Sleep menu

The menu uses current EE texture and button identifiers. It contains:

- 1 hour
- 3 hours
- 9 hours
- Sleep until healed
- Cancel

The layout must work with mouse/keyboard. Controller behavior must be
tested because EE adds controller navigation that was absent from ABC.

### Transition controller

The first release uses a short dark-screen transition and accelerated game
time. It does not reuse story cinematics or ABC's missing dream textures.

The controller stores the original time factor before changing it, then uses
the engine's existing fast-forward value of `10000`. A fixed sleep completes
after the requested amount of in-game time. "Sleep until healed" chooses
`ceil((1 - actor.health) * 9)` hours, clamped to 1 through 9 hours, and sets
health to full only after successful completion. It does not alter radiation
or bleeding.

The primary update mechanism is the existing actor update hook. The in-game
probe checks:

- Whether actor updates continue during the dark transition.
- Whether a custom menu pauses simulation.
- Whether the custom dark overlay permits actor updates. If it pauses them,
  the specified fallback is a non-pausing tutorial entry added through a
  marked `ui_movies.xml` block; the actor update state machine and completion
  deadline remain unchanged.
- How item consumption is ordered relative to `callback.use_object`.

This probe is part of implementation, not throwaway repository code. Its
results are recorded in `docs/ARCHITECTURE.md` before the controller is
finalized.

## Gameplay flow

1. Actor spawn/load calls the module's recovery routine.
2. Recovery restores normal transient engine state if a previous sleep was
   interrupted.
3. A delayed inventory check creates `sleep_bag` if it is absent.
4. EE invokes `actor_binder:use_inventory_item(obj)` when the player uses
   the bag.
5. The marked integration hook delegates the bag to the gameplay module
   while preserving all existing EE code.
6. Eligibility checks return either an allowed result or a localization ID
   describing the refusal.
7. An allowed action opens the duration menu.
8. Selecting a duration closes the menu and starts the transition.
9. The actor update hook advances the state machine and watches for damage,
   death, or invalid state.
10. Completion or abort passes through the same idempotent cleanup path.
11. If the engine consumed the item, the module restores one bag after the
    menu action finishes.

## Sleep eligibility

The first release requires all of the following:

- A level is present.
- The actor object exists and is alive.
- The actor is not talking.
- `actor:get_bleeding()` is `0`.
- `actor.radiation` is below `0.7`, matching EE's existing severe-radiation
  warning threshold.
- The actor has not taken damage during the previous 10 seconds of
  `time_global()` time.

EE's existing actor-hit callback supplies the recent-hit timestamp. The
integration hook must call existing EE behavior before or after notifying
the sleep module without changing the original callback's result.

Direct enemy detection is omitted from the first release. The player actor's
`best_enemy()` behavior is not established, and scanning nearby NPC state
would introduce a heuristic restriction. The recent-hit cooldown is the
first-release combat safeguard.

If the actor takes damage during sleep, the transition aborts and cleanup
runs immediately. Map-specific danger evaluation is deferred.

## Recovery and failure handling

Cleanup is idempotent. It may be called when no transition is active.

It restores:

- The captured time factor, or the normal configured factor if no capture
  survives.
- Player input.
- The actor's weapon state when the actor is alive.
- The transition overlay or tutorial state owned by this mod.
- Internal transition flags and deadlines.

Actor spawn/load calls cleanup before provisioning the bag. This prevents a
save made during an unexpected shutdown from leaving accelerated time or
disabled input active after loading.

The first release does not add custom serialized data to the actor save
packet. Transient state is deliberately recoverable rather than persistent,
avoiding save-format coupling and removal hazards.

## Merge-aware deployment

Deployment reads `config/local.json` for `steamGameDir`. It never hardcodes
the developer's path in distributable scripts.

`deploy.ps1` defaults to dry-run mode. Before any write it:

1. Resolves and validates the game directory.
2. Reports the executable version and known baseline hashes.
3. Checks every shared-file anchor and requires exactly one match.
4. Detects an existing marked block.
5. Shows the planned copies and edits.

An explicit apply flag performs the installation. The deployer creates
timestamped backups outside `gamedata`, copies mod-owned files, and inserts
or updates marked blocks. Repeated deployment produces the same result.

Unknown hashes are not an automatic failure when all semantic anchors are
recognized and unique, because unrelated mods can change the file. Missing
or ambiguous anchors are a hard failure. A force option must not bypass an
ambiguous patch location.

The deployer preserves the user's current weight and repair changes and is
designed to share `bind_stalker.script` with the loot tracker. It never
replaces `fsgame_soc.ltx`.

`uninstall.ps1` removes only marked blocks and files still matching the
deployed manifest. If a mod-owned file changed after deployment, uninstall
reports it and leaves it in place. It never restores an entire old backup
over newer third-party changes.

## Validation strategy

### Automated checks

- Parse every shipped XML file.
- Verify that referenced localization IDs exist for each shipped locale.
- Check Lua syntax with a compatible local interpreter when available.
- Verify module, XML, and `.ltx` references.
- Test patch insertion against clean and pre-modified fixtures.
- Test deployment idempotency.
- Test preservation of unrelated fixture edits.
- Test refusal when anchors are missing or duplicated.
- Test ownership-aware uninstall behavior.
- Reject tracked files below `references/`.
- Reject complete upstream GSC or ABC files outside ignored references.
- Report the reference EE version and baseline hashes.

### Runtime checks

Use a disposable save rather than the user's live saves. Verify:

- Automatic provisioning on a new game and an existing save.
- No duplicate bags after load, use, level transition, or repeated updates.
- All fixed duration options.
- Health restoration and duration bounds for "Sleep until healed."
- Refusal while talking, severely bleeding, highly irradiated, recently
  hit, dead, or outside a loaded level.
- Abort and full cleanup when damaged during sleep.
- Cleanup after save/load or forced interruption.
- Original EE achievements and item-use behavior remain active.
- Weight and repair modifications remain present after deployment.
- Mouse/keyboard and controller navigation.

## Documentation and repository policy

The repository includes:

- `AGENTS.md` with verified engine facts, safety constraints, and the next
  implementation step.
- `README.md` with scope, status, installation state, and attribution.
- `docs/ARCHITECTURE.md` for confirmed engine and integration behavior.
- `docs/COMPATIBILITY.md` for supported builds and known conflicts.
- `docs/DEVELOPMENT.md` for extraction, validation, deployment, and runtime
  testing.
- `CONTRIBUTING.md`, `CHANGELOG.md`, `VERSION`, `.editorconfig`,
  `.gitattributes`, and `.gitignore` following the loot-tracker repository's
  conventions.

`references/` remains local and ignored. Documentation may identify ABC as
design inspiration and describe observed behavior, but shipped code and
assets must be independently authored.

## Release boundary

The first releasable milestone is complete when the merge-aware installer
can add and remove the mod safely on the supported EE build, automated
checks pass, and the runtime checklist passes on a disposable save alongside
the user's weight and repair mods.

Dream variants, map-specific safety rules, trader distribution, and
Workshop packaging remain later features.
