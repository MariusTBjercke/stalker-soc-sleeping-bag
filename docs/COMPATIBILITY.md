# Compatibility

## Supported build

The current release (`0.1.0`) supports the manual PC Steam installation of
S.T.A.L.K.E.R.: Shadow of Chornobyl Enhanced Edition, executable
`1.10.3+68-42`, Steam build `24067120`. This build is verified through the
measured known-build registry and the deployment record in
[Runtime tests](RUNTIME-TESTS.md); the disposable-save acceptance matrix
there is the release gate. Original Shadow of Chornobyl, other Enhanced
Edition games, Anomaly, GAMMA, and Call of Chernobyl are outside support.

## Installation model

The project uses loose files under the game's `gamedata` directory. It does
not replace `fsgame_soc.ltx`, packed archives, or whole shared scripts. The
deployer materializes a missing shared file from the installed archive when
necessary (a pinned, hash-verified read; no external tools), then applies
uniquely marked semantic edits. It defaults to
dry-run and needs `-Apply` to write.

The inventory icon needs one more shared file: the engine has no per-item
icon setting and reads every icon from `ui\ui_icon_equipment`. The deployer
installs `gamedata/textures/ui/ui_icon_equipment.dds`, built from the game's
own copy with only the bag's icon cell changed (cells 2-3, rows 38-39, empty
in the shipped texture). Another mod that ships its own version of that
file conflicts: the deployer refuses to overwrite it. Icons from such a mod
would have to be merged by hand.

## Coexistence

Weight-limit, repair-vendor, and loot-tracker mods are explicit coexistence
targets. Their unrelated edits must survive deployment and removal. A shared
file with a missing or duplicate patch anchor is a hard stop, not permission
to overwrite the file.

## Distribution

Release `0.1.0` is a manual-install ZIP with a checksum, published on
GitHub. Steam Workshop distribution is not part of `0.1.0`: the mod patches
two shared files and installs a rebuilt texture, which needs separate design
work for a Workshop pack.
