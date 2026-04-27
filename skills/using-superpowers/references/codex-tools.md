# Codex Tool Mapping

Skills use Claude Code tool names. When you encounter these in a skill, use your platform equivalent:

| Skill references | Codex equivalent |
|-----------------|------------------|
| `Task` tool (dispatch subagent) | `spawn_agent` (then `wait`, then `close_agent`) |
| Multiple `Task` calls (parallel) | Multiple `spawn_agent` calls |
| `TodoWrite` (task tracking) | `update_plan` |
| `Skill` tool (invoke a skill) | Skills load natively — just follow the instructions |
| `Read`, `Write`, `Edit` (files) | Use your native file tools |
| `Bash` (run commands) | Use your native shell tools |

## Subagents

`spawn_agent` creates generic agents (`default`, `explorer`, `worker`). When a
skill says to dispatch a named agent type (e.g. `superpowers:code-reviewer`),
read the agent's prompt file, fill any template placeholders, and pass the
filled content as the `message` to a `worker` agent.
