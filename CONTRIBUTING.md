# Contributing to Unlatch

Thanks for your interest in Unlatch. Bug reports, fixes, and well-scoped improvements are all
welcome. This file covers what you need to know as an outside contributor. The maintainer-side
process, covering versioning, milestones, labels, and cutting releases, lives in
[RELEASING.md](RELEASING.md) and is not something you need to follow yourself.

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Building and testing

You need:

- macOS 14 or later
- A Swift 6 toolchain (Swift 6.3 or later; Xcode or the standalone toolchain both work)

There is no Xcode project. Everything goes through SwiftPM from the repository root:

```sh
swift build
swift test
```

Both must pass before a pull request can merge. CI runs the same two commands.

To produce a standalone `Unlatch.app`, run `Scripts/package-app.sh`. It ad-hoc signs the bundle,
so no Apple Developer account is needed. See [Building locally](RELEASING.md#building-locally) in
`RELEASING.md` for details.

### Test fixtures

The test PDFs live in `Tests/UnlatchCoreTests/Fixtures` and are generated, not collected. To
regenerate them:

```sh
brew install qpdf
./Scripts/generate-fixtures.sh
```

If a test needs a new kind of PDF, add it to `Scripts/generate-fixtures.sh` (or
`Scripts/MakeBasePDFs.swift`) and commit the regenerated output. **Never commit a real-world PDF**,
even one you believe is harmless. The README's [fixture corpus](README.md#the-fixture-corpus)
section explains why the encrypted fixtures come from two different producers.

## Workflow

1. **Start from an issue.** For anything beyond a typo, open an issue first (or comment on an
   existing one) so the approach can be agreed before you spend time on it.
2. **Branch off `main`** with a short-lived branch named `feature/...` or `fix/...`.
3. **Keep each pull request to one change.** Unrelated fixes go in separate pull requests.

## Pull requests

- **The title is the changelog line.** Pull requests are squash-merged, and the PR title becomes
  both the commit subject on `main` and the line in the release notes. Write it as a user-facing,
  imperative sentence: "Keep bookmarks when unlocking a PDF", not "fix outline bug" or "WIP".
- **The body says `Closes #N`** for the issue it resolves, plus a short summary of what changed and
  how you tested it. The pull request template has a checklist for this.
- **Commit history inside the PR does not matter.** It is squashed on merge, so do not worry about
  tidying it up.
- **Labels are the maintainer's job.** The type, `area:`, and `skip-changelog` labels decide where a
  change appears in the release notes. You are not expected to apply them.
- Do not change version numbers anywhere. The git tag is the only source of truth for the version.
- Do not add signing material or credentials. `.gitignore` already excludes them.

## Filing a good issue

Pick the form that fits: **Bug report** for something that does not behave as documented,
**Feature request** for a change or addition. Security problems do not go in public issues; see
[Security](#security) below.

### Reproducing with a synthetic PDF

Unlatch handles password-protected documents, and those are often confidential. **Do not attach a
real document to an issue**, even a redacted one. What matters for a bug is how the file is
protected and what produced it:

- **How it is protected:** an open password, permissions only (it opens freely but printing or
  copying is restricted), or neither.
- **What produced it:** Acrobat, Word, Preview, a scanner, another tool, and the version if you
  know it.

Then try to reproduce the problem with a PDF you made yourself and can share. Either:

- Use one of the fixtures produced by `Scripts/generate-fixtures.sh`, or
- Encrypt any harmless PDF with [qpdf](https://qpdf.readthedocs.io/):

  ```sh
  # Needs a password to open (user password "hunter2")
  qpdf --encrypt hunter2 owner 256 -- plain.pdf user-locked.pdf

  # Opens freely, but printing and modification are restricted
  qpdf --encrypt "" owner 256 --print=none --modify=none -- plain.pdf owner-restricted.pdf
  ```

If the bug only shows up with the original file, say so in the issue and describe the producer as
precisely as you can rather than attaching it.

## Security

Please do not open a public issue for a security vulnerability. Report it privately as described
in [SECURITY.md](SECURITY.md).

## A note on AI agents

Some issues and pull requests in this repository are prepared with AI coding agents, configured
through [CLAUDE.md](CLAUDE.md) and `.claude/agents/`. That is how the maintainer works; it is not a
requirement for contributors. You do not need to use those agents or any AI tooling, and the rules
above are the same either way.
