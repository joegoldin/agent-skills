---
name: gh-checks
description: Use when reading CI check statuses, viewing test/lint failure logs, or diagnosing why PR checks are failing
argument-hint: "[pr-number]"
---

# gh-checks

Read and diagnose GitHub Actions CI check statuses and failure logs for pull requests.

## Workflow

1. Identify the PR — use `$ARGUMENTS` if given, otherwise detect from the current branch
2. Fetch check statuses and show a summary table
3. For any failing checks, fetch the failure logs
4. Categorize failures (test, lint, build, security, etc.)
5. Propose fixes or next steps

## Identifying the PR

Use one of these approaches (in priority order):

1. **Explicit PR number** — if the user provides one, use it directly
2. **Current branch** — `gh pr view --json number -q '.number'` to find the PR for the current branch
3. **Multiple PRs** — the user may ask about several PRs at once; handle them in a loop

## Fetching Check Statuses

### Quick status overview

```sh
gh pr checks <PR_NUMBER> --repo <OWNER/REPO>
```

This gives a table of all checks with their status/conclusion. Use `--json` for structured output:

```sh
gh pr checks <PR_NUMBER> --json name,status,conclusion,detailsUrl
```

### Detailed check run info via API

```sh
# Get HEAD SHA for a PR
sha=$(gh pr view <PR_NUMBER> --json headRefOid -q '.headRefOid')

# List all check runs with conclusions
gh api "repos/<OWNER>/<REPO>/commits/$sha/check-runs" \
  --jq '.check_runs[] | "\(.name): \(.conclusion // .status)"'
```

## Reading Failure Logs

### Step 1: Find the workflow run

```sh
sha=$(gh pr view <PR_NUMBER> --json headRefOid -q '.headRefOid')
gh api "repos/<OWNER>/<REPO>/actions/runs?head_sha=$sha" \
  --jq '.workflow_runs[] | "\(.id) \(.name) \(.status) \(.conclusion)"'
```

### Step 2: Get failed job logs

```sh
# Get the log for failed steps only (most useful)
gh run view <RUN_ID> --repo <OWNER>/<REPO> --log-failed
```

This outputs logs prefixed with `<job_name>\t<step_name>\t<timestamp> <message>`. Filter with grep to find relevant errors.

### Step 3: Parse common failure patterns

**Test failures:**
```sh
gh run view <RUN_ID> --repo <OWNER>/<REPO> --log-failed 2>&1 | grep -E "FAIL|ERROR|assert|Traceback|raise" | head -30
```

**Lint failures:**
```sh
gh run view <RUN_ID> --repo <OWNER>/<REPO> --log-failed 2>&1 | grep -E "\.py:\d+:|\.ts:\d+:|\.js:\d+:" | head -30
```

**Build failures:**
```sh
gh run view <RUN_ID> --repo <OWNER>/<REPO> --log-failed 2>&1 | grep -E "error|Error|BUILD FAILED" | head -30
```

### Step 4: Get annotations (summary errors)

```sh
sha=$(gh pr view <PR_NUMBER> --json headRefOid -q '.headRefOid')
run_id=$(gh api "repos/<OWNER>/<REPO>/commits/$sha/check-runs" \
  --jq '.check_runs[] | select(.name=="<CHECK_NAME>") | .id')
gh api "repos/<OWNER>/<REPO>/check-runs/$run_id/annotations" \
  --jq '.[] | "\(.path):\(.start_line) \(.annotation_level): \(.message)"'
```

## Handling Multiple PRs

When checking many PRs at once, be efficient:

1. **Batch the status check** — loop over PR numbers, collect statuses
2. **Only fetch logs for failures** — skip passing checks
3. **Look for common root causes** — if multiple PRs fail the same way, diagnose once
4. **Group by failure type** — present results organized by check name or failure category

```sh
for pr in <PR_NUMBERS>; do
  echo "=== PR #$pr ==="
  gh pr checks $pr --repo <OWNER>/<REPO> --json name,conclusion \
    --jq '.[] | select(.conclusion != "success" and .conclusion != "skipped") | "\(.name): \(.conclusion)"'
done
```

## Diagnosing Failures

When presenting results:

1. **Summary table** — show all checks and their pass/fail status
2. **Failure details** — for each failing check, show the relevant error lines from the log
3. **Root cause** — identify what's actually broken (not just the symptom)
4. **Fix suggestion** — propose specific code changes or actions to resolve the failure
5. **Scope** — note whether the failure is specific to the PR's changes or a pre-existing issue (e.g., flaky tests, infra problems)

## Re-running Checks

If a failure looks transient (network timeout, flaky test):

```sh
gh run rerun <RUN_ID> --repo <OWNER>/<REPO>
# Or rerun only failed jobs:
gh run rerun <RUN_ID> --repo <OWNER>/<REPO> --failed
```

Only suggest re-runs for clearly transient failures, not for deterministic code issues.
