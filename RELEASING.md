# Releasing Unlatch

This is the canonical process document for the repository: how work lands on `main`, how versions
are decided, and how a release is cut. If a change alters the process, it changes this file in the
same pull request.

Unlatch ships two things from one SwiftPM package:

- **`UnlatchCore`**, a library consumed through Swift Package Manager, versioned by the git tag.
- **`Unlatch.app`**, a menu bar app, distributed as a zip attached to a GitHub Release. It is
  **ad-hoc signed and not notarized** (see [Distribution and signing](#distribution-and-signing)).
  From v1.1, installed copies learn about new releases from a Sparkle update feed that the release
  workflow signs and publishes (see [Update feed and signing key](#update-feed-and-signing-key)).

Both are released together under a single version.

---

## Branching and pull requests

Trunk-based. `main` is always green and always releasable.

- Work happens on short-lived branches off `main`: `feature/...`, `fix/...`. Use `release/...` only
  if a release genuinely needs stabilization while other work continues; this should be rare.
- Every change lands through a pull request. Nothing is pushed to `main` directly.
- **Pull requests are squash-merged.** The repository allows squash merges only (merge commits and
  rebase merges are disabled), and the squash commit takes the PR title as its title and the PR body
  as its message. The PR title is therefore both the commit subject on `main` and the changelog
  line. Write it as a user-facing, imperative sentence — "Unlock PDFs from a Finder Quick Action",
  not "wip: fix stuff" and not a dump of commit subjects. If you would not want to read it in release
  notes, retitle before merging.
- The PR body references its issue with `Closes #N`.
- The PR carries the labels that decide its release-note section: `enhancement`, `bug`, or
  `documentation`, plus its `area:` labels. See [.github/release.yml](.github/release.yml).
- A PR with no user-facing effect also carries `skip-changelog`, which keeps it out of the release
  notes. Its title still follows the rule above, because it is still the commit subject on `main`.
- Head branches are deleted automatically on merge (repository setting); nothing to do by hand.

CI (`.github/workflows/ci.yml`) runs `swift build` and `swift test` on every pull request and every
push to `main`. A red `main` is fixed before anything else is merged.

`main` is intended to be protected so that the `build-and-test` check (the job in `ci.yml`) must pass
before a pull request can merge. Branch protection is configured by the maintainer in the repository
settings, not by any agent or workflow; if it is missing, merge only with that check green anyway.

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
| Release notes | `skip-changelog` | Pull requests only, as applicable |

`release-blocker` means the milestone cannot close while it is open. `needs-decision` means the
issue is waiting on the maintainer, not on an implementer — it is excluded from release notes.

`skip-changelog` goes on a pull request whose change has no user-facing effect: agent and tooling
configuration (`CLAUDE.md`, `.claude/`), CI-only housekeeping that does not change the published
artifact, and repository docs written for maintainers (`RELEASING.md`, issue templates,
`.github/release.yml`). It excludes the PR from the generated release notes. It does not replace the
type label: the PR still carries exactly one of `bug`, `enhancement`, or `documentation`, plus its
`area:` labels. When in doubt, leave it off; a line users can ignore is better than a change users
needed to know about going missing. User-facing docs such as the README's Install steps are not
internal and do not get it.

---

## Release checklist

Work through this in order. Do not skip ahead; each step exists because skipping it has a specific
failure mode.

### 1. Confirm the milestone is empty

```sh
gh issue list --milestone "v1.0" --state open
```

Zero results, or every remaining issue explicitly moved to the next milestone.

**Exception: a mid-milestone beta.** A beta (`vX.Y.Z-beta.N`) may be cut while its milestone still
has open issues, but only when the maintainer approves that exact version — typically to exercise
release-pipeline changes that only a tag push runs, or to get an early build to testers. The task
handed to `release-manager` names the version and states that the maintainer approved a
mid-milestone beta; without both, this check applies as written. An early beta does not commit the
milestone: the final `vX.Y.Z` still requires the check above, and later betas increment `N`.

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

Verify on the clean machine, running macOS 15 or later:

- Unzipping and launching from `/Applications` shows the Gatekeeper block that the README's Install
  section describes, and the README's first-launch steps get past it **exactly as written**. Check
  both paths, System Settings > Privacy & Security > Open Anyway and `xattr -dr
  com.apple.quarantine /Applications/Unlatch.app`, each on a fresh copy. If the dialog wording or the
  steps differ from the README, fix the README before tagging.
- After that first launch, relaunching with a plain double-click raises no further prompt.
- No Dock icon appears; the lock status item does.
- A password-protected PDF, an owner-restricted one, and a damaged one each behave correctly.
- The outputs open in Preview without a password.
- Get Info shows the version from the tag, not `0.0.0`.
- "Check for Updates…" in the popover's ellipsis menu reaches the feed and reports that this build
  is up to date. A beta install follows the `beta` channel, so it is offered betas and stable
  releases; a stable install is offered stable releases only.

Downloading with `curl` does not exercise Gatekeeper — the file has to carry the quarantine
attribute that a browser download applies.

**Upgrade test.** When the release changes any of the following, also check that the previous
build updates in place:

- the Sparkle version pinned in `Package.resolved`;
- the update configuration or the bundle identifier in `Resources/Info.plist.template`;
- how `Scripts/package-app.sh` signs the bundle, or how it numbers `CFBundleVersion`;
- `Sources/Unlatch/AppUpdater.swift`, or the update-channel logic in `Sources/Unlatch/Logic.swift`
  (`allowedUpdateChannels(forVersion:)`);
- the `appcast` or `deploy-feed` jobs, or `Scripts/update-appcast.sh`.

 Install the previous beta in `/Applications`
on the clean machine through the README's first-launch steps, then choose "Check for Updates…": it
must offer the new version with its notes, and "Install and Relaunch" must finish with the footer
menu showing the new version. Record whether Gatekeeper, TCC (save to Desktop again), or App
Management prompts again, and that the CDHash changed. The full procedure, including the scheduled
check, is in [Design/sparkle-updates.md](Design/sparkle-updates.md) §4, "Manual: the real N → N+1
upgrade test". If the install fails outright without a manual App Management grant, stop and raise
it with the maintainer before tagging the release; repeated prompts do not block it, they go in the
README.

A stable hotfix that skips its beta (see [Hotfix path](#hotfix-path)) cannot run the upgrade test
before tagging. If it touches anything in the list above, run the test right after the release is
published, from the previous stable release, and treat a failure as a new hotfix.

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

`.github/workflows/release.yml` runs on the pushed tag as four jobs, each starting only after the
previous one succeeds:

1. **`build-and-package`** packages and ad-hoc signs through `Scripts/package-app.sh`, verifies the
   signature, the embedded Sparkle framework, and the version, zips, and launches the unzipped copy.
2. **`publish`** creates the GitHub Release with notes generated from squashed PR titles.
3. **`appcast`** downloads `Unlatch.zip` from the published release (checked against the asset's
   sha256 digest), starts from the live feed, and runs `Scripts/update-appcast.sh`. That script
   signs the zip with the EdDSA key and adds one item with `generate_appcast --maximum-versions 0`,
   so every older item is kept. A `-beta.N` tag's item goes on the `beta` channel; a stable item has
   no channel. A stable tag on the same commit as its last beta shares that beta's build number, so
   its item replaces the beta item. The script fails if the new signature does not verify against
   the bundle's `SUPublicEDKey`.
4. **`deploy-feed`** re-fetches the live feed and refuses to deploy if the new one would drop or
   demote a live item, comparing items by `sparkle:version` and channel. It then publishes
   `appcast.xml` to GitHub Pages at <https://pablocolaiacovo.github.io/unlatch/appcast.xml>.

The feed is updated after the release exists, so it never points at a missing asset. Once the run
finishes:

- All four jobs are green, and the `codesign --verify --deep --strict` step genuinely passed.
- `Unlatch.zip` is attached and its size is plausible.
- The generated notes read like a changelog. Fix a bad line by editing the release body; fix the
  cause by writing better PR titles next time. The feed item embeds the notes as they were when
  `appcast` ran: a later edit to the release body reaches the update window only after re-running
  `appcast` as described below, which is possible for 30 days after the run.
- The prerelease flag matches the tag.
- The live feed carries the release. From the repository root, with the tag just pushed:

  ```sh
  TAG=v1.1.0     # the tag just pushed
  CHECK="$(mktemp -d)"
  curl -sS -o "$CHECK/appcast.xml" -w '%{http_code}\n' \
    "https://pablocolaiacovo.github.io/unlatch/appcast.xml?cb=$(date +%s)"   # 200
  xmllint --xpath "//item[enclosure[contains(@url,'/$TAG/Unlatch.zip')]]" "$CHECK/appcast.xml"
  gh release view "$TAG" --json assets --jq '.assets[] | [.name, .size] | @tsv'
  gh release download "$TAG" -p Unlatch.zip -D "$CHECK"
  swift Scripts/verify-ed-signature.swift <SUPublicEDKey> <edSignature> "$CHECK/Unlatch.zip"   # exit 0
  ```

  There is exactly one item for the tag. Its `sparkle:shortVersionString` is the tag without the
  `v`, its `sparkle:version` is the app's `CFBundleVersion`, and its `sparkle:channel` is `beta`
  for a beta and absent for a stable release. The enclosure URL is
  `https://github.com/pablocolaiacovo/unlatch/releases/download/<tag>/Unlatch.zip`, and its
  `length` equals the asset size. `<SUPublicEDKey>` comes from `Resources/Info.plist.template`,
  `<edSignature>` from the enclosure, and `verify-ed-signature.swift` exits 0.
- An installed previous version that should receive this release (a beta install for a beta, any
  install from v1.1 on for a stable release) is offered it by "Check for Updates…": the update
  window shows the new version and its notes. Installing it is not required for this check.

**If `appcast` or `deploy-feed` fails,** the release is public but installed copies are not told
about it. Fix the cause, then open the run and use **Re-run this job** on `appcast`; GitHub re-runs
its dependent `deploy-feed` with it. `appcast` takes the zip from the release rather than the 7-day
build artifact and rebuilds from the live feed, so this works days later too, but not forever:
GitHub allows re-running jobs only within 30 days of the original run. After that there is no
supported way to add or refresh a tag's feed item, because a `workflow_dispatch` run never reaches
`appcast`; ship the next version instead.

- Never use **Re-run all jobs**: `publish` fails because the release already exists.
- Do not use **Re-run failed jobs** when only `deploy-feed` failed: it redeploys the feed artifact
  from the earlier `appcast` run, which may be stale.
- A `deploy-feed` failure saying the deploy "would drop or demote live feed items" means another
  feed deploy landed in between. Re-running `appcast` is the fix, not working around the check.

**If the workflow published something broken,** fix forward: fix it on `main` through a pull
request and tag `vX.Y.Z+1` (a new beta, for a beta). How to handle the broken release depends on
whether `appcast` already published its item:

- **No feed item yet:** delete the release **and** the tag, but only after the run has finished
  with `deploy-feed` not green. `deploy-feed` does not check that the asset still exists, so never
  re-run that run afterwards: it would publish an item pointing at the deleted release.
- **The feed item is live:** leave the release in place and ship `vX.Y.Z+1` promptly. Its item
  supersedes the broken one for everyone who checks. When the broken release is a stable one, the
  fix ships directly as a stable release, without a beta first: stable installs do not see beta
  items, so they would keep being offered the broken build while a beta is tested. Delete the release and tag only if installing
  the build does real harm, such as data loss or an app that does not launch. Its feed item then
  points at a missing asset until the `+1` release's `deploy-feed` publishes a newer item, and users
  who check in between get a download error and stay on the version they have. That is accepted.
  There is no supported way to remove an item from the live feed: do not deploy Pages by hand. The
  dead item stays in the feed, below the newer one.

Never move or force-push a tag that has been published — anyone who already fetched it now has a
different artifact under the same version.

### 6. Close the milestone and open the next one

```sh
gh api repos/pablocolaiacovo/unlatch/milestones/<n> -X PATCH -f state=closed
```

Then create the next milestone with a one-sentence theme, and move any deferred issues into it or
into `Backlog`.

---

## Hotfix path

For a bug serious enough that it cannot wait for the next planned release — data loss, a crash on
launch, a build whose signature is broken so macOS reports it as damaged even after the documented
first-launch steps.

1. Open an issue, label it `bug` and `release-blocker`, and put it in a new patch milestone
   (`v1.0.1` belongs to the `v1.0` milestone if it is still open, otherwise create `v1.0.1`).
2. Branch `fix/...` from `main`, not from the release tag. `main` is the only supported line;
   Unlatch does not maintain old release branches.
3. Land the fix through a normal squash-merged pull request with CI green.
4. Tag `vX.Y.Z+1` from `main` and follow the release checklist from step 4. A hotfix may skip the
   beta in step 3 only if the fix is small and clearly verified, and the reason is recorded in the
   release notes. A fix for a broken stable release whose feed item is live always skips the beta
   (step 5), and runs the upgrade test after publishing instead (step 3).

If the broken release was deleted after its feed item went live (step 5), that item points at a
missing asset until the hotfix's `deploy-feed` publishes a newer one. Users who check in between
get a download error, so the hotfix should not wait.

If the fix cannot be released from `main` because `main` has already moved on with unreleased,
unfinished work, that is a signal that changes are sitting on `main` too long — not a reason to
start maintaining release branches.

---

## Distribution and signing

**Current state: ad-hoc signed, not notarized.** The maintainer decided not to join the paid Apple
Developer Program for now, because the expected audience is small (issue #8). This decision is
deferred, not rejected.

What that means in practice:

- `Scripts/package-app.sh` seals the whole bundle with an ad-hoc signature (`codesign --force --sign
  -`), without the hardened runtime. That signature is required on Apple Silicon, not optional: a
  bundle that is not sealed as a whole is reported as "damaged" once downloaded. The release workflow
  verifies it with `codesign --verify --deep --strict` before publishing.
- The release workflow reads no Apple credentials and no repository-level secrets. Its only secret
  is the Sparkle update-signing key, scoped to the `sparkle-signing` environment (see [Update feed
  and signing key](#update-feed-and-signing-key)).
- Every downloaded copy is quarantined, and Gatekeeper blocks its first launch. The README's Install
  section tells users how to open it: System Settings > Privacy & Security > Open Anyway, or `xattr
  -dr com.apple.quarantine /Applications/Unlatch.app`. Right-click > Open no longer bypasses
  Gatekeeper on macOS 15 and later. Keep that section accurate. It is part of the product.
- Never strip the quarantine attribute in the workflow, the zip, or a Homebrew cask. The user takes
  that step knowingly.
- The official `homebrew/cask` repository does not accept apps that fail Gatekeeper checks, so a
  cask (#12) can only live in a personal tap until the app is notarized.

### Update feed and signing key

From v1.1, Unlatch checks for updates with Sparkle (issue #13). The design is
[Design/sparkle-updates.md](Design/sparkle-updates.md); the one-time setup is its §2.9.

- **The feed** is <https://pablocolaiacovo.github.io/unlatch/appcast.xml>, the `SUFeedURL` in
  `Resources/Info.plist.template`. GitHub Pages serves it, deployed by the `deploy-feed` job through
  Actions, not from a `gh-pages` branch. Nothing in the repository holds the feed: the live feed is
  the state, and every release adds to it. Its items point at the `Unlatch.zip` assets on GitHub
  Releases. Betas are on the `beta` channel of the same feed.
- **The signing key** is an EdDSA (ed25519) key pair. The public half is `SUPublicEDKey` in
  `Resources/Info.plist.template`. The private half is `SPARKLE_ED_PRIVATE_KEY`, an environment
  secret of the `sparkle-signing` environment, which only `v*` tags may use. Branch runs and
  `workflow_dispatch` runs never see it, and only the `appcast` job reads it, piping it to the
  tools on stdin. Never echo it or run that step under `set -x`.
- **The `github-pages` environment** allows `main` and `v*` tags to deploy. Without the tag rule,
  `deploy-feed` fails with "Tag … is not allowed to deploy to github-pages due to environment
  protection rules".
- **The backup** of the private key is in the maintainer's 1Password. Never in the repository, and
  never as a plain file.
- **Losing the private key strands every installed copy.** With ad-hoc signing, the EdDSA
  signature is Sparkle's only trust anchor, so no update signed with another key installs, and
  every user would have to download and reinstall by hand. Rotating the key is possible only while
  the old one exists: ship an update signed with the old key that carries the new public key.
- v1.0.0 has no updater. Its users install v1.1.0 by hand once.

### Path back to notarization

Tracked in issue #8, in the `Backlog` milestone. Revisit it when people other than the maintainer
report Gatekeeper friction, or when an official Homebrew cask or smoother Sparkle updates become
goals. Switching requires:

1. A paid Apple Developer Program membership, a **Developer ID Application** certificate, and an App
   Store Connect API key for `notarytool`.
2. These repository secrets:

   | Secret | What it is |
   | --- | --- |
   | `MACOS_CERTIFICATE_P12` | Base64 of the exported Developer ID Application `.p12` |
   | `MACOS_CERTIFICATE_PASSWORD` | Password protecting that `.p12` |
   | `MACOS_SIGNING_IDENTITY` | Full identity string, `Developer ID Application: Name (TEAMID)` |
   | `APPLE_API_KEY_ID` | App Store Connect API key ID, used by `notarytool` |
   | `APPLE_API_ISSUER_ID` | App Store Connect issuer ID |
   | `APPLE_API_KEY_P8` | Base64 of the `.p8` private key |
   | `APPLE_TEAM_ID` | Apple Developer team identifier |

3. Passing that identity to `Scripts/package-app.sh` instead of `-`, then `notarytool submit --wait`, `stapler staple`, and `spctl -a
   -vvv -t install`. In the workflow: import the certificate into a temporary keychain, deleted in an
   `always()` step, and attach the zip only after stapling. For Sparkle: `CODESIGN_ARGS` in
   `Scripts/package-app.sh` gets `--options runtime --timestamp` (never while ad-hoc, where the
   hardened runtime turns on library validation and dyld refuses the embedded framework), the
   nested Sparkle code is signed inside-out with the same identity, and the "Verify Sparkle bundle"
   step's ad-hoc, no-`Authority`, and no-`runtime` assertions flip. Keep the same EdDSA key: as long
   as it does not change, ad-hoc installs update to the Developer ID build without a manual
   reinstall.
4. Updating this file: the release checklist verifies that the app opens with no Gatekeeper prompt,
   and the published-release check confirms that notarization and `spctl` passed. The README's
   first-launch steps are removed. Record the certificate's expiry date here. **Developer ID
   certificates expire after five years**, and an expired certificate breaks releases, although
   already-notarized builds keep working.

Rules that hold either way:

- Signing material is never committed. `.gitignore` already excludes `*.p12`, `*.cer`, `*.pem`, and
  `.env`; do not weaken it.

---

## Building locally

Contributors do not need an Apple Developer account. `Scripts/package-app.sh` produces the same
ad-hoc signed `dist/Unlatch.app` that the release workflow ships. A locally built copy is not
quarantined, so it opens without the first-launch steps. It carries the real feed URL and public
key, so it may be offered a newer stable release; that is harmless.
