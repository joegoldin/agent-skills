/**
 * agent-skills session-start context injection, for pi.
 *
 * pi has no hook system, so this is the extension form of
 * hooks/session-start.sh. That hook emits SessionStart additionalContext;
 * the pi equivalent is appending to event.systemPrompt in
 * before_agent_start, which pi chains across extensions.
 *
 * Difference from the hook, deliberate: Claude injects once as a transcript
 * message, pi re-appends every turn to a system prompt it rebuilds anyway.
 * The appended string is byte-stable, so caching is unaffected. The legacy
 * warning is the one part that must not repeat, so it is gated to the first
 * turn after each session start — matching the hook's once-per-session
 * delivery of "IN YOUR FIRST REPLY AFTER SEEING THIS MESSAGE".
 *
 * @USING_AGENT_SKILLS@ is replaced at Nix build time with the store path of
 * the rendered using-agent-skills SKILL.md, exactly as the shell hook does.
 */
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const SKILL_CONTENT_PATH = "@USING_AGENT_SKILLS@";
const LEGACY_SKILLS_DIR = join(homedir(), ".config", "superpowers", "skills");

const LEGACY_WARNING =
  "\n\n<important-reminder>IN YOUR FIRST REPLY AFTER SEEING THIS MESSAGE YOU MUST TELL THE USER:" +
  "⚠️ **WARNING:** Superpowers now uses Claude Code's skills system. Custom skills in " +
  "~/.config/superpowers/skills will not be read. Move custom skills to ~/.claude/skills instead. " +
  "To make this message go away, remove ~/.config/superpowers/skills</important-reminder>";

function readSkillContent(): string {
  try {
    return readFileSync(SKILL_CONTENT_PATH, "utf-8");
  } catch {
    return "Error reading using-agent-skills skill";
  }
}

function buildBlock(warning: string): string {
  return (
    "<EXTREMELY_IMPORTANT>\n" +
    "You have agent skills.\n\n" +
    "**Below is the full content of your 'agent-skills:using-agent-skills' skill - " +
    "your introduction to using skills. For all other skills, use the 'Skill' tool:**\n\n" +
    readSkillContent() +
    "\n\n" +
    warning +
    "\n</EXTREMELY_IMPORTANT>"
  );
}

export default function agentSkillsSessionStart(pi: ExtensionAPI) {
  // Read once per process; the store path is immutable.
  const steady = buildBlock("");
  let warnPending = false;

  const armWarning = () => {
    warnPending = existsSync(LEGACY_SKILLS_DIR);
  };

  pi.on("session_start", () => {
    armWarning();
  });

  // Post-compaction context refresh, the analogue of the hook's
  // "compact" SessionStart matcher.
  pi.on("session_compact", () => {
    armWarning();
  });

  pi.on("before_agent_start", (event) => {
    const block = warnPending ? buildBlock(LEGACY_WARNING) : steady;
    warnPending = false;
    return { systemPrompt: `${event.systemPrompt}\n\n${block}` };
  });
}
