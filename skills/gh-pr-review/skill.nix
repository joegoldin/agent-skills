{ claudeLib, ... }:
{
  name = "gh-pr-review";
  description = "Use when viewing, replying to, or managing inline GitHub PR review comments and threads from the terminal";

  commands = [
    (claudeLib.mkCommand
      {
        name = "pr-review";
        description = "Fetch and analyze inline PR review comments for the current branch";
        allowed-tools = [
          "Bash"
          "Read"
          "Glob"
          "Grep"
          "Skill"
        ];
      }
      ''
        Invoke the gh-pr-review skill, then fetch and analyze inline PR review comments for the current branch.

        IMPORTANT: ghreview is a fish function. Always run it via: fish -c 'ghreview ...'
        Include bot comments by default (Copilot, etc.) — do NOT pass --no-bots unless the user asks.

        Steps:
        1. Use the Skill tool to load the gh-pr-review skill
        2. Run `fish -c 'ghreview --raw'` to get the full review JSON (includes code context by default)
        3. Summarize each reviewer's feedback (including bots like Copilot)
        4. List all unresolved comments grouped by file, with the referenced code and the reviewer's concern
        5. Categorize feedback (bugs, security, performance, style, architecture, questions)
        6. Propose a prioritized plan to address the comments

        If there are thread replies, note which comments already have responses and which are unanswered.

        After addressing comments with code changes:
        7. Reply to each addressed comment thread explaining what was changed
        8. Resolve threads that were fully addressed (do NOT resolve threads where you disagree or need reviewer sign-off)
        9. Update the PR description to reflect changes made from review feedback

        $ARGUMENTS
      ''
    )
  ];
}
