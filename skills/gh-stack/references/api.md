# Stacks API reference

Covers the REST stacks endpoints, the `stack` object on pull requests, the async merge API, the read-only GraphQL fields, and webhook payloads.

Authoritative upstream docs:
- <https://docs.github.com/en/rest/pulls/stacks>
- <https://github.github.io/gh-stack/reference/merge-api/>

If stacked PRs are not enabled for a repository, the stacks endpoints return `404 Not Found`.

## Contents

- [The `stack` object on pull requests](#the-stack-object-on-pull-requests)
- [Stacks REST API](#stacks-rest-api)
- [The stack resource](#the-stack-resource)
- [Async merge API](#async-merge-api)
- [GraphQL](#graphql)
- [Webhooks](#webhooks)
- [GitHub Actions](#github-actions)

## The `stack` object on pull requests

Every REST endpoint that returns a pull request carries a `stack` object describing that PR's stack membership — including `GET /repos/{owner}/{repo}/pulls` and `GET /repos/{owner}/{repo}/pulls/{pull_number}`. It is `null` for standalone PRs, so no separate lookup is needed to answer "is this PR stacked?".

```sh
gh api /repos/OWNER/REPO/pulls/42 --jq '.stack'
```

```json
{
  "id": 123456,
  "number": 50,
  "size": 5,
  "position": 2,
  "base": { "ref": "main", "sha": "def456..." }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `stack.id` | `integer` | Global identifier for the stack. |
| `stack.number` | `integer` | Repository-scoped stack number, shown in the GitHub UI. Addresses the stack in these endpoints. |
| `stack.size` | `integer` | Total number of PRs in the stack. |
| `stack.position` | `integer` | 1-based position of this PR, where `1` is the bottom (closest to the stack's base). |
| `stack.base.ref` | `string` | The branch the **entire stack** ultimately targets. |
| `stack.base.sha` | `string` | HEAD SHA of the stack's base branch. |

The PR's own `base.ref` is the branch it directly targets (the PR below it). `stack.base.ref` is the whole stack's target. These differ for every PR except the bottom one.

## Stacks REST API

A stack is addressed by its **stack number** — the same value as `stack.number` above.

### List stacks

```
GET /repos/{owner}/{repo}/stacks
```

Ordered by stack number, newest first.

| Parameter | In | Type | Description |
|---|---|---|---|
| `pull_request` | query | `integer` | Filter to the stack containing this PR number. |
| `per_page` | query | `integer` | Results per page (max 100). |
| `page` | query | `integer` | Page of results. |

```sh
gh api repos/OWNER/REPO/stacks
gh api "repos/OWNER/REPO/stacks?pull_request=102"
```

Returns `200`. An array of [stack resources](#the-stack-resource).

### Get a stack

```
GET /repos/{owner}/{repo}/stacks/{stack_number}
```

```sh
gh api repos/OWNER/REPO/stacks/42
```

Returns `200` with a single stack, or `404`.

### Create a stack

```
POST /repos/{owner}/{repo}/stacks
```

Creates a stack from an ordered list of PR numbers, **bottom to top**. Each PR's base ref must match the previous PR's head ref, forming a valid chain.

| Body field | Type | Description |
|---|---|---|
| `pull_requests` | `array[integer]` | Ordered PR numbers, bottom to top. Minimum 2, maximum 100. |

```sh
echo '{"pull_requests": [101, 102, 103]}' | \
  gh api --method POST repos/OWNER/REPO/stacks --input -
```

Returns `201 Created`. `404` if not found or stacks are unavailable; `422` on validation failure (broken chain, fewer than 2 PRs).

### Add pull requests to a stack

```
POST /repos/{owner}/{repo}/stacks/{stack_number}/add
```

Appends onto the **top** of an existing stack. Send only the delta, ordered from the current top upward — do not re-list PRs already in the stack. The first new PR's base ref must match the current top PR's head ref.

| Body field | Type | Description |
|---|---|---|
| `pull_requests` | `array[integer]` | Ordered PR numbers to append. Minimum 1, maximum 100. |

```sh
echo '{"pull_requests": [104]}' | \
  gh api --method POST repos/OWNER/REPO/stacks/42/add --input -
```

Returns `200 OK` with the updated stack. `409` on conflict, `422` on validation failure.

### Unstack

```
POST /repos/{owner}/{repo}/stacks/{stack_number}/unstack
```

Removes the unmerged PRs from a stack. **No request body.** PRs that are merged, merging (auto-merge enabled), or queued for merge cannot be unstacked and are left in place.

- `200 OK` with the updated stack when PRs remain.
- `204 No Content` when none remain and the stack is dissolved.

```sh
gh api --method POST repos/OWNER/REPO/stacks/42/unstack
```

This removes the **grouping only** — it never deletes pull requests or branches.

## The stack resource

Returned by get, create, and add (singly), by list (as an array), and by unstack when PRs remain.

| Field | Type | Description |
|---|---|---|
| `id` | `integer` | Global identifier. |
| `number` | `integer` | Repository-scoped stack number. Used to address the stack. |
| `node_id` | `string` | Global node ID. |
| `url` | `string` | API URL of the stack. |
| `base.ref` | `string` | Branch the stack targets. |
| `open` | `boolean` | Whether any PR is still open. `false` when all are merged or closed. |
| `created_at` | `string` | ISO 8601 creation timestamp. |
| `pull_requests` | `array` | The PRs, ordered **bottom to top**. |

Each `pull_requests` entry is a minimal representation:

| Field | Type | Description |
|---|---|---|
| `number` | `integer` | PR number. |
| `state` | `string` | `open` or `closed`. |
| `draft` | `boolean` | Whether the PR is a draft. |
| `merged_at` | `string \| null` | Merge timestamp, or `null`. |
| `head.ref` | `string` | Head branch. |
| `head.sha` | `string` | HEAD SHA of that branch. |

```json
[
  {
    "id": 9876543,
    "number": 42,
    "node_id": "S_kwDOABCDEF4AAAAA",
    "url": "https://api.github.com/repos/octocat/hello-world/stacks/42",
    "base": { "ref": "main" },
    "open": true,
    "created_at": "2026-04-15T10:00:00Z",
    "pull_requests": [
      { "number": 101, "state": "open", "draft": false, "merged_at": null,
        "head": { "ref": "user-model", "sha": "aaa1111..." } },
      { "number": 102, "state": "open", "draft": false, "merged_at": null,
        "head": { "ref": "user-api", "sha": "bbb2222..." } }
    ]
  }
]
```

## Async merge API

**This is the required method for merging stacked PRs.** A stack cannot be merged with the legacy synchronous [merge endpoint](https://docs.github.com/rest/pulls/pulls#merge-a-pull-request) or the `mergePullRequest` GraphQL mutation. Merging a stacked PR merges every PR in the stack up to and including the one requested.

Because a stack merge can take minutes, it runs in the background: **submit**, then **poll**.

A stack merge request is **atomic** — either the whole group lands (or is queued), or none of it does.

### Submit a merge request

```
PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge-async
```

All body fields are optional.

| Body field | Type | Description |
|---|---|---|
| `merge_method` | `string` | `merge`, `squash`, or `rebase`. Defaults to a merge commit. Not supported with `merge_queue`. |
| `merge_action` | `string` | `default` (recommended), `direct_merge`, or `merge_queue`. `default` merges directly, or queues when the base branch requires a merge queue. Omitting the field equals `default`. |
| `commit_title` | `string` | Title for the automatic commit message. Not supported with `merge_queue`. |
| `commit_message` | `string` | Extra detail appended to the commit message. Not supported with `merge_queue`. |
| `sha` | `string` | SHA the PR head must match. The merge is rejected on mismatch. |

```sh
echo '{"merge_method": "squash", "merge_action": "default"}' | \
  gh api --method PUT repos/OWNER/REPO/pulls/102/merge-async --input -
```

| Status | When | Body `status` |
|---|---|---|
| `202 Accepted` | Accepted, running in the background. | `pending` |
| `200 OK` | The PR was already merged. | `merged` |
| `409 Conflict` | A merge request already exists. Returns that request's `uuid` — **its options may differ from the ones you requested**. | `pending` |
| `400 Bad Request` | Not ready to merge (closed, draft). | `failed` |
| `404 Not Found` | Async merge unavailable for the repo, or PR not found. | — |
| `422 Unprocessable Entity` | Body failed validation (bad `merge_method`/`merge_action`). | — |

Only basic PR state is checked at submit (open, not a draft). **Branch protection and repository rules are evaluated later, when the merge runs**, and surface as a `failed` result while polling.

Only a `pending` response carries a `uuid`. `merged`, `failed`, and `enqueued` are terminal at submit.

```json
{
  "status": "pending",
  "details": {
    "message": "Merge request enqueued.",
    "uuid": "630b9d5e-3f2a-4f7e-8b0c-2d5f9a8c1e42",
    "merge_method": "squash",
    "merge_action": "default",
    "expected_head_sha": "6dcb09b5b57875f334f61aebed695e2e4193db5e"
  }
}
```

### Poll for the result

```
GET /repos/{owner}/{repo}/pulls/{pull_number}/merge-async/{uuid}
```

A valid lookup always returns `200 OK`; read `status`. Poll roughly once a second until `status` is no longer `pending`. Results are retained for **24 hours** after their last update, after which the UUID returns `404`.

```sh
gh api repos/OWNER/REPO/pulls/102/merge-async/630b9d5e-3f2a-4f7e-8b0c-2d5f9a8c1e42
```

### Status values

| Status | Meaning |
|---|---|
| `pending` | Running in the background. Keep polling. |
| `merged` | Merged directly. `details.sha` is the resulting merge commit. |
| `enqueued` | Added to the base branch's merge queue. **Terminal for this request** — track the queue for the final outcome. |
| `failed` | Attempted but could not complete (conflict, unmet branch rule). `details.message` explains. Nothing was merged. |

### Details fields

| Field | Type | Present when | Description |
|---|---|---|---|
| `message` | `string` | always | Human-readable description of the current state. |
| `uuid` | `string` | `pending` | Identifier used to poll. |
| `merge_method` | `string` | `pending` | Method in use. |
| `merge_action` | `string` | `pending` | Requested action. |
| `expected_head_sha` | `string` | `pending` | SHA the PR head must match to proceed. |
| `sha` | `string` | `merged` | Resulting merge commit SHA. |

### Limitations

- **No bypassing merge requirements.** Admin privileges cannot override a stack's branch protection rules or rulesets; every PR must satisfy its requirements.
- **No auto-merge.** A stacked PR cannot be set to merge automatically once requirements are met.

## GraphQL

Stack fields on `PullRequest` are **read-only** — there are no stack mutations in GraphQL. Use the REST API to create or modify stacks.

| Field on `PullRequest` | Type | Description |
|---|---|---|
| `stack` | `PullRequestStack` | The stack this PR belongs to, or `null`. |
| `stackEntry` | `PullRequestStackEntry` | This PR's entry, including position, or `null`. |

**`PullRequestStack`** — `id: ID!`, `number: Int!`, `size: Int!`, `baseRefName: String!`, `entries: PullRequestStackEntryConnection!`

**`PullRequestStackEntry`** — `id: ID!`, `position: Int!` (1 = closest to base), `pullRequest: PullRequest`, `stack: PullRequestStack`

**`PullRequestStackEntryConnection`** — standard connection: `edges`, `nodes`, `pageInfo: PageInfo!`, `totalCount: Int!`

```graphql
{
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: 42) {
      number
      baseRefName
      stackEntry { position }
      stack {
        number
        size
        baseRefName
        entries(first: 5) {
          totalCount
          nodes {
            position
            pullRequest { number title state }
          }
        }
      }
    }
  }
}
```

As with REST, the PR's own `baseRefName` is the branch directly below it; `stack.baseRefName` is the stack's ultimate target. Check `totalCount` for the full size and page with `pageInfo` when a stack has more entries than requested.

## Webhooks

When a PR belongs to a stack, GitHub adds a `stack` property to the `pull_request` object in webhook payloads, using the [same fields](#the-stack-object-on-pull-requests) as REST. It appears on pull request lifecycle events that fire while the PR is part of a stack, and is `null` for standalone PRs.

**The `opened` event never includes a stack.** A PR is always created before it is added to one.

### The `stacked` action

| | |
|---|---|
| Event (`X-GitHub-Event`) | `pull_request` |
| Action | `stacked` |
| Fires when | A pull request is added to a stack |

This is the event to listen for when you need to know exactly when a PR joins a stack. Its payload surfaces the stack as a **top-level `stack` object** in addition to the one nested under `pull_request`. The two always match, so read either. The top-level object is unique to `stacked`; other actions (`opened`, `synchronize`, …) carry only the nested one.

```json
{
  "action": "stacked",
  "number": 42,
  "stack": {
    "id": 123456, "number": 50, "size": 5, "position": 2,
    "base": { "ref": "main", "sha": "def456..." }
  },
  "pull_request": {
    "number": 42,
    "title": "Add API routes",
    "base": { "ref": "feat/auth-layer", "sha": "abc123..." },
    "stack": {
      "id": 123456, "number": 50, "size": 5, "position": 2,
      "base": { "ref": "main", "sha": "def456..." }
    }
  }
}
```

## GitHub Actions

Actions evaluates workflow triggers against the **stack's base branch**, so a workflow configured for PRs targeting `main` runs for every PR in a stack targeting `main` — no workflow changes needed.

The stack is available in expressions as `github.event.pull_request.stack`. Because a workflow runs for every PR in the stack, use these fields to skip redundant jobs. Guard on `stack != null` so the logic does not affect standalone PRs.

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run for the lowest unmerged PR in the stack
        if: github.event.pull_request.stack != null && github.event.pull_request.stack.base.ref == github.event.pull_request.base.ref
        run: echo "Lowest unmerged PR in the stack"

      - name: Run for the top PR in the stack
        if: github.event.pull_request.stack != null && github.event.pull_request.stack.position == github.event.pull_request.stack.size
        run: echo "Top PR in the stack"
```

The lowest unmerged PR is the one whose own `base.ref` equals the stack's `base.ref`. The top PR is the one where `position == size`.
