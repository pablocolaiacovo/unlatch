# Releasing Unlatch

This is the canonical process document for the repository: how work lands on `main`, how versions
are decided, and how a release is cut. If a change alters the process, it changes this file in the
same pull request.

Unlatch ships two things from one SwiftPM package:

- **`UnlatchCore`**, a library consumed through Swift Package Manager, versioned by the git tag.
- **`Unlatch.app`**, a signed and notarized menu bar app, distributed as a zip attached to a
  GitHub Release.

Both are released together under a single version.

---

## Branching and pull requests

Trunk-based. `main` is always green and always releasable.

- Work happens on short-lived branches off `main`: `feature/...`, `fix/...`. Use `release/...` only
  if a release genuinely needs stabilization while other work continues; this should be rare.
- Every change lands through a pull request. Nothing is pushed to `main` directly.
- **Pull requests are squash-merged**, and the PR title becomes the merge commit message and the
  changelog line. Write it as a user-facing, imperative sentence — "Add drag-and-drop onto the menu
  bar icon", not "wip: fix stuff" and not a dump of commit subjects. If you would not want to read
  it in release notes, retitle before merging.
- The PR body references its issue with `Closes #N`.
- The PR carries the labels that decide its release-note section: `enhancement`, `bug`, or
  `documentation`, plus its `area:` labels. See [.github/release.yml](.github/release.yml).
- Delete the branch after merging.

CI (`.github/workflows/ci.yml`) runs `swift build` and `swift test` on every pull request and every
push to `main`. A red `main` is fixed before anything else is merged.

---

## Versioning

[Semantic versioning](https://semver.org). Given `MAJOR.MINOR.PATCH`:

- **MAJOR** — a breaking change to the `UnlatchCore` public API, or a change that raises the minimum
  macOS version.
- **MINOR** — new user-visible capability, backwards compatible.
- **PATCH** — bug fixes only.

**The git tag is the single source of truth for the version. Nothing in the repository is bumped by
hand.** There is no version constant in `Package.swift`, no `VERSION` file, no hardcoded string in
`Info.plist`. `Scripts/package-app.sh` derives `CFBundleShortVersionString` from `git describe
--tags` at build time. A pull request that edits a version number is doing something wrong.

- Releases are **annotated** git tags: `v1.0.0`, `v1.2.3`.
- Pre-releases are `vX.Y.Z-beta.N` — `v1.0.0-beta.1`, `v1.0.0-beta.2` — and are published as
  GitHub prereleases. The release workflow marks them automatically based on the `-beta.` in the tag.
- Tags are only ever created on a commit that is on `main`.

---

## Milestones

- One milestone per release, named after the version without the patch number: `v1.0`, `v1.1`.
- Plus a permanent `Backlog` milestone for accepted-but-unscheduled work.
- Every open issue belongs to exactly one milestone. An issue with no milestone has not been triaged.
- A milestone description states the theme of that release in one or two sentences.

**A release is cut only when its milestone has zero open issues**, or when every remaining issue has
been explicitly moved out to a later milestone by the maintainer. "It is probably fine" is not a
reason to leave a `release-blocker` open.

---

## Labels

| Kind | Labels | Rule |
| --- | --- | --- |
| Type | `bug`, `enhancement`, `documentation` | Exactly one per issue |
| Area | `area:core`, `area:app`, `area:release` | At least one per issue |
| Status | `release-blocker`, `needs-decision`, `good first issue` | As applicable |

`release-blocker` means the milestone cannot close while it is open. `needs-decision` means the
issue is waiting on the maintainer, not on an implementer — it is excluded from release notes.

---

## Release checklist

Work through this in order. Do not skip ahead; each step exists because skipping it has a specific
failure mode.

### 1. Confirm the milestone is empty

```sh
gh issue list --milestone "v1.0" --state open
```

Zero results, or every remaining issue explicitly moved to the next milestone.

### 2. Confirm `main` is green

```sh
git checkout main && git pull
gh run list --branch main --limit 5
swift build && swift test
```

### 3. Cut a beta and smoke-test it

Never tag `vX.Y.0` as the first artifact anyone sees. Tag a beta, let the release workflow publish it
as a prerelease, then **download the zip in a browser** on a machine that has never built this
project — a second Mac, a fresh user account, or a clean VM.

```sh
git tag -a v1.0.0-beta.1 -m "Unlatch 1.0.0-beta.1"
git push origin v1.0.0-beta.1
```

Verify on the clean machine:

- Unzipping and launching from `/Applications` raises no Gatekeeper warning.
- No Dock icon appears; the lock status item does.
- A password-protected PDF, an owner-restricted one, and a damaged one each behave correctly.
- The outputs open in Preview without a password.
- Get Info shows the version from the tag, not `0.0.0`.

Downloading with `curl` does not exercise Gatekeeper — the file has to carry the quarantine
attribute that a browser download applies.

Any failure is fixed on `main` through a pull request, followed by a new beta. Betas are cheap.

### 4. Tag the release

```sh
git checkout main && git pull
git tag -a v1.0.0 -m "Unlatch 1.0.0"
git push origin v1.0.0
```

The tag must be annotated (`-a`), and pushed explicitly. `git push --tags` is discouraged: it pushes
every local tag, including experiments you meant to keep to yourself.

### 5. Verify the published release

`.github/workflows/release.yml` runs on the pushed tag: it packages, signs, notarizes, staples, zips,
and publishes a GitHub Release with notes generated from squashed PR titles. Once it finishes:

- The run is green, and the notarization and `spctl` verification steps genuinely passed.
- `Unlatch.zip` is attached and its size is plausible.
- The generated notes read like a changelog. Fix a bad line by editing the release body; fix the
  cause by writing better PR titles next time.
- The prerelease flag matches the tag.

If the workflow published something broken, delete the release **and** the tag, fix forward on
`main`, and tag `vX.Y.Z+1`. Never move or force-push a tag that has been published — anyone who
already fetched it now has a different artifact under the same version.

### 6. Close the milestone and open the next one

```sh
gh api repos/pablocolaiacovo/unlatch/milestones/<n> -X PATCH -f state=closed
```

Then create the next milestone with a one-sentence theme, and move any deferred issues into it or
into `Backlog`.

---

## Hotfix path

For a bug serious enough that it cannot wait for the next planned release — data loss, a crash on
launch, a build that fails Gatekeeper.

1. Open an issue, label it `bug` and `release-blocker`, and put it in a new patch milestone
   (`v1.0.1` belongs to the `v1.0` milestone if it is still open, otherwise create `v1.0.1`).
2. Branch `fix/...` from `main`, not from the release tag. `main` is the only supported line;
   Unlatch does not maintain old release branches.
3. Land the fix through a normal squash-merged pull request with CI green.
4. Tag `vX.Y.Z+1` from `main` and follow the release checklist from step 4. A hotfix may skip the
   beta in step 3 only if the fix is small and clearly verified, and the reason is recorded in the
   release notes.

If the fix cannot be released from `main` because `main` has already moved on with unreleased,
unfinished work, that is a signal that changes are sitting on `main` too long — not a reason to
start maintaining release branches.

---

## Signing and notarization credentials

Distribution requires a paid Apple Developer Program membership and a **Developer ID Application**
certificate. The release workflow reads these from repository secrets:

| Secret | What it is |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Base64 of the exported Developer ID Application `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | Password protecting that `.p12` |
| `MACOS_SIGNING_IDENTITY` | Full identity string, `Developer ID Application: Name (TEAMID)` |
| `APPLE_API_KEY_ID` | App Store Connect API key ID, used by `notarytool` |
| `APPLE_API_ISSUER_ID` | App Store Connect issuer ID |
| `APPLE_API_KEY_P8` | Base64 of the `.p8` private key |
| `APPLE_TEAM_ID` | Apple Developer team identifier |

Rules:

- Signing material is never committed. `.gitignore` already excludes `*.p12`, `*.cer`, `*.pem`, and
  `.env`; do not weaken it.
- The workflow imports the certificate into a temporary keychain and deletes it in an `always()`
  step, so a failed run leaves nothing behind on the runner.
- **Developer ID certificates expire after five years.** Record the expiry date here when the
  certificate is created, and renew before it lapses — an expired certificate breaks releases, though
  already-notarized builds keep working.

Certificate expiry: _to be recorded when the certificate is created (see issue #8)._

---

## Building locally without a certificate

Contributors do not need an Apple Developer account. `Scripts/package-app.sh` has an unsigned mode
that produces a launchable `dist/Unlatch.app` for local testing. The result is not distributable and
will be rejected by Gatekeeper on any other machine — that is expected.
