#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${1:-_site}"
PAGES_DIR="_pages"

if [[ ! -d "$BUILD_DIR" ]]; then
  echo "Build directory '$BUILD_DIR' does not exist." >&2
  exit 1
fi

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

git fetch origin gh-pages || true

if git show-ref --verify --quiet refs/remotes/origin/gh-pages; then
  git worktree add "$PAGES_DIR" origin/gh-pages
else
  git worktree add -B gh-pages "$PAGES_DIR" HEAD
fi

find "$PAGES_DIR" -mindepth 1 -maxdepth 1 ! -name ".git" ! -name "previews" -exec rm -rf {} +
cp -a "$BUILD_DIR"/. "$PAGES_DIR"/
touch "$PAGES_DIR/.nojekyll"

if [[ -n "$(git -C "$PAGES_DIR" status --porcelain)" ]]; then
  git -C "$PAGES_DIR" add -A
  git -C "$PAGES_DIR" commit -m "Deploy live site from main"
  git -C "$PAGES_DIR" push origin HEAD:gh-pages
else
  echo "No live site changes to publish."
fi
