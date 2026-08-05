{
  name = "gh-stack";
  description = "Use when working with GitHub stacked pull requests — a chain of dependent PRs where each builds on the branch below it. Triggers on `gh stack`, stacked PRs, PR stacks, branch layers, dependent or chained PRs, splitting large work into reviewable layers, and on reading or driving stacks through the REST /stacks endpoints, the async merge-async API, the GraphQL PullRequestStack fields, or the `stacked` pull_request webhook action.";

  allowed-tools = [
    # Read-only and local-only operations. Commands that write to GitHub
    # (push, submit, link, merge, unstack) intentionally prompt.
    "Bash(gh stack view:*)"
    "Bash(gh stack up:*)"
    "Bash(gh stack down:*)"
    "Bash(gh stack top:*)"
    "Bash(gh stack bottom:*)"
    "Bash(gh stack trunk:*)"
    "Bash(gh stack checkout:*)"
    "Bash(gh stack init:*)"
    "Bash(gh stack add:*)"
    "Bash(gh stack rebase:*)"
    "Bash(gh stack sync:*)"
  ];
}
