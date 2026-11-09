---
name: release
description: Cut an Unlatch beta, stable, or hotfix release for an exact version, following RELEASING.md.
argument-hint: vX.Y.Z or vX.Y.Z-beta.N
disable-model-invocation: true
---

Release `$ARGUMENTS`. `RELEASING.md` is the procedure: read its "Release checklist" and "Hotfix path"
in full before doing anything, and follow it step by step. If it and this file disagree, it wins;
report the discrepancy.

## Hard rules

1. **The version must be exact.** `$ARGUMENTS` must be a full `vX.Y.Z` or `vX.Y.Z-beta.N`. If it is
   empty, partial, or differs from what the checklist leads you to, stop and ask.
2. **Tags are annotated, created on `main` equal to `origin/main`, and pushed one at a time by name.**
   Never `git push --tags`.
3. **Never move or force-push a tag once its `publish` job has run.** Fix forward with the next
   version. Before `publish` runs (a `check-feed-commit` failure), RELEASING.md step 5 deletes the tag
   and reuses the version. Deleting any tag or release, and re-running any job, happens only after the
   maintainer says yes in this conversation, naming the version.
4. **A `vX.Y.0` needs a beta that passed the clean-machine smoke test.** The smoke test is the
   maintainer's step: after a beta is verified, list its checks from step 3 and stop. Tag the stable
   release only after the maintainer confirms it passed.
5. **Never edit code, workflows, or `Package.swift` during a release.** If the workflow fails, show the
   failing log excerpt (`gh run view <id> --log-failed`), find the matching case in RELEASING.md step 5
   (re-run `appcast`, delete and reuse the version, or ship the next version), and propose it to the
   maintainer. A code or workflow fix lands as a normal PR first.
6. **Do not run `spctl` or `stapler`.** The app is ad-hoc signed and not notarized, so both always
   fail by design.
7. **`gh` posts as the maintainer.** Never write a comment, release body, or commit that records a
   maintainer decision the maintainer did not make in this conversation.

## Preflight

Before checklist step 1, confirm and print the evidence for each:

- `gh auth status` succeeds.
- The working tree is clean, on `main`, and equal to `origin/main`.
- The bump is right under SemVer: compare against `git tag --sort=-v:refname | head -1` and the PR
  titles merged since. If a PR looks breaking and the bump is not major, say so and stop.

## Report

Print the evidence for the preflight and checklist steps 1 and 2, the exact commands that changed public state, the
artifact verification output, and what is left for the maintainer.
