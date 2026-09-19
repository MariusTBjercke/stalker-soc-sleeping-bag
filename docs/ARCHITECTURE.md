# Architecture

This document separates inspected EE facts from runtime observations that the
implementation still needs to collect. The target is Shadow of Chornobyl
Enhanced Edition executable `1.10.3+68-42`, Steam build `24067120`.

## Verified engine facts

- Loose `gamedata` files provide the manual-PC installation model. This mod
  must not modify `fsgame_soc.ltx`.
- EE exposes `callback.use_object` through
  `actor_binder:use_inventory_item(obj)`. The sleeping-bag integration uses
  that callback instead of ABC's older item-drop workaround.
- `bind_stalker.script` contains EE-specific achievement, hit, death,
  treasure, and task behavior. A deployment patch must preserve those lines
  and add only marked calls into the mod-owned module.
- The actor hit callback provides the recent-hit signal used by the sleep
  safety check.
- The configured normal time factor is `10`; the established accelerated
  value is `10000`. Cleanup restores the captured factor or the normal value.
- Shared-file integration is limited to marked semantic edits. The deployer
  owns marker insertion, update, and removal under `soc_sleeping_bag`.

## Planned component boundary

Mod-owned Lua, LTX, XML, and localization files contain sleeping-bag
behavior. The deployer will patch `gamedata/config/system.ltx` and
`gamedata/scripts/bind_stalker.script` through unique anchors. It may patch
`gamedata/config/ui/ui_movies.xml` only if the runtime probe requires the
fallback. The game directory and `references/` remain input locations.

## Sleeping state machine

`gamedata/scripts/soc_sleeping_bag.script` is an offline-testable Lua 5.1
module. All engine-facing calls sit in local adapters or the guarded
`soc_sleeping_bag_menu` references, so `tools/tests/lua/xray_mocks.lua` can
replace the engine globals.

Transitions:

- `idle` - normal play. `update` only runs the delayed provisioning check.
- `menu` - `on_item_use` passed eligibility and the menu module owns the
  window. Menu selection calls `start_sleep`; cancellation returns through
  `abort_sleep`.
- `sleeping` - `start_sleep` captured the original time factor once, disabled
  input, hid the weapon, and selected the fast factor. `update` completes the
  sleep at the game-time deadline or aborts on a lost or dead actor; the hit
  callback aborts immediately.
- `aborting` - the same `cleanup` path as completion, without healing. A hit
  or death during sleep lands here.
- `cleanup` - the single restoration path. It restores the captured factor,
  or the normal configured factor when a stale fast factor has no surviving
  capture, then input, the weapon (only while the actor is alive), and all
  transition flags.

Invariants:

- Only `cleanup` restores engine state, and `cleanup` is idempotent: with
  nothing captured or flagged it performs no engine writes, so repeated
  cleanup is harmless.
- `start_sleep` refuses while a sleep is active, so the original factor is
  captured at most once per transition and is never overwritten with the fast
  value.
- Healing applies only inside `finish_sleep`, after the deadline is reached.
  Aborts never heal.
- The sleep deadline is `game.get_game_time()` plus the requested in-game
  hours and is never derived from frame counts or the accelerated factor.
  `update` ignores the binder's `delta` for that reason. `time_global()` is
  used only for the recent-hit cooldown and the delayed provisioning check.
- Spawn/load recovery (`recover`) clears a stale transition before
  scheduling provisioning; provisioning creates at most one bag per schedule
  and skips when the actor already owns one.
- Transient state is deliberately not serialized: a save made during a sleep
  recovers through `on_actor_net_spawn` on load.

## Pending probes

The following are not established by this repository contract and must be
recorded before finalizing the transition controller:

- Whether actor updates continue during the selected dark-screen transition.
- Whether the custom sleep menu pauses simulation.
- Whether the `ui_movies.xml` tutorial fallback is needed and non-pausing.
- The order in which EE consumes an inventory item relative to
  `callback.use_object`.
- Mouse, keyboard, and controller behavior for the completed menu.

Task 8 performs these probes on a disposable save and records their results.
