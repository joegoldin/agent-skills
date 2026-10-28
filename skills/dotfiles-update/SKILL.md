---
name: dotfiles-update
description: Prepares a targeted dotfiles input update from local dependency changes. Use when asked to publish the required dependencies and leave dotfiles committed locally, ready for a machine build.
disable-model-invocation: true
argument-hint: "[input or dependency repository]"
---

# Dotfiles Update

Publish the requested dependency changes, then leave dotfiles ready to build
with only the relevant inputs updated. Default endpoint: dependencies pushed,
dotfiles committed locally but not pushed, no machine build or activation.
An explicit instruction to push dotfiles or build the machine changes that
endpoint; otherwise stop at the local commit.

## Follow the dependency path

1. Identify the requested input from the conversation or arguments. Read
   `flake.nix` and `flake.lock` in dotfiles and the relevant dependency repositories.
   Trace nested inputs and `follows` edges rather than assuming a root-level pin.
   Use the existing checkouts; inspect their VCS state before writing. Use jj
   where `.jj/` exists, git otherwise.
2. Work from the deepest changed dependency outward. Verify the scoped changes,
   commit them without unrelated work, push the intended branch/bookmark, and
   confirm the remote revision. Reuse passing checks when their inputs match.
   Do not point a published consumer at an unpublished dependency revision.
3. Update an intermediate repository's required input when its release needs
   that dependency. Preserve its other pins, check the consumer, then commit and
   push it. A dependency-first release does not require updating every input in
   every repository.
4. Update only the requested dotfiles input paths to the published revisions.
   For example, `nix flake update agent-skills/pi-nix` targets a nested Pi pin;
   updating `agent-skills` itself is appropriate when shipping a new skill.
   Follow the actual lock graph, including intentional nested overrides.

## Keep the machine update narrow

Compare the lock graph before and after, not just renamed node keys. Confirm
that the requested revisions resolve and that unrelated pins—including the
machine's nixpkgs inputs—are unchanged. A parent input update can import new
transitive pins: inspect that closure and retain existing unrelated overrides
rather than accepting a whole-flake refresh. If a changed input declaration
requires a wider update, explain the dependency and get a scope decision.

Run focused evaluation or package checks for the affected inputs. Never use a
bare `nix flake update`, update all lock inputs, or run `switch` as a shortcut.
Commit only the scoped dotfiles changes. Do not push that commit by default.

Finish with the dependency commits and push results, the exact updated input
paths, the local dotfiles commit, and verification results. State that dotfiles
was not pushed and the machine was not built or activated. Leave unrelated
working-copy changes intact.
