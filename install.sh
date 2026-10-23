#!/usr/bin/env bash
# install.sh — push the Inspector Brad workflow file into many of your repos at once.
#
# Usage:
#   ./install.sh [--update] OWNER/repo1 OWNER/repo2 OWNER/repo3
#   ./install.sh $(gh repo list YOUR_USERNAME --limit 100 --json nameWithOwner -q '.[].nameWithOwner')
#
# Requires: gh CLI authenticated (`gh auth login`).

set -euo pipefail

UPDATE=false
if [ "${1:-}" = "--update" ]; then
  UPDATE=true
  shift
fi

if [ $# -eq 0 ]; then
  cat <<USAGE
Usage:
  $0 [--update] OWNER/repo [OWNER/repo ...]

  --update   Overwrite an existing workflow file if it differs from the
             current template (otherwise existing installs are skipped).

Examples:
  # Install on a single repo
  $0 brad/my-side-project

  # Install on every repo you own (be careful!)
  $0 \$(gh repo list YOUR_USERNAME --limit 100 --json nameWithOwner -q '.[].nameWithOwner')

  # Install on repos in an org
  $0 \$(gh repo list YOUR_ORG --limit 100 --json nameWithOwner -q '.[].nameWithOwner')

  # Roll out workflow changes to repos that already have Brad
  $0 --update \$(gh repo list YOUR_ORG --limit 100 --json nameWithOwner -q '.[].nameWithOwner')

Before running, edit the BOT_OWNER variable at the top of this script
to point at YOUR inspector-brad repo (e.g. "brad").
USAGE
  exit 1
fi

# ---- EDIT THIS ----
BOT_OWNER="BradleyEvans96"      # e.g. "brad"
BOT_REPO="inspector-brad"       # the action repo name
BOT_VERSION="v1"                # tag to pin to
# -------------------

WORKFLOW_PATH=".github/workflows/claude-review.yml"
TEMPLATE="$(cd "$(dirname "$0")" && pwd)/examples/consumer-workflow.yml"
TMP_FILE=$(mktemp)
trap 'rm -f "$TMP_FILE"' EXIT

# The example workflow is the single source of truth. Drop its leading
# instructions comment block and point it at this bot's coordinates.
awk 'body { print; next } /^#/ || /^$/ { next } { body = 1; print }' "$TEMPLATE" \
  | sed -e "s|YOUR_GH_USERNAME/inspector-brad@v1|${BOT_OWNER}/${BOT_REPO}@${BOT_VERSION}|" \
  > "$TMP_FILE"
CONTENT=$(base64 < "$TMP_FILE" | tr -d '\n')

for repo in "$@"; do
  echo "→ Installing in $repo..."

  # Test the exit code, not the output: on a 404 gh still prints the error
  # JSON to stdout, which would look like an existing file.
  if ! SHA=$(gh api "repos/$repo/contents/$WORKFLOW_PATH" --jq .sha 2>/dev/null); then
    SHA=""
  fi
  if [ -n "$SHA" ]; then
    if [ "$UPDATE" != true ]; then
      echo "  ⚠️  $WORKFLOW_PATH already exists — skipping. Re-run with --update to overwrite."
      continue
    fi
    if gh api "repos/$repo/contents/$WORKFLOW_PATH" -H "Accept: application/vnd.github.raw" \
        | cmp -s - "$TMP_FILE"; then
      echo "  ✓ Already up to date"
      continue
    fi
    # Push via the contents API (single-file commit, no clone needed)
    gh api -X PUT "repos/$repo/contents/$WORKFLOW_PATH" \
      -f message="Update Inspector Brad workflow" \
      -f content="$CONTENT" \
      -f sha="$SHA" >/dev/null
    echo "  ✅ Updated"
  else
    gh api -X PUT "repos/$repo/contents/$WORKFLOW_PATH" \
      -f message="Install Inspector Brad" \
      -f content="$CONTENT" >/dev/null
    echo "  ✅ Installed"
  fi
done

cat <<DONE

All done. Make sure each repo has CLAUDE_CODE_OAUTH_TOKEN as a secret —
if you set it at the org level, every repo inherits it for free.

⚠️  GitHub Free plan: org-level Actions secrets are only readable from
   PUBLIC repos. For private repos under a Free org, set the secret at
   the repo level instead:
     gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo OWNER/REPO

Per-repo tuning: commit a .inspector-brad.md file at the repo root (on the
branch your PRs target) with guidance Brad should apply to every review of that
repo. e.g.:

  # .inspector-brad.md
  This is a Django app. Be strict about N+1 queries and missing
  select_related on querysets in views.

  Tests use Pytest. The 'noqa: B008' pattern in tests is intentional
  (DI fixtures) — don't flag it.

To trigger a review, comment "@inspector-brad" or "/inspector-brad" on any PR.
DONE
