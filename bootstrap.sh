#!/usr/bin/env bash
# Quality Loop — one-command installer. No clone required.
#
# Public repo:
#   curl -fsSL https://raw.githubusercontent.com/nickohold/quality-loop/main/bootstrap.sh | bash
#
# Private repo (uses your gh auth):
#   gh api repos/nickohold/quality-loop/contents/bootstrap.sh -H "Accept: application/vnd.github.raw" | bash
#
# Downloads a tarball to a temp dir, runs install.sh, cleans up. Nothing is left
# behind except the installed engine under ~/.claude.
set -euo pipefail

REPO="${QL_REPO:-nickohold/quality-loop}"
BRANCH="${QL_BRANCH:-main}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Fetching $REPO@$BRANCH …"
if curl -fsSL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" -o "$TMP/ql.tgz" 2>/dev/null; then
  : # public download succeeded
elif command -v gh >/dev/null 2>&1 && gh api "repos/$REPO/tarball/$BRANCH" > "$TMP/ql.tgz" 2>/dev/null; then
  : # private download via authenticated gh
else
  echo "ERROR: could not download $REPO@$BRANCH."
  echo "If the repo is private, install the GitHub CLI and run: gh auth login"
  exit 1
fi

tar -xzf "$TMP/ql.tgz" -C "$TMP"
DIR="$(find "$TMP" -maxdepth 1 -type d -name '*quality-loop*' | head -1)"
[ -n "$DIR" ] || { echo "ERROR: unexpected archive layout"; exit 1; }

bash "$DIR/install.sh"
