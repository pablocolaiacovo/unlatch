# Security policy

## Supported versions

Only the latest release of Unlatch receives security fixes. Fixes ship as a new release from `main`;
older releases are not patched. If you build from source, use the latest commit on `main`.

## Reporting a vulnerability

Please **do not open a public issue** for a security vulnerability.

Report it privately through GitHub's private vulnerability reporting:
[**Report a vulnerability**](https://github.com/pablocolaiacovo/unlatch/security/advisories/new).
Only the maintainer can see the report.

Include as much of the following as you can:

- Which part is affected: the menu bar app (`Unlatch`), the library (`UnlatchCore`), or packaging
  and distribution.
- The Unlatch version (or commit, if built from source) and your macOS version.
- What an attacker can do, and what they need to do it.
- Steps to reproduce, or a proof of concept.

**Never attach a real sensitive document**, not even to a private report. If the problem involves a
particular kind of PDF, reproduce it with a synthetic file instead, for example one made by
`Scripts/generate-fixtures.sh` or with `qpdf --encrypt`. [CONTRIBUTING.md](CONTRIBUTING.md#reproducing-with-a-synthetic-pdf)
shows how.

## What to expect

Unlatch is maintained by one person in their spare time. Reports are handled on a best-effort
basis: the maintainer will acknowledge the report, work on a fix, and coordinate disclosure with you
through the advisory. Once a fix is released, the advisory is published with credit to you, unless
you prefer to stay anonymous.
