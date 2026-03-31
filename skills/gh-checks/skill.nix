{ claudeLib, ... }:
{
  name = "gh-checks";
  description = "Use when reading CI check statuses, viewing test/lint failure logs, or diagnosing why PR checks are failing";

  commands = [
    (claudeLib.mkCommand
      {
        name = "gh-checks";
        description = "View CI check statuses and failure logs for a PR";
        allowed-tools = [
          "Bash"
          "Read"
          "Glob"
          "Grep"
          "Skill"
        ];
      }
      ''
        Invoke the gh-checks skill, then fetch and analyze CI check statuses and failure logs for the specified PR (or current branch).

        Steps:
        1. Use the Skill tool to load the gh-checks skill
        2. Identify the PR — use $ARGUMENTS if given, otherwise detect from current branch
        3. Fetch check statuses and show a summary table
        4. For any failing checks, fetch the failure logs
        5. Categorize failures (test, lint, build, security, etc.)
        6. Propose fixes or next steps

        $ARGUMENTS
      ''
    )
  ];
}
