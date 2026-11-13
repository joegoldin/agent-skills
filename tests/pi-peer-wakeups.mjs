// Real broker -> registered Intercom extension -> native SDK -> local model.
// No user prompt seeds the peer: both model turns must start from incoming work.
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const [root, sdkRoot, bunExe, policy] = process.argv.slice(2);
assert.ok(root && sdkRoot && bunExe && policy, "expected runtime source, SDK root, Bun and profile policy");
const { createAgentSession, DefaultResourceLoader, SessionManager, SettingsManager } = await import(join(sdkRoot, "dist/index.js"));
const { createAssistantMessageEventStream } = await import(join(sdkRoot, "../pi-ai/dist/compat.js"));
const { default: registerIntercom } = await import(join(root, "src/intercom/index.ts"));
const { IntercomClient } = await import(join(root, "src/intercom/broker/client.ts"));
const { spawnBrokerIfNeeded } = await import(join(root, "src/intercom/broker/spawn.ts"));
const directory = mkdtempSync(join(tmpdir(), "pi-wake-"));
const previousDir = process.env.PI_CODING_AGENT_DIR;
const previousStableId = process.env.PI_INTERCOM_STABLE_ID;
process.env.PI_CODING_AGENT_DIR = directory;
delete process.env.PI_INTERCOM_STABLE_ID;
mkdirSync(join(directory, "intercom"));
writeFileSync(join(directory, "intercom/config.json"), JSON.stringify({
  brokerCommand: bunExe, brokerArgs: [], inboundTrigger: policy, claude: { enabled: false },
}));
let requests = 0, ended = 0;
const contexts = [];
const model = {
  id: "wake-fixture", name: "Fixture", api: "anthropic-messages", provider: "peer-wake-fixture",
  baseUrl: "http://127.0.0.1:1", reasoning: false, input: ["text"],
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 200000, maxTokens: 1000,
};
const settingsManager = SettingsManager.inMemory({ packages: [], extensions: [], retry: { enabled: false } });
const manager = SessionManager.create(directory, directory);
const loader = new DefaultResourceLoader({
  cwd: directory, agentDir: directory, settingsManager,
  noExtensions: true, noSkills: true, noPromptTemplates: true, noThemes: true, disabledBuiltinExtensions: ["mcp"],
  extensionFactories: [(api) => {
    registerIntercom(api);
    api.on("agent_end", () => { ended++; });
    api.registerProvider("peer-wake-fixture", {
      api: model.api, baseUrl: model.baseUrl, apiKey: "synthetic-local-fixture-key", models: [model],
      streamSimple: (_model, context) => {
        contexts.push(JSON.stringify(context.messages));
        const message = {
          role: "assistant", api: model.api, provider: model.provider, model: model.id, timestamp: Date.now(),
          content: [{ type: "text", text: `PEER_RUN_${++requests}` }], stopReason: "stop",
          usage: { input: 1, output: 1, cacheRead: 0, cacheWrite: 0, totalTokens: 2, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
        };
        const stream = createAssistantMessageEventStream();
        queueMicrotask(() => stream.push({ type: "done", reason: "stop", message }));
        return stream;
      },
    });
  }],
});
async function until(condition, label) {
  const deadline = Date.now() + 5000;
  while (!await condition()) {
    assert.ok(Date.now() < deadline, `timed out: ${label}`);
    await new Promise(resolve => setTimeout(resolve, 20));
  }
}
const sender = new IntercomClient();
let session;
try {
  await spawnBrokerIfNeeded(bunExe, []);
  await loader.reload();
  assert.deepEqual(loader.getExtensions().errors, []);
  ({ session } = await createAgentSession({ cwd: directory, agentDir: directory, model, thinkingLevel: "off", sessionManager: manager, settingsManager, resourceLoader: loader, tools: [] }));
  await session.bindExtensions({ mode: "tui", uiContext: { notify() {}, setProgramStatus() {}, confirm: async () => true } });
  await sender.connect({ name: "requester", cwd: directory, model: "fixture", pid: process.pid, startedAt: Date.now(), lastActivity: Date.now() }, "wake-requester");
  const peerId = manager.getSessionId();
  await until(async () => (await sender.listSessions()).some(row => row.id === peerId), "peer registers");
  assert.equal(requests, 0, "starting Pi alone must not fabricate work");
  assert.equal((await sender.send(peerId, { text: "FIRST_ASSIGNMENT: inspect this fixture only" })).delivered, true);
  await until(() => ended === 1, "initial unsolicited assignment starts the idle peer");
  assert.equal(requests, 1);
  assert.ok(contexts[0].includes("FIRST_ASSIGNMENT"));
  assert.equal(session.isStreaming, false);
  assert.equal((await sender.send(peerId, { text: "FOLLOWUP_ASSIGNMENT: inspect the next fixture only" })).delivered, true);
  await until(() => ended === 2, "later unsolicited message resumes the idle peer");
  assert.equal(requests, 2);
  assert.ok(contexts[1].includes("FOLLOWUP_ASSIGNMENT"));
  assert.equal(session.isStreaming, false);
  console.log("PASS: first assignment and later message each start exactly one real SDK model turn through the broker.");
} finally {
  if (session) {
    await session.abort();
    await session.extensionRunner.emit({ type: "session_shutdown", reason: "quit" });
    session.dispose();
  }
  await sender.disconnect();
  // Only this fixture's broker lives in its fresh private agent directory.
  try { process.kill(Number.parseInt(readFileSync(join(directory, "intercom/broker.pid"), "utf8").trim(), 10), "SIGTERM"); } catch (error) { if (error.code !== "ENOENT" && error.code !== "ESRCH") throw error; }
  if (previousDir === undefined) delete process.env.PI_CODING_AGENT_DIR; else process.env.PI_CODING_AGENT_DIR = previousDir;
  if (previousStableId === undefined) delete process.env.PI_INTERCOM_STABLE_ID; else process.env.PI_INTERCOM_STABLE_ID = previousStableId;
  rmSync(directory, { recursive: true, force: true });
}
