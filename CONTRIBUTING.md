# Contributing

## Scope and safety

Read `AGENTS.md` and the relevant document in `docs/` before changing code.
Keep game extracts, ABC material, saves, backups, and local configuration out
of Git. Do not modify `fsgame_soc.ltx`. Shared EE files are changed only by
the deployer through its `soc_sleeping_bag` markers.

## Workflow

1. Record a focused failing test before each behavior change.
2. Implement the smallest change that makes that test pass.
3. Run the repository checks and the focused test.
4. Use a disposable save for in-game tests. Do not run game-side writes
   without explicit approval and an `-Apply` command.
5. Update the design specification or implementation plan when the intended
   behavior changes.

## Commit messages

Use Conventional Commits:

```text
type(scope): imperative summary
```

Use a lowercase type such as `feat`, `fix`, `docs`, `test`, `build`, or
`chore`. Keep the summary concise and omit a trailing period. Put the version
only in `VERSION`; move release notes from `Unreleased` into a dated
`CHANGELOG.md` heading when releasing.

## Localization status

`gamedata/config/text/eng/st_soc_sleeping_bag.xml` holds the reviewed English
strings. Every other EE locale folder carries the same English text as
explicit fallback content, reviewed only by the authors, until a native
speaker reviews it. Do not label that fallback as a translated locale; mark
translation contributions as reviewed only after a fluent speaker checks the
text for the game's tone and terminology.
