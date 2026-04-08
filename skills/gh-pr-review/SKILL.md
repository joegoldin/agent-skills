
# gh-pr-review

GitHub CLI extension for inline PR review comments with LLM-friendly JSON output.

## Running ghreview

`ghreview` is a fish script with `#!/usr/bin/env fish` and lives on `$PATH`. **Run it directly from any shell** — bash, zsh, the Bash tool, whatever:

```sh
ghreview
ghreview --pretty
ghreview comments reply --thread-id PRRT_xxx --body "Fixed in abc123"
```

Do **not** wrap it in `fish -c '...'`. That used to be necessary; it isn't anymore.

The wrapper auto-detects repo (`-R`) and PR (`--pr`) from the current branch and forwards everything else to `gh pr-review`. Unknown flags pass through, so subcommand-specific flags like `--thread-id`, `--body`, `--unresolved`, `--not_outdated`, `--reviewer`, `--states` all just work.

### Wrapper-only flags

| Flag | Purpose |
|------|---------|
| `--no-code` | Skip injecting source code context into comments |
| `--pretty` | Render reviews/threads as readable markdown |
| `--raw` | Output raw JSON (skip jq pretty-printing) |

Code context is included by default — every comment gets a `code_context` field with ±3 lines around the referenced line.

## Subcommands (forwarded to `gh pr-review`)

Default subcommand is `review view`, so bare `ghreview` shows all reviews on the current PR.

### View reviews

```sh
ghreview                                          # all reviews, JSON
ghreview --pretty                                 # all reviews, markdown
ghreview review view --unresolved --not_outdated  # actionable only
ghreview review view --reviewer octocat
ghreview review view --states CHANGES_REQUESTED,COMMENTED
ghreview review view --tail 1                     # last reply per thread
```

### List threads

```sh
ghreview threads list
ghreview threads list --unresolved
ghreview threads list --unresolved --mine
```

### Reply / resolve / unresolve

```sh
ghreview comments reply --thread-id PRRT_xxx --body "Fixed in abc123"
ghreview threads resolve   --thread-id PRRT_xxx
ghreview threads unresolve --thread-id PRRT_xxx
```

### Create and submit a review

```sh
ghreview review --start
ghreview review --add-comment --review-id PRR_xxx --path src/file.go --line 42 --body "nit: use helper"
ghreview review --submit --review-id PRR_xxx --event REQUEST_CHANGES --body "See inline comments"
```

Events: `APPROVE`, `REQUEST_CHANGES`, `COMMENT`.

## Output format

JSON by default. ID prefixes: `PRR_` (reviews), `PRRT_` (threads), `PRRC_` (comments). Each comment includes `thread_id`, `path`, `line`, `body`, `is_resolved`, `is_outdated`, `code_context`, and any `thread_comments` (replies).

`--pretty` renders the same data as markdown with fenced code blocks for `code_context` and blockquoted thread replies.

## Full flow: addressing review feedback

This is the canonical loop. Do all of it — replies and resolves are not optional.

### 1. Get the actionable list

```sh
ghreview --pretty review view --unresolved --not_outdated
```

Read the rendered feedback. For batch processing, grab JSON and extract `thread_id` per comment:

```sh
ghreview --raw review view --unresolved --not_outdated > /tmp/pr.json
python3 -c "
import json
d = json.load(open('/tmp/pr.json'))
for r in d.get('reviews', []):
    for c in r.get('comments', []):
        if not c.get('is_resolved') and not c.get('is_outdated'):
            print(c['thread_id'], c['path'] + ':' + str(c.get('line')))
            print('  ', c['body'][:120])
"
```

### 2. Make the code changes, run tests, commit, push

Standard dev loop. Reference the resulting commit SHA in your replies so reviewers can see what changed.

### 3. Reply to every addressed thread

One reply per thread, specific about what changed. Cite the commit and the actual fix — never just "done" or "fixed".

```sh
ghreview comments reply --thread-id PRRT_xxx \
  --body "Fixed in 1907889 — _compute_missing_stubs now skips canonical kinds already present anywhere in the plan, so a plan starting with SUBMIT_MOBILE no longer gets a duplicate."
```

### 4. Resolve threads you've fully addressed

```sh
ghreview threads resolve --thread-id PRRT_xxx
```

**Resolve when:**
- You made the requested code change.
- The comment was a question and your reply answers it definitively.

**Do NOT resolve when:**
- You disagree or chose not to change — let the reviewer decide.
- The thread needs further discussion or sign-off.

### 5. Update the PR description

```sh
gh pr edit --body "$(cat <<'EOF'
...updated description with a "Changes from review" section...
EOF
)"
```

### End-to-end example (single thread)

```sh
# 1. See what's open
ghreview --pretty review view --unresolved --not_outdated

# 2. (edit code, run tests)
git add -u && git commit -m "fix: address review feedback" && git push

# 3. Reply
ghreview comments reply --thread-id PRRT_kwDODXqFN855XW1G \
  --body "Fixed in $(git rev-parse --short HEAD) — dropped the misleading docstring phrase."

# 4. Resolve
ghreview threads resolve --thread-id PRRT_kwDODXqFN855XW1G

# 5. Refresh PR description
gh pr edit --body "$(cat <<'EOF'
## Summary
...
## Changes from review
- Dropped misleading docstring phrase (thread PRRT_...G)
EOF
)"
```
