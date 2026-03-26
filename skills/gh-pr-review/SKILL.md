
# gh-pr-review

GitHub CLI extension for inline PR review comments with LLM-friendly JSON output.

## IMPORTANT: Running Commands

`ghreview` is a fish shell function. **Always run it via fish:**

```sh
fish -c 'ghreview'
fish -c 'ghreview --pretty'
```

Never run `ghreview` directly in bash — it will fail with `command not found`.

## Shell Wrapper

`ghreview` auto-detects repo and PR from the current directory/branch. All args pass through to `gh pr-review`. Defaults to `review view` with code context.

### Wrapper Flags

| Flag | Default | Purpose |
|------|---------|---------|
| `--no-code` | off | Skip injecting source code context into comments |
| `--pretty` | off | Render as readable markdown instead of JSON |
| `--raw` | off | Output raw JSON (skip jq pretty-printing) |

Code context is injected by default — each comment includes a `code_context` field with the referenced source lines (3 lines above and below). Use `--no-code` to disable.

### Quick Reference

```sh
# View all reviews for current PR (default, includes code context)
fish -c 'ghreview'

# Readable markdown output with code
fish -c 'ghreview --pretty'

# Raw compact JSON (for piping)
fish -c 'ghreview --raw'

# Skip code injection (faster, less output)
fish -c 'ghreview --no-code'

# Override auto-detection
fish -c 'ghreview -R owner/repo --pr 42 review view'
```

## Core Commands

### View Reviews and Threads

```sh
fish -c 'ghreview'
fish -c 'ghreview review view --unresolved --not_outdated'
fish -c 'ghreview review view --reviewer octocat'
fish -c 'ghreview review view --states CHANGES_REQUESTED,COMMENTED'
fish -c 'ghreview review view --tail 1'
```

| Flag | Purpose |
|------|---------|
| `--reviewer <login>` | Filter by reviewer |
| `--states <list>` | APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED |
| `--unresolved` | Only unresolved threads |
| `--not_outdated` | Exclude outdated threads |
| `--tail <n>` | Keep last n replies per thread |
| `--include-comment-node-id` | Add GraphQL comment IDs |

### Reply to Threads

```sh
fish -c 'ghreview comments reply --thread-id PRRT_xxx --body "Addressed in latest commit"'
```

### List Threads

```sh
fish -c 'ghreview threads list --unresolved --mine'
```

### Resolve / Unresolve Threads

```sh
fish -c 'ghreview threads resolve --thread-id PRRT_xxx'
fish -c 'ghreview threads unresolve --thread-id PRRT_xxx'
```

### Create and Submit Reviews

```sh
# Start pending review
fish -c 'ghreview review --start'

# Add inline comment
fish -c 'ghreview review --add-comment --review-id PRR_xxx --path src/file.go --line 42 --body "nit: use helper"'

# Submit
fish -c 'ghreview review --submit --review-id PRR_xxx --event REQUEST_CHANGES --body "Please address the comments"'
```

Events: `APPROVE`, `REQUEST_CHANGES`, `COMMENT`

## Output Format

### JSON (default)

Structured JSON with code context. IDs use GraphQL format: `PRR_` (reviews), `PRRT_` (threads), `PRRC_` (comments).

```json
{
  "reviews": [
    {
      "id": "PRR_...",
      "state": "CHANGES_REQUESTED",
      "author_login": "reviewer",
      "comments": [
        {
          "thread_id": "PRRT_...",
          "path": "src/file.go",
          "line": 42,
          "author_login": "reviewer",
          "body": "Consider refactoring this",
          "is_resolved": false,
          "is_outdated": false,
          "code_context": "39: func handler() {\n40:   ...\n41:   // existing code\n42:   problematicCall()\n43:   ...\n44: }\n45: ",
          "thread_comments": [
            {
              "author_login": "author",
              "body": "Good point, will fix"
            }
          ]
        }
      ]
    }
  ]
}
```

### Markdown (`--pretty`)

Renders reviews as readable markdown with fenced code blocks for code context and threaded replies as blockquotes.

## Addressing Review Feedback

When you've made code changes to address review comments, you MUST complete the feedback loop:

### 1. Update PR Description

After addressing feedback, update the PR description to reflect the current state. Use `gh pr edit` to update:

```sh
gh pr edit --body "$(cat <<'EOF'
Updated description here...
EOF
)"
```

Include a "Changes from review" or similar section summarizing what was addressed.

### 2. Reply to Addressed Comments

For every comment you've addressed with a code change, reply to the thread explaining what you did:

```sh
fish -c 'ghreview comments reply --thread-id PRRT_xxx --body "Fixed — refactored to use the helper as suggested"'
```

Keep replies concise and specific. Reference the actual change made, not just "done" or "fixed."

### 3. Resolve Addressed Threads

After replying to a comment you've fully addressed, resolve the thread:

```sh
fish -c 'ghreview threads resolve --thread-id PRRT_xxx'
```

**When to resolve:**
- You made the requested code change → resolve
- The comment was a question and you replied with an answer → resolve
- You replied explaining why you disagree or won't change → do NOT resolve (let the reviewer decide)
- The comment requires discussion or reviewer sign-off → do NOT resolve

**Batch workflow for addressing feedback:**

```sh
# 1. Get all unresolved threads with IDs
fish -c 'ghreview threads list --unresolved'

# 2. For each addressed thread: reply then resolve
fish -c 'ghreview comments reply --thread-id PRRT_xxx --body "Addressed — changed X to Y"'
fish -c 'ghreview threads resolve --thread-id PRRT_xxx'

# 3. Update PR description
gh pr edit --body "$(cat <<'EOF'
...updated description...
EOF
)"
```

## Common Workflows

### Get actionable review feedback

```sh
fish -c 'ghreview --pretty review view --unresolved --not_outdated'
```

### Reply and resolve

```sh
# Get thread IDs
fish -c 'ghreview threads list --unresolved'

# Reply
fish -c 'ghreview comments reply --thread-id PRRT_xxx --body "Fixed in abc123"'

# Resolve
fish -c 'ghreview threads resolve --thread-id PRRT_xxx'
```

### Full review cycle

```sh
fish -c 'ghreview review --start'
fish -c 'ghreview review --add-comment --review-id PRR_xxx --path file.go --line 10 --body "Issue here"'
fish -c 'ghreview review --submit --review-id PRR_xxx --event REQUEST_CHANGES --body "See inline comments"'
```
