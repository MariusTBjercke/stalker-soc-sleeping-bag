# Development

## Local configuration

Copy `config/local.example.json` to `config/local.json` and set only local
paths. `steamGameDir` points at the EE game directory; `sevenZipPath` points
at 7-Zip; `lua51Path` is optional. `config/local.json` is ignored and must
not be committed.

## Extraction prerequisite

The deployer needs 7-Zip with an X-Ray database plugin when a shared loose
file is absent and must be materialized from `resources/configs.db`. Install
7-Zip, close its UI, and copy the plugin DLL matching the 7-Zip architecture
into the 7-Zip `Formats` directory. For the usual 64-bit installation this is
`XDB_x64.dll` under `C:\Program Files\7-Zip\Formats\`. Use the plugin's x86
DLL only with 32-bit 7-Zip. If Windows marked the downloaded DLL as blocked,
open its Properties dialog and select **Unblock** before starting 7-Zip.

Verify the plugin from PowerShell before deploying:

```powershell
& 'C:\Program Files\7-Zip\7z.exe' l '<game-dir>\resources\configs.db'
```

The listing must succeed and report `Type = xdb`. Copy
`config/local.example.json` to the ignored `config/local.json` and set
`sevenZipPath` to that `7z.exe`. Existing loose shared files are used as the
merge base, so extraction is needed only when a declared shared loose file is
absent.

## Tests and checks

Run commands from the repository root. Windows PowerShell 5.1 is the
interpreter available in the current development environment:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/tests/patch_engine_test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/tests/deploy_test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/tests/uninstall_test.ps1
```

PowerShell 7 may be used with the equivalent `pwsh -NoProfile -File ...`
commands when installed. The deployer and uninstaller support an explicit dry run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/deploy.ps1 -GameDir '<game-dir>' -SevenZipPath 'C:\Program Files\7-Zip\7z.exe'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/uninstall.ps1 -GameDir '<game-dir>'
```

The commands print each planned action and its target path. Neither command
writes to the game directory unless `-Apply` is supplied.

## Deployment and removal semantics

`tools/deploy.ps1` and `tools/uninstall.ps1` operate as dry-run by default.
Review their plan before adding `-Apply`.

- **Deployment (`tools/deploy.ps1`):** Stages patches and mod-owned files,
  creates timestamped backups of pre-existing loose files, atomically replaces
  targets, and writes `gamedata/soc_sleeping_bag_deployed.json` last.
- **Removal (`tools/uninstall.ps1`):** Manifest-driven and ownership-aware.
  Unchanged mod-owned files are deleted; mod-owned files modified after
  deployment are reported and retained. Shared files lose only marked lines;
  an archive-materialized shared file that reproduces its recorded clean base
  hash after marker removal is deleted, while one with unrelated edits remains
  loose. The deployment manifest is deleted last.

Game-side writes require explicit approval. Use a disposable save for every
in-game test, including sleep, damage interruption, cleanup, deploy, uninstall,
and redeploy checks. Do not test against a live save.
