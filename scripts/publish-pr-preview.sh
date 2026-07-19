#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${1:-_site}"
PR_NUMBER="${2:-}"
PR_ACTION="${3:-}"
PAGES_DIR="_pages"

if [[ -z "$PR_NUMBER" || -z "$PR_ACTION" ]]; then
  echo "Usage: publish-pr-preview.sh <build_dir> <pr_number> <pr_action>" >&2
  exit 1
fi

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

git fetch origin gh-pages || true
BOOTSTRAPPED_BRANCH=false

if ! git show-ref --verify --quiet refs/remotes/origin/gh-pages; then
  if [[ "$PR_ACTION" == "closed" ]]; then
    echo "gh-pages does not exist; nothing to clean."
    exit 0
  fi
  BOOTSTRAPPED_BRANCH=true
  git worktree add -B gh-pages "$PAGES_DIR" HEAD
else
  git worktree add "$PAGES_DIR" origin/gh-pages
fi

if [[ "$BOOTSTRAPPED_BRANCH" == "true" ]]; then
  find "$PAGES_DIR" -mindepth 1 -maxdepth 1 ! -name ".git" ! -name "previews" -exec rm -rf {} +
fi

touch "$PAGES_DIR/.nojekyll"

PREVIEW_DIR="$PAGES_DIR/previews/pr-$PR_NUMBER"

if [[ "$PR_ACTION" != "closed" && ! -d "$BUILD_DIR" ]]; then
  echo "Build directory '$BUILD_DIR' does not exist." >&2
  exit 1
fi

for attempt in 1 2 3; do
  if [[ "$attempt" -gt 1 ]]; then
    git fetch origin gh-pages || true
    if git show-ref --verify --quiet refs/remotes/origin/gh-pages; then
      git -C "$PAGES_DIR" fetch origin gh-pages
      git -C "$PAGES_DIR" reset --hard origin/gh-pages
    fi
  fi

  touch "$PAGES_DIR/.nojekyll"

  if [[ "$PR_ACTION" == "closed" ]]; then
    rm -rf "$PREVIEW_DIR"
    COMMIT_MESSAGE="Remove preview for PR #$PR_NUMBER"
  else
    rm -rf "$PREVIEW_DIR"
    mkdir -p "$PREVIEW_DIR"
    cp -a "$BUILD_DIR"/. "$PREVIEW_DIR"/
    COMMIT_MESSAGE="Update preview for PR #$PR_NUMBER"
  fi

  if [[ -z "$(git -C "$PAGES_DIR" status --porcelain)" ]]; then
    echo "No preview changes to publish."
    exit 0
  fi

  git -C "$PAGES_DIR" add -A
  git -C "$PAGES_DIR" commit -m "$COMMIT_MESSAGE"

  if git -C "$PAGES_DIR" push origin HEAD:gh-pages; then
    exit 0
  fi

  if [[ "$attempt" -eq 3 ]]; then
    echo "Failed to push preview update after 3 attempts." >&2
    exit 1
  fi

  echo "Push failed due to concurrent update, retrying..."
done
