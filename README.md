# 🕵️ Inspector Brad

A Claude-powered PR reviewer that runs on your **Claude Max subscription**.
Triggered by commenting `@inspector-brad` (or `/inspector-brad`) on any PR
— never runs automatically, so it doesn't burn through your quota on every
push.

The bot lives in **one repo** (this one). Every other repo of yours
"installs" it with a small workflow file that points at `@v1`.

---

## How it works

```
You comment "@inspector-brad" on a PR
      ↓
GitHub Actions in that repo fires (write-access commenters only)
      ↓
The workflow calls YOUR_USERNAME/inspector-brad@v1
      ↓
Claude (using your Max subscription) investigates the diff and the code
around it, posts inline findings, and returns a structured verdict
      ↓
The action posts the summary, swaps 👀 for 👍/👎, and sets the
"Inspector Brad" commit status
```

Claude only does the judgement work: reading code and filing findings.
Routine steps like the summary comment, reactions, commit status and
clearing old summaries run as plain shell after Claude finishes. That makes
them reliable, keeps them from using model turns, and means Claude needs no
write access to the GitHub API beyond posting inline comments.

---

## Can I install once and have it work in ALL my repos?

Honest answer: **not without a hosted GitHub App.** GitHub Actions is
fundamentally per-repo — each repo needs a workflow file in
`.github/workflows/`. That's how Cursor Bugbot avoids this: it's a
GitHub App on hosted infrastructure, not an Action.

**What this repo gives you instead:**

- ONE place to maintain the bot's logic (prompts, model choice, tools).
- A 5-second-per-repo install script (`install.sh`) that pushes the
  workflow file into many repos at once via the GitHub API.
- After that, you rarely touch consumer repos. Update the bot here, move
  the `v1` tag, and every repo picks it up on the next review. When the
  consumer workflow itself changes, `./install.sh --update` rolls it out.

---

## Setup

### 1. Generate your OAuth token

On your Mac, with Claude Code installed and logged in to Max:

```bash
claude setup-token
```

Copy the `sk-ant-oat01-...` token it prints.

### 2. Push this repo

```bash
cd inspector-brad
git init
git add . && git commit -m "initial"
git remote add origin git@github.com:YOUR_USERNAME/inspector-brad.git
git push -u origin main
git tag v1 && git push origin v1
```

### 3. Make it accessible

- **Public repo** → nothing to do.
- **Private repo, personal account** → Settings → Actions → General →
  "Accessible from repositories owned by the user account".
- **Private repo, org** → org Settings → Actions → "Accessible from
  repositories in the organization".

### 4. Add the secret

Set `CLAUDE_CODE_OAUTH_TOKEN` once at the org level (Org Settings →
Secrets → Actions → New organization secret) — every repo inherits it.
For personal accounts, set it per repo, e.g.:

```bash
for repo in $(gh repo list YOUR_USERNAME --limit 100 \
  --json nameWithOwner -q '.[].nameWithOwner'); do
  gh secret set CLAUDE_CODE_OAUTH_TOKEN \
    --body "sk-ant-oat01-PASTE_YOUR_TOKEN" --repo "$repo"
done
```

### 5. Install in your repos

**Single repo (manual):** copy `examples/consumer-workflow.yml` to
`.github/workflows/claude-review.yml`, swap `YOUR_GH_USERNAME` for yours,
commit, push.

**Many repos at once:** edit `install.sh`, set `BOT_OWNER` to your handle,
then:

```bash
# Install on specific repos
./install.sh brad/repo-a brad/repo-b brad/repo-c

# Install on every repo you own
./install.sh $(gh repo list YOUR_USERNAME --limit 100 \
  --json nameWithOwner -q '.[].nameWithOwner')

# Install on an org
./install.sh $(gh repo list YOUR_ORG --limit 100 \
  --json nameWithOwner -q '.[].nameWithOwner')
```

The script skips repos that already have a `claude-review.yml`, so it's
safe to re-run. Pass `--update` to overwrite existing copies that differ
from the current template:

```bash
./install.sh --update $(gh repo list YOUR_ORG --limit 100 \
  --json nameWithOwner -q '.[].nameWithOwner')
```

`install.sh` uses `examples/consumer-workflow.yml` as its template, so
that file is the one place to change the consumer workflow.

---

## Using it

Open a PR. When you want a review, comment:

```
@inspector-brad
```

or with extra direction, which is passed to Brad as a focus area:

```
@inspector-brad focus on the auth changes
```

The action picks it up, runs the review, posts inline comments + summary.
No reviews fire on push, on open, on synchronize — only when you ask, and
only for commenters with write access (owners, members, collaborators).

---

## Per-repo tuning

### `.inspector-brad.md`

Commit a `.inspector-brad.md` at the repo root with guidance Brad should
apply to every review of that repo. It's read from the PR's **base**
branch, not the PR itself, so a PR can't change the rules it's reviewed
under. Edits to the file take effect once they're merged.

When a human 👎s a finding or replies "false positive", Brad proposes a
one-line lesson in the next summary. Copy the ones you agree with into
`.inspector-brad.md`.

### Workflow inputs

```yaml
      - uses: YOUR_GH_USERNAME/inspector-brad@v1
        with:
          oauth-token:  ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
          model:        claude-opus-5-5      # or claude-sonnet-5-5 to save quota
          effort:       high                 # low | medium | high | xhigh | max
          extra-instructions: |
            This is a Django app. Be strict about N+1 queries and missing
            select_related / prefetch_related in views/ and serializers/.
```

`effort` is passed straight to Claude Code's `--effort` flag and is the main
control over how deep Brad digs and how much quota a review uses. The default
is `high`. On Opus 5.5, `medium` is a strong cheaper setting. Use `xhigh` or
`max` for critical PRs where you'd rather spend quota than miss something.

---

## Tuning the bot itself

- **Review behaviour** → edit `prompts/inspector_brad_system.md`.
- **Summary format, reactions, commit status** → the "Publish verdict"
  step in `action.yml`.
- **What Claude returns** → `schemas/review-result.json`.
- **Defaults** (model, effort) → `action.yml` inputs.
- **Allowed tools** → `--allowedTools` in `action.yml`.
- **Trigger phrase / who can trigger** → `examples/consumer-workflow.yml`,
  then `./install.sh --update` to roll it out.

After any bot change: `git tag -f v1 && git push -f origin v1`.

---

## Things to watch

- **OAuth token expiry.** Long-lived but not eternal. If reviews start
  failing with auth errors, re-run `claude setup-token` and update the
  secret.
- **Quota.** Reviews draw from your Max usage. If heavy review days eat
  into your interactive sessions, drop `effort` to `medium` or switch to
  `claude-sonnet-5-5`.
- **Commit status.** Needs `statuses: write` in the consumer workflow
  (included in the current template). Without it, the review still works;
  the status is just skipped.

---

## Fallback: API key mode

For any repo where you'd rather bill API tokens (e.g. a shared team
automation), pass `anthropic-api-key:` instead of `oauth-token:`. The
action handles both; if both are set, the OAuth token wins.
