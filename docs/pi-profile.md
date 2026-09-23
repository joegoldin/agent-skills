# Personal Pi profile

`homeManagerModules.pi` wraps pi-nix with the personal configuration in
`modules/pi-profile.nix`, the shared prompt and skills, and the selected
extensions. Importing it also imports the shared agent-skills module.

```nix
imports = [ inputs.agent-skills.homeManagerModules.pi ];
programs.pi.coding-agent.enable = true;
```

Keep host integration in the consuming configuration: secret file locations,
macOS credential commands, the host's audiomemo package and voice keys, and
machine-specific permission policy. Additional provider definitions go in
`programs.agent-skills.pi.providers`; credentials must be environment names
or commands, never literal keys.

pi-nix owns the Pi release, extension versions, and public module defaults.
This repository owns extension selection, personal settings, keybindings,
shell shortcuts, prompts, and skills. Dotfiles does not select the extension
list or override the pi-nix input.

After publishing a pi-nix update, run `nix flake update pi-nix` here and publish
the resulting lockfile. Consumers run `nix flake update agent-skills` to adopt
the whole profile and its dependencies. A consumer's lockfile records the
transitive Pi revision for reproducibility; it is not another version choice.
Changes in local checkouts can be tested with `--override-input` and
`--no-write-lock-file` before publication.

Routine implementation does not require a written plan. `/brainstorming` and
`/writing-plans` are explicit workflows; their bodies also support direct user
requests for brainstorming or a written plan. The skills bootstrap explains
selection and loading without imposing a chain of process skills.
