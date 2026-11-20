---
name: design
description: Write a short technical design in Design/<slug>.md before building an Unlatch feature that adds public UnlatchCore API, touches entitlements, sandboxing, or system integration, or spans more than a couple of files.
argument-hint: issue number or feature idea
---

Design `$ARGUMENTS` before any code is written. Do not edit `Sources/` or `Tests/` in this step.

1. Read the issue (`gh issue view`), the sources and tests it touches, and `README.md`'s PDFKit traps.
   Name real files and types only.
2. Decide what belongs in `UnlatchCore` (UI-free, testable) and what belongs in the app.
3. Settle trade-offs with the maintainer as they come up, in this conversation: give a recommendation
   for each, and ask only about genuine product calls. Do not leave an "open questions" list for later.
4. For macOS concerns (sandboxing, entitlements, ServiceManagement, Services, signing), check
   availability against macOS 14 and say where the claim comes from.

Write `Design/<slug>.md`. Aim for one page; the design is a plan, not a spec of every line.

- **Summary**: the feature in two or three sentences, and what is out of scope.
- **Design**: files touched, new or changed public API as Swift signatures, and where state crosses
  actor isolation.
- **Tests**: what `UnlatchCoreTests` or `UnlatchTests` cover, new fixtures (and whether
  `Scripts/generate-fixtures.sh` must grow), and what is checked by hand.
- **Tasks**: ordered PR-sized steps, each with acceptance criteria.

Once the design is merged, it is history: do not open PRs only to keep it in sync with what shipped.
