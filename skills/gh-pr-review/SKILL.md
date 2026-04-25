
# gh-pr-review

GitHub CLI extension for inline PR review comments with LLM-friendly JSON output.

## Setup

`gh pr-review` is a GitHub CLI extension. Run it with `gh pr-review <subcommand>` and pass `-R owner/repo` and `--pr <number>` to target a specific PR.

### Auto-detecting repo and PR

From within a repo checkout on a PR branch, auto-detect both:

```sh
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
PR=$(gh pr view --json number -q .number)
```

Then pass them explicitly:

```sh
gh pr-review review view -R "$REPO" --pr "$PR" --unresolved --not_outdated
```

If you are already in the repo directory on the correct branch, `-R` and `--pr` can often be omitted — the extension will detect them from git context.

### Getting code context

The extension outputs comment metadata (path, line number). To see surrounding code, read the file directly with the Read tool or `git show` rather than relying on a wrapper.

## Subcommands

Default subcommand is `review view`, so bare `gh pr-review` shows all reviews on the current PR.

### View reviews

```sh
gh pr-review review view                                          # all reviews, JSON
gh pr-review review view --unresolved --not_outdated              # actionable only
gh pr-review review view --reviewer octocat
gh pr-review review view --states CHANGES_REQUESTED,COMMENTED
gh pr-review review view --tail 1                                 # last reply per thread
```

### List threads

```sh
gh pr-review threads list
gh pr-review threads list --unresolved
gh pr-review threads list --unresolved --mine
```

### Reply / resolve / unresolve

```sh
gh pr-review comments reply --thread-id PRRT_xxx --body "Fixed in abc123"
gh pr-review threads resolve   --thread-id PRRT_xxx
gh pr-review threads unresolve --thread-id PRRT_xxx
```

### Create and submit a review

```sh
gh pr-review review --start
gh pr-review review --add-comment --review-id PRR_xxx --path src/file.go --line 42 --body "nit: use helper"
gh pr-review review --submit --review-id PRR_xxx --event REQUEST_CHANGES --body "See inline comments"
```

Events: `APPROVE`, `REQUEST_CHANGES`, `COMMENT`.

## Output format

JSON by default. ID prefixes: `PRR_` (reviews), `PRRT_` (threads), `PRRC_` (comments). Each comment includes `thread_id`, `path`, `line`, `body`, `is_resolved`, `is_outdated`, and any `thread_comments` (replies).

To render output as readable markdown, format it yourself from the JSON.

## Full flow: addressing review feedback

This is the canonical loop. Do all of it — replies and resolves are not optional.

### 1. Get the actionable list

```sh
gh pr-review review view --unresolved --not_outdated
```

Read the feedback. For batch processing, extract `thread_id` per comment:

```sh
gh pr-review review view --unresolved --not_outdated > /tmp/pr.json
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

For code context around a comment, use the Read tool on the file at the referenced line.

### 2. Make the code changes, run tests, commit, push

Standard dev loop. Reference the resulting commit SHA in your replies so reviewers can see what changed.

### 3. Reply to every addressed thread

One reply per thread, specific about what changed. Cite the commit and the actual fix — never just "done" or "fixed".

```sh
gh pr-review comments reply --thread-id PRRT_xxx \
  --body "Fixed in 1907889 — _compute_missing_stubs now skips canonical kinds already present anywhere in the plan, so a plan starting with SUBMIT_MOBILE no longer gets a duplicate."
```

### 4. Resolve threads you've fully addressed

```sh
gh pr-review threads resolve --thread-id PRRT_xxx
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
gh pr-review review view --unresolved --not_outdated

# 2. (edit code, run tests)
git add -u && git commit -m "fix: address review feedback" && git push

# 3. Reply
gh pr-review comments reply --thread-id PRRT_kwDODXqFN855XW1G \
  --body "Fixed in $(git rev-parse --short HEAD) — dropped the misleading docstring phrase."

# 4. Resolve
gh pr-review threads resolve --thread-id PRRT_kwDODXqFN855XW1G

# 5. Refresh PR description
gh pr edit --body "$(cat <<'EOF'
## Summary
...
## Changes from review
- Dropped misleading docstring phrase (thread PRRT_...G)
EOF
)"
```
