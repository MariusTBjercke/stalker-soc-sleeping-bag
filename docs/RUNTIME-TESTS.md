# Runtime tests

This document records the disposable-save runtime evidence for the
supported build (EE executable `1.10.3+68-42`, Steam build `24067120`).
It never records personal save paths. Rows marked **pending** are the
expected results for a runtime run that has not been executed yet; a row
may only move to pass after its observed result matches.

## Deployment record

First automated installation was applied on 2026-09-19 after a clean
dry-run review, and an idempotent redeploy followed the version bump to
`0.1.0` with byte-identical results (exactly five binder hook calls, one
system include line, no duplicate markers).

- Backup roots (oldest first): `out/backups/20260919T125715005Z`
  (initial install; contains the pre-existing loose
  `gamedata/config/system.ltx`; the binder had no loose copy, so it was
  materialized from `resources/configs.db` and correctly has no backup),
  `out/backups/20260919T130954664Z` (redeploy after the version bump;
  also contains the previously materialized binder).
- Deployed manifest: `gamedata/soc_sleeping_bag_deployed.json`, 21 files,
  mod version `0.1.0`.
- Shared-file diff after apply:
  - `gamedata/config/system.ltx`: exactly one added line,
    `#include "misc\soc_sleeping_bag.ltx" ; soc_sleeping_bag`. The user's
    weight (`max_weight = 1000`, `max_ruck = 1000.0`), repair-vendor
    include (`dialogs_repair`), and hand-radio edits are byte-identical.
  - `gamedata/scripts/bind_stalker.script`: exactly five added hook lines
    against the clean archive member, one per public gameplay function.
- `fsgame_soc.ltx` was not modified.
- All 21 installed SHA-256 hashes match the deployed manifest, including
  shared installed hashes `6864ee5f...` (`config/system.ltx` clean base
  registry hash) for the loose base `9a07fd45...` and binder installed
  content built from base `c8e746df...`.

## Engine probe (task 8)

Run in a disposable new save and a copied existing save. Before playing,
set `DEBUG = true` at the top of `gamedata/scripts/soc_sleeping_bag.script`
in the game's `gamedata` folder, then set it back to `false` afterwards.
Probe lines print as `soc_sleeping_bag DEBUG: ...` in the game log
(`xray_<user>.log`).

| # | Question | How to observe | Expected | Observed | Pass |
| --- | --- | --- | --- | --- | --- |
| 1 | Is `II_ANTIR` consumed before or after `callback.use_object` returns? | Use the bag, watch inventory immediately; DEBUG `bag used` line prints on use. If the bag disappears at once, consumption precedes or overlaps the callback; the scheduled 1000 ms restore must then bring back exactly one bag. | One bag returns ~1 s after use, or the bag never disappears | pending | pending |
| 2 | Does actor `update(delta)` run while the custom menu is visible? | Open the menu and stand still; if the clock advances, updates continue | Recorded | pending | pending |
| 3 | Does actor `update(delta)` run while the dark overlay/transition is visible? | Start a sleep; if the game clock advances to the deadline and `sleep finished` prints, updates continue under accelerated time | Recorded | pending | pending |
| 4 | Is the original time factor restored after normal completion, damage abort, menu cancel, and load? | Use the debug console (`g_time_factor`) before/after each path | Factor returns to the captured value (normally `10`) in all four paths | pending | pending |
| 5 | Do weapon and controls recover in all four paths? | Watch the weapon return and input work after each path | Recovered in all four paths | pending | pending |
| 6 | Menu/window and controller navigation wiring | The menu opens, buttons highlight, controller d-pad moves focus, Escape cancels | Recorded | pending | pending |

If probe 3 fails (actor updates pause under the Lua dialog), the fallback is
the conditional `ui_movies.xml` tutorial block described in
`docs/superpowers/plans/2026-09-18-sleeping-bag-implementation.md` task 8;
it is intentionally not deployed until the probe demands it.

## Acceptance matrix (task 9)

Build: EE `1.10.3+68-42`, Steam build `24067120`. Save types: D = disposable
new save, C = copied existing save.

### Provisioning and uniqueness

| Check | Save | Expected | Observed | Pass |
| --- | --- | --- | --- | --- |
| Bag appears automatically | D | One `soc_sleeping_bag` ~1 s after spawn | pending | pending |
| Bag appears automatically | C | One bag after load, no duplicates | pending | pending |
| Ten repeated inventory opens | D | Still exactly one bag | pending | pending |
| After use, cancel, load, level transition | D/C | Exactly one bag each time | pending | pending |

### Durations

| Check | Expected | Observed | Pass |
| --- | --- | --- | --- |
| Sleep 1 hour | Game clock advances 1 h (small frame overshoot allowed) | pending | pending |
| Sleep 3 hours | Game clock advances 3 h | pending | pending |
| Sleep 9 hours | Game clock advances 9 h | pending | pending |
| Heal at full health | 1 hour, health unchanged (already full) | pending | pending |
| Heal at half health | 5 hours, full health after completion only | pending | pending |
| Heal at near-zero health | 9 hours, full health after completion only | pending | pending |

### Refusals and interruption

| Check | Expected | Observed | Pass |
| --- | --- | --- | --- |
| Use while talking | Localized refusal, no time change | pending | pending |
| Use while bleeding | Localized refusal, no time change | pending | pending |
| Use at radiation 0.7+ | Localized refusal, no time change | pending | pending |
| Use within 10 s of damage | Localized refusal, no time change | pending | pending |
| Damage during sleep | Immediate abort, no healing, factor/input/weapon restored | pending | pending |
| Death during sleep | Abort and recovery on reload | pending | pending |

### Coexistence and input

| Check | Expected | Observed | Pass |
| --- | --- | --- | --- |
| Repair vendors and dialogs | Unchanged, dialogs work | pending | pending |
| Carry weight | Still `1000` | pending | pending |
| EE achievements and vodka/bread use | Still work (vodka/bread counters advance) | pending | pending |
| Mouse, keyboard, controller | Every action selectable, Escape/controller cancel closes | pending | pending |

### Recovery and removal

| Check | Expected | Observed | Pass |
| --- | --- | --- | --- |
| Save/load during menu or sleep | Factor, input, weapon, overlay recovered after load | pending | pending |
| Level transition during sleep | Same recovery on arrival | pending | pending |
| `tools/uninstall.ps1` dry run | Reports remove/unpatch plan only | pending | pending |
| `tools/uninstall.ps1 -Apply` | Weight/repair lines remain; marker lines gone | pending | pending |
| Redeploy after uninstall | Identical installed hashes | pending | pending |
