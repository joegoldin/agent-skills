import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const dir = mkdtempSync(join(tmpdir(), "temporal-pi-"));
const originalNow = Date.now;
try {
  process.env.TEMPORAL_STATE_DIR = dir;
  process.env.TEMPORAL_INTERVAL = "300";
  let now = Date.UTC(2026, 10, 24, 3, 55, 39);
  Date.now = () => now;
  const { default: temporal } = await import(pathToFileURL(process.argv[2]).href);
  const handlers = new Map();
  temporal({ on: (name, handler) => handlers.set(name, handler) });
  const ctx = { sessionManager: { getSessionId: () => "test-session" } };
  const emit = (name, event = {}) => handlers.get(name)(event, ctx);
  const systemPrompt = "Stable system instructions";
  const stamp = (messageType) => {
    const result = emit("before_agent_start", { messageType, systemPrompt });
    if (!result) return undefined;
    assert.deepEqual(Object.keys(result), ["message"], "a clock refresh must never replace the request prefix");
    assert.equal(result.message.customType, "temporal");
    assert.equal(result.message.display, false);
    return result.message.content;
  };

  emit("session_start");
  assert.match(stamp("user"), /utc=2026-11-24T03:55:39Z.*session=0s/);
  now += 299_000;
  assert.equal(stamp("user"), undefined, "the original time message is still in the transcript");
  now += 1_000;
  assert.match(stamp("custom"), /utc=2026-11-24T04:00:39Z.*session=5m00s/, "a custom-triggered run appends a timestamp too");
  assert.equal(stamp("user"), undefined);

  now += 1_000;
  emit("session_compact");
  assert.match(stamp("user"), /^\[⏱ post-compaction time check.*session=5m01s/);
  assert.equal(stamp("user"), undefined);
  console.log("Pi appends throttled time checks without replacing the system prompt");
} finally {
  Date.now = originalNow;
  rmSync(dir, { recursive: true, force: true });
}
