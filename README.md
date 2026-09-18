# STALKER SoC Sleeping Bag

This pre-release Lua mod adds a reusable sleeping-bag gameplay feature for
manual PC installations of **S.T.A.L.K.E.R.: Shadow of Chornobyl Enhanced
Edition**. No public release package exists yet.

The design takes behavioral inspiration from the 2007 ABC Sleeping Bag Mod.
This repository contains independently authored code and assets only; it does
not contain ABC code, textures, XML, or icon atlases.

## Current status

Version `0.1.0-dev` is repository setup work. The deployer, gameplay module,
and in-game acceptance evidence have not been implemented. The supported
target under investigation is EE executable `1.10.3+68-42`, Steam build
`24067120`; other builds are not supported until verified.

## Documentation

| Document | Contents |
| --- | --- |
| [Architecture](docs/ARCHITECTURE.md) | Verified engine facts and pending probes |
| [Compatibility](docs/COMPATIBILITY.md) | Supported build and coexistence boundary |
| [Development](docs/DEVELOPMENT.md) | Configuration, extraction, checks, and runtime policy |
| [Design specification](docs/superpowers/specs/2026-09-18-sleeping-bag-design.md) | Approved feature behavior and constraints |
| [Implementation plan](docs/superpowers/plans/2026-09-18-sleeping-bag-implementation.md) | Task-by-task delivery plan |

## License

Repository code written for this project is under the MIT license. Game files,
third-party reference material, and ABC material are not covered by that
license. See [LICENSE](LICENSE).
