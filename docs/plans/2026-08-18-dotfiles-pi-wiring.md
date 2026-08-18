# dotfiles pi wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn on pi as the fourth first-class agent in `/home/joe/dotfiles` — a `den.aspects.pi.homeManager` aspect matching the existing three AI modules, with auth for the three chosen paths, the shared statusline, the bubblewrap jail, and one declaration of auto-mode rules that both Claude Code and pi honour.

**Architecture:** `modules/ai/pi.nix` is a den aspect that imports `inputs.agent-skills.homeManagerModules.pi` (phase 4) and sets `programs.pi.coding-agent`, exactly as `modules/ai/claude.nix` imports the claude module and sets `programs.claude-nix`. Auth is layered to match pi's own resolution order: `/login` OAuth in `~/.pi/agent/auth.json` wins, agenix-backed environment variables come second, and a `models.json` whose `apiKey` values are `!op read` commands is the last-resort fallback. Auto-mode rules live in a separate `modules/ai/auto-mode.nix` aspect that sets `programs.agent-skills.autoMode` and never imports anything, mirroring how `modules/ai/mcp.nix` contributes `programs.agent-skills.mcpServers`.

**Tech Stack:** Nix (flake-parts + import-tree + den), home-manager, agenix, jail.nix (bubblewrap), 1Password CLI, nixfmt.

This is phase 6 of the design in `docs/plans/2026-08-18-pi-nix-agent-stack-design.md` (§13). It is the last phase: everything it configures is produced by phases 1–5.

## Global Constraints

- **No secret may enter the Nix store.** Every credential is read at runtime from a path outside the store. The only credential-adjacent strings that may be written into a store file are (a) *paths* under `/run/agenix/`, and (b) `op://` vault *references* — neither is a secret. Task 7 Step 4 is the mechanical gate.
- **`environment.<NAME>.file` must be given a Nix *string*, never a Nix path literal.** pi-nix types it as `either str nixPath`; a path literal is copied into the store, a string is not. Every `file` value in this plan is a double-quoted string starting with `/run/agenix/`.
- **The jail runs the wrapper, not just pi.** `finalPackage = jailBuilder "pi" wrapped permissions` wraps the whole `writeShellScriptBin "pi"`, so pi-nix's `envPrelude` (`export NAME="$(cat FILE)"`) executes *inside* bubblewrap. Any secret file referenced by `environment.<NAME>.file` must therefore be explicitly bound into the jail. jail.nix binds only the runtime closure's store paths — `/nix/store` as a whole is not mounted — so nothing outside the closure is visible unless a combinator says so.
- **`jail.enable` is Linux-only.** `options.nix` throws `"pi.coding-agent.jail is supported only on Linux"` when the flag is set on Darwin. `torrent` is aarch64-darwin and receives this aspect, so the flag must be gated on `pkgs.stdenv.hostPlatform.isLinux`.
- **The aspect ships to exactly three hosts:** `elphael` (x86_64-linux), `volcano-manor` (x86_64-linux), `torrent` (aarch64-darwin) — the members of `den.aspects.workstation-packages`. Every agenix secret this plan references must be deployed on all three, or the launch wrapper prints a `cat: No such file` on every start.
- **Do not set `programs.pi.coding-agent.settings`.** Upstream jq-merges it into `~/.pi/agent/settings.json` on every launch, so a declared `model` would clobber an interactive `/model` choice each run (design §7, "Known upstream behaviour, retained"). Leaving it `{ }` skips the prelude entirely. Extensions contribute their own settings through `passthru.settings` in phase 2.
- **Do not set `programs.pi.coding-agent.models` either.** Upstream's `modelsPrelude` installs the file only `if [ ! -f "$PI_CODING_AGENT_DIR/models.json" ]`, so a declared models.json goes stale the moment it changes. This plan writes it from a home-manager activation script instead, as a real 0600 file (a store symlink would be unreadable inside the jail).
- Nix formatting: `nix fmt` (nixfmt-rfc-style) before every commit. Comment voice: match the sibling files in `modules/ai/` — full sentences, explaining *why*, wrapped at ~76 columns.
- No `git commit` in `/home/joe/Development/agent-skills`; the parent session commits the plans. Commits *inside* `/home/joe/dotfiles` and `/home/joe/dotfiles-secrets` are part of this plan and are expected.

### Interfaces this plan consumes from earlier phases

| Produced by | Name | Type |
| --- | --- | --- |
| phase 1 | `agent-statusline.lib.<system>.statuslineOptions` | attrset of `mkOption`s |
| phase 1 | `agent-statusline.lib.<system>.renderConfig` | `cfg -> derivation` (config JSON) |
| phase 2 | `programs.pi.coding-agent.statusline` | submodule of `statuslineOptions` + `enable` |
| phase 2 | `programs.pi.coding-agent.systemPrompt` | `nullOr (either lines path)` |
| phase 2 | `programs.pi.coding-agent.autoMode` | submodule with `allow`/`soft_deny`/`hard_deny`/`environment`, each `listOf str` |
| phase 3 | `programs.pi.coding-agent.jail.permissions` default | `combinators -> [ Permission ]` |
| phase 4 | `agent-skills.homeManagerModules.pi` | home-manager module |
| phase 4 | `programs.agent-skills.autoMode` | submodule with the same four `listOf str` lists |

Upstream, already present and verified in `/home/joe/Development/pi-nix/coding-agent/options.nix`:
`programs.pi.coding-agent.{enable,package,environment,jail.enable,jail.permissions,models,settings,extraArgs,finalPackage,finalArgs}`.

---

### Task 1: The `pi` aspect skeleton and its host wiring

Create the aspect and put it on the three workstations, with nothing configured yet beyond `enable`. This proves the module import, the den plumbing, and the Darwin jail gate before any secret or permission work rides on them.

**Files:**
- Create: `/home/joe/dotfiles/modules/ai/pi.nix`
- Modify: `/home/joe/dotfiles/modules/home/packages/workstation.nix` (add `den.aspects.pi` to `includes`)
- Modify: `/home/joe/dotfiles/flake.nix` (no new inputs — see Step 1)

**Interfaces:**
- Consumes: `inputs.agent-skills.homeManagerModules.pi` (phase 4); `programs.pi.coding-agent.{enable,jail.enable}` (upstream)
- Produces:
  - `den.aspects.pi.homeManager` — a home-manager module function
  - `den.aspects.workstation-packages.includes` gains `den.aspects.pi`, so the aspect reaches `elphael`, `volcano-manor`, and `torrent` and no other host

- [ ] **Step 1: Confirm no new flake inputs are needed**

Run:
```bash
cd /home/joe/dotfiles && grep -n 'claude-nix\|codex-nix\|antigravity-cli-nix\|agent-statusline\|pi-nix' flake.nix
```

Expected: **no matches.** `dotfiles` consumes every agent repo transitively through the single `agent-skills` input — `modules/ai/claude.nix` imports `inputs.agent-skills.homeManagerModules.claude`, and `claude-nix` itself is not a dotfiles input. `pi-nix` and `agent-statusline` follow the same route, so **this plan adds zero flake inputs.** If this grep ever finds a match, the repo convention changed and this task must be re-derived.

Then confirm the module is actually re-exported by the pinned `agent-skills`:
```bash
cd /home/joe/dotfiles && nix eval --json '.#inputs.agent-skills.homeManagerModules' --apply builtins.attrNames
```

Expected: `["agent-skills","antigravity","claude","codex","pi"]`. If `"pi"` is missing, phase 4 has not landed in the pinned rev — run `nix flake update agent-skills` first, and if it is still missing, stop: this task's precondition is unmet.

- [ ] **Step 2: Write the failing verification**

Run:
```bash
cd /home/joe/dotfiles && nix eval --raw '.#nixosConfigurations.elphael.config.home-manager.users.joe.programs.pi.coding-agent.finalPackage.outPath'
```

Expected: FAIL with `error: attribute 'pi' missing`. That is the gate — it must fail before Step 3 and succeed after Step 4.

- [ ] **Step 3: Write `modules/ai/pi.nix`**

```nix
# pi (pi-nix) + the agent-skills library. The fourth first-class agent
# alongside Claude Code, Codex, and Antigravity.
{ inputs, ... }:
{
  den.aspects.pi.homeManager =
    {
      pkgs,
      lib,
      ...
    }:
    let
      # The same guard the sibling AI aspects use. pi's package comes from
      # pi-nix (re-exported through agent-skills) rather than the llm-agents
      # overlay, so this is not a hard dependency — it is this repo's marker
      # for "this host carries the AI toolchain", and keeping the condition
      # identical means all four agents switch on and off together.
      enabled = pkgs ? llm-agents;

      # jail.nix is bubblewrap, so Linux only; pi-nix throws outright rather
      # than degrading if the flag is set on Darwin, and torrent gets this
      # aspect.
      jailed = pkgs.stdenv.hostPlatform.isLinux;
    in
    {
      imports = [ inputs.agent-skills.homeManagerModules.pi ];

      programs.pi.coding-agent = lib.mkIf enabled {
        enable = true;

        jail.enable = jailed;
      };
    };
}
```

- [ ] **Step 4: Put the aspect on the three workstations**

In `modules/home/packages/workstation.nix`, replace:

```nix
  # day-sync's rendered config travels with the workstations (see
  # ../../ai/day-sync.nix).
  den.aspects.workstation-packages.includes = [ den.aspects.day-sync ];
```

with:

```nix
  # day-sync's rendered config travels with the workstations (see
  # ../../ai/day-sync.nix). pi rides here rather than on home-baseline
  # because it needs the agenix provider keys and (on linux) the bubblewrap
  # jail, and only the three workstations deploy both.
  den.aspects.workstation-packages.includes = [
    den.aspects.day-sync
    den.aspects.pi
  ];
```

- [ ] **Step 5: Re-run the verification**

```bash
cd /home/joe/dotfiles && nix fmt modules/ai/pi.nix modules/home/packages/workstation.nix
nix eval --raw '.#nixosConfigurations.elphael.config.home-manager.users.joe.programs.pi.coding-agent.finalPackage.outPath'
```

Expected: a `/nix/store/...-pi` (jailed wrapper) path. `nix fmt` must leave both files unchanged on a second run.

- [ ] **Step 6: Prove the Darwin gate**

```bash
cd /home/joe/dotfiles
nix eval --json '.#darwinConfigurations.torrent.config.home-manager.users.joe.programs.pi.coding-agent.jail.enable'
nix eval --raw '.#darwinConfigurations.torrent.config.home-manager.users.joe.programs.pi.coding-agent.finalPackage.outPath'
```

Expected: `false`, then a store path. If the second command throws `pi.coding-agent.jail is supported only on Linux`, `jailed` is not wired to `pkgs.stdenv.hostPlatform.isLinux`.

- [ ] **Step 7: Prove the aspect did not leak onto the servers**

```bash
cd /home/joe/dotfiles
for h in farum-azula rennala melina siofra erdtree; do
  printf '%s: ' "$h"
  nix eval --json ".#nixosConfigurations.$h.config.home-manager.users.joe.programs" \
    --apply 'p: p ? pi' 2>/dev/null || echo "no home-manager user"
done
```

Expected: `false` for every host listed (or "no home-manager user"). `farum-azula` includes `home-baseline` but not `workstation-packages`, so it must report `false` — that is the check that `pi` went on the right aspect.

- [ ] **Step 8: Commit**

```bash
cd /home/joe/dotfiles
git add modules/ai/pi.nix modules/home/packages/workstation.nix
git commit -m "feat(pi): add the pi coding agent as a den aspect

Fourth first-class agent alongside Claude Code, Codex, and Antigravity,
consuming pi-nix through agent-skills' re-exported home-manager module the
same way claude.nix does. Rides workstation-packages rather than
home-baseline: it needs the agenix provider keys and, on linux, the
bubblewrap jail, and only the three workstations have both. The jail flag is
gated on isLinux because pi-nix throws on darwin rather than degrading."
```

---

### Task 2: agenix secrets for the three provider keys

`environment.<NAME>.file` reads its path with `cat` at every launch, so a missing file is a visible error on every start. Deploy all three keys on all three workstations *before* anything references them.

**Files:**
- Create: `/home/joe/dotfiles-secrets/openrouter_api_key.age`
- Modify: `/home/joe/dotfiles-secrets/secrets.nix`
- Modify: `/home/joe/dotfiles/modules/hosts/elphael/default.nix`
- Modify: `/home/joe/dotfiles/modules/hosts/volcano-manor/default.nix`
- Modify: `/home/joe/dotfiles/modules/hosts/torrent/default.nix`
- Modify: `/home/joe/dotfiles/flake.lock` (via `nix flake update dotfiles-secrets`)

**Interfaces:**
- Consumes: `inputs.dotfiles-secrets` (existing flake input, `flake = false`)
- Produces: the runtime paths `/run/agenix/anthropic_api_key`, `/run/agenix/openai_api_key`, `/run/agenix/openrouter_api_key`, mode `0400`, owner `joe`, present on `elphael`, `volcano-manor`, and `torrent`

- [ ] **Step 1: Write the failing verification**

```bash
cd /home/joe/dotfiles
for h in elphael volcano-manor; do
  printf '%s: ' "$h"
  nix eval --json ".#nixosConfigurations.$h.config.age.secrets" \
    --apply 'a: builtins.filter (n: builtins.match ".*(anthropic|openai|openrouter).*" n != null) (builtins.attrNames a)'
done
printf 'torrent: '
nix eval --json '.#darwinConfigurations.torrent.config.age.secrets' \
  --apply 'a: builtins.filter (n: builtins.match ".*(anthropic|openai|openrouter).*" n != null) (builtins.attrNames a)'
```

Expected today: `["anthropic_api_key"]`, `["anthropic_api_key"]`, `[]`. The target is `["anthropic_api_key","openai_api_key","openrouter_api_key"]` on all three.

- [ ] **Step 2: Create the OpenRouter secret**

`anthropic_api_key.age` and `openai_api_key.age` already exist in `dotfiles-secrets`; only OpenRouter is new. Mint the key at <https://openrouter.ai/settings/keys>, then:

```bash
cd /home/joe/dotfiles-secrets
git pull --ff-only
secret-helper add openrouter_api_key
```

`secret-helper add` appends `"openrouter_api_key.age".publicKeys = users;` to `secrets.nix` and opens `$EDITOR` on the decrypted buffer. Paste the key with **no trailing newline concerns** — pi-nix's prelude uses `$(cat …)`, which strips trailing newlines, so a trailing newline is harmless.

Verify:
```bash
cd /home/joe/dotfiles-secrets
grep -n 'openrouter_api_key' secrets.nix
secret-helper decrypt-file openrouter_api_key.age | head -c 12; echo
```

Expected: the `secrets.nix` line is present with `publicKeys = users;` (matching the neighbouring `anthropic_api_key.age` / `openai_api_key.age` entries), and the decrypt prints the key's prefix (`sk-or-v1-`).

- [ ] **Step 3: Push the secrets repo**

```bash
cd /home/joe/dotfiles-secrets
git add openrouter_api_key.age secrets.nix
git commit -m "feat: add openrouter_api_key for the pi agent"
git push
```

- [ ] **Step 4: Deploy the secrets on the two Linux workstations**

In `modules/hosts/elphael/default.nix`, immediately after the existing `age.secrets.anthropic_api_key` block, insert:

```nix
      # Provider keys for pi (modules/ai/pi.nix). anthropic_api_key above is
      # shared with other tooling; these two exist only for pi's
      # environment.<NAME>.file wiring, which cats them at launch.
      age.secrets.openai_api_key = {
        file = "${inputs.dotfiles-secrets}/openai_api_key.age";
        mode = "0400";
        owner = meta.username;
      };
      age.secrets.openrouter_api_key = {
        file = "${inputs.dotfiles-secrets}/openrouter_api_key.age";
        mode = "0400";
        owner = meta.username;
      };
```

Insert the identical block after `age.secrets.anthropic_api_key` in `modules/hosts/volcano-manor/default.nix`.

- [ ] **Step 5: Deploy the secrets on torrent**

`torrent` has no `anthropic_api_key` yet, so all three go in. In `modules/hosts/torrent/default.nix`, inside the `darwin.age.secrets` group (next to `age.secrets.kanary-notion-api-token`), add:

```nix
      # Provider keys for pi (modules/ai/pi.nix). agenix-darwin decrypts to
      # /run/agenix/<name> exactly as on NixOS, so the home-manager aspect
      # needs no per-platform path handling.
      age.secrets.anthropic_api_key = {
        file = "${inputs.dotfiles-secrets}/anthropic_api_key.age";
        mode = "0400";
        owner = meta.username;
      };
      age.secrets.openai_api_key = {
        file = "${inputs.dotfiles-secrets}/openai_api_key.age";
        mode = "0400";
        owner = meta.username;
      };
      age.secrets.openrouter_api_key = {
        file = "${inputs.dotfiles-secrets}/openrouter_api_key.age";
        mode = "0400";
        owner = meta.username;
      };
```

- [ ] **Step 6: Bump the secrets input and re-run the verification**

```bash
cd /home/joe/dotfiles
nix flake update dotfiles-secrets
nix fmt modules/hosts/elphael/default.nix modules/hosts/volcano-manor/default.nix modules/hosts/torrent/default.nix
```

Then re-run the Step 1 commands.

Expected: `["anthropic_api_key","openai_api_key","openrouter_api_key"]` from all three hosts. Order may differ; sort before comparing if it matters.

- [ ] **Step 7: Confirm the `.age` ciphertext, and only the ciphertext, is what enters the store**

```bash
cd /home/joe/dotfiles
SECRETS=$(nix eval --raw '.#inputs.dotfiles-secrets.outPath')
head -1 "$SECRETS/openrouter_api_key.age"
grep -c 'sk-or-v1-' "$SECRETS/openrouter_api_key.age" || true
```

Expected: the first line is `-----BEGIN AGE ENCRYPTED FILE-----` (or `age-encryption.org/v1`), and the `grep -c` prints `0`. The store holds ciphertext; agenix decrypts it to `/run/agenix/` at activation, which is a tmpfs outside the store.

- [ ] **Step 8: Commit**

```bash
cd /home/joe/dotfiles
git add modules/hosts/elphael/default.nix modules/hosts/volcano-manor/default.nix modules/hosts/torrent/default.nix flake.lock
git commit -m "feat(agenix): deploy the openai/openrouter provider keys for pi

pi reads provider keys through environment.<NAME>.file, which cats the path
at every launch, so a host that gets the pi aspect must have all three keys
decrypted or every start prints a cat error. torrent gains anthropic too;
agenix-darwin uses the same /run/agenix/<name> layout as NixOS."
```

---

### Task 3: Auth wiring — agenix env vars, the `!op read` fallback, and the `/login` runbook

Three auth paths, layered to match pi's documented resolution order (CLI `--api-key` > `auth.json` > environment > `models.json` provider keys). `/login` writes `auth.json` and therefore always wins, which is exactly what the ChatGPT/Codex and OpenRouter subscription paths need.

**Files:**
- Create: `/home/joe/dotfiles-secrets/pi.nix`
- Modify: `/home/joe/dotfiles/modules/ai/pi.nix`
- Modify: `/home/joe/dotfiles/flake.lock` (second `nix flake update dotfiles-secrets`)

**Interfaces:**
- Consumes: `programs.pi.coding-agent.environment` (upstream, `attrsOf (attrTag { file | value })`); the `/run/agenix/*` paths from Task 2
- Produces:
  - `home.activation.piModelsJson` — a `lib.hm.dag.entryAfter [ "writeBoundary" ]` script installing `~/.pi/agent/models.json` at mode `0600`
  - the runtime environment `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `OPENROUTER_API_KEY` inside pi's launch wrapper

- [ ] **Step 1: Verify the three assumptions this task rests on**

Read the two upstream docs before writing anything:

```bash
curl -sSL https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/docs/providers.md \
  | grep -n 'Resolution Order' -A 8
curl -sSL https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/docs/models.md \
  | grep -n 'Overriding Built-in Providers' -A 14
```

Expected, and required for this task to be correct:

1. Resolution order is `--api-key` > `auth.json` > environment variable > `models.json` custom provider keys. **If `models.json` ever outranks the environment, swap the two layers below** — the `!op read` fallback must never shadow an agenix key.
2. A `models.json` entry naming a *built-in* provider merges into it rather than replacing it ("All built-in Anthropic models remain available. Existing OAuth or API key auth continues to work.").
3. `apiKey` accepts `"!command"` (stdout, cached for the process lifetime) and `"$ENV_VAR"`.

**Open assumption (verify at implementation time):** the docs only demonstrate a `baseUrl`-only override of a built-in provider. This task writes an `apiKey`-only override. If pi rejects a provider entry with neither `baseUrl` nor `models`, add `"baseUrl"` set to the provider's public endpoint alongside `apiKey`, and record the change here. Step 8 is the runtime check for this.

- [ ] **Step 2: Write the failing verification**

```bash
cd /home/joe/dotfiles
W=$(nix eval --raw '.#nixosConfigurations.elphael.config.home-manager.users.joe.programs.pi.coding-agent.finalPackage.outPath')
grep -o 'export [A-Z_]*_API_KEY[^\n]*' "$W"/bin/pi 2>/dev/null || echo 'NO ENV PRELUDE'
```

Expected today: `NO ENV PRELUDE` (or nothing), because `bin/pi` is currently the jail wrapper around an unconfigured package. After Step 5 the *inner* wrapper must contain three `export …="$(cat /run/agenix/…)"` lines.

- [ ] **Step 3: Add the 1Password references to the secrets repo**

The `op://` coordinates are private and `dotfiles` is a public repo, so they live in `dotfiles-secrets` and are imported the way `day-sync.nix` and `1password.nix` already are.

Create `/home/joe/dotfiles-secrets/pi.nix`:

```nix
# pi (modules/ai/pi.nix in dotfiles) — 1Password references for the
# models.json apiKey fallback. These are *references*, not secrets: pi runs
# `op read <ref>` at model-selection time and the plaintext never leaves the
# op process's stdout. Used only where the agenix key is absent (a fresh
# machine, or a host that has not activated yet).
{
  anthropicKeyRef = "op://Private/Anthropic API Key/credential";
  openaiKeyRef = "op://Private/OpenAI API Key/credential";
  openrouterKeyRef = "op://Private/OpenRouter API Key/credential";
}
```

Confirm each reference resolves before committing:

```bash
for r in "op://Private/Anthropic API Key/credential" \
         "op://Private/OpenAI API Key/credential" \
         "op://Private/OpenRouter API Key/credential"; do
  printf '%s -> ' "$r"; op read "$r" >/dev/null && echo OK || echo MISSING
done
```

Expected: `OK` three times. A `MISSING` means the item title or vault differs — fix the reference in `pi.nix`, never the check. Then:

```bash
cd /home/joe/dotfiles-secrets
git add pi.nix && git commit -m "feat: add pi.nix with the op:// provider key references" && git push
cd /home/joe/dotfiles && nix flake update dotfiles-secrets
```

- [ ] **Step 4: Extend `modules/ai/pi.nix` with the auth wiring**

Replace the whole file with:

```nix
# pi (pi-nix) + the agent-skills library. The fourth first-class agent
# alongside Claude Code, Codex, and Antigravity.
{ inputs, ... }:
let
  # `op://` references for the models.json fallback keys. References, not
  # secrets — the real vault coordinates are private, so they come from the
  # secrets repo the same way day-sync's config does.
  piSecrets = import "${inputs.dotfiles-secrets}/pi.nix";
in
{
  den.aspects.pi.homeManager =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      # The same guard the sibling AI aspects use. pi's package comes from
      # pi-nix (re-exported through agent-skills) rather than the llm-agents
      # overlay, so this is not a hard dependency — it is this repo's marker
      # for "this host carries the AI toolchain", and keeping the condition
      # identical means all four agents switch on and off together.
      enabled = pkgs ? llm-agents;

      # jail.nix is bubblewrap, so Linux only; pi-nix throws outright rather
      # than degrading if the flag is set on Darwin, and torrent gets this
      # aspect.
      jailed = pkgs.stdenv.hostPlatform.isLinux;

      homeDir = config.home.homeDirectory;

      # agenix decrypts to /run/agenix/<name> on NixOS and on nix-darwin
      # alike, so one helper covers both. These are runtime paths handed to
      # pi as *strings*: pi-nix's `file` tag accepts `either str path`, and a
      # Nix path literal would copy the plaintext into the store.
      ageKey = name: "/run/agenix/${name}";

      # Last-resort provider keys, for a machine where agenix has not run.
      # This file holds only the *command* that fetches a key, never a key,
      # so it is safe in the store — but it is installed as a real 0600 file
      # rather than symlinked, because the jail binds only the runtime
      # closure and a bare store symlink would dangle inside it. Upstream's
      # own `models` option is deliberately unused: its prelude installs the
      # file only when absent, so a declared models.json goes stale on the
      # first edit.
      modelsJson = pkgs.writeText "pi-models.json" (
        builtins.toJSON {
          providers = {
            anthropic.apiKey = "!op read '${piSecrets.anthropicKeyRef}'";
            openai.apiKey = "!op read '${piSecrets.openaiKeyRef}'";
            openrouter.apiKey = "!op read '${piSecrets.openrouterKeyRef}'";
          };
        }
      );
    in
    {
      imports = [ inputs.agent-skills.homeManagerModules.pi ];

      programs.pi.coding-agent = lib.mkIf enabled {
        enable = true;

        # Auth, layered to match pi's resolution order (auth.json > env >
        # models.json). Nothing here fights the interactive `/login` flows:
        #
        #   1. `/login` (ChatGPT Plus/Pro for Codex, and OpenRouter's PKCE
        #      flow) writes ~/.pi/agent/auth.json, which outranks everything
        #      below. That is the primary path and needs no declaration —
        #      see the first-run runbook in this plan.
        #   2. These agenix-backed variables are the API-key path. pi-nix
        #      cats each file at launch, so the plaintext exists only in the
        #      wrapper's process environment.
        #   3. models.json's `!op read` entries (below) are the fallback for
        #      a machine that has not activated agenix yet.
        environment = {
          ANTHROPIC_API_KEY.file = ageKey "anthropic_api_key";
          OPENAI_API_KEY.file = ageKey "openai_api_key";
          OPENROUTER_API_KEY.file = ageKey "openrouter_api_key";
        };

        jail.enable = jailed;
      };

      # models.json is read-only from pi's perspective (it reloads on
      # `/model`; pi writes settings.json and auth.json, not this), so
      # re-installing it on every activation costs nothing and keeps the
      # op:// references from drifting.
      home.activation.piModelsJson = lib.mkIf enabled (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run mkdir -p ${lib.escapeShellArg "${homeDir}/.pi/agent"}
          run install -m 0600 ${modelsJson} ${lib.escapeShellArg "${homeDir}/.pi/agent/models.json"}
        ''
      );
    };
}
```

- [ ] **Step 5: Re-run the verification**

```bash
cd /home/joe/dotfiles && nix fmt modules/ai/pi.nix
W=$(nix eval --raw '.#nixosConfigurations.elphael.config.home-manager.users.joe.programs.pi.coding-agent.finalPackage.outPath')
# bin/pi is the jail wrapper; follow it to the inner writeShellScriptBin.
INNER=$(grep -o '/nix/store/[a-z0-9]\{32\}-pi/bin/pi' "$W"/bin/pi | head -1)
grep -n 'export .*_API_KEY' "$INNER"
```

Expected, exactly three lines:
```
export ANTHROPIC_API_KEY="$(cat /run/agenix/anthropic_api_key)"
export OPENAI_API_KEY="$(cat /run/agenix/openai_api_key)"
export OPENROUTER_API_KEY="$(cat /run/agenix/openrouter_api_key)"
```

If `INNER` is empty, the jail wrapper names the inner derivation differently; find it with `grep -o '/nix/store/[^ "]*' "$W"/bin/pi | sort -u`.

- [ ] **Step 6: Verify models.json holds commands, not credentials**

```bash
cd /home/joe/dotfiles
M=$(nix eval --raw --impure --expr '
  let f = builtins.getFlake "/home/joe/dotfiles";
      hm = f.nixosConfigurations.elphael.config.home-manager.users.joe;
  in builtins.head (builtins.filter (s: builtins.match ".*pi-models.json" s != null)
       (builtins.attrNames (builtins.getContext (toString hm.home.activation.piModelsJson.data))))
')
cat "$M"; echo
```

Expected:
```json
{"providers":{"anthropic":{"apiKey":"!op read 'op://Private/Anthropic API Key/credential'"},"openai":{"apiKey":"!op read 'op://Private/OpenAI API Key/credential'"},"openrouter":{"apiKey":"!op read 'op://Private/OpenRouter API Key/credential'"}}}
```

Every value starts with `!op read` — no key material. If the context extraction above is awkward on your nix version, the equivalent direct read is:
```bash
nix eval --raw '.#nixosConfigurations.elphael.config.home-manager.users.joe.home.activation.piModelsJson.data' | grep -o '/nix/store/[^ ]*pi-models.json'
```

- [ ] **Step 7: Record the first-run runbook**

Append to `modules/ai/pi.nix`, immediately below the `environment` block's comment, nothing further — the runbook belongs in the commit message and here, because it is a one-time interactive step Nix cannot express:

```
First run, once per machine:

  pi
  /login            # pick "ChatGPT Plus/Pro (Codex)" -> browser PKCE flow
  /login openrouter # pick "Sign in with OpenRouter" -> mints a scoped key

Both write ~/.pi/agent/auth.json (0600), which outranks the agenix
environment variables, so the subscription paths win once they exist. Over
SSH the loopback callback cannot be reached; paste the final redirect URL
into the prompt instead. `/logout` clears a provider and drops it back to
the agenix key.
```

- [ ] **Step 8: Runtime check of the models.json override (resolves the Step 1 assumption)**

After the first `nixos-rebuild switch` in Task 7, run:

```bash
pi
/model
```

Expected: the model picker lists the built-in Anthropic, OpenAI, and OpenRouter models, and pi prints no parse error for `models.json`. If it errors on a provider with no `baseUrl`/`models`, add the endpoint to each entry:

```nix
anthropic = { baseUrl = "https://api.anthropic.com/v1"; apiKey = "!op read '${piSecrets.anthropicKeyRef}'"; };
openai = { baseUrl = "https://api.openai.com/v1"; apiKey = "!op read '${piSecrets.openaiKeyRef}'"; };
openrouter = { baseUrl = "https://openrouter.ai/api/v1"; apiKey = "!op read '${piSecrets.openrouterKeyRef}'"; };
```

- [ ] **Step 9: Commit**

```bash
cd /home/joe/dotfiles
git add modules/ai/pi.nix flake.lock
git commit -m "feat(pi): wire the three auth paths without storing a secret

Layered to match pi's own resolution order. /login OAuth (ChatGPT Plus/Pro
for Codex, and OpenRouter's PKCE flow) writes auth.json and outranks
everything, so the subscription paths need no declaration. Below it,
environment.<NAME>.file points at /run/agenix/<key> as a *string* — a Nix
path literal would copy the plaintext into the store, a string is read with
cat at launch. Below that, models.json carries \`!op read op://...\`
commands as a fallback for a machine agenix has not reached; the file holds
the command, never the key. models.json is installed by an activation script
rather than upstream's \`models\` option, which only installs when the file
is absent and would therefore go stale."
```

---

### Task 4: Jail permissions for the secrets, SSH, and the statusline

`envPrelude` runs *inside* bubblewrap, and jail.nix binds only the runtime closure's store paths. Without explicit binds the `cat /run/agenix/...` calls added in Task 3 fail, git push loses the 1Password agent, and the statusline cannot write its cache.

**Files:**
- Modify: `/home/joe/dotfiles/modules/ai/pi.nix`

**Interfaces:**
- Consumes: `options.programs.pi.coding-agent.jail.permissions.default` — a `combinators -> [ Permission ]` function; phase 3 owns its contents (network, mount-cwd, toolchain `add-pkg-deps`, and the generic try-readonly set)
- Consumes (jail.nix combinators, verified in `~alexdavid/jail.nix@404e7da`): `try-readonly : String -> Permission`, `try-readwrite : String -> Permission`, `add-pkg-deps : [Package] -> Permission`, `noescape : String -> NoEscapedString`
- Produces: `programs.pi.coding-agent.jail.permissions` — the phase-3 default list concatenated with this machine's host-path allowlist

- [ ] **Step 1: Confirm the phase-3 default is a plain `mkOption` default you can call**

```bash
cd /home/joe/dotfiles
nix eval --json '.#nixosConfigurations.elphael.options.home-manager.users.type.getSubOptions' 2>/dev/null >/dev/null || true
nix eval --raw --impure --expr '
  let f = builtins.getFlake "/home/joe/dotfiles";
      o = f.nixosConfigurations.elphael.config.home-manager.users.joe.programs.pi.coding-agent;
  in builtins.typeOf o.jail.permissions
'
```

Expected: `lambda`. Then check whether phase 3 shipped a dedicated additive option, which would be cleaner than composing the default:

```bash
nix eval --json '.#nixosConfigurations.elphael.config.home-manager.users.joe.programs.pi.coding-agent.jail' --apply builtins.attrNames
```

Expected: `["enable","permissions"]`. **If phase 3 added `extraPermissions`, use it instead of the `options.…default` composition below** and note the substitution — the goal is "phase 3's set plus these paths", not a re-declaration of phase 3's set.

- [ ] **Step 2: Write the failing verification**

```bash
cd /home/joe/dotfiles
W=$(nix eval --raw '.#nixosConfigurations.elphael.config.home-manager.users.joe.programs.pi.coding-agent.finalPackage.outPath')
grep -c 'run/agenix' "$W"/bin/pi
```

Expected today: `0`. After Step 3 it must be `3` or more (one `--ro-bind-try` per key).

- [ ] **Step 3: Add the permission extras**

In `modules/ai/pi.nix`, add `options` to the module's argument list, and replace `jail.enable = jailed;` with:

```nix
        jail.enable = jailed;

        # The jail wraps pi-nix's launch wrapper, not just the pi binary, so
        # the `cat /run/agenix/...` in the environment prelude above runs
        # *inside* bubblewrap and needs the secret files bound. jail.nix
        # binds only the runtime closure's store paths — /nix/store is not
        # mounted whole — so nothing on the host is visible unless it is
        # named here.
        #
        # Assigning this option replaces its default, so phase 3's set is
        # called and concatenated rather than restated; that keeps pi-nix
        # free to change the generic list without a dotfiles edit.
        jail.permissions = lib.mkIf jailed (
          combinators:
          options.programs.pi.coding-agent.jail.permissions.default combinators
          ++ (
            with combinators;
            [
              # The provider keys from Task 2. try-readonly, not readonly:
              # activation order means a fresh machine may not have them yet,
              # and a hard bind of a missing path aborts the launch.
              (try-readonly "/run/agenix/anthropic_api_key")
              (try-readonly "/run/agenix/openai_api_key")
              (try-readonly "/run/agenix/openrouter_api_key")

              # The same host-side SSH paths modules/ai/claude.nix punches
              # through Claude's sandbox: 1Password's agent socket covers
              # agent-backed signing, known_hosts and ~/.ssh/config cover
              # host-key verification and per-host config. Private key files
              # (id_*) are deliberately omitted — the agent is the supported
              # path here.
              (try-readonly (noescape "\"$HOME/.1password/agent.sock\""))
              (try-readonly (noescape "\"$HOME/.ssh/known_hosts\""))
              (try-readonly (noescape "\"$HOME/.ssh/known_hosts2\""))
              (try-readonly (noescape "\"$HOME/.ssh/config\""))
              (try-readonly (noescape "\"$HOME/.gitconfig\""))

              # agent-statusline keeps its git/transcript caches here and the
              # `hook` subcommand writes the tool-timing sidecar, so this one
              # is read-write.
              (try-readwrite (noescape "\"$HOME/.cache/agent-statusline\""))

              # The `pr` widget shells out to gh, which needs its own config
              # for the host token.
              (try-readonly (noescape "\"$HOME/.config/gh\""))
              (add-pkg-deps [
                pkgs.gh
                pkgs.openssh
              ])
            ]
          )
        );
```

- [ ] **Step 4: Re-run the verification**

```bash
cd /home/joe/dotfiles && nix fmt modules/ai/pi.nix
W=$(nix eval --raw '.#nixosConfigurations.elphael.config.home-manager.users.joe.programs.pi.coding-agent.finalPackage.outPath')
grep -o 'run/agenix/[a-z_]*' "$W"/bin/pi | sort -u
grep -c 'agent.sock\|known_hosts\|agent-statusline' "$W"/bin/pi
```

Expected: the three `run/agenix/...` paths, and a count of at least `4`.

- [ ] **Step 5: Prove the jail actually reaches the secret at runtime**

After the Task 7 rebuild:

```bash
cd /tmp && pi --print 'run: sh -c "wc -c < /run/agenix/openrouter_api_key"'
```

Expected: a byte count, not `No such file or directory`. A stricter smoke test that never prints the key:

```bash
cd /tmp && pi --print 'run: sh -c "test -n \"$OPENROUTER_API_KEY\" && echo SET || echo UNSET"'
```

Expected: `SET`.

- [ ] **Step 6: Record what the jail cannot do**

Add this comment above the `modelsJson` binding in `modules/ai/pi.nix`:

```nix
      # NOTE: the `!op read` fallback only works with the jail off (i.e. on
      # torrent, where bubblewrap does not exist anyway). `op` needs the
      # desktop app's socket and biometric unlock, neither of which is bound
      # into the jail, and binding them would hand the agent the whole vault.
      # On the linux workstations agenix is therefore the working key path
      # and this file is a documentation of intent plus a Darwin fallback.
```

- [ ] **Step 7: Commit**

```bash
cd /home/joe/dotfiles
git add modules/ai/pi.nix
git commit -m "feat(pi): bind the agenix keys and SSH paths into the jail

The jail wraps pi-nix's launch wrapper, so the environment prelude's cat of
/run/agenix/<key> runs inside bubblewrap; jail.nix binds only the runtime
closure, so each secret needs naming. The SSH allowlist mirrors the
extraSandbox allowlist modules/ai/claude.nix already declares for Claude.
Phase 3's default permission list is called and concatenated, not restated,
so pi-nix can change the generic set without a dotfiles edit."
```

---

### Task 5: Statusline parity with Claude

Both agents must render the same line. Since phase 1 moved the schema into `agent-statusline.lib.statuslineOptions` and both `claude-nix` and `pi-nix` mount that same submodule, parity is achieved by *not overriding anything* — and asserted by rendering both option sets through the same `renderConfig`.

**Files:**
- Modify: `/home/joe/dotfiles/modules/ai/pi.nix`

**Interfaces:**
- Consumes: `programs.pi.coding-agent.statusline.enable` (phase 2); `agent-statusline.lib.<system>.renderConfig` (phase 1)
- Produces: a rendered pi statusline config byte-identical to Claude's

- [ ] **Step 1: Capture the reference**

```bash
cd /home/joe/dotfiles
nix build --no-link --print-out-paths '.#nixosConfigurations.elphael.config.home-manager.users.joe.home.activationPackage'
```

Then read Claude's rendered config from the built tree:

```bash
P=$(nix build --no-link --print-out-paths '.#nixosConfigurations.elphael.config.home-manager.users.joe.home.activationPackage')
cat "$P"/home-files/.claude/statusline-config.json | tee /tmp/claude-statusline-config.json; echo
```

Expected today (this is the live value on this machine, and is the contract):
```json
{"activityRows":4,"barWidth":8,"gitCacheTtlSeconds":5,"hideWhenIdle":true,"padding":0,"refreshInterval":1,"sevenDayThreshold":50,"tokenFormat":"compact","transcriptWindowSeconds":300,"widgets":{"hide":[],"row1":["model","cwd","git","duration","usage5h","usage7d"],"row2":["context","tokens","burnRate","voice","compaction","pr","cost"]}}
```

Note `barWidth` is `8` and `tokenFormat` is `compact` — the phase-1 plan's Task 7 draft used `10` and an enum of `compact|full`; its Step 4 instructs that `claude-nix`'s values win. If the file above disagrees with these, phase 1 regressed and must be fixed there, not compensated for here.

- [ ] **Step 2: Write the failing verification**

```bash
cd /home/joe/dotfiles
nix eval --json --impure --expr '
  let
    f = builtins.getFlake "/home/joe/dotfiles";
    hm = f.nixosConfigurations.elphael.config.home-manager.users.joe;
    asl = f.inputs.agent-skills.inputs.agent-statusline.lib.x86_64-linux;
    read = cfg: builtins.fromJSON (builtins.readFile (asl.renderConfig cfg));
  in {
    claude = read hm.programs.claude-nix.statusLine;
    pi = read hm.programs.pi.coding-agent.statusline;
  }
' | jq -e '.claude == .pi'
```

Expected today: an evaluation error (`attribute 'statusline' missing`) or `false`. After Step 3 it must print `true` and exit `0`.

- [ ] **Step 3: Turn the statusline on, and change nothing else**

In `modules/ai/pi.nix`, inside `programs.pi.coding-agent`, immediately after `enable = true;`, add:

```nix
        # The statusline options come from agent-statusline's shared schema
        # (phase 1), which claude-nix mounts under `statusLine` and pi-nix
        # mounts here. dotfiles overrides nothing on either side, so both
        # render from the same defaults and the two lines are identical by
        # construction rather than by a duplicated widget list. Under pi the
        # `cost` widget always shows (the auth is Codex/OpenRouter, so cost
        # is the primary meter) and `usage5h`/`usage7d` hide themselves for
        # want of anthropic-ratelimit headers — that is mode-gated inside
        # the Go binary, not a config difference.
        statusline.enable = true;
```

- [ ] **Step 4: Re-run the verification**

```bash
cd /home/joe/dotfiles && nix fmt modules/ai/pi.nix
nix eval --json --impure --expr '
  let
    f = builtins.getFlake "/home/joe/dotfiles";
    hm = f.nixosConfigurations.elphael.config.home-manager.users.joe;
    asl = f.inputs.agent-skills.inputs.agent-statusline.lib.x86_64-linux;
    read = cfg: builtins.fromJSON (builtins.readFile (asl.renderConfig cfg));
  in {
    claude = read hm.programs.claude-nix.statusLine;
    pi = read hm.programs.pi.coding-agent.statusline;
  }
' | jq -e '.claude == .pi'
```

Expected: `true`, exit code `0`. A `false` means one of the two consumers diverged from the shared schema — fix it in `claude-nix` or `pi-nix`, never by pinning values here.

- [ ] **Step 5: Confirm Claude's rendered config did not move**

```bash
P=$(nix build --no-link --print-out-paths '.#nixosConfigurations.elphael.config.home-manager.users.joe.home.activationPackage')
diff /tmp/claude-statusline-config.json "$P"/home-files/.claude/statusline-config.json && echo IDENTICAL
```

Expected: `IDENTICAL`. Adding pi must not perturb the daily driver.

- [ ] **Step 6: Visual check after the rebuild**

After Task 7's switch, open both agents in the same repo and compare:

```bash
cd /home/joe/dotfiles && claude   # note row1 and row2
cd /home/joe/dotfiles && pi       # note row1 and row2
```

Expected: identical widget order and formatting. Differences allowed and expected: pi shows a `$` cost figure where Claude may hide it, and pi omits `usage5h`/`usage7d`.

- [ ] **Step 7: Commit**

```bash
cd /home/joe/dotfiles
git add modules/ai/pi.nix
git commit -m "feat(pi): render the same statusline as Claude Code

Both agents mount agent-statusline's shared option schema, so parity comes
from overriding nothing on either side rather than from a duplicated widget
list. An eval check renders both option sets through the same renderConfig
and asserts they are equal."
```

---

### Task 6: The shared auto-mode rule set

One declaration, fanned out by `agent-skills` to Claude Code's native classifier and to both of pi's permission layers. These are natural-language rules read by a model, not glob patterns — they must describe *this* machine specifically enough to be actionable and generally enough to survive a repo being added.

**Files:**
- Create: `/home/joe/dotfiles/modules/ai/auto-mode.nix`
- Modify: `/home/joe/dotfiles/modules/home/baseline.nix`

**Interfaces:**
- Consumes: `programs.agent-skills.autoMode.{allow,soft_deny,hard_deny,environment}` — each `types.listOf types.str` (phase 4)
- Produces: `den.aspects.auto-mode.homeManager`, and `den.aspects.home-baseline.includes` gains `den.aspects.auto-mode`

- [ ] **Step 1: Read the four list meanings before drafting a rule**

```bash
cd /home/joe/Development/claude-nix && sed -n '681,765p' modules/home-manager.nix
```

Expected, and binding on every rule below:
- `allow` — proceed without prompting.
- `soft_deny` — destructive or irreversible; **explicit user intent clears it**, so the classifier also sees recent user turns.
- `hard_deny` — a security boundary; **user intent does NOT clear it**.
- `environment` — facts about this machine the classifier should assume.

Also confirm the additive contract:
```bash
cd /home/joe/Development/claude-nix && sed -n '30,45p' lib/mergeClaudeSettings.nix
```
Expected: `(defaultSettings.autoMode.${section} or []) ++ (extraAutoMode.${section} or [])`. Because `claude-nix`'s shipped `allow` already leads with the literal `"$defaults"`, **this file must not add `"$defaults"` itself** — it would appear twice.

- [ ] **Step 2: Capture the current state as the failing verification**

```bash
cd /home/joe/dotfiles
P=$(nix build --no-link --print-out-paths '.#nixosConfigurations.elphael.config.home-manager.users.joe.home.activationPackage')
C=$(grep -o '/nix/store/[a-z0-9]\{32\}-claude-config' "$P"/activate | head -1)
jq '.autoMode | map_values(length)' "$C"/settings.json
```

Expected today: `{"allow": 2}` — the two `rtk` rules `claude-nix` ships. After Step 3 the shape must be `{"allow": 13, "soft_deny": 13, "hard_deny": 11, "environment": 9}` (2 shipped + 11 added in `allow`; exact counts follow the lists below).

- [ ] **Step 3: Write `modules/ai/auto-mode.nix`**

Follow `modules/ai/mcp.nix`: contribute to `programs.agent-skills.*` without importing the module — `modules/ai/claude.nix` already imports `inputs.agent-skills.homeManagerModules.agent-skills`, and importing the same anonymous module twice risks a duplicate evaluation.

```nix
# Auto-mode rules, declared once and fanned out by the agent-skills module to
# Claude Code's native classifier and to both of pi's permission layers.
#
# These are natural-language rules read by a model, not glob patterns. Four
# lists, with meanings that are NOT interchangeable:
#
#   allow       proceed without prompting
#   soft_deny   destructive, but explicit user intent in the conversation
#               clears it
#   hard_deny   a security boundary; user intent does not clear it
#   environment facts about this machine the classifier should assume
#
# Additive: these concatenate onto whatever each agent ships, so `allow` must
# NOT repeat the literal "$defaults" — claude-nix's own list already leads
# with it. No import here; modules/ai/claude.nix imports the agent-skills
# module and modules/ai/mcp.nix contributes the same way.
{ ... }:
{
  den.aspects.auto-mode.homeManager =
    { ... }:
    {
      programs.agent-skills.autoMode = {
        environment = [
          "This is a single-user personal workstation — NixOS on the desktops, nix-darwin on the laptop — managed by one Nix flake at ~/dotfiles. There is no shared, staging, or production infrastructure reachable from it, and no other person's work can be lost by a mistake here."
          "The login shell is fish, not bash. Do not assume bash syntax works in an interactive shell: `export VAR=value`, `VAR=value cmd`, `&>`, and process substitution are all bash-only. Scripts should declare their own interpreter rather than relying on the ambient shell."
          "Essentially everything that matters is recoverable: files under ~/Development and ~/dotfiles are in git, and the system itself is rebuildable from the flake and rollback-able with `nixos-rebuild --rollback` or by selecting an older boot generation. Treat a lost edit as an inconvenience, not a catastrophe."
          "SSH authentication and git commit signing go through the 1Password SSH agent (~/.1password/agent.sock on Linux, the Group Containers agent.sock on macOS). There are no usable private key files on disk, so a command that reads ~/.ssh/id_* is confused rather than hostile — but it should still not be run."
          "Secrets are agenix-encrypted in ~/dotfiles-secrets and decrypt at activation to /run/agenix/<name>, mode 0400 and owned by the user. Nix modules refer to those runtime paths; the plaintext must never be copied anywhere else, echoed into the conversation, or committed."
          "Personal code lives under ~/Development, one directory per repository, roughly seventy of them. ~/dotfiles is the Nix configuration; ~/dotfiles-secrets is the encrypted secrets repo. Anything outside those trees is either the Nix store or user data."
          "CI is a self-hosted garnix instance running on the user's own hardware, with its domain held in the private secrets repo. Pushing a branch triggers real builds on it. Builds are cheap and cause no external side effects, so triggering CI is not a destructive act."
          "`nix build`, `nix eval`, `nix flake check`, `nix flake show`, `nix path-info`, and `nix-instantiate` have no effect beyond filling the Nix store and using the network. Treat them as read-only. The Nix store itself is immutable, so a command that tries to write into /nix/store fails harmlessly rather than damaging anything."
          "Long-running processes belong in a zmx session rather than a bare background job, because the harness's own process tree does not outlive the task."
        ];

        allow = [
          "Read any file the user can read under ~/Development, ~/dotfiles, or the current working directory, including dotfiles, lockfiles, and generated output."
          "Run read-only inspection tools anywhere the user can read: rg, grep, fd, find, ls, cat, head, tail, `sed -n`, jq, file, stat, wc, and `nix path-info`."
          "Run any nix evaluation or build command against a local flake or store path — `nix build`, `nix eval`, `nix flake check`, `nix flake show`, `nix repl`, `nix-instantiate`, `nix fmt` — including ones that populate the store from a substituter."
          "Run a project's own build, test, lint, and format commands (cargo, go, npm, pnpm, bun, pytest, gradle, maven, nixfmt, gofmt, treefmt, eslint), including ones that write into a project-local build, target, dist, or node_modules directory."
          "Run read-only git commands: status, log, diff, show, blame, branch, remote -v, stash list, worktree list, rev-parse, describe."
          "Create git commits, create and switch local branches, stage and unstage hunks, and create git worktrees under the repository's own worktree location."
          "Push a feature branch to origin, and open, update, or comment on pull requests in repositories the user owns, using the gh CLI."
          "Query build and check status from GitHub and from the user's self-hosted garnix instance."
          "Create, edit, and delete files inside the session's working directory and inside the scratchpad directory the harness provides."
          "Start and stop local development servers and other processes that bind only to localhost, and read their logs."
          "Read the user's own Obsidian vault, calendar, and Notion workspace through the CLIs configured for them (obsidian, gws, day-sync)."
        ];

        soft_deny = [
          "Force-pushing, or any push that rewrites history that already exists on a remote — `git push --force`, `--force-with-lease`, or a push after an amend or rebase of pushed commits."
          "Pushing to, or merging into, the default branch (main or master) of any repository. Feature branches and pull requests are the normal path."
          "Discarding uncommitted work: `git reset --hard`, `git clean -fdx`, `git checkout -- .`, `git stash drop`, or deleting a worktree with unsaved changes."
          "Activating a new system or home configuration: `nixos-rebuild switch`, `nixos-rebuild boot`, `darwin-rebuild switch`, `home-manager switch`. Building the same configuration is allowed; switching the running system is the user's call."
          "Deleting files or directories outside the current working directory, and any recursive delete that would remove more than a handful of files."
          "Garbage collection or store deletion: `nix-collect-garbage`, `nix store gc`, `nix store delete`, `nix profile wipe-history`."
          "Installing or removing software outside the Nix flake — `brew install`, `npm install -g`, `pip install --user`, `cargo install` — because it creates state the flake cannot reproduce."
          "Modifying anything under ~/dotfiles-secrets, or running `secret-helper add`, `edit`, `remove`, or `rekey`."
          "Stopping, restarting, or disabling a systemd unit, container, or microVM that is not a dev server this session started."
          "Publishing artifacts: `npm publish`, `cargo publish`, `gh release create`, or pushing a git tag."
          "Writing to any repository the user does not own, including opening pull requests, filing issues, or posting review comments on someone else's project."
          "Sending a message that reaches another person — email, Slack, Discord, or a comment on a third-party issue tracker."
          "Changing repository configuration through the GitHub API: branch protection, collaborators, webhooks, deploy keys, or Actions secrets."
        ];

        hard_deny = [
          "Reading the plaintext of a credential into the conversation or into any file: anything under /run/agenix, ~/dotfiles-secrets, ~/.ssh, ~/.aws, ~/.config/op, ~/.pi/agent/auth.json, ~/.claude/.credentials.json, or a .env file. Passing such a path to the tool that legitimately consumes it is fine; printing, copying, or echoing its contents is not."
          "Writing a secret value anywhere it would persist: into a tracked file, a commit message, a log, or a command line that lands in shell history."
          "Weakening the agent's own guardrails — editing the autoMode or permissions sections of ~/.claude/settings.json or ~/.pi/agent/settings.json, passing flags that bypass the classifier or the sandbox, or launching a second agent process outside the jail in order to escape it."
          "Editing the Nix modules that define this permission system or the sandboxes — modules/ai/*.nix in ~/dotfiles — as a means of widening the agent's own permissions during the session. Changing them because the user asked for a configuration change is fine; changing them to get past a refusal is not."
          "Downloading and executing code in one step: `curl | sh`, `wget -O- | bash`, `iex(irm ...)`, or running a binary fetched from a URL that is not a Nix flake input or a package registry the project already depends on."
          "Escalating privilege: sudo, doas, su, pkexec, or writing into a systemd unit or launchd plist that would run as root."
          "Writing outside the user's home directory to system paths — /etc, /var, /boot, /usr, /nix/store — by any means."
          "Adding or repointing a git remote to a host the user did not name in this session."
          "Sending repository contents, transcripts, environment variables, or file listings to any host other than GitHub, the user's own garnix instance, the model provider being used for this session, and services the user explicitly named."
          "Deleting or rewriting history on a remote default branch, or deleting a remote branch this session did not create."
          "Disabling or uninstalling security tooling: the 1Password agent, the SSH known_hosts checks, gitleaks, or the sandbox wrappers."
        ];
      };
    };
}
```

- [ ] **Step 4: Include the aspect in the home baseline**

Claude Code runs on every full home, so the rules belong on `home-baseline` next to `mcp`, not on `workstation-packages`. In `modules/home/baseline.nix`, change:

```nix
      den.aspects.mcp
```

to:

```nix
      den.aspects.mcp
      den.aspects.auto-mode
```

- [ ] **Step 5: Re-run the verification**

```bash
cd /home/joe/dotfiles && nix fmt modules/ai/auto-mode.nix modules/home/baseline.nix
P=$(nix build --no-link --print-out-paths '.#nixosConfigurations.elphael.config.home-manager.users.joe.home.activationPackage')
C=$(grep -o '/nix/store/[a-z0-9]\{32\}-claude-config' "$P"/activate | head -1)
jq '.autoMode | map_values(length)' "$C"/settings.json
```

Expected:
```json
{
  "allow": 13,
  "soft_deny": 13,
  "hard_deny": 11,
  "environment": 9
}
```

`allow` is 13 because `claude-nix` ships two `rtk` rules ahead of the eleven here. Confirm the `$defaults` sentinel appears exactly once:

```bash
jq -r '.autoMode.allow[0]' "$C"/settings.json
jq '[.autoMode.allow[] | select(. == "$defaults")] | length' "$C"/settings.json
```

Expected: `$defaults`, then `1`.

- [ ] **Step 6: Confirm the same rules reached pi**

```bash
cd /home/joe/dotfiles
nix eval --json --impure --expr '
  let
    f = builtins.getFlake "/home/joe/dotfiles";
    hm = f.nixosConfigurations.elphael.config.home-manager.users.joe;
    shared = hm.programs.agent-skills.autoMode;
    pi = hm.programs.pi.coding-agent.autoMode;
  in builtins.all (k: builtins.all (r: builtins.elem r pi.${k}) shared.${k})
       [ "allow" "soft_deny" "hard_deny" "environment" ]
'
```

Expected: `true`. Every shared rule must appear in pi's lists; pi may hold additional rules of its own (phase 3's deterministic layer), which is why this is containment rather than equality.

- [ ] **Step 7: Confirm the rules landed on the servers too**

```bash
cd /home/joe/dotfiles
nix eval --json '.#nixosConfigurations.farum-azula.config.home-manager.users.joe.programs.agent-skills.autoMode.hard_deny' --apply builtins.length
```

Expected: `11`. `farum-azula` has `home-baseline` and therefore Claude, so it should get the rules even though it does not get pi.

- [ ] **Step 8: Commit**

```bash
cd /home/joe/dotfiles
git add modules/ai/auto-mode.nix modules/home/baseline.nix
git commit -m "feat(ai): declare shared auto-mode rules once for Claude and pi

Natural-language rules read by a model classifier, split across the four
lists whose meanings are not interchangeable: allow proceeds, soft_deny is
cleared by explicit user intent, hard_deny is not, and environment is
context. Drafted for this machine specifically — NixOS plus nix-darwin, fish
login shell, 1Password SSH agent with no key files on disk, agenix secrets
at /run/agenix, self-hosted garnix CI, and ~70 repos under ~/Development.

Contributed the way modules/ai/mcp.nix contributes mcpServers: no import,
because modules/ai/claude.nix already imports the agent-skills module. The
lists are additive, so \"\$defaults\" is deliberately absent — claude-nix's
own allow list already leads with it."
```

---

### Task 7: Full build, generated-config inspection, and rollout

Prove the whole thing builds on every host that receives it, that no secret reached the store, and that the generated pi configuration is what the plan says it is. Then switch.

**Files:**
- Modify: none (verification and rollout only)

**Interfaces:**
- Consumes: everything produced by Tasks 1–6
- Produces: a switched system on `elphael` and a documented state for the other two

- [ ] **Step 1: Build all three workstation configurations**

```bash
cd /home/joe/dotfiles
nix build --no-link --print-out-paths \
  '.#nixosConfigurations.elphael.config.home-manager.users.joe.home.activationPackage' \
  '.#nixosConfigurations.volcano-manor.config.home-manager.users.joe.home.activationPackage' \
  '.#darwinConfigurations.torrent.config.home-manager.users.joe.home.activationPackage'
```

Expected: three `/nix/store/...-home-manager-generation` paths and exit `0`. `torrent` cross-builds from Linux only for evaluation of the closure it can fetch; if it needs an aarch64-darwin builder, run `nix eval` on the same attribute instead and note that the build happens on the Mac.

- [ ] **Step 2: Build the full system closures**

```bash
cd /home/joe/dotfiles
nix build --no-link --print-out-paths '.#nixosConfigurations.elphael.config.system.build.toplevel'
nix build --no-link --print-out-paths '.#nixosConfigurations.volcano-manor.config.system.build.toplevel'
```

Expected: two store paths, exit `0`. A failure here and not in Step 1 means the `age.secrets` additions from Task 2 are wrong.

- [ ] **Step 3: Inspect the generated pi configuration**

```bash
cd /home/joe/dotfiles
P=$(nix build --no-link --print-out-paths '.#nixosConfigurations.elphael.config.home-manager.users.joe.home.activationPackage')

echo '── the wrapper pi actually launches ──'
readlink -f "$P"/home-path/bin/pi

echo '── the jail invocation ──'
sed -n '1,80p' "$(readlink -f "$P"/home-path/bin/pi)"

echo '── the inner wrapper: env prelude + resource args ──'
INNER=$(grep -o '/nix/store/[a-z0-9]\{32\}-pi/bin/pi' "$(readlink -f "$P"/home-path/bin/pi)" | head -1)
cat "$INNER"

echo '── models.json as it will be installed ──'
grep -o '/nix/store/[a-z0-9]\{32\}-pi-models.json' "$P"/activate | head -1 | xargs cat; echo

echo '── the statusline config both agents share ──'
cat "$P"/home-files/.claude/statusline-config.json; echo

echo '── the auto-mode rules Claude will read ──'
C=$(grep -o '/nix/store/[a-z0-9]\{32\}-claude-config' "$P"/activate | head -1)
jq '.autoMode' "$C"/settings.json
```

Expected, in order:
- `bin/pi` resolves to a jail wrapper containing `bwrap`, `--ro-bind-try` entries for the three `/run/agenix/*` keys, `$HOME/.1password/agent.sock`, the two `known_hosts` files, `$HOME/.ssh/config`, `$HOME/.gitconfig`, `$HOME/.config/gh`, and a `--bind` for `$HOME/.cache/agent-statusline`.
- the inner wrapper begins with the three `export …_API_KEY="$(cat /run/agenix/…)"` lines, then `exec …/bin/pi --system-prompt … --skill … --extension … "$@"`.
- `models.json` is the three-provider object whose every `apiKey` starts with `!op read`.
- the statusline config matches Task 5 Step 1 byte for byte.
- `autoMode` has the four lists with the counts from Task 6 Step 5.

- [ ] **Step 4: The no-secret-in-the-store gate**

```bash
cd /home/joe/dotfiles
P=$(nix build --no-link --print-out-paths '.#nixosConfigurations.elphael.config.home-manager.users.joe.home.activationPackage')

# 1. The literal key material must be absent from the whole closure.
for pat in 'sk-ant-api' 'sk-or-v1-' 'sk-proj-' 'BEGIN OPENSSH PRIVATE KEY'; do
  printf '%s: ' "$pat"
  if nix path-info -r "$P" | xargs -I{} sh -c 'grep -rl -- "$1" {} 2>/dev/null' _ "$pat" | head -1 | grep -q .; then
    echo 'FOUND — STOP'
  else
    echo clean
  fi
done

# 2. Only the runtime paths and the op:// references may appear.
nix path-info -r "$P" | xargs -I{} sh -c 'grep -rho "/run/agenix/[a-z_]*" {} 2>/dev/null' _ | sort -u
nix path-info -r "$P" | xargs -I{} sh -c 'grep -rho "op://[^'"'"']*" {} 2>/dev/null' _ | sort -u
```

Expected: `clean` for all four patterns; then exactly `/run/agenix/anthropic_api_key`, `/run/agenix/gws-credentials`, `/run/agenix/kanary-notion-api-token`, `/run/agenix/openai_api_key`, `/run/agenix/openrouter_api_key`; then the three `op://Private/... /credential` references. Any `FOUND` aborts the rollout.

The closure walk is slow (tens of thousands of files). A faster equivalent for iteration, sufficient for the pi-specific files:
```bash
grep -rl -e 'sk-ant-api' -e 'sk-or-v1-' "$(readlink -f "$P"/home-path/bin/pi)" "$INNER" "$C" || echo clean
```

- [ ] **Step 5: Switch elphael**

```bash
cd /home/joe/dotfiles
sudo nixos-rebuild switch --flake .#elphael
```

Expected: activation succeeds, and the agenix step reports the three new secrets. Verify:

```bash
ls -l /run/agenix/openai_api_key /run/agenix/openrouter_api_key /run/agenix/anthropic_api_key
ls -l ~/.pi/agent/models.json
```

Expected: three files, mode `-r--------`, owner `joe`; and `models.json` at mode `-rw-------`, a **regular file, not a symlink** — a symlink here would dangle inside the jail.

- [ ] **Step 6: First-run auth**

```bash
pi
```

Then in the TUI:
```
/login              # select "ChatGPT Plus/Pro (Codex)"; complete the browser flow
/login openrouter   # select "Sign in with OpenRouter"; complete the PKCE flow
/model              # confirm the picker lists models from all three providers
```

Expected: `~/.pi/agent/auth.json` exists at mode `0600` and contains an `openai` OAuth entry and an `openrouter` api_key entry. Verify without printing anything:

```bash
stat -c '%a %n' ~/.pi/agent/auth.json
jq -r 'to_entries | map("\(.key)=\(.value.type)") | join(" ")' ~/.pi/agent/auth.json
```

Expected: `600 /home/joe/.pi/agent/auth.json`, then something like `openai=oauth openrouter=api_key`. The values are types, never keys.

- [ ] **Step 7: End-to-end smoke test inside the jail**

```bash
cd /home/joe/dotfiles
pi --print 'What is the name of the flake description in flake.nix? Answer with just the string.'
```

Expected: `Joe Goldin Nix Config`. This exercises the jail's `mount-cwd`, the model call, and the auth chain in one shot.

Then confirm the guardrails are live:
```bash
cd /tmp && pi --print 'run: sudo -n true'
```
Expected: the agent refuses, citing a privilege-escalation boundary, rather than running it. If it runs, the `hard_deny` fan-out did not reach pi — return to Task 6 Step 6.

- [ ] **Step 8: Roll out to the other two hosts**

```bash
# volcano-manor
ssh volcano-manor 'cd ~/dotfiles && git pull --ff-only && sudo nixos-rebuild switch --flake .#volcano-manor'
# torrent
ssh torrent 'cd ~/dotfiles && git pull --ff-only && darwin-rebuild switch --flake .#torrent'
```

Expected: both activate cleanly. On `torrent`, additionally confirm the Darwin path:

```bash
ssh torrent 'readlink -f ~/.nix-profile/bin/pi | xargs head -20'
```

Expected: the plain `writeShellScriptBin "pi"` with the three `export` lines and **no `bwrap`** — the jail is Linux-only, so on Darwin the `!op read` fallback in `models.json` is the working 1Password path.

- [ ] **Step 9: Final commit**

```bash
cd /home/joe/dotfiles
git status --short
git log --oneline -6
```

Expected: a clean tree and six commits from Tasks 1–6. Nothing new to commit here; this task is verification and rollout only.

---

## Self-Review

**Spec coverage.** This plan implements design §13 in full and nothing outside it.

- "`modules/ai/pi.nix`, a `den.aspects.pi.homeManager` aspect matching the existing three" — Task 1. The aspect mirrors `modules/ai/claude.nix` line for line in shape: a `{ inputs, ... }:` outer module, a `den.aspects.<name>.homeManager` function taking `{ pkgs, lib, config, options, ... }`, an `enabled = pkgs ? llm-agents` let-binding, `imports = [ inputs.agent-skills.homeManagerModules.<agent> ]`, and one `programs.<agent> = lib.mkIf enabled { … }` block. The one deviation is documented in the file itself: `pkgs ? llm-agents` is not a true dependency for pi (its package comes from pi-nix through agent-skills, not from the llm-agents overlay), and it is kept because it is this repo's marker for "this host carries the AI toolchain" and keeps the four aspects switching together.
- "Auth, per the chosen paths — ChatGPT/Codex `/login`, 1Password- or agenix-backed API keys, and OpenRouter" — Task 3, layered to pi's documented resolution order rather than picking one mechanism: `/login` OAuth for Codex and OpenRouter (auth.json, highest), agenix `environment.<NAME>.file` second, `!op read` in `models.json` last.
- "uses `environment.<NAME>.file` pointing at an agenix path, **or** pi's `!command` key resolution for `op read`" — the spec offered a choice; this plan takes both, because they occupy different priority levels and different machines. Reading `options.nix` in full settled which fits where: `environment.<NAME>.file` is `cat`'d at launch by `envPrelude`, so it is the right home for a root-owned tmpfs path; `!op read` lives in `models.json`, which pi-nix can install but never reads itself.
- "No secret enters the Nix store" — Global Constraints plus Task 7 Step 4, which greps the entire closure for four credential shapes and asserts that the only credential-adjacent strings present are `/run/agenix/*` paths and `op://` references.
- "statusline… so both agents render the same line" — Task 5, achieved by overriding nothing and asserted by rendering both option sets through the same phase-1 `renderConfig`.
- "Enable the jail" — Task 1 Step 3 (`jail.enable = jailed`), with the machine-specific binds in Task 4.
- "`programs.agent-skills.autoMode` shared rules with a starter rule set" — Task 6, forty-four rules drafted against this machine: NixOS + nix-darwin, fish, 1Password SSH agent with no key files on disk, agenix at `/run/agenix`, self-hosted garnix, ~70 repos under `~/Development`.
- "Verification tasks must include a real `nix build` of the home-manager activation package and inspection of the generated pi config" — Task 7 Steps 1–3. Step 1's attribute path was executed against the live repo while writing this plan and returns `/nix/store/m1famg337z124ig6giw7bm818kncppii-home-manager-generation` today.

**Two findings that changed the design, both from reading the sources rather than the spec.**

1. *The jail wraps the wrapper.* `finalPackage = jailBuilder "pi" wrapped permissions` bubblewraps the entire `writeShellScriptBin "pi"`, so `envPrelude`'s `cat /run/agenix/…` executes inside the sandbox. jail.nix's base permissions include `bind-nix-store-runtime-closure`, which binds only the closure's store paths and never mounts `/nix/store` whole. Without Task 4 the auth wiring from Task 3 would fail silently at every launch with an empty key. This also means the `!op read` path cannot work under the jail at all — `op` needs the desktop socket and biometric unlock, and binding those would hand the agent the whole vault — which is why Task 4 Step 6 writes that limitation into the module.
2. *Upstream's `models` option installs once and never updates* (`if [ ! -f "$PI_CODING_AGENT_DIR/models.json" ]`), and its prelude actively `rm`s a symlink at that path. So neither `programs.pi.coding-agent.models` nor `home.file` is usable; Task 3 installs a real 0600 file from an activation script instead.

**Placeholder scan.** Every code block is complete Nix, JSON, or shell — no `…`, no `TODO`, no invented option names. Concrete values were taken from the live repo, not guessed: `/run/agenix/<name>` matches the existing `notion_token_file` and `GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE` usages; the expected `statusline-config.json` in Task 5 Step 1 is the file currently at `/nix/store/zfkwvg5bqqf0r88qa7m6j5hkwadljm5y-claude-config/statusline-config.json`; the `-claude-config` derivation name comes from `claude-nix/lib/mkClaudeConfig.nix:50`; the "2 shipped `allow` rules" baseline in Task 6 was read out of that same settings.json. The jail combinator names (`try-readonly`, `try-readwrite`, `add-pkg-deps`, `noescape`) were confirmed against `~alexdavid/jail.nix` at the rev pinned in `pi-nix/flake.lock`.

**Type consistency.** `environment.<NAME>` is written as `{ file = "<string>"; }` everywhere, matching `options.nix`'s `attrTag { file : either str nixPath; value : str; }` — and deliberately never as `{ value = …; }`, which would be a store literal. `jail.permissions` is always a `combinators: [ … ]` lambda, matching `functionTo (listOf raw)`, and `lib.mkIf` wraps the whole lambda rather than appearing inside it. `programs.agent-skills.autoMode`'s four keys use `claude-nix`'s exact names (`allow`, `soft_deny`, `hard_deny`, `environment` — snake_case, not camelCase) and each is a `listOf str`. `statusline.enable` and `statusLine.enable` differ in case between pi-nix and claude-nix; both spellings are used against their own namespace throughout, and Task 5's verification exercises both in one expression, so a typo fails loudly.

**Known gaps carried forward.**

- *One live assumption*, flagged at its point of use in Task 3 Step 1 and resolved by Task 3 Step 8: pi's docs demonstrate overriding a built-in provider with `baseUrl` only, never with `apiKey` only. The fallback (adding each provider's public `baseUrl`) is written out, so the fix is a substitution rather than a redesign.
- *Task 4 Step 1 is a branch point.* This plan composes phase 3's `jail.permissions` default rather than restating it, using `options.programs.pi.coding-agent.jail.permissions.default`. If phase 3 ships a dedicated additive option, Step 1 catches it and Step 3 should use that instead.
- *`systemPrompt` is not set here.* Design §12 routes `core + shared + pi` into `--system-prompt`, but phases 4 and 5 own that wiring inside `agent-skills`; dotfiles has nothing to declare. Task 7 Step 3's inspection of the inner wrapper is where a missing `--system-prompt` flag would surface.
- *The `pr` widget under pi remains design assumption A5.* Task 4 binds `~/.config/gh` and adds `pkgs.gh` to the jailed PATH so the extension *can* shell out, but phase 1 explicitly ships the field unpopulated, so the widget will hide until that changes. The binds are harmless and ready.
- *No new flake inputs.* Task 1 Step 1 verifies rather than assumes this: `dotfiles` reaches every agent repo through the single `agent-skills` input, and `claude-nix`/`codex-nix`/`antigravity-cli-nix` are not inputs today. `pi-nix` and `agent-statusline` follow the same route. Step 1's grep is written to fail loudly if that convention ever changes.
