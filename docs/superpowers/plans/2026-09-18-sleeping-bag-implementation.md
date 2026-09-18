# Sleeping Bag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a safe, reversible manual-PC sleeping bag mod for S.T.A.L.K.E.R.: Shadow of Chornobyl Enhanced Edition 1.10.3 that preserves existing loose-file mods.

**Architecture:** Mod-owned Lua, LTX, UI, and localization files contain all gameplay behavior. A PowerShell deployer materializes missing shared files from the installed EE archive, then adds small, uniquely marked hooks to `system.ltx` and `bind_stalker.script`. Installation and removal are manifest-driven, idempotent, and refuse ambiguous edits.

**Tech Stack:** X-Ray Lua 5.1, LTX/XML game data, PowerShell 7-compatible scripts, plain PowerShell test harness, 7-Zip with the X-Ray database plugin.

**Spec:** `docs/superpowers/specs/2026-09-18-sleeping-bag-design.md`

## Global Constraints

- Target only manual PC installs of Enhanced Edition build `24067120`, executable `1.10.3+68-42`, until another build is verified.
- Do not modify or replace `fsgame_soc.ltx`.
- Do not commit complete GSC files, ABC files, extracted archives, game saves, or deployment backups.
- Do not redistribute ABC textures, scripts, XML, or icon atlases. The shipped implementation must be independently authored.
- Treat `gamedata/config/system.ltx`, `gamedata/scripts/bind_stalker.script`, and the conditional `gamedata/config/ui/ui_movies.xml` as shared files. Edit them only through marked semantic patches.
- Keep `deploy.ps1` and `uninstall.ps1` dry-run by default. Writes require `-Apply`.
- A known hash is evidence, not permission to replace a file. Unique semantic anchors are mandatory even on a known build.
- Never offer a force switch that bypasses missing or duplicate anchors.
- Preserve CRLF in materialized or patched game files.
- Use `soc_sleeping_bag` for owned section names, module names, XML IDs, marker text, and manifest identity.
- Preserve unrelated weight-limit, repair-vendor, and loot tracker changes during every deploy and uninstall test.
- Add a focused test first for each behavior change, observe it fail for the intended reason, then implement the minimum code that passes it.
- Run `pwsh -NoProfile -File tools/check.ps1` before every task commit once that command exists.
- Do not mark the runtime milestone complete until a disposable save has passed the checklist. Automated checks alone are insufficient.

---

## Task 1: Establish the repository contract

**Consumes:** Approved design specification and conventions observed in `C:/Users/micro/source/repos/stalker-soc-loot-tracker`.

**Produces:** A documented repository with ignored research material, local configuration, and an explicit implementation status.

**Files:**

- Create: `.editorconfig`
- Create: `.gitattributes`
- Create: `.gitignore`
- Create: `AGENTS.md`
- Create: `README.md`
- Create: `LICENSE`
- Create: `VERSION`
- Create: `CHANGELOG.md`
- Create: `CONTRIBUTING.md`
- Create: `config/local.example.json`
- Create: `docs/ARCHITECTURE.md`
- Create: `docs/COMPATIBILITY.md`
- Create: `docs/DEVELOPMENT.md`
- Create: `references/README.md`

- [ ] **Step 1: Write a failing repository-policy check**

  Run these assertions before creating the files:

  ```powershell
  $required = @(
      '.editorconfig', '.gitattributes', '.gitignore', 'AGENTS.md',
      'README.md', 'LICENSE', 'VERSION', 'CHANGELOG.md',
      'CONTRIBUTING.md', 'config/local.example.json',
      'docs/ARCHITECTURE.md', 'docs/COMPATIBILITY.md',
      'docs/DEVELOPMENT.md', 'references/README.md'
  )
  $missing = $required | Where-Object { -not (Test-Path -LiteralPath $_) }
  if ($missing) { throw "Missing repository files: $($missing -join ', ')" }
  ```

  Expected result: failure listing the files not yet present.

- [ ] **Step 2: Add line-ending and ignore policies**

  `.gitattributes` must keep source text stable while preserving Windows game files:

  ```gitattributes
  * text=auto
  *.ps1 text eol=crlf
  *.psm1 text eol=crlf
  *.script text eol=crlf
  *.ltx text eol=crlf
  *.xml text eol=crlf
  *.md text eol=lf
  *.json text eol=lf
  ```

  `.gitignore` must include:

  ```gitignore
  /config/local.json
  /dist/
  /out/
  /references/*
  !/references/README.md
  .DS_Store
  Thumbs.db
  Desktop.ini
  ```

  `.editorconfig` must specify UTF-8, final newlines, four-space PowerShell indentation, and two-space JSON/XML indentation.

- [ ] **Step 3: Add project metadata and local configuration**

  Set `VERSION` to `0.1.0-dev`. Use the MIT license for independently authored repository code. State clearly that the license does not cover game files or third-party reference material.

  `config/local.example.json` must contain only machine-local paths and optional tool paths:

  ```json
  {
    "steamGameDir": "D:\\SteamLibrary\\steamapps\\common\\STALKER Shadow of Chornobyl - EE",
    "sevenZipPath": "C:\\Program Files\\7-Zip\\7z.exe",
    "lua51Path": null
  }
  ```

- [ ] **Step 4: Document the current boundary**

  `README.md` must say the project is pre-release, manual-PC only, and inspired by ABC behavior without containing ABC code or assets. Link the architecture, compatibility, development, specification, and implementation-plan documents.

  `AGENTS.md` must record these verified facts:

  - EE exposes `callback.use_object` through `actor_binder:use_inventory_item`.
  - The existing actor binder already contains EE-specific achievement, hit, death, treasure, and task behavior that must be preserved.
  - The normal configured time factor is `10`; the established fast-forward value is `10000`.
  - The actor hit callback supplies the recent-hit signal.
  - Shared-file changes must use the deployer's markers.
  - `references/` and the game directory are research/input locations, not source trees to copy into the repository.
  - The next task is Task 2 of this plan.

  `docs/ARCHITECTURE.md` must separate verified engine facts from probe results that are still pending. `docs/COMPATIBILITY.md` must list the supported build, the manual loose-file model, known coexistence targets (weight, repair, and loot-tracker mods), and the Workshop exclusion. `docs/DEVELOPMENT.md` must describe configuration, extraction prerequisites, test commands, dry-run behavior, and disposable-save policy.

- [ ] **Step 5: Re-run the repository-policy check**

  Expected result: success. Also verify the local references are ignored but their policy file is not:

  ```powershell
  git check-ignore references/community-mods/abc_sleep_mod
  if ($LASTEXITCODE -ne 0) { throw 'ABC reference directory is not ignored' }
  git check-ignore references/README.md
  if ($LASTEXITCODE -eq 0) { throw 'references/README.md must remain trackable' }
  Get-Content -Raw config/local.example.json | ConvertFrom-Json | Out-Null
  ```

- [ ] **Step 6: Commit the repository foundation**

  ```powershell
  git add .editorconfig .gitattributes .gitignore AGENTS.md README.md LICENSE VERSION CHANGELOG.md CONTRIBUTING.md config/local.example.json docs/ARCHITECTURE.md docs/COMPATIBILITY.md docs/DEVELOPMENT.md references/README.md
  git commit -m "chore: establish sleeping bag repository foundation"
  ```

---

## Task 2: Build and test semantic patch primitives

**Consumes:** Shared-file marker contract from Task 1.

**Produces:** Pure patch functions that can insert, update, and remove hooks without touching the game.

**Files:**

- Create: `tools/common.ps1`
- Create: `tools/tests/testlib.ps1`
- Create: `tools/tests/patch_engine_test.ps1`
- Create: `tools/tests/fixtures/system.clean.ltx`
- Create: `tools/tests/fixtures/bind.clean.script`
- Create: `tools/tests/fixtures/bind.modified.script`
- Create: `patches/manifest.json`

- [ ] **Step 1: Create a dependency-free test harness**

  `tools/tests/testlib.ps1` must expose `Assert-Equal`, `Assert-True`, `Assert-Match`, and `Assert-Throws`. A failed assertion throws; a passing file exits zero. No Pester installation is required.

- [ ] **Step 2: Describe the patch contract in failing tests**

  Tests must cover:

  1. Insert after a unique anchor.
  2. Insert before a unique anchor.
  3. Scope an anchor to one Lua function.
  4. Preserve unrelated lines in a pre-modified fixture.
  5. Normalize inserted lines to CRLF.
  6. A second application is byte-identical.
  7. An existing marked line is updated in place.
  8. Marker removal leaves unrelated changes intact.
  9. Missing anchors throw.
  10. Duplicate anchors throw.
  11. Missing or duplicate function signatures throw.
  12. A resolved path outside the declared root throws.

  Run:

  ```powershell
  pwsh -NoProfile -File tools/tests/patch_engine_test.ps1
  ```

  Expected result: failure because `tools/common.ps1` does not exist.

- [ ] **Step 3: Implement the pure helpers**

  `tools/common.ps1` must define these exact entry points:

  ```powershell
  function Get-RepoRoot { [CmdletBinding()] param() }
  function Get-Sha256 { [CmdletBinding()] param([Parameter(Mandatory)][string] $Path) }
  function ConvertTo-Crlf { [CmdletBinding()] param([AllowEmptyString()][string] $Text) }
  function Resolve-ConfinedPath {
      [CmdletBinding()]
      param([Parameter(Mandatory)][string] $Root, [Parameter(Mandatory)][string] $RelativePath)
  }
  function Add-MarkedLine {
      [CmdletBinding()]
      param(
          [Parameter(Mandatory)][string] $Text,
          [Parameter(Mandatory)][string] $Anchor,
          [Parameter(Mandatory)][string] $Line,
          [Parameter(Mandatory)][string] $Marker,
          [ValidateSet('Before','After')][string] $Position = 'After'
      )
  }
  function Add-MarkedLineInFunction {
      [CmdletBinding()]
      param(
          [Parameter(Mandatory)][string] $Text,
          [Parameter(Mandatory)][string] $FunctionSignature,
          [Parameter(Mandatory)][string] $Anchor,
          [Parameter(Mandatory)][string] $Line,
          [Parameter(Mandatory)][string] $Marker,
          [ValidateSet('Before','After')][string] $Position = 'After'
      )
  }
  function Remove-MarkedLines {
      [CmdletBinding()]
      param([Parameter(Mandatory)][string] $Text, [Parameter(Mandatory)][string] $Marker)
  }
  function Add-MarkedBlock {
      [CmdletBinding()]
      param(
          [Parameter(Mandatory)][string] $Text,
          [Parameter(Mandatory)][string] $Anchor,
          [Parameter(Mandatory)][string[]] $Lines,
          [Parameter(Mandatory)][string] $BeginMarker,
          [Parameter(Mandatory)][string] $EndMarker,
          [ValidateSet('Before','After')][string] $Position = 'Before'
      )
  }
  function Remove-MarkedBlock {
      [CmdletBinding()]
      param(
          [Parameter(Mandatory)][string] $Text,
          [Parameter(Mandatory)][string] $BeginMarker,
          [Parameter(Mandatory)][string] $EndMarker
      )
  }
  ```

  Match anchors as complete literal lines after trimming trailing whitespace. A patch is valid only when its anchor occurs exactly once in its scope. Treat the next top-level `function ` line as the end of a Lua function scope. Marker replacement may replace only the marked line, never the surrounding function.

  A marked block includes its unique begin and end marker lines. Applying it again replaces the complete existing block. Removal requires exactly one ordered marker pair; an orphaned or duplicate marker is an error. This primitive is reserved for the conditional `ui_movies.xml` fallback in Task 8.

- [ ] **Step 4: Define the declarative patch manifest**

  `patches/manifest.json` must use this shape and these hook calls:

  ```json
  {
    "marker": "soc_sleeping_bag",
    "sharedFiles": [
      {
        "path": "gamedata/config/system.ltx",
        "archivePath": "config/system.ltx",
        "patches": [
          {
            "kind": "line",
            "anchor": "#include \"misc\\items.ltx\"",
            "position": "After",
            "line": "#include \"misc\\soc_sleeping_bag.ltx\" ; soc_sleeping_bag"
          }
        ]
      },
      {
        "path": "gamedata/scripts/bind_stalker.script",
        "archivePath": "scripts/bind_stalker.script",
        "patches": [
          {
            "kind": "luaFunction",
            "function": "function actor_binder:net_spawn(data)",
            "anchor": "death_manager.init_drop_settings()",
            "position": "After",
            "line": "    soc_sleeping_bag.on_actor_net_spawn() -- soc_sleeping_bag"
          },
          {
            "kind": "luaFunction",
            "function": "function actor_binder:net_destroy()",
            "anchor": "self.bCheckStart = false",
            "position": "After",
            "line": "    soc_sleeping_bag.on_actor_net_destroy() -- soc_sleeping_bag"
          },
          {
            "kind": "luaFunction",
            "function": "function actor_binder:use_inventory_item(obj)",
            "anchor": "local obj_section = obj:section()",
            "position": "After",
            "line": "    soc_sleeping_bag.on_item_use(obj) -- soc_sleeping_bag"
          },
          {
            "kind": "luaFunction",
            "function": "function actor_binder:hit_callback(obj, amount, local_direction, who, bone_index)",
            "anchor": "local hitted_by = who and who:id()",
            "position": "After",
            "line": "    soc_sleeping_bag.on_actor_hit() -- soc_sleeping_bag"
          },
          {
            "kind": "luaFunction",
            "function": "function actor_binder:update(delta)",
            "anchor": "object_binder.update(self, delta)",
            "position": "After",
            "line": "    soc_sleeping_bag.update(delta) -- soc_sleeping_bag"
          }
        ]
      }
    ]
  }
  ```

  If an inspected EE function uses a different literal signature or anchor, update the fixture and manifest together and record the verified line in `docs/ARCHITECTURE.md`. Do not weaken exact-one matching.

- [ ] **Step 5: Run patch tests twice**

  ```powershell
  pwsh -NoProfile -File tools/tests/patch_engine_test.ps1
  pwsh -NoProfile -File tools/tests/patch_engine_test.ps1
  ```

  Expected result: both runs pass with no fixture modifications.

- [ ] **Step 6: Commit patch primitives**

  ```powershell
  git add tools/common.ps1 tools/tests patches/manifest.json
  git commit -m "test: define safe shared-file patching"
  ```

---

## Task 3: Implement archive materialization and merge-aware deployment

**Consumes:** Patch primitives and declarative manifest from Task 2.

**Produces:** A dry-run-first installer that works whether shared files are loose or still inside `resources/configs.db`.

**Files:**

- Create: `tools/deploy.ps1`
- Create: `tools/tests/deploy_test.ps1`
- Create: `tools/tests/fake_7z.ps1`
- Create: `tools/known-builds.json`
- Modify: `tools/common.ps1`
- Modify: `docs/DEVELOPMENT.md`

- [ ] **Step 1: Write deployment contract tests**

  Build each test under a unique temporary directory. Cover these cases:

  - Dry-run reports copies and patches but writes nothing.
  - `-Apply` copies every mod-owned file and patches both shared files.
  - A loose shared file is used as the base and its unrelated edits survive.
  - A missing loose shared file is materialized through the fake 7-Zip command.
  - Repeated apply is byte-identical and does not duplicate markers.
  - Missing `XR_3DA.exe`, `resources/configs.db`, or `$game_data$ = true` fails before writing.
  - Missing and duplicate anchors fail before writing any target.
  - A failed staged patch leaves the game fixture unchanged.
  - An unknown executable version is reported and rejected by apply.
  - Backups are created only for pre-existing loose files.
  - The deployment manifest records origins and hashes.

  Run:

  ```powershell
  pwsh -NoProfile -File tools/tests/deploy_test.ps1
  ```

  Expected result: failure because `tools/deploy.ps1` does not exist.

- [ ] **Step 2: Add configuration and archive helpers**

  Add these entry points to `tools/common.ps1`:

  ```powershell
  function Get-LocalConfig { [CmdletBinding()] param([string] $ConfigPath) }
  function Get-GameIdentity { [CmdletBinding()] param([Parameter(Mandatory)][string] $GameDir) }
  function Get-EffectiveGameFile {
      [CmdletBinding()]
      param(
          [Parameter(Mandatory)][string] $GameDir,
          [Parameter(Mandatory)][string] $LooseRelativePath,
          [Parameter(Mandatory)][string] $ArchiveRelativePath,
          [Parameter(Mandatory)][string] $SevenZipPath,
          [Parameter(Mandatory)][string] $StageDir
      )
  }
  function Invoke-PatchManifest {
      [CmdletBinding()]
      param([Parameter(Mandatory)][string] $Text, [Parameter(Mandatory)] $FileDefinition)
  }
  ```

  `Get-EffectiveGameFile` returns an object with `Text`, `Origin` (`loose` or `archive`), `BaseHash`, and `SourcePath`. Invoke 7-Zip with an argument array, not a composed command string. Extract exactly one archive member into the staging directory. Reject archive extraction that produces zero or multiple candidates.

- [ ] **Step 3: Add the known-build registry**

  `tools/known-builds.json` must contain the reference executable version, Steam build, and SHA-256 values measured from the installed executable and the clean extracted shared files. Generate the hash values from the user's installed build rather than copying values from prose.

  The registry schema is:

  ```json
  {
    "builds": [
      {
        "executableVersion": "1.10.3+68-42",
        "steamBuild": "24067120",
        "executableSha256": "<64 lowercase hex characters>",
        "files": {
          "config/system.ltx": "<64 lowercase hex characters>",
          "scripts/bind_stalker.script": "<64 lowercase hex characters>"
        }
      }
    ]
  }
  ```

  Angle-bracket strings above describe measured data and must not appear in the committed JSON.

- [ ] **Step 4: Implement a transactional deployer**

  `tools/deploy.ps1` must expose:

  ```powershell
  [CmdletBinding()]
  param(
      [string] $GameDir,
      [string] $ConfigPath,
      [string] $SevenZipPath,
      [switch] $Apply
  )
  ```

  Required sequence:

  1. Resolve the game path from `-GameDir`, then local config.
  2. Validate the path, executable, resources archive, and enabled loose-data setting.
  3. Identify the supported build.
  4. Create a temporary staging directory under `out/staging`.
  5. Read or extract every shared file into staging.
  6. Apply every manifest patch in staging.
  7. Stage every mod-owned file from `gamedata/`.
  8. Print one plan containing origin, source hash, destination, and action.
  9. Stop here unless `-Apply` is present.
  10. Create `out/backups/<UTC timestamp>/` and back up only pre-existing loose targets.
  11. Copy all staged outputs with temporary destination names, then atomically rename them.
  12. Write `gamedata/soc_sleeping_bag_deployed.json` last.

  The deployment manifest must include mod version, game identity, UTC time, and for every installed file: relative path, ownership (`owned` or `shared`), source origin, base hash, and installed hash.

- [ ] **Step 5: Prove the deployer is idempotent**

  ```powershell
  pwsh -NoProfile -File tools/tests/deploy_test.ps1
  pwsh -NoProfile -File tools/deploy.ps1 -GameDir tools/tests/fixtures/game -SevenZipPath tools/tests/fake_7z.ps1
  ```

  Expected result: tests pass; the explicit deploy command reports a dry run and changes no fixture file.

- [ ] **Step 6: Document the extraction dependency and commit**

  Document how to install the 7-Zip X-Ray database plugin, how to set `sevenZipPath`, and why extraction is needed only when a shared loose file does not already exist.

  ```powershell
  git add tools/deploy.ps1 tools/common.ps1 tools/known-builds.json tools/tests/deploy_test.ps1 tools/tests/fake_7z.ps1 docs/DEVELOPMENT.md
  git commit -m "feat: add merge-aware deployment pipeline"
  ```

---

## Task 4: Implement ownership-aware uninstall

**Consumes:** Deployment manifest written by Task 3.

**Produces:** A dry-run-first remover that never rolls back unrelated later edits.

**Files:**

- Create: `tools/uninstall.ps1`
- Create: `tools/tests/uninstall_test.ps1`
- Modify: `docs/DEVELOPMENT.md`

- [ ] **Step 1: Write uninstall contract tests**

  Cover:

  - Dry-run writes nothing.
  - An unchanged owned file is removed.
  - A changed owned file is reported and retained.
  - A shared file that originated loose loses only marked lines.
  - A shared file that originated in the archive is deleted when marker removal produces its recorded base hash.
  - An archive-origin shared file with later unrelated edits loses only marked lines and remains loose.
  - A missing deployment manifest is a clean refusal.
  - A manifest path escaping the game root is rejected.
  - Repeated uninstall after successful removal reports that the mod is absent and writes nothing.

  Run and observe the intended failure:

  ```powershell
  pwsh -NoProfile -File tools/tests/uninstall_test.ps1
  ```

- [ ] **Step 2: Implement uninstall planning and apply**

  `tools/uninstall.ps1` must expose:

  ```powershell
  [CmdletBinding()]
  param([string] $GameDir, [string] $ConfigPath, [switch] $Apply)
  ```

  It must derive every candidate path from `soc_sleeping_bag_deployed.json`, confine it under the game directory, compute current hashes, and print `remove`, `unpatch`, `retain changed`, or `already absent`. Apply only the first two actions. Remove the deployment manifest last and only when all required unpatch operations succeed.

- [ ] **Step 3: Run deploy/uninstall round trips**

  ```powershell
  pwsh -NoProfile -File tools/tests/deploy_test.ps1
  pwsh -NoProfile -File tools/tests/uninstall_test.ps1
  ```

  Expected result: both suites pass, including the modified-file preservation cases.

- [ ] **Step 4: Document removal semantics and commit**

  ```powershell
  git add tools/uninstall.ps1 tools/tests/uninstall_test.ps1 docs/DEVELOPMENT.md
  git commit -m "feat: add ownership-aware uninstall"
  ```

---

## Task 5: Implement the testable gameplay state machine

**Consumes:** Eligibility, recovery, provisioning, duration, and abort rules from the specification.

**Produces:** A Lua 5.1-compatible module whose calculations and transitions can run against mocks.

**Files:**

- Create: `gamedata/scripts/soc_sleeping_bag.script`
- Create: `tools/tests/lua/sleeping_bag_test.lua`
- Create: `tools/tests/lua/xray_mocks.lua`
- Create: `tools/tests/gameplay_test.ps1`
- Modify: `docs/ARCHITECTURE.md`

- [ ] **Step 1: Encode gameplay rules as failing Lua tests**

  Cover at least these cases:

  - `healing_hours(1.0)` returns `1`.
  - `healing_hours(0.5)` returns `5`.
  - `healing_hours(0.0)` returns `9`.
  - Values outside `[0, 1]` clamp safely.
  - Eligibility rejects missing level, missing actor, dead actor, talking, bleeding, radiation `>= 0.7`, and a hit less than 10,000 ms ago.
  - Eligibility permits radiation below `0.7` and a hit exactly 10,000 ms ago.
  - `start_sleep` captures the old factor once, disables input, hides the weapon, and selects factor `10000`.
  - Completion restores the captured factor and state.
  - Healing reaches full health only after successful completion.
  - "Sleep until healed" uses the bounded healing duration rather than an unbounded wait.
  - A hit during sleep aborts without healing.
  - Repeated cleanup is harmless.
  - Spawn recovery clears a stale transition before scheduling provisioning.
  - Provisioning creates one item when absent and none when present.
  - Item-use ignores every section except `soc_sleeping_bag`.

  `tools/tests/gameplay_test.ps1` must find Lua 5.1 from local config or `lua5.1`/`lua` on `PATH`. If none exists, it must report `SKIP` and return zero; `tools/check.ps1` will surface the skip in its summary.

- [ ] **Step 2: Define the public Lua surface**

  The module must expose exactly these integration functions:

  ```lua
  function on_actor_net_spawn()
  function on_actor_net_destroy()
  function on_item_use(obj)
  function on_actor_hit()
  function update(delta)
  ```

  Keep these calculation/transition functions public for tests:

  ```lua
  function healing_hours(health)
  function eligibility_reason(actor, now_ms)
  function start_sleep(hours, heal_on_complete)
  function abort_sleep(reason)
  function finish_sleep()
  function ensure_item()
  function recover()
  ```

- [ ] **Step 3: Implement state and time semantics**

  Use module-local state with named constants:

  ```lua
  local ITEM_SECTION = "soc_sleeping_bag"
  local FAST_TIME_FACTOR = 10000
  local FALLBACK_TIME_FACTOR = 10
  local RECENT_HIT_MS = 10000
  local RADIATION_LIMIT = 0.7
  local PROVISION_DELAY_MS = 1000
  ```

  Use `time_global()` only for real-time cooldown and delayed provisioning. Use `game.get_game_time()` plus the requested in-game duration for the sleep deadline. Never derive the deadline from frame count or the accelerated time factor.

  Return these localization IDs from `eligibility_reason`:

  - `st_soc_sleeping_bag_no_level`
  - `st_soc_sleeping_bag_no_actor`
  - `st_soc_sleeping_bag_dead`
  - `st_soc_sleeping_bag_talking`
  - `st_soc_sleeping_bag_bleeding`
  - `st_soc_sleeping_bag_radiation`
  - `st_soc_sleeping_bag_recent_hit`

  `on_item_use` must return `false` for non-owned items and `true` when it handles the bag. It must call the UI adapter only after eligibility succeeds. Engine-facing calls must be concentrated in small local adapters so mocks can replace them.

- [ ] **Step 4: Run gameplay tests with Lua 5.1**

  ```powershell
  pwsh -NoProfile -File tools/tests/gameplay_test.ps1
  ```

  Expected result: all tests pass, or a visible `SKIP: Lua 5.1 interpreter not configured` while static validation continues. Before release, replace the skip with a passing run on a configured interpreter.

- [ ] **Step 5: Record state-machine invariants and commit**

  Document the idle, menu, sleeping, aborting, and cleanup transitions. State that only cleanup may restore engine state and that cleanup is idempotent.

  ```powershell
  git add gamedata/scripts/soc_sleeping_bag.script tools/tests/lua tools/tests/gameplay_test.ps1 docs/ARCHITECTURE.md
  git commit -m "feat: implement sleeping state machine"
  ```

---

## Task 6: Add the item, binder hooks, and comprehensive static checks

**Consumes:** Gameplay module from Task 5 and patch pipeline from Tasks 2 through 4.

**Produces:** A usable inventory item plus validated EE integration hooks.

**Files:**

- Create: `gamedata/config/misc/soc_sleeping_bag.ltx`
- Create: `tools/check.ps1`
- Create: `tools/tests/static_test.ps1`
- Modify: `patches/manifest.json`
- Modify: `docs/ARCHITECTURE.md`

- [ ] **Step 1: Write failing static integration checks**

  Tests must assert:

  - The item section is named `[soc_sleeping_bag]`.
  - Its `class` is `II_ANTIR`, its `quest_item` is `true`, and all consumable effects are zero.
  - Its visual and icon coordinates point to existing EE-owned assets recorded in architecture docs.
  - The system include refers to the exact owned LTX path.
  - Every binder call names a public gameplay function.
  - Every patch line contains the marker.
  - No tracked path exists under `references/` except `references/README.md`.
  - No file outside fixtures defines a complete `actor_binder` or ships an equipment texture atlas.
  - Every JSON file parses and every shipped XML file parses.

  Run:

  ```powershell
  pwsh -NoProfile -File tools/tests/static_test.ps1
  ```

  Expected result: failure because the item file and aggregate checker do not exist.

- [ ] **Step 2: Add the independently authored item definition**

  The section must inherit no item with side effects. Set the identity, usable inventory class, `equipments\\item_merger.ogf` visual, zero condition effects, weight `1.2`, cost `0`, and `eat_portions_num = 1`. Use verified vanilla icon coordinates rather than ABC's atlas. Record the source EE section whose icon coordinates are reused.

- [ ] **Step 3: Validate manifest hooks against the installed EE files**

  Extract clean `system.ltx` and `bind_stalker.script` into an ignored working directory. Run the patch engine against clean copies and the user's current loose `system.ltx`. Confirm each anchor occurs once and that current weight and repair lines are byte-identical after removing the sleeping-bag marker line.

  If a literal in Task 2 differs from the installed build, change only the fixture, manifest anchor, and the verified-facts documentation. Keep the hook positions and calls unchanged.

- [ ] **Step 4: Implement the aggregate checker**

  `tools/check.ps1` must run repository-policy checks, JSON/XML parsing, static integration checks, patch tests, deploy tests, uninstall tests, and gameplay tests. It must print one summary with pass, fail, and skip counts and return nonzero on any failure.

- [ ] **Step 5: Run all checks and commit**

  ```powershell
  pwsh -NoProfile -File tools/check.ps1
  ```

  Expected result: zero failures. A missing Lua interpreter may be the only skip before the release task.

  ```powershell
  git add gamedata/config/misc/soc_sleeping_bag.ltx tools/check.ps1 tools/tests/static_test.ps1 patches/manifest.json docs/ARCHITECTURE.md
  git commit -m "feat: integrate sleeping bag item with EE"
  ```

---

## Task 7: Implement the sleep menu and localization

**Consumes:** Gameplay callbacks and refusal IDs from Task 5.

**Produces:** A mouse, keyboard, and controller-aware duration menu with complete locale files.

**Files:**

- Create: `gamedata/scripts/soc_sleeping_bag_ui.script`
- Create: `gamedata/config/ui/ui_soc_sleeping_bag.xml`
- Create: `gamedata/config/text/cze/st_soc_sleeping_bag.xml`
- Create: `gamedata/config/text/eng/st_soc_sleeping_bag.xml`
- Create: `gamedata/config/text/fra/st_soc_sleeping_bag.xml`
- Create: `gamedata/config/text/ger/st_soc_sleeping_bag.xml`
- Create: `gamedata/config/text/hg/st_soc_sleeping_bag.xml`
- Create: `gamedata/config/text/ita/st_soc_sleeping_bag.xml`
- Create: `gamedata/config/text/jpn/st_soc_sleeping_bag.xml`
- Create: `gamedata/config/text/kor/st_soc_sleeping_bag.xml`
- Create: `gamedata/config/text/pol/st_soc_sleeping_bag.xml`
- Create: `gamedata/config/text/rus/st_soc_sleeping_bag.xml`
- Create: `gamedata/config/text/spa/st_soc_sleeping_bag.xml`
- Create: `gamedata/config/text/ukr/st_soc_sleeping_bag.xml`
- Create: `gamedata/config/text/zh_cn/st_soc_sleeping_bag.xml`
- Create: `gamedata/config/text/zh_tw/st_soc_sleeping_bag.xml`
- Create: `gamedata/config/text/zho/st_soc_sleeping_bag.xml`
- Create: `tools/tests/ui_test.ps1`
- Modify: `gamedata/scripts/soc_sleeping_bag.script`

- [ ] **Step 1: Write failing UI and localization checks**

  Parse the layout and every locale XML. Assert that every locale contains this exact ID set:

  ```text
  st_soc_sleeping_bag_name
  st_soc_sleeping_bag_description
  st_soc_sleeping_bag_title
  st_soc_sleeping_bag_sleep_1
  st_soc_sleeping_bag_sleep_3
  st_soc_sleeping_bag_sleep_9
  st_soc_sleeping_bag_sleep_heal
  st_soc_sleeping_bag_cancel
  st_soc_sleeping_bag_no_level
  st_soc_sleeping_bag_no_actor
  st_soc_sleeping_bag_dead
  st_soc_sleeping_bag_talking
  st_soc_sleeping_bag_bleeding
  st_soc_sleeping_bag_radiation
  st_soc_sleeping_bag_recent_hit
  st_soc_sleeping_bag_interrupted
  ```

  Assert that XML button IDs map once each to 1, 3, 9, heal, and cancel callbacks. Assert that Escape/controller cancel closes without sleeping and that directional actions move focus among five buttons.

- [ ] **Step 2: Implement the UI adapter**

  `soc_sleeping_bag_ui.script` must expose:

  ```lua
  function show(on_choice)
  function close()
  function show_refusal(string_id)
  function show_interrupted()
  function is_open()
  ```

  Create one `CUIScriptWnd`, initialize it from `ui_soc_sleeping_bag.xml`, register five button callbacks, and destroy it through `close`. Pass `1`, `3`, `9`, or the calculated healing duration to the gameplay callback. Cancel returns no duration. Use current EE button texture IDs verified from the installed UI definitions.

- [ ] **Step 3: Connect gameplay to the UI without a circular dependency**

  The gameplay module may call the UI module, but the UI module must receive a callback and must not import gameplay state. Refusal display receives a localization ID. Closing the menu must not start or complete a transition.

- [ ] **Step 4: Add locale files**

  Supply reviewed English strings in `eng`. Until native translations are reviewed, use the English text as explicit fallback content in the other fourteen EE locale folders. Record that status in `CONTRIBUTING.md`; do not label machine-generated text as a reviewed translation.

- [ ] **Step 5: Run UI checks and commit**

  ```powershell
  pwsh -NoProfile -File tools/tests/ui_test.ps1
  pwsh -NoProfile -File tools/check.ps1
  ```

  ```powershell
  git add gamedata/scripts gamedata/config/ui gamedata/config/text tools/tests/ui_test.ps1 CONTRIBUTING.md
  git commit -m "feat: add sleep menu and localization"
  ```

---

## Task 8: Probe and finalize the non-pausing transition

**Consumes:** Deployable item, menu, and gameplay state machine.

**Produces:** Recorded runtime facts and one working dark transition whose update loop continues during accelerated time.

**Files:**

- Create: `docs/RUNTIME-TESTS.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `gamedata/scripts/soc_sleeping_bag.script`
- Modify: `gamedata/scripts/soc_sleeping_bag_ui.script`
- Conditional create: `patches/ui_movies/soc_sleeping_bag_transition.xml`
- Conditional modify: `patches/manifest.json`
- Conditional modify: `tools/tests/patch_engine_test.ps1`

- [ ] **Step 1: Dry-run against the real installation**

  ```powershell
  Copy-Item config/local.example.json config/local.json
  pwsh -NoProfile -File tools/check.ps1
  pwsh -NoProfile -File tools/deploy.ps1
  ```

  Inspect the plan. It must preserve the existing repair dialog include, weight values, hand-radio edits, and any loot-tracker marker. Do not apply while an anchor or preservation assertion is unresolved.

- [ ] **Step 2: Apply with backups and inspect the diff**

  ```powershell
  pwsh -NoProfile -File tools/deploy.ps1 -Apply
  ```

  Compare the backup and installed shared files. The only new shared-file lines must contain `soc_sleeping_bag`. Record the backup path and installed hashes in `docs/RUNTIME-TESTS.md` without recording user save paths.

- [ ] **Step 3: Run the disposable-save engine probe**

  In a disposable new save and a copied existing save, record:

  - Whether `II_ANTIR` is consumed before or after `callback.use_object` returns.
  - Whether actor `update(delta)` runs while the custom menu is visible.
  - Whether actor `update(delta)` runs while the dark overlay is visible.
  - Whether the original time factor is restored after normal completion, damage abort, menu cancel, and load.
  - Whether the weapon and controls recover in all four paths.

  Add temporary diagnostic logging behind a local `DEBUG` constant and set it back to `false` before committing.

- [ ] **Step 4: Select the transition path from observed evidence**

  If actor updates continue under the custom dark overlay, retain the Lua-owned overlay and document that result.

  If the overlay pauses actor updates, add a single `soc_sleeping_bag_transition` tutorial definition with `pause_state` disabled. Extend the manifest with a `block` patch that uses `<!-- soc_sleeping_bag begin -->` and `<!-- soc_sleeping_bag end -->`, inserted immediately before the unique closing root tag in `ui_movies.xml`. Add missing-anchor, duplicate-anchor, orphan-marker, idempotency, and uninstall tests. Control the tutorial through `game.start_tutorial` and `game.stop_tutorial`. Do not add this shared-file patch when the Lua overlay passes.

- [ ] **Step 5: Finalize item restoration timing**

  Use the observed callback order to schedule `ensure_item` after the engine's consume operation. Confirm one and only one bag exists after use, cancel, load, and level transition. Record the order and delay in `docs/ARCHITECTURE.md`.

- [ ] **Step 6: Re-run automated checks and commit probe results**

  ```powershell
  pwsh -NoProfile -File tools/check.ps1
  git diff --check
  ```

  ```powershell
  git add docs/RUNTIME-TESTS.md docs/ARCHITECTURE.md gamedata/scripts patches tools/tests/patch_engine_test.ps1
  git commit -m "feat: finalize EE sleep transition"
  ```

---

## Task 9: Execute the runtime acceptance matrix

**Consumes:** Final transition path from Task 8.

**Produces:** A completed, reproducible acceptance record alongside the user's weight and repair mods.

**Files:**

- Modify: `docs/RUNTIME-TESTS.md`
- Modify: `docs/COMPATIBILITY.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Verify provisioning and uniqueness**

  Check a new game and copied existing save. Check after load, bag use, level transition, and ten repeated inventory opens. Record pass/fail for automatic provisioning and absence of duplicates.

- [ ] **Step 2: Verify every duration**

  Run 1-, 3-, and 9-hour sleep and compare the game clock before and after. Allow only normal frame-level overshoot. Run healing sleep at full, half, and near-zero health; confirm durations of 1, 5, and 9 hours and full health only on successful completion.

- [ ] **Step 3: Verify refusals and interruption**

  Exercise talking, bleeding, radiation at and above `0.7`, a hit within ten seconds, dead actor/load recovery, and no loaded level where reproducible. Confirm the correct localized reason and no time-factor change. Take damage during sleep and confirm immediate abort without healing.

- [ ] **Step 4: Verify coexistence and input**

  Confirm:

  - Repair vendors and their dialogs still work.
  - The user's configured carry weight remains unchanged.
  - EE achievements and ordinary vodka/bread item-use behavior still execute.
  - Loot tracker hooks remain present if installed.
  - Mouse, keyboard, and controller can select every action and cancel.

- [ ] **Step 5: Verify recovery and removal**

  Interrupt during menu display, active sleep, level transition, death, and save/load. Confirm time factor, input, weapon, and overlay recover. Run uninstall dry-run, inspect it, apply it, and confirm unrelated mod lines remain. Reinstall and confirm identical installed hashes.

- [ ] **Step 6: Record results and commit**

  Every acceptance row must include build, save type, expected result, observed result, and pass/fail. Any failure returns work to the task that owns the behavior; do not waive it in documentation.

  ```powershell
  git add docs/RUNTIME-TESTS.md docs/COMPATIBILITY.md CHANGELOG.md
  git commit -m "test: record sleeping bag runtime acceptance"
  ```

---

## Task 10: Prepare the first manual release

**Consumes:** Passing automated and runtime acceptance evidence.

**Produces:** Version `0.1.0` source and a reproducible manual-install archive.

**Files:**

- Modify: `VERSION`
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/COMPATIBILITY.md`
- Create: `tools/package.ps1`
- Create: `tools/tests/package_test.ps1`

- [ ] **Step 1: Write the package-content test**

  Require the archive to contain `gamedata/`, `patches/`, `tools/`, `config/local.example.json`, `README.md`, `LICENSE`, `VERSION`, and compatibility/install documentation. Reject `config/local.json`, `references/`, `out/backups`, test fixtures, `.git`, and any ABC filename.

- [ ] **Step 2: Implement reproducible packaging**

  `tools/package.ps1` must run `tools/check.ps1`, require a clean tracked worktree, stage the allowlisted release files under `out/package/soc-sleeping-bag-<version>/`, and create `dist/soc-sleeping-bag-<version>.zip`. It must stop if `VERSION` contains `-dev`.

- [ ] **Step 3: Set release metadata**

  Change `VERSION` to `0.1.0`. Move changelog entries from Unreleased to `0.1.0` with the current date. README installation must use dry-run, review, then `-Apply`; removal must use dry-run, review, then `-Apply`. State the exact supported EE build and the 7-Zip plugin prerequisite.

- [ ] **Step 4: Run final verification**

  ```powershell
  pwsh -NoProfile -File tools/check.ps1
  pwsh -NoProfile -File tools/tests/package_test.ps1
  pwsh -NoProfile -File tools/package.ps1
  git diff --check
  git status --short
  ```

  Expected result: all checks pass, a single versioned ZIP is produced, and only deliberate release-metadata edits are shown before commit.

- [ ] **Step 5: Commit the release candidate**

  ```powershell
  git add VERSION README.md CHANGELOG.md docs/COMPATIBILITY.md tools/package.ps1 tools/tests/package_test.ps1
  git commit -m "release: prepare sleeping bag 0.1.0"
  ```

## Completion Criteria

- All ten task commits exist in order and `pwsh -NoProfile -File tools/check.ps1` reports zero failures and zero release-blocking skips.
- `docs/RUNTIME-TESTS.md` records a passing disposable-save matrix on EE `1.10.3+68-42` / Steam build `24067120`.
- A deploy/uninstall/redeploy round trip preserves unrelated weight, repair, and loot-tracker changes.
- The installed mod never duplicates the bag, never leaves factor `10000` active after cleanup, and never leaves input disabled.
- The release ZIP contains no local paths, backups, extracted game files, ABC assets, or full shared GSC files.
- The manual installation and removal commands in README match the verified scripts exactly.
