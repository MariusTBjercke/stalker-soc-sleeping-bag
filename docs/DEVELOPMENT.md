# Development

## Local configuration

Copy `config/local.example.json` to `config/local.json` and set only local
paths. `steamGameDir` points at the EE game directory; `lua51Path` is
optional. `config/local.json` is ignored and must not be committed. The
deployer also accepts `-GameDir`, so a local config is optional.

## Reading game files (no external tools)

The deployer needs no 7-Zip, plugin, or Python. Existing loose shared files
are used as the merge base. When a declared shared file has no loose copy, and
for the icon atlas, it reads the game's own bytes straight out of
`resources/configs.db` and `resources/resources.db10`. Both archives store
those files uncompressed, so `tools/known-builds.json` pins each file's
archive, offset, size, and SHA-256 for the supported build
(`archiveFiles` and `atlas`), and the deployer trusts an offset only when the
bytes match the hash. An unknown build is refused before anything is written.

To re-pin the entries for a new game build, list the archive's file table with
a tool that understands X-Ray `.db` files (for example `db-extract` from
stalker-tools, or 7-Zip with the xray-db-7z-plugin) and copy the offset,
size, and SHA-256 of `config/system.ltx`, `scripts/bind_stalker.script`, and
`textures/ui/ui_icon_equipment.dds`. Keep any extracted copies in
`references/` only. Those tools are a development aid and are never needed to
install or build the mod.

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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/deploy.ps1 -GameDir '<game-dir>'
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

## Inventory icon

The icon source is `art/icon/sleeping-bag-source.png` (500x500, transparent).
`art/icon/sleeping-bag-2x2-100x100.png` is the downscale placed in the game's
50 px grid (2x2 cells), and `art/icon/sleeping-bag-2x2.dxt5` is that image as
raw DXT5 blocks (10000 bytes), which is what the deployer ships. To change
the icon, replace the 100x100 PNG and regenerate the blocks (needs Python and
Pillow; players never need either):

```powershell
python tools/icon_atlas.py encode --icon art/icon/sleeping-bag-2x2-100x100.png --out art/icon/sleeping-bag-2x2.dxt5
```

`python tools/icon_atlas.py splice --atlas <atlas> --icon <png> --out <dds>`
builds a full patched atlas with the same layout; `tools/deploy.ps1` must
produce a byte-identical file. The game's own atlas is in
`resources/resources.db10` (offset and SHA-256 pinned in
`tools/known-builds.json`). 7-Zip's plugin cannot open that archive; the
`db-extract` tool from stalker-tools can, once its `lzo` import is satisfied.
Extracted copies belong in `references/` only and are never committed
(`check.ps1` rejects any tracked `.dds`).
