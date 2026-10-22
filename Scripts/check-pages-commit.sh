#!/usr/bin/env bash
#
# Fails if another tag already deployed this tag's commit to GitHub Pages.
# See issues #76, #77 and #78, and RELEASING.md step 4.
#
# Pages dedupes on `pages_build_version`, which actions/deploy-pages sets to
# the commit SHA, so a second deploy of a commit is accepted, reported as a
# success, and never served (v1.1.0 on v1.1.0-beta.5's commit). Each
# deploy-feed run leaves a `github-pages` deployment record on the tag's ref (a
# failed attempt a `failure` status), so only a record for this commit, on a
# different ref, whose latest status is `success`, counts as a clash. Records on
# this tag's own ref are earlier attempts of this same tag (a re-run), which
# must stay possible.
#
# release.yml runs this twice with the same rules: in `check-feed-commit`,
# before `publish`, so a clashing tag never creates a release; and in
# `deploy-feed`, right before the deploy, as a backstop for a deploy that lands
# in between (`appcast` can be re-run up to 30 days later).
#
# Two cases this cannot see, both still caught by deploy-feed's post-deploy
# live-feed check, after up to ~13 minutes:
#   - A prior tag's Pages deploy went through but its post-deploy verify step
#     failed, so its deployment record ends as `failure` and is not counted.
#   - Two tags pushed to the same commit at the same time: neither has
#     deployed yet, so both pass.
#
# Usage:
#   Scripts/check-pages-commit.sh --stage before-publish|before-deploy
#
# --stage only changes what the error tells the maintainer to do next: before
# `publish` nothing exists to clean up; before the deploy the release does.
#
# Environment (all set by GitHub Actions on a tag push, except GH_TOKEN):
#   GH_TOKEN           Token with `deployments: read`.
#   GITHUB_REPOSITORY  owner/name.
#   GITHUB_REF         refs/tags/<tag>.
#   GITHUB_SHA         The tagged commit.
set -euo pipefail

die() { echo "::error::$*" >&2; exit 1; }

STAGE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage) STAGE="${2:-}"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done
case "$STAGE" in
  before-publish|before-deploy) ;;
  *) die "--stage must be before-publish or before-deploy" ;;
esac

: "${GITHUB_REPOSITORY:?}" "${GITHUB_REF:?}" "${GITHUB_SHA:?}"
[[ "$GITHUB_REF" == refs/tags/* ]] || die "GITHUB_REF '$GITHUB_REF' is not a tag; this check only runs on a tag push"
TAG="${GITHUB_REF#refs/tags/}"

IDS="$(gh api --paginate "repos/$GITHUB_REPOSITORY/deployments?environment=github-pages&sha=$GITHUB_SHA&per_page=100" \
  | jq -r --arg ref "$TAG" '.[] | select(.ref != $ref) | "\(.id) \(.ref)"')"
CLASH=""
while read -r ID REF; do
  [[ -n "$ID" ]] || continue
  STATE="$(gh api "repos/$GITHUB_REPOSITORY/deployments/$ID/statuses?per_page=1" --jq '.[0].state // "none"')"
  echo "deployment $ID (ref $REF) of commit $GITHUB_SHA: latest status $STATE"
  if [[ "$STATE" == success ]]; then CLASH="$CLASH $REF"; fi
done <<<"$IDS"

if [[ -n "$CLASH" ]]; then
  MSG="Commit $GITHUB_SHA is already deployed to Pages by:$CLASH. Pages would accept a second deploy of the same commit, report success, and keep serving the first one. $TAG needs a different commit: tag the next commit on main (RELEASING.md step 4). Do not re-run this run."
  if [[ "$STAGE" == before-publish ]]; then
    MSG="$MSG No release, feed item, or Pages deploy was created, so the only cleanup is deleting the tag: git push origin :refs/tags/$TAG"
  else
    MSG="$MSG The release already exists: delete the release and $TAG as RELEASING.md describes, then ship the next version from a different commit. Do not reuse $TAG."
  fi
  die "$MSG"
fi
echo "No other tag has deployed $GITHUB_SHA"
