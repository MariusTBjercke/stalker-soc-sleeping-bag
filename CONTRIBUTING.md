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
4. Use a disposable save for in-game tests. Review the dry-run plan of
   `tools/deploy.ps1` before running it with `-Apply`.
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

## Releasing

1. Set `VERSION` to the release version and move the `CHANGELOG.md` entries
   under a dated `## <version> - <YYYY-MM-DD>` heading.
2. Run the checks, then commit everything (packaging refuses a dirty tracked
   worktree):

   ```powershell
   powershell -NoProfile -File tools/check.ps1
   ```

3. Build the archive. It writes `dist/soc-sleeping-bag-<version>.zip` and a
   `.sha256` file next to it, and `tools/tests/package_test.ps1` checks its
   contents:

   ```powershell
   powershell -NoProfile -File tools/package.ps1
   ```

4. Commit as `chore(release): <version>` and tag `v<version>`.
5. Push `main` and the tag, then publish the GitHub release with the ZIP and
   its checksum attached:

   ```powershell
   gh release create v<version> dist/soc-sleeping-bag-<version>.zip dist/soc-sleeping-bag-<version>.zip.sha256 --title "Sleeping Bag <version>" --notes-file <notes.md>
   ```
