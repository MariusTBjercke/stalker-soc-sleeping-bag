# Development

## Local configuration

Copy `config/local.example.json` to `config/local.json` and set only local
paths. `steamGameDir` points at the EE game directory; `sevenZipPath` points
at 7-Zip; `lua51Path` is optional. `config/local.json` is ignored and must
not be committed.

## Extraction prerequisite

The deployer needs 7-Zip with an X-Ray database plugin when a shared loose
file is absent and must be materialized from `resources/configs.db`. Install
the plugin compatible with the local 7-Zip architecture, then configure its
executable path in `config/local.json`. Existing loose shared files are used
as the base, so archive extraction is not required for those files.

## Tests and checks

Run commands from the repository root. Task 1's repository-policy check is
the current validation. After Task 2 adds the harness, run:

```powershell
pwsh -NoProfile -File tools/tests/patch_engine_test.ps1
pwsh -NoProfile -File tools/check.ps1
```

The deployer will also support an explicit fixture dry run:

```powershell
pwsh -NoProfile -File tools/deploy.ps1 -GameDir tools/tests/fixtures/game -SevenZipPath tools/tests/fake_7z.ps1
```

These future commands are documented here as the planned interface; they do
not exist at repository-contract stage.

## Deployment and runtime tests

`tools/deploy.ps1` and `tools/uninstall.ps1` will be dry-run by default.
Review their plan before adding `-Apply`. Game-side writes require explicit
approval. Use a disposable save for every in-game test, including sleep,
damage interruption, cleanup, deploy, uninstall, and redeploy checks. Do not
test against a live save.
