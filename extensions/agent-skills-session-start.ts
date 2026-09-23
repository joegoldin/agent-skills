import { readFileSync } from "node:fs";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// The immutable store content stays identical across turns for prompt caching.
const guidance = readFileSync("@USING_AGENT_SKILLS@", "utf-8");

export default function agentSkillsSessionStart(pi: ExtensionAPI) {
  pi.on("before_agent_start", (event) => ({
    systemPrompt: `${event.systemPrompt}\n\n${guidance}`,
  }));
}
