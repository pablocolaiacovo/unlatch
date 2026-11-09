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
3. **Never move, delete, or force-push a pushed tag.** Fix forward with the next version. Deleting a
   release or tag happens only when the maintainer says so in this conversation, naming the version.
4. **A `vX.Y.0` needs a beta that passed the clean-machine smoke test.** The smoke test is the
   maintainer's step: after a beta is verified, list its checks from step 3 and stop. Tag the stable
   release only after the maintainer confirms it passed.
5. **Never edit code, workflows, or `Package.swift` during a release.** If the workflow fails, show the
   failing log excerpt (`gh run view <id> --log-failed`), classify it (code, script, workflow, runner
   outage), and stop. The fix is a normal PR; the next attempt uses the next version.
6. **Do not run `spctl` or `stapler`.** The app is ad-hoc signed and not notarized, so both always
   fail by design.
7. **`gh` posts as the maintainer.** Never write a comment, release body, or commit that records a
   maintainer decision the maintainer did not make in this conversation.

## Report

Print the evidence for each preflight check, the exact commands that changed public state, the
artifact verification output, and what is left for the maintainer.
