# The macOS half of `re-shell`: a disposable NixOS microVM, one per launch,
# that shares the directory the launcher ran in and enters the x86_64-linux
# re-shell devShell inside it under Rosetta.
#
# Why a VM at all: the shell is x86_64-linux, and a third of it (wine, i2c-dev,
# hidraw, v4l2, pe-bear, detect-it-easy) has no macOS build or no macOS kernel
# interface to drive. Emulating the tools individually would fork the toolchain;
# a Linux guest keeps one shell definition for both platforms.
#
# Why no ssh: vfkit's networking is NAT-only, and microvm.nix's vfkit runner
# throws on both bridge networking ("requires vmnet-helper which is not yet
# implemented") and vsock. The guest console is therefore the terminal that ran
# `re-shell`, which is also why the VM powers off when the shell exits.
{ nixpkgs, microvm }:
{
  # Host directory shared as /work — where `re-shell` was launched.
  workdir,
  # Host directory holding the persistent volume images.
  stateDir,
  # Per-session host directory shared as /run/re-shell, carrying the command to
  # run (if any) in and the guest's exit status back out.
  ctlDir,
  # Absolute path for vfkit's control socket. microvm.socket defaults to a
  # relative "<hostName>.sock", which the runner would create in the directory
  # the analysis is happening in.
  socketPath,
  # Flake reference the guest takes the devShell from.
  flakeRef,
  hostSystem,
  # A local agent-skills checkout to share as /flake, for `re-shell -f <path>`.
  # The guest cannot see host paths that are not shared, so a path flakeRef has
  # to travel as a share rather than as a reference.
  flakeDir ? null,
  vcpu ? 6,
  mem ? 8192,
  storeSize ? 81920,
}:
let
  inherit (nixpkgs) lib;

  # Virtualization.framework runs same-architecture guests only, so the guest
  # is aarch64-linux on Apple silicon and the x86_64-linux toolchain inside it
  # runs through Rosetta's binfmt handler.
  guestSystem = builtins.replaceStrings [ "-darwin" ] [ "-linux" ] hostSystem;

  guest =
    { config, pkgs, ... }:
    let
      shellRef = "${if flakeDir != null then "/flake" else flakeRef}#devShells.x86_64-linux.re-shell";

      # Runs on the console instead of a login shell. The control share is the
      # only channel back to the host: the runner's exit status is vfkit's, not
      # the guest's, and the console carries boot logs interleaved with output,
      # which is unusable for `re-shell cmd | ...`. So a command's streams are
      # captured to files the launcher replays, and only an interactive session
      # talks to the console directly.
      enter = pkgs.writeShellScript "re-shell-enter" ''
        if ! ${pkgs.util-linux}/bin/mountpoint -q /run/re-shell; then
          echo "re-shell: control share is not mounted; the host cannot see this session" >&2
        fi
        cd /work || exit 1
        if [ -r /run/re-shell/cmd ]; then
          # bash -c, not -lc: a login shell would source the profile this
          # script is called from and enter the devShell again, once per level,
          # until execve gives up with E2BIG. The devShell has already set PATH
          # by then, so there is nothing a login profile needs to add.
          nix develop ${lib.escapeShellArg shellRef} \
            --command bash -c "$(cat /run/re-shell/cmd)" \
            > /run/re-shell/out 2> /run/re-shell/err
        else
          # bash -i, not bash: without it the inner shell runs without job
          # control, so Ctrl-C is delivered to the whole foreground group —
          # killing the session and powering off the VM instead of stopping the
          # tool that is running. Ctrl-C on a long analysis is not optional.
          nix develop ${lib.escapeShellArg shellRef} --command bash -i
        fi
        status=$?
        echo "$status" > /run/re-shell/status
        exit "$status"
      '';
    in
    {
      system.stateVersion = lib.trivial.release;

      networking = {
        hostName = "re-vm";
        # NAT for substituters and for whatever the analysis talks to. Nothing
        # can reach in — vfkit does not forward host ports to the guest.
        interfaces.eth0.useDHCP = true;
        firewall.enable = false;
      };

      services.getty.autologinUser = "root";

      # The console login and the virtiofs mounts are both wanted by
      # multi-user.target, so without this the shell can start before /work and
      # the control share exist: it then finds no command to run, falls through
      # to the interactive branch, reads EOF, and exits — and agetty respawns it
      # for a second helping. Ordering only, never Requires: a failed mount
      # should still leave a console to diagnose it from.
      systemd.services."serial-getty@hvc0".after = [
        "work.mount"
        "run-re\\x2dshell.mount"
      ];

      microvm = {
        hypervisor = "vfkit";
        inherit vcpu mem;
        socket = socketPath;
        # The runner is a darwin package driving vfkit; only the guest closure
        # is Linux.
        vmHostPackages = nixpkgs.legacyPackages.${hostSystem};
        vfkit.rosetta = {
          enable = true;
          # The x86_64 half of the toolchain is the point of the VM; if Rosetta
          # is missing, prompt for it rather than boot a guest that cannot run
          # a single tool.
          install = true;
        };

        interfaces = [
          {
            type = "user";
            id = "eth0";
            mac = "02:52:45:53:48:01";
          }
        ];

        shares = [
          {
            proto = "virtiofs";
            tag = "work";
            source = workdir;
            mountPoint = "/work";
          }
          {
            proto = "virtiofs";
            tag = "ctl";
            source = ctlDir;
            mountPoint = "/run/re-shell";
          }
        ]
        ++ lib.optional (flakeDir != null) {
          proto = "virtiofs";
          tag = "flake";
          source = flakeDir;
          mountPoint = "/flake";
        };

        # The guest store is its own — the host's /nix/store is deliberately
        # not shared, so a sample that gets loose cannot read it. Everything the
        # devShell pulls lands in the overlay volume and survives the VM.
        writableStoreOverlay = "/nix/.rw-store";
        volumes = [
          {
            image = "${stateDir}/store-overlay.img";
            label = "re-store";
            mountPoint = "/nix/.rw-store";
            size = storeSize;
          }
          {
            image = "${stateDir}/nix-var.img";
            label = "re-var";
            mountPoint = "/nix/var";
            size = 4096;
          }
        ];
      };

      # /nix/var carries the Nix database, and stage-2 replays the system
      # closure's registration into it via boot.postBootCommands before systemd
      # mounts anything. Without neededForBoot the volume lands on top of that
      # registration, the database the guest reads is empty, and every boot
      # re-downloads what the last one already wrote to the overlay.
      fileSystems."/nix/var".neededForBoot = true;

      # Frida is the one part of the toolchain Rosetta cannot run: every entry
      # point (the python module, frida, frida-ps, frida-trace) dies on
      # "Unimplemented syscall number 284" — eventfd. A native aarch64 build
      # sits outside the devShell at /run/current-system/sw/bin so the
      # dynamic-instrumentation workflow has something that works; the shell's
      # own x86_64 frida still shadows it on PATH, which the skills call out.
      environment.systemPackages = [ pkgs.frida-tools ];

      # microvm's root filesystem is a tmpfs sized at half of guest RAM, and a
      # Nix build scratch directory defaults onto it — so building anything
      # substantial in the shell (a tool added to the devShell, a from-source
      # fallback) is charged against the same RAM the tools are using, and the
      # VM dies rather than the build. Put the scratch on the persistent volume
      # instead, where the space is disk and survives nothing but also costs
      # nothing.
      systemd.tmpfiles.rules = [ "d /nix/var/re-builds 0755 root root - -" ];

      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        build-dir = "/nix/var/re-builds";
      };

      # Autologin lands on hvc0; anything else (a graphics console, a rescue
      # tty) gets a plain root shell rather than a shell that powers the
      # machine off when it exits.
      # RE_SHELL_ACTIVE belts the braces on `bash -c`: any login shell started
      # from inside the session — a script, a tool that shells out — would
      # otherwise re-enter here rather than run.
      programs.bash.loginShellInit = ''
        if [ "$(tty)" = /dev/hvc0 ] && [ -z "''${RE_SHELL_ACTIVE:-}" ]; then
          export RE_SHELL_ACTIVE=1
          ${enter}
          exec ${config.systemd.package}/bin/systemctl poweroff
        fi
      '';
    };
in
(lib.nixosSystem {
  system = guestSystem;
  modules = [
    microvm.nixosModules.microvm
    guest
  ];
}).config.microvm.declaredRunner
