# agent-skills-temporal

Time-injection hook ported from
[asakin's gist](https://gist.github.com/asakin/e4225721bb8f16dd6bc34f4eec5499f9)
(v1). A v2 repo with extended features lives at
https://github.com/asakin/claude-context-hook — we vendor v1 because it's
single-file and dependency-free.

## What changed from upstream

1. State directory is configurable via `$TEMPORAL_STATE_DIR` (default
   `~/.claude/.temporal`). Each target plugin (Claude/Codex/Antigravity) sets
   this to its own CLI's home, preventing cross-contamination.
2. `SessionStart` now also fires on `source=startup`/`source=resume`/missing
   source, so non-Claude CLIs that don't pass `source` still get a timestamp
   at session open. Compact behavior is unchanged.
3. Defensive `OSError`/`JSONDecodeError` handling around state I/O — the hook
   silently no-ops on filesystem issues instead of failing the prompt.

## Attribution

Apache-style: credit + linkback. See ATTRIBUTION.md.
