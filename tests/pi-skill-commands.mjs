import assert from "node:assert/strict";
import { readFileSync, mkdtempSync, symlinkSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [modules, plugin] = process.argv.slice(2);
const load = name => import(pathToFileURL(`${modules}/@earendil-works/pi-coding-agent/dist/${name}.js`).href);
const { loadSkills } = await load("core/skills");
const { AgentSession } = await load("core/agent-session");
const { InteractiveMode } = await load("modes/interactive/interactive-mode");
const manifest = JSON.parse(readFileSync(join(plugin, "package.json"), "utf8"));
assert.deepEqual(manifest.pi.prompts ?? [], [], "skills must not also be registered as prompt templates");
const dir = mkdtempSync(join(tmpdir(), "pi-skill-registration-"));
try {
  symlinkSync(join(plugin, "skills"), join(dir, "skills"), "dir");
  const loaded = loadSkills({ cwd: dir, agentDir: dir, skillPaths: [join(plugin, "skills")], includeDefaults: true });
  assert.equal(loaded.diagnostics.length, 0, "global and package paths must resolve to the same skills without collisions");
  assert(loaded.skills.length > 0);
  const loader = { getSkills: () => loaded };
  let core;
  const runner = { getRegisteredCommands: () => [], bindCore: value => { core = value; } };
  const session = { _resourceLoader: loader, resourceLoader: loader, extensionRunner: runner, promptTemplates: [] };
  AgentSession.prototype._bindExtensionCore.call(session, runner);
  const commands = core.getCommands();
  assert.equal(commands.length, loaded.skills.length);
  assert.equal(new Set(commands.map(command => command.name)).size, commands.length);
  assert(commands.every(command => command.name.startsWith("skill:")), "use Pi's existing namespaced registration only");
  for (const name of ["dotfiles-update", "nix-dotfiles", "format-nix"]) {
    assert.equal(commands.filter(command => command.name === `skill:${name}`).length, 1);
    assert(!commands.some(command => command.name === name));
  }
  const host = { session, settingsManager: { getEnableSkillCommands: () => true }, sessionManager: { getCwd: () => dir }, skillCommands: new Map(), prefixAutocompleteDescription: value => value };
  const provider = InteractiveMode.prototype.createBaseAutocompleteProvider.call(host);
  const names = (await provider.getSuggestions(["/dotfiles"], 0, 9, { signal: new AbortController().signal })).items.map(item => item.value);
  assert(names.includes("skill:dotfiles-update"));
  assert(names.includes("skill:nix-dotfiles"));
  assert(!names.includes("dotfiles-update"));
  assert(!names.includes("nix-dotfiles"));
  assert.equal(names.length, new Set(names).size);
  console.log(`${commands.length} skills registered once through native /skill:NAME commands; no short aliases`);
} finally { rmSync(dir, { recursive: true, force: true }); }
