import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const { default: todos } = await import(pathToFileURL(process.argv[2]).href);
const cwd = mkdtempSync(join(tmpdir(), "pi-todos-"));
const root = join(cwd, ".pi/todo");
const block = "block:01a21059-3f19-7c0c-a37e-881042bcb88a";
const session = "session:01a1ea8f-c8d0-7dcd-aacc-70b239b5d803";
const viewer = join(cwd, "viewer");
const calls = [];
const notices = [];
let command;
let reportedBlock = block;
let selected;
let choices;
let splitCode = 0;
todos({
  registerCommand(name, value) { assert.equal(name, "todos"); command = value; },
  async exec(program, args, options) {
    calls.push({ program, args, options });
    return args.includes("whoami")
      ? { code: 0, stdout: JSON.stringify({ block_id: reportedBlock, session_id: session }) }
      : { code: splitCode, stderr: "split error" };
  },
});
const run = () => command.handler("", { cwd, ui: {
  notify: (message, type) => notices.push([message, type]),
  select: (_, items) => { choices = items; return selected; },
} });
try {
  process.env.REX_BLOCK = block;
  process.env.PI_CHECKLIST_VIEWER = viewer;
  writeFileSync(viewer, "#!/bin/sh\n", { mode: 0o700 });
  await run();
  assert.match(notices.pop()[0], /No checklists/);
  assert.equal(calls.length, 0);

  for (const [name, time] of [["older checklist", 1], ["newer checklist", 2]]) {
    const dir = join(root, name);
    mkdirSync(dir, { recursive: true });
    const file = join(dir, "checklist.md");
    writeFileSync(file, "# Todo\n- [ ] Test\n");
    utimesSync(file, time, time);
  }
  symlinkSync(join(root, "older checklist"), join(root, "ignored"));
  await run();
  assert.deepEqual(choices, [".pi/todo/newer checklist/checklist.md", ".pi/todo/older checklist/checklist.md"]);
  assert.equal(calls.length, 0, "cancelling selection must not open a pane");

  selected = choices[1];
  await run();
  assert.equal(calls.length, 2);
  assert.deepEqual(calls[0], { program: "rex", args: ["--autostart=false", "--timeout", "5s", "whoami", "--json"], options: { cwd, timeout: 7000 } });
  assert.deepEqual(calls[1].args, ["--autostart=false", "--timeout", "5s", "split", "-s", session, "-b", block, "--split=right", "--ratio=40", "--focus=false", "-c", cwd, "--label", "Checklist", "--shell=none", "--", viewer, join(cwd, selected)]);
  assert.equal(notices.length, 0);

  splitCode = 1;
  await run();
  assert.deepEqual(notices.pop(), ["Could not open checklist: split error", "error"]);

  reportedBlock = "block:stale";
  calls.length = 0;
  await run();
  assert.equal(calls.length, 1);
  assert.match(notices.pop()[0], /Could not verify/);

  delete process.env.REX_BLOCK;
  calls.length = 0;
  await run();
  assert.equal(calls.length, 0);
  assert.match(notices.pop()[0], /Outside Rex/);

  process.env.REX_BLOCK = block;
  process.env.PI_CHECKLIST_VIEWER = join(cwd, "missing");
  await run();
  assert.equal(calls.length, 0);
  assert.match(notices.pop()[0], /viewer unavailable/);
} finally {
  rmSync(cwd, { force: true, recursive: true });
}
console.log("PASS: /todos discovers, selects and safely opens worktree checklists");
