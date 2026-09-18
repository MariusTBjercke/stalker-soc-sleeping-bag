# Compatibility

## Supported build

The current target is the manual PC Steam installation of S.T.A.L.K.E.R.:
Shadow of Chornobyl Enhanced Edition, executable `1.10.3+68-42`, Steam build
`24067120`. This is a pre-release contract, not a tested gameplay release.
Original Shadow of Chornobyl, other Enhanced Edition games, Anomaly, GAMMA,
and Call of Chernobyl are outside support.

## Installation model

The project uses loose files under the game's `gamedata` directory. It does
not replace `fsgame_soc.ltx`, packed archives, or whole shared scripts. The
future deployer materializes a missing shared file from the installed archive
when necessary, then applies uniquely marked semantic edits. It defaults to
dry-run and needs `-Apply` to write.

## Coexistence

Weight-limit, repair-vendor, and loot-tracker mods are explicit coexistence
targets. Their unrelated edits must survive deployment and removal. A shared
file with a missing or duplicate patch anchor is a hard stop, not permission
to overwrite the file.

## Distribution

Steam Workshop distribution is excluded. The feature requires scripts and
configuration files, and this project supports manual PC installation only.
