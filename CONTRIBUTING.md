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
strings. The other locale folders hold translations that Claude wrote and no native
speaker has reviewed yet. Each file uses the code page the game reads that
language in (cp1250 for cze, pol and hg, cp1251 for rus and ukr, cp1252 for
fra, ger, ita and spa, UTF-8 for jpn, kor and the Chinese folders), and
shared words such as Cancel, Rest and Bleeding follow the game's own
translations. Do not call a locale reviewed until a fluent speaker has
checked the text for the game's tone and terminology. Corrections are welcome.

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
