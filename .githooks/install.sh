#!/bin/sh
# Turn on the hooks in this directory for this clone, and give the clone the
# owner's identity when it has none or has Claude's (a fresh cloud checkout).
# Run by the SessionStart hook in .claude/settings.json; safe to run by hand.
cd "$(dirname "$0")/.." || exit 0
. .githooks/patterns.sh

git config core.hooksPath .githooks

ident="$(git config user.name) <$(git config user.email)>"
if [ "$ident" = " <>" ] || is_bad_ident "$ident"; then
  git config user.name "$owner_name"
  git config user.email "$owner_email"
fi
