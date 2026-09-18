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
