---
name: council-review
description: Review an Unlatch change with two independent reviewer agents, then rank their findings into must-fix and nice-to-have. Use before opening a PR for merge, or on a PR number or branch.
argument-hint: PR number, branch, or empty for the working tree
---

Review target: `$ARGUMENTS` (a PR number, a branch, or the working tree when empty).

## 1. Convene the council

In one message, launch two `reviewer` agents in parallel. Give both the same short brief: the
target, the linked issue number if there is one, and "review it as your instructions say and report".
Do not pass your own view of the change, what you think is risky, or the other reviewer's existence:
each must start from a fresh context so their findings are independent.

## 2. Decide

When both reports are in, check every finding yourself against the code before ranking it. Read the
line, and walk through the reviewer's scenario. Then sort each one into exactly one bucket:

- **Must fix**: a concrete scenario produces a wrong result, crash, data loss, race, broken
  `UnlatchCore` boundary, PDFKit trap, missing test for new behaviour, or a release-hygiene violation
  (hardcoded version, credentials, PR title or labels). Order by severity: data loss and security first,
  then wrong behaviour users would see, then tests, then hygiene.
- **Nice to have**: real but would not block a merge (clearer naming, an extra edge-case test, a
  simplification).
- **Dismissed**: you could not reproduce the scenario, or it contradicts the code. Give the reason in
  one line.

A finding both reviewers raised independently is stronger evidence, not proof: still verify it. Where
the reviewers disagree, the code decides, not a vote.

## 3. Report and act

Report in this order: verdict (merge / merge after fixes / do not merge), **Must fix** as a numbered
list with `path:line` and the one-line scenario, **Nice to have**, **Dismissed**, then each reviewer's
build and test result.

Then fix the must-fix items in order, run `swift build` and `swift test`, and show the output. When
the target is a PR, fix only on its head branch: if the checkout is on another branch, run
`gh pr checkout <n>` when the working tree is clean; otherwise stop after the report and say why. Leave
nice-to-haves for the maintainer to pick; do not fix them unasked.
