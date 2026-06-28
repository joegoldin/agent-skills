{
  name = "sem";
  description = "Use when reviewing or understanding code changes at the entity level — functions, classes, methods — instead of line-by-line. Covers entity-aware diffs (working tree, staged, commit ranges), impact/blast-radius analysis ('what breaks if I change X', which tests to run), entity blame ('who last touched this function'), tracking how a single entity evolved through history, listing entities in a file/dir, and generating token-budgeted dependency-aware context for an LLM. Trigger when the user mentions `sem`, asks what entities changed, what depends on a symbol, who changed a function, or wants compact context for one symbol before editing it.";

  # sem includes mutating commands (e.g. `setup`/`unsetup` that install git config/hooks).
  # Only pre-approve the read-only subcommands used for review/context.
  allowed-tools = [
    "Bash(sem diff:*)"
    "Bash(sem impact:*)"
    "Bash(sem context:*)"
    "Bash(sem blame:*)"
    "Bash(sem log:*)"
    "Bash(sem entities:*)"
  ];
}
