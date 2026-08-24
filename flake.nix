{
  description = "Agent skills, commands, and hooks for Claude, Antigravity, and Codex";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    claude-nix = {
      url = "github:joegoldin/claude-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    antigravity-cli-nix = {
      url = "github:joegoldin/antigravity-cli-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    codex-nix = {
      # github: (not git+ssh) so CI — garnix injects its app token for github:
      # refs but has no SSH key — and tokenized local nix can fetch it.
      url = "github:joegoldin/codex-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pi-nix = {
      # github: (not git+ssh) for the same reason codex-nix uses it — garnix
      # injects its app token for github: refs but has no SSH key.
      url = "github:joegoldin/pi-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ── re-shell reverse-engineering devShell inputs ──
    # Only the `devShells.<linux>.re-shell` output uses these; the plugin
    # builds do not. See ATTRIBUTION.md (schlarpc/re-shell).
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      claude-nix,
      antigravity-cli-nix,
      codex-nix,
      pi-nix,
      pyproject-nix,
      uv2nix,
      pyproject-build-systems,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f {
            pkgs = import nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };
            inherit system;
          }
        );

      # ── re-shell devShell plumbing ──
      # The RE toolchain is heavy, unfree, and Linux-only, so it ships as an
      # opt-in `nix develop .#re-shell` rather than riding into the plugin
      # buildEnv. These bindings are system-independent (they only read the
      # workspace files) and are forced only by the Linux devShells below.
      # x86_64-linux only: the toolchain is x86_64-centric and several tools
      # (e.g. aapt) have no aarch64-linux build, so an aarch64 shell would fail
      # to even evaluate.
      reShellSystems = [ "x86_64-linux" ];
      reWorkspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };
      rePyOverlay = reWorkspace.mkPyprojectOverlay { sourcePreference = "wheel"; };
    in
    {
      packages = forAllSystems (
        { pkgs, ... }:
        let
          lib = pkgs.lib;
          claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
          agyLib = import "${antigravity-cli-nix}/lib" { inherit pkgs lib; };
          codexLib = import "${codex-nix}/lib" { inherit pkgs lib; };
          piLib = import "${pi-nix}/lib" { inherit pkgs lib; };
          build = import ./lib/default.nix {
            inherit
              pkgs
              lib
              claudeLib
              agyLib
              codexLib
              piLib
              ;
          };

          skills = build.discoverSkills ./skills;

          promptLib = import ./lib/prompt.nix { inherit lib; };
          sharedPromptText = promptLib.mkPrompt { layers = [ ./prompt/shared ]; };
          piPromptText = promptLib.mkPrompt {
            layers = [
              ./prompt/core
              ./prompt/shared
              ./prompt/pi
            ];
          };

          vibecad = pkgs.callPackage ./packages/vibecad { };
          pxd = pkgs.callPackage ./packages/pxd { };
          figr = pkgs.callPackage ./packages/figr { };
          avoidAiDetect = pkgs.callPackage ./packages/avoid-ai-detect { };

          # ── Claude plugin ──
          # Skill-owned tool packages (figr, pxd, vibecad, avoid-ai-detect)
          # ride in via each skill's sidecar `packages`, not extraPackages.
          claude-plugin = build.buildPlugin {
            name = "agent-skills";
            description = "Agent skills, commands, and agents";
            inherit skills;
            hooksDir = ./hooks;
            attributionFile = ./ATTRIBUTION.md;
          };

          # ── Antigravity plugin ──
          antigravity-plugin = build.buildAntigravityPlugin {
            name = "agent-skills";
            description = "Agent skills for Antigravity CLI";
            inherit skills;
            hooksDir = ./hooks;
            attributionFile = ./ATTRIBUTION.md;
          };

          # ── Codex plugin ──
          codex-plugin = build.buildCodexPlugin {
            name = "agent-skills";
            description = "Agent skills for Codex";
            inherit skills;
            hooksDir = ./hooks;
            attributionFile = ./ATTRIBUTION.md;
          };

          # ── pi package ──
          # Skills ride in as the same per-skill derivations the Claude
          # plugin ships, which is what makes the ~/.agents/skills double
          # load free (design §11, assumption A3).
          pi-plugin = build.buildPiPlugin {
            name = "agent-skills";
            description = "Agent skills for pi";
            inherit skills;
            extensionsDir = ./extensions;
            attributionFile = ./ATTRIBUTION.md;
          };

          # ── Cross-agent plugins (temporal) ──
          # Discovered from ./plugins; built per target. Exposed as
          # "<name>-<target>" packages (e.g. temporal-claude, temporal-codex).
          targetLibs = {
            claude = claudeLib;
            antigravity = agyLib;
            codex = codexLib;
            pi = piLib;
          };
          discoveredPlugins = build.discoverPlugins ./plugins;
          crossPlugins = lib.listToAttrs (
            lib.concatMap
              (
                target:
                map (p: {
                  name = "${p.name}-${target}";
                  value = build.mkCrossAgentPlugin {
                    def = p.raw { inherit pkgs lib target; };
                    inherit target;
                    targetLib = targetLibs.${target};
                    attributionFile = ./ATTRIBUTION.md;
                  };
                }) discoveredPlugins
              )
              [
                "claude"
                "antigravity"
                "codex"
                "pi"
              ]
          );

          perSkillPackages = lib.listToAttrs (
            map (s: {
              name = s.name;
              value = s.drv;
            }) skills
          );

          # ── Web/app uploadable skills bundle ──
          # One folder per skill (folder = zip root for the Claude web/app
          # "Customize > Skills" upload format). avoid-ai-writing ships its
          # Node detector vendored into scripts/ so it runs in the sandbox.
          web-skills = build.buildWebBundle {
            inherit skills;
            avoidAiDetectSrc = ./packages/avoid-ai-detect;
          };

          # One zip per skill (zip root = exactly one folder + one SKILL.md), the layout
          # the Claude web "Customize > Skills" upload UI requires. Published as a
          # garnix artifact (garnix.yaml `artifacts:`), replacing the GitHub workflow.
          web-skills-zips = pkgs.runCommand "web-skills-zips" { nativeBuildInputs = [ pkgs.zip ]; } ''
            mkdir -p $out staging
            cp -rL ${web-skills}/. staging/
            chmod -R u+w staging
            cd staging
            for name in */; do
              name="''${name%/}"
              zip -q -r -X "$out/$name.zip" "$name"
            done
          '';
        in
        perSkillPackages
        // crossPlugins
        // {
          default = claude-plugin;
          inherit web-skills web-skills-zips;
          prompt-shared = pkgs.writeText "agent-skills-shared-prompt.md" sharedPromptText;
          prompt-pi = pkgs.writeText "agent-skills-pi-SYSTEM.md" piPromptText;
          avoid-ai-detect = avoidAiDetect;
          inherit
            claude-plugin
            antigravity-plugin
            codex-plugin
            pi-plugin
            vibecad
            pxd
            figr
            ;
        }
      );

      # ── re-shell reverse-engineering devShell (Linux only) ──
      # Faithful port of schlarpc/re-shell's dev environment: the general RE
      # toolchain plus the android/windows/web discipline tools, a uv2nix-built
      # Python venv, and the apk-mitm Node tool. Entered with
      # `nix develop github:joegoldin/agent-skills#re-shell`. Documented by the
      # reverse-engineering, android-re, windows-re, and web-re skills.
      devShells = nixpkgs.lib.genAttrs reShellSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          lib = pkgs.lib;
          python = pkgs.python3;

          nodeModules = pkgs.importNpmLock.buildNodeModules {
            npmRoot = self;
            inherit (pkgs) nodejs;
          };

          pythonSet =
            (pkgs.callPackage pyproject-nix.build.packages {
              inherit python;
            }).overrideScope
              (
                lib.composeManyExtensions [
                  pyproject-build-systems.overlays.default
                  rePyOverlay
                  # Add dependency fixups here as needed, e.g.:
                  # (_final: prev: {
                  #   some-package = prev.some-package.overrideAttrs (old: {
                  #     buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.some-lib ];
                  #   });
                  # })
                ]
              );

          venv = pythonSet.mkVirtualEnv "re-env" reWorkspace.deps.default;

          # A dir-of-symlinks of common wordlists/rules linked into
          # $PWD/wordlists by the shellHook so cracking tools don't need
          # /nix/store paths. Add more entries here as needed.
          wordlists = pkgs.linkFarm "re-wordlists" [
            {
              name = "rockyou.txt";
              path = "${pkgs.rockyou}/share/wordlists/rockyou.txt";
            }
            {
              name = "seclists";
              path = "${pkgs.seclists}/share/wordlists/seclists";
            }
            {
              name = "john-password.lst";
              path = "${pkgs.john}/share/john/password.lst";
            }
            {
              name = "hashcat-rules";
              path = "${pkgs.hashcat}/share/doc/hashcat/rules";
            }
            {
              name = "john-rules";
              path = "${pkgs.john}/share/john/rules";
            }
            {
              # best64.rule ships with john (not this hashcat build)
              name = "best64.rule";
              path = "${pkgs.john}/share/john/rules/best64.rule";
            }
          ];
        in
        {
          re-shell = pkgs.mkShell {
            packages = [
              venv
              pkgs.uv
              pkgs.nodejs
              pkgs.importNpmLock.hooks.linkNodeModulesHook

              # --- General: native binary reverse engineering ---
              pkgs.ghidra # NSA's SRE suite (disassembler + decompiler)
              pkgs.radare2 # UNIX-like RE framework and CLI toolset
              pkgs.rizin # Modern fork of radare2
              pkgs.binwalk # Firmware/binary analysis and extraction

              # --- General: dynamic instrumentation ---
              pkgs.frida-tools # frida, frida-ps, frida-trace, etc.

              # --- General: static analysis ---
              pkgs.yara # Pattern matching for malware research

              # --- General: network interception & discovery ---
              pkgs.mitmproxy # HTTPS man-in-the-middle proxy
              pkgs.wireshark-cli # tshark
              pkgs.nmap # Host/port/service discovery
              pkgs.avahi # avahi-browse - mDNS/DNS-SD discovery

              # --- General: utilities ---
              pkgs.unzip
              pkgs.p7zip
              pkgs.binutils # strings/nm/objdump/readelf
              pkgs.file
              pkgs.curl
              pkgs.jq
              pkgs.sqlite
              pkgs.openssl
              pkgs.upx # Executable packer/unpacker
              pkgs.unixtools.xxd
              pkgs.exiftool
              pkgs.innoextract # Inno Setup installer extraction
              pkgs.asar # Electron app.asar archives

              # --- General: display / monitor firmware ---
              pkgs.v4l-utils # edid-decode
              pkgs.ddcutil # DDC/CI VCP codes
              pkgs.i2c-tools # raw I2C frames

              # --- General: USB ---
              pkgs.libusb1 # backend for pyusb
              pkgs.usbutils # lsusb -v, usbhid-dump
              pkgs.hid-tools # hid-decode/hid-recorder/hid-replay

              # --- General: password / hash cracking ---
              pkgs.hashcat
              pkgs.john # John the Ripper (Jumbo)

              # --- General: FPGA bitstream & netlist analysis ---
              pkgs.trellis # ecpunpack/ecppack (Lattice ECP5)
              pkgs.yosys
              pkgs.hal-hardware-analyzer

              # --- General: embedded / RP2040-RP2350 (Pico) firmware ---
              pkgs.picotool
              pkgs.pico-sdk
              pkgs.cmake
              pkgs.gcc-arm-embedded

              # --- Android: APK disassembly & manipulation ---
              pkgs.apktool
              pkgs.apkeditor
              pkgs.apksigner
              pkgs.apksigcopier
              pkgs.apkid
              pkgs.aapt
              pkgs.bundletool

              # --- Android: Java/DEX decompilation ---
              pkgs.jadx
              pkgs.dex2jar
              pkgs.bytecode-viewer

              # --- Android: dynamic instrumentation ---
              pkgs.jnitrace

              # --- Android: static analysis & security scanning ---
              pkgs.trueseeing
              pkgs.quark-engine
              pkgs.koodousfinder

              # --- Android: ADB & device interaction ---
              pkgs.android-tools # ADB + fastboot
              pkgs.scrcpy

              # --- Android: image & OTA tools ---
              pkgs.simg2img
              pkgs.sdat2img
              pkgs.payload-dumper-go
              pkgs.imgpatchtools

              # --- Windows: PE analysis & inspection ---
              pkgs.pe-bear
              pkgs.detect-it-easy # diec
              pkgs.imhex

              # --- Windows: .NET decompilation ---
              pkgs.ilspycmd
              pkgs.avalonia-ilspy # ILSpy

              # --- Windows: string & capability analysis ---
              pkgs.flare-floss # floss

              # --- Windows: memory forensics ---
              pkgs.volatility3

              # --- Windows: archive & installer extraction ---
              pkgs.cabextract
              pkgs.msitools # msiinfo/msiextract

              # --- Windows: signing & verification ---
              pkgs.osslsigncode

              # --- Windows: running Windows binaries ---
              pkgs.wineWow64Packages.stable
              pkgs.winetricks

              # --- Web: protocol buffers & gRPC ---
              pkgs.protobuf # protoc
              pkgs.protoscope
              pkgs.grpcurl
              pkgs.grpcui

              # --- Web: HTTP & TLS ---
              pkgs.curl-impersonate
              pkgs.httpie

              # --- Web: WebSocket ---
              pkgs.websocat

              # --- Web: HTML parsing ---
              pkgs.pup
            ];

            npmDeps = nodeModules;

            env = {
              GHIDRA_JAVA_HOME = "${pkgs.jdk}/lib/openjdk";
              GHIDRA_INSTALL_DIR = "${pkgs.ghidra}/lib/ghidra";
              PICO_SDK_PATH = "${pkgs.pico-sdk}/lib/pico-sdk";
              # pyusb resolves its backend with ctypes.util.find_library, which
              # finds nothing on NixOS. Point it at the shared object directly.
              LIBUSB1_SO = "${pkgs.libusb1}/lib/libusb-1.0.so";
              # Nix manages the venv; keep uv from creating/downloading its own.
              UV_NO_SYNC = "1";
              UV_PYTHON = "${venv}/bin/python";
              UV_PYTHON_DOWNLOADS = "never";
            };

            shellHook = ''
              unset PYTHONPATH
              if [ -d "$npmDeps/node_modules" ]; then
                linkNodeModulesHook
              fi
              # Stable wordlists/ symlink at the working dir (gitignored).
              ln -sfn ${wordlists} "$PWD/wordlists"
              # pyghidra/JPype spill large temp files into java.io.tmpdir; the
              # default /tmp tmpfs is too small and it crashes on big programs,
              # so keep JVM scratch working-dir-local (gitignored).
              mkdir -p "$PWD/tmp/jtmp"
              case "''${_JAVA_OPTIONS-}" in
                *-Djava.io.tmpdir=*) ;;
                *) export _JAVA_OPTIONS="-Djava.io.tmpdir=$PWD/tmp/jtmp''${_JAVA_OPTIONS:+ $_JAVA_OPTIONS}" ;;
              esac
              echo "re-shell RE environment loaded. See the reverse-engineering, android-re, windows-re, and web-re skills for tool docs."
            '';
          };
        }
      );

      checks = forAllSystems (
        { pkgs, system, ... }:
        let
          lib = pkgs.lib;
          mcp = import ./lib/mcp.nix { inherit lib; };
          # Fill submodule defaults exactly as the real option does.
          servers =
            (lib.evalModules {
              modules = [
                {
                  options.servers = lib.mkOption { type = lib.types.attrsOf mcp.normalizedModule; };
                  config.servers = {
                    ctx = {
                      command = "npx";
                      args = [
                        "-y"
                        "ctx"
                      ];
                    };
                    remote = {
                      url = "https://x/mcp";
                      headers.Authorization = "Bearer Y";
                      bearerTokenEnvVar = "TOK";
                    };
                    off = {
                      command = "nope";
                      disabled = true;
                    };
                  };
                }
              ];
            }).config.servers;
          claudeJson = pkgs.writeText "claude-mcp.json" (builtins.toJSON (mcp.mcpNativeFor "claude" servers));
          agyJson = pkgs.writeText "agy-mcp.json" (builtins.toJSON (mcp.mcpNativeFor "antigravity" servers));
          codexJson = pkgs.writeText "codex-mcp.json" (builtins.toJSON (mcp.mcpNativeFor "codex" servers));
          piJson = pkgs.writeText "pi-mcp.json" (builtins.toJSON (mcp.mcpNativeFor "pi" servers));
        in
        {
          mcp-standalone-tests = import ./tests/mcp-standalone-test.nix { inherit pkgs; };
          eval-mcp = pkgs.runCommand "eval-mcp" { nativeBuildInputs = [ pkgs.jq ]; } ''
            # disabled servers are omitted from every target
            jq -e 'has("off") | not' ${claudeJson} >/dev/null
            jq -e 'has("off") | not' ${agyJson} >/dev/null
            jq -e 'has("off") | not' ${codexJson} >/dev/null

            # stdio is identical across all four targets
            jq -e '.ctx.command == "npx" and (.ctx.args == ["-y","ctx"])' ${claudeJson} >/dev/null
            jq -e '.ctx.command == "npx"' ${agyJson} >/dev/null
            jq -e '.ctx.command == "npx"' ${codexJson} >/dev/null

            # claude remote → type:"http" + url + headers
            jq -e '.remote.type == "http" and .remote.url == "https://x/mcp" and .remote.headers.Authorization == "Bearer Y"' ${claudeJson} >/dev/null

            # antigravity remote → serverUrl (no url), + headers
            jq -e '.remote.serverUrl == "https://x/mcp" and (.remote | has("url") | not)' ${agyJson} >/dev/null

            # codex remote → url + bearer_token_env_var + http_headers (no headers/type)
            jq -e '.remote.url == "https://x/mcp" and .remote.bearer_token_env_var == "TOK" and .remote.http_headers.Authorization == "Bearer Y"' ${codexJson} >/dev/null
            jq -e '.remote | (has("type") | not) and (has("serverUrl") | not)' ${codexJson} >/dev/null

            # disabled servers are omitted from the pi target too
            jq -e 'has("off") | not' ${piJson} >/dev/null
            jq -e '.ctx.command == "npx" and (.ctx.args == ["-y","ctx"])' ${piJson} >/dev/null

            # pi remote -> pi-mcp-adapter shape: url + headers + auth/bearerTokenEnv
            jq -e '.remote.url == "https://x/mcp" and .remote.headers.Authorization == "Bearer Y"' ${piJson} >/dev/null
            jq -e '.remote.auth == "bearer" and .remote.bearerTokenEnv == "TOK"' ${piJson} >/dev/null

            # pi must not inherit any other target's remote spelling
            jq -e '.remote | (has("type") | not) and (has("serverUrl") | not) and (has("bearer_token_env_var") | not) and (has("http_headers") | not)' ${piJson} >/dev/null

            touch $out
          '';

          frontmatter-tests =
            let
              failures = import ./lib/frontmatter-tests.nix { inherit lib; };
            in
            if failures == [ ] then
              pkgs.runCommand "frontmatter-tests" { } "touch $out"
            else
              throw "frontmatter tests failed: ${builtins.toJSON failures}";

          lint-tests =
            let
              failures = import ./lib/lint-tests.nix { inherit lib; };
            in
            if failures == [ ] then
              pkgs.runCommand "lint-tests" { } "touch $out"
            else
              throw "lint tests failed: ${builtins.toJSON failures}";

          # Every shipped skill must load into pi without a diagnostic. The
          # agent-skills rules are strictly stricter than pi's, so this
          # should never fire — it fires only if that stops being true.
          pi-frontmatter =
            let
              lintLib = import ./lib/lint.nix { inherit lib; };
              build = import ./lib/default.nix {
                inherit pkgs lib;
                claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
              };
              skills = build.discoverSkills ./skills;
              offenders = lib.concatMap (
                s:
                map (w: "${s.name}: ${w}") (
                  lintLib.piSkillWarnings {
                    dirName = s.name;
                    inherit (s) parsed;
                  }
                )
              ) skills;
            in
            if offenders == [ ] then
              pkgs.runCommand "pi-frontmatter" { } "touch $out"
            else
              throw "pi frontmatter violations: ${builtins.toJSON offenders}";

          # ── A3 gate ──
          # pi de-duplicates skills by canonicalised real path BEFORE it
          # de-duplicates by name (skills.ts loadSkills: realPathSet is
          # consulted first, and a hit is skipped silently; a name hit that
          # is not a real-path hit raises a startup collision warning).
          # ~/.agents/skills and the pi package therefore cost nothing only
          # while both bottom out at the same skill-<name> derivation.
          # A cp -r in buildPiPlugin would still "work" and would still
          # de-duplicate — it would just print one warning per skill on every
          # session start. This check is the only thing that notices.
          pi-skill-realpath-identity =
            let
              piTree = self.packages.${system}.pi-plugin;
              claudeTree = self.packages.${system}.claude-plugin;
              build = import ./lib/default.nix {
                inherit pkgs lib;
                claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
              };
              skills = build.discoverSkills ./skills;
            in
            pkgs.runCommand "pi-skill-realpath-identity"
              {
                inherit piTree claudeTree;
                names = lib.concatStringsSep " " (map (s: s.name) skills);
                sources = lib.concatStringsSep " " (map (s: "${s.name}=${s.drv}") skills);
              }
              ''
                fail=0
                for pair in $sources; do
                  n="''${pair%%=*}"
                  drv="''${pair#*=}"
                  want="$(realpath "$drv/skills/$n/SKILL.md")"
                  got_pi="$(realpath "$piTree/skills/$n/SKILL.md")"
                  got_cc="$(realpath "$claudeTree/skills/$n/SKILL.md")"
                  if [ "$got_pi" != "$want" ]; then
                    echo "pi package copies '$n' instead of linking it:"
                    echo "  want $want"
                    echo "  got  $got_pi"
                    fail=1
                  fi
                  if [ "$got_pi" != "$got_cc" ]; then
                    echo "realpath drift between pi and claude trees for '$n':"
                    echo "  pi     $got_pi"
                    echo "  claude $got_cc"
                    fail=1
                  fi
                done
                [ "$fail" = 0 ] || exit 1
                touch $out
              '';

          # The pi manifest must be present and well-formed; pi's
          # readPiManifest returns null (and silently falls back to
          # convention directories) for anything it cannot parse.
          pi-package-manifest =
            let
              piTree = self.packages.${system}.pi-plugin;
            in
            pkgs.runCommand "pi-package-manifest" { nativeBuildInputs = [ pkgs.jq ]; } ''
              jq -e '.pi.skills == ["./skills"]' ${piTree}/package.json >/dev/null
              jq -e '.keywords | index("pi-package")' ${piTree}/package.json >/dev/null
              jq -e '.name == "agent-skills"' ${piTree}/package.json >/dev/null
              touch $out
            '';

          # Command-style skills (disable-model-invocation) get a pi prompt
          # template so they are reachable as /name, not just /skill:name.
          # Model-invocable skills must NOT get one.
          pi-prompt-templates =
            let
              piTree = self.packages.${system}.pi-plugin;
            in
            pkgs.runCommand "pi-prompt-templates" { nativeBuildInputs = [ pkgs.jq ]; } ''
              jq -e '.pi.prompts == ["./prompts"]' ${piTree}/package.json >/dev/null

              test -f ${piTree}/prompts/format-nix.md
              test -f ${piTree}/prompts/nix-dotfiles.md

              # description and argument-hint carried over from frontmatter
              grep -qxF 'description: Format all Nix files in the project with nixfmt' \
                ${piTree}/prompts/format-nix.md
              grep -qxF 'argument-hint: "[directory]"' ${piTree}/prompts/format-nix.md
              grep -qxF 'argument-hint: "<what to change>"' ${piTree}/prompts/nix-dotfiles.md

              # body carried over verbatim, including pi-native $ARGUMENTS
              grep -qF '$ARGUMENTS' ${piTree}/prompts/format-nix.md

              # Claude-only frontmatter must not leak into the template
              grep -q '^disable-model-invocation:' ${piTree}/prompts/format-nix.md && exit 1
              grep -q '^allowed-tools:' ${piTree}/prompts/format-nix.md && exit 1

              # model-invocable skills get no template
              test ! -e ${piTree}/prompts/using-agent-skills.md
              test ! -e ${piTree}/prompts/writing-skills.md

              # ...but they are still shipped as skills
              test -f ${piTree}/skills/format-nix/SKILL.md
              test -f ${piTree}/skills/using-agent-skills/SKILL.md

              touch $out
            '';

          pi-extensions =
            let
              piTree = self.packages.${system}.pi-plugin;
            in
            pkgs.runCommand "pi-extensions" { nativeBuildInputs = [ pkgs.jq ]; } ''
              jq -e '.pi.extensions == ["./extensions"]' ${piTree}/package.json >/dev/null
              test -f ${piTree}/extensions/agent-skills-session-start.ts

              # The build-time placeholder must be gone and replaced by a
              # store path that exists and holds the real skill.
              ! grep -q '@USING_AGENT_SKILLS@' ${piTree}/extensions/agent-skills-session-start.ts
              p=$(grep -o '/nix/store/[^"]*using-agent-skills-content' \
                    ${piTree}/extensions/agent-skills-session-start.ts | head -1)
              test -n "$p"
              grep -q 'name: using-agent-skills' "$p"

              # Only type imports — a value import from @earendil-works
              # would fail to resolve from a /nix/store path.
              ! grep -E '^import[^t]' ${piTree}/extensions/agent-skills-session-start.ts \
                | grep -q '@earendil-works'

              touch $out
            '';

          temporal-pi =
            let
              tree = self.packages.${system}.temporal-pi;
            in
            pkgs.runCommand "temporal-pi" { nativeBuildInputs = [ pkgs.jq ]; } ''
              jq -e '.name == "agent-skills-temporal"' ${tree}/package.json >/dev/null
              jq -e '.pi.extensions == ["./extensions"]' ${tree}/package.json >/dev/null
              test -f ${tree}/extensions/temporal.ts
              test -f ${tree}/skills/temporal/SKILL.md

              # the pi build must not drag in the Python the hook targets need
              test ! -e ${tree}/bin/python3

              # behaviour parity with temporal.py: the three env knobs and
              # both stamp forms must be present
              grep -qF 'TEMPORAL_INTERVAL' ${tree}/extensions/temporal.ts
              grep -qF 'TEMPORAL_TTL_DAYS' ${tree}/extensions/temporal.ts
              grep -qF 'TEMPORAL_STATE_DIR' ${tree}/extensions/temporal.ts
              grep -qF 'post-compaction time check' ${tree}/extensions/temporal.ts
              grep -qF 'unix_ms=' ${tree}/extensions/temporal.ts

              touch $out
            '';

          # Design §14: every skill must build for all four targets. This
          # catches the failure mode where one target's mkSkill silently
          # drops a skill whose frontmatter it cannot model.
          skills-all-four-targets =
            let
              build = import ./lib/default.nix {
                inherit pkgs lib;
                claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
              };
              skills = build.discoverSkills ./skills;
            in
            pkgs.runCommand "skills-all-four-targets"
              {
                trees = lib.concatStringsSep " " [
                  "claude=${self.packages.${system}.claude-plugin}"
                  "antigravity=${self.packages.${system}.antigravity-plugin}"
                  "codex=${self.packages.${system}.codex-plugin}"
                  "pi=${self.packages.${system}.pi-plugin}"
                ];
                names = lib.concatStringsSep " " (map (s: s.name) skills);
                expected = toString (builtins.length skills);
              }
              ''
                fail=0
                for pair in $trees; do
                  t="''${pair%%=*}"
                  tree="''${pair#*=}"

                  # every discovered skill is present, with a non-empty SKILL.md
                  for n in $names; do
                    f="$tree/skills/$n/SKILL.md"
                    if [ ! -f "$f" ]; then
                      echo "MISSING: $t is missing skill '$n'"
                      fail=1
                    elif [ ! -s "$f" ]; then
                      echo "EMPTY: $t ships an empty SKILL.md for '$n'"
                      fail=1
                    fi
                  done

                  # and no target ships extras or drops any
                  got=$(ls -1 "$tree/skills" | wc -l)
                  if [ "$got" != "$expected" ]; then
                    echo "COUNT: $t ships $got skills, expected $expected"
                    fail=1
                  fi
                done
                [ "$fail" = 0 ] || exit 1
                echo "all $expected skills present in all four targets"
                touch $out
              '';

          module-tests =
            let
              failures = import ./modules/module-tests.nix { inherit pkgs lib; };
            in
            if failures == [ ] then
              pkgs.runCommand "module-tests" { } "touch $out"
            else
              throw "module tests failed: ${builtins.toJSON failures}";

          prompt-tests =
            let
              failures = import ./lib/prompt-tests.nix { inherit lib; };
            in
            if failures == [ ] then
              pkgs.runCommand "prompt-tests" { } "touch $out"
            else
              throw "prompt tests failed: ${builtins.toJSON failures}";

          prompt-budget =
            let
              promptLib = import ./lib/prompt.nix { inherit lib; };
              prompts = {
                core = promptLib.mkPrompt { layers = [ ./prompt/core ]; };
                shared = promptLib.mkPrompt { layers = [ ./prompt/shared ]; };
                pi-delta = promptLib.mkPrompt { layers = [ ./prompt/pi ]; };
                pi-full = promptLib.mkPrompt {
                  layers = [
                    ./prompt/core
                    ./prompt/shared
                    ./prompt/pi
                  ];
                };
              };
              limits = {
                core = {
                  words = 430;
                  characters = 3200;
                };
                shared = {
                  words = 400;
                  characters = 2800;
                };
                pi-delta = {
                  words = 70;
                  characters = 500;
                };
                pi-full = {
                  words = 900;
                  characters = 6500;
                };
              };
              check =
                name: limit:
                let
                  text = prompts.${name};
                  words = promptLib.wordCount text;
                  characters = builtins.stringLength text;
                in
                lib.optional (
                  words > limit.words
                ) "${name}: ${toString words} words exceeds ${toString limit.words}"
                ++ lib.optional (
                  characters > limit.characters
                ) "${name}: ${toString characters} characters exceeds ${toString limit.characters}";
              failures = lib.concatLists (lib.mapAttrsToList check limits);
            in
            if failures == [ ] then
              pkgs.runCommand "prompt-budget" { } "touch $out"
            else
              throw "prompt budget exceeded: ${lib.concatStringsSep "; " failures}";

          prompt-lint-tests =
            let
              failures = import ./lib/prompt-lint-tests.nix { inherit lib; };
            in
            if failures == [ ] then
              pkgs.runCommand "prompt-lint-tests" { } "touch $out"
            else
              throw "prompt lint tests failed: ${builtins.toJSON failures}";

          # The governing rule from the design's §12, as a build gate: prompt
          # fragments state policy, never inventory. Skill names come from the
          # real tree, so adding a skill immediately widens the ban.
          prompt-inventory =
            let
              promptLib = import ./lib/prompt.nix { inherit lib; };
              promptLint = import ./lib/prompt-lint.nix { inherit lib; };
              build = import ./lib/default.nix {
                inherit pkgs lib;
                claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
              };
              skillNames =
                map (s: s.name) (build.discoverSkills ./skills)
                ++ map (p: p.name) (build.discoverPlugins ./plugins);
              layers = {
                core = ./prompt/core;
                shared = ./prompt/shared;
                pi = ./prompt/pi;
              };
              checkFragment =
                layer: dir: name:
                let
                  prefix = "prompt/${layer}/${name}";
                  nameFailure = lib.optional (
                    !promptLib.validateFragmentName name
                  ) "${prefix}: file name must match NN-kebab-case.md";
                  termFailures = map (v: "${prefix}: ${v.rule}: ${v.term}") (
                    promptLint.lint {
                      inherit skillNames;
                      text = promptLib.readFragment dir name;
                    }
                  );
                in
                nameFailure ++ termFailures;
              failures = lib.concatLists (
                lib.mapAttrsToList (
                  layer: dir: lib.concatMap (checkFragment layer dir) (promptLib.fragmentNames dir)
                ) layers
              );
            in
            if failures == [ ] then
              pkgs.runCommand "prompt-inventory" { } "touch $out"
            else
              throw "prompt fragments state inventory, not policy:\n  ${lib.concatStringsSep "\n  " failures}";

          # core/ replaces pi's default prompt and must never be appended to
          # the agents that ship equivalent guidance built in.
          prompt-layering =
            let
              promptLib = import ./lib/prompt.nix { inherit lib; };
              core = promptLib.mkPrompt { layers = [ ./prompt/core ]; };
              shared = promptLib.mkPrompt { layers = [ ./prompt/shared ]; };
              piPrompt = promptLib.mkPrompt {
                layers = [
                  ./prompt/core
                  ./prompt/shared
                  ./prompt/pi
                ];
              };
              failures =
                lib.optional (core == "") "core layer is empty"
                ++ lib.optional (shared == "") "shared layer is empty"
                ++ lib.optional (
                  !(lib.hasInfix (lib.removeSuffix "\n" shared) piPrompt)
                ) "pi prompt does not contain the shared layer verbatim"
                ++ lib.optional (lib.hasInfix (lib.removeSuffix "\n" core) shared) "shared layer contains core content; core is pi-only";
            in
            if failures == [ ] then
              pkgs.runCommand "prompt-layering" { } "touch $out"
            else
              throw "prompt layering: ${lib.concatStringsSep "; " failures}";

          eval-prompt-fanout = import ./tests/prompt-fanout-test.nix { inherit pkgs; };

          skills-lint =
            let
              build = import ./lib/default.nix {
                inherit pkgs lib;
                claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
              };
              skills = build.discoverSkills ./skills;
              # toJSON forces every parsed/linted field deeply.
              summary = builtins.toJSON (
                map (s: {
                  inherit (s) name;
                  inherit (s.meta) description;
                  tools = s.meta.allowed-tools;
                  agents = map (a: a.name) (s.meta.agentSpecs or [ ]);
                }) skills
              );
            in
            pkgs.runCommand "skills-lint"
              {
                inherit summary;
                passAsFile = [ "summary" ];
              }
              ''
                cp "$summaryPath" $out
              '';

          # Builds the detector package, whose checkPhase runs the vendored
          # engine tests (patterns.test.js + categories.test.js).
          avoid-ai-detect = pkgs.callPackage ./packages/avoid-ai-detect { };
        }
      );

      # ── Re-exported home-manager modules ──
      homeManagerModules = {
        claude =
          {
            lib,
            pkgs,
            ...
          }:
          let
            build = import ./lib/default.nix {
              inherit pkgs lib;
              claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
            };
            skills = build.discoverSkills ./skills;
            skillPermissions = map (s: "Skill(agent-skills:${s.name})") skills;
            claudePlugins = map (p: self.packages.${pkgs.system}."${p.name}-claude") (
              build.discoverPlugins ./plugins
            );
          in
          {
            imports = [ "${claude-nix}/modules/home-manager.nix" ];
            programs.claude-nix.plugins = lib.mkBefore (
              [ self.packages.${pkgs.system}.claude-plugin ] ++ claudePlugins
            );
            programs.claude-nix.extraPermissions.allow = skillPermissions;
            programs.claude-nix.extraHooks = build.foldClaudeHooks (
              map (p: p.passthru.claudeHooks or { }) claudePlugins
            );
            programs.claude-nix.statusLine.enable = true;
            # Fall through to Sonnet if the primary model is unavailable.
            # Additive + rebuild-safe (unlike a declared `model`/`effortLevel`,
            # which would re-assert on every rebuild and clobber an in-session
            # /model or /effort switch — those are intentionally left unset).
            programs.claude-nix.fallbackModel = [ "claude-sonnet-5" ];

            # Preferences that were only ever runtime state in
            # ~/.claude/settings.json, so a fresh config dir (a container, a
            # new machine, an extraAccounts wrapper) started without them.
            # Both are set-and-forget rather than per-session, so declaring
            # them costs nothing to the rebuild-clobber caveat above.
            #
            # Auto permission mode and the fullscreen renderer are deliberately
            # absent: claude-nix defaults to both as of the bump below.
            programs.claude-nix.voice = {
              enabled = true;
              mode = "tap";
            };
            # Accept the multi-agent usage warning up front; until it is set,
            # auto mode prompts before every workflow run.
            programs.claude-nix.workflows.skipUsageWarning = true;
          };

        antigravity =
          {
            lib,
            pkgs,
            ...
          }:
          let
            build = import ./lib/default.nix {
              inherit pkgs lib;
              claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
            };
            antigravityPlugins = map (p: self.packages.${pkgs.system}."${p.name}-antigravity") (
              build.discoverPlugins ./plugins
            );
          in
          {
            imports = [ "${antigravity-cli-nix}/modules/home-manager.nix" ];
            programs.antigravity-cli-nix.plugins = lib.mkBefore (
              [ self.packages.${pkgs.system}.antigravity-plugin ] ++ antigravityPlugins
            );
          };

        codex =
          {
            lib,
            pkgs,
            ...
          }:
          let
            build = import ./lib/default.nix {
              inherit pkgs lib;
              claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
            };
            codexPlugins = map (p: self.packages.${pkgs.system}."${p.name}-codex") (
              build.discoverPlugins ./plugins
            );
          in
          {
            imports = [ "${codex-nix}/modules/home-manager.nix" ];
            programs.codex-nix.plugins = lib.mkBefore (
              [ self.packages.${pkgs.system}.codex-plugin ] ++ codexPlugins
            );
          };

        pi =
          {
            config,
            lib,
            pkgs,
            ...
          }:
          let
            build = import ./lib/default.nix {
              inherit pkgs lib;
              claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
            };
            piPlugins = map (p: self.packages.${pkgs.system}."${p.name}-pi") (build.discoverPlugins ./plugins);
            piPackages = [ self.packages.${pkgs.system}.pi-plugin ] ++ piPlugins;
          in
          {
            imports = [ pi-nix.homeManagerModules.coding-agent ];
            # pi loads a package directory wholesale — its skills, prompt
            # templates, and extensions in one entry. Local absolute paths
            # are a first-class package source, so the store paths go in
            # directly with no npm or git round trip.
            #
            # Caveat, inherited from upstream (design §7): `settings` is
            # types.attrs and is jq-merged into ~/.pi/agent/settings.json on
            # every launch, so a Nix-declared key wins over an interactive
            # change to that key. Same trade-off as modules/ai/codex.nix.
            #
            # Auto mode rides along here rather than only on --extension, and
            # the reason is subagents. pi-subagents spawns a child pi and hands
            # it a fixed extension list -- the prompt runtime, its fanout child,
            # and the permission system -- so a child inherits nothing from this
            # process's command line. It does read settings.json, which is how
            # the skill packages above reach it, so naming auto mode there is
            # what gives a child the same classifier the parent has. Without it
            # the child loads the permission system, finds `pi-automode` named
            # in its authorizerChain and never registered, skips the link
            # ("more prompting, never less"), and every ask it cannot settle
            # deterministically becomes a prompt no child has a terminal to
            # answer.
            #
            # Listing it twice is safe: pi resolves a package directory through
            # its manifest and de-duplicates the resulting entry paths
            # (loader.js's addPaths), so the parent loads one copy.
            programs.pi.coding-agent.settings.packages =
              map toString piPackages
              ++ lib.optional config.programs.pi.coding-agent.autoMode.enable (
                toString config.programs.pi.coding-agent.autoMode.package
              );

            # The curated third-party set, enabled by default because each one
            # restores something pi deliberately omits and this library's
            # skills assume: MCP, subagents, todos, background bash, structured
            # questions, and goal-driven looping. pi-nix packages them; the
            # choice of which to run is an opinion, and this is the opinion
            # layer, so it lives here rather than there.
            #
            # mkDefault, so a host can replace the list wholesale without
            # fighting a priority. The first-party extensions (auto-mode,
            # notify, statusline, intercom) are not listed: each arrives from
            # its own option in pi-nix, and naming them here would enable them
            # behind that option's back.
            programs.pi.coding-agent.extensionPackages = lib.mkDefault (
              map (n: pi-nix.packages.${pkgs.system}.${n}) [
                "ext-pi-mcp-adapter"
                "ext-pi-subagents"
                "ext-pi-background-tasks"
                "ext-juicesharp-rpiv-ask-user-question"
                "ext-juicesharp-rpiv-todo"
                "ext-narumitw-pi-goal"
                "ext-narumitw-pi-btw"
                "ext-gotgenes-pi-permission-system"
                "ext-pi-cache-optimizer"
                "ext-heyhuynhgiabuu-pi-pretty"
              ]
            );
          };

        agent-skills =
          {
            lib,
            pkgs,
            ...
          }:
          {
            imports = [ ./modules/agent-skills.nix ];
            programs.agent-skills.enable = lib.mkDefault true;
            programs.agent-skills.plugins = lib.mkBefore [
              self.packages.${pkgs.system}.claude-plugin
            ];
          };
      };

      # ── Re-exported libs ──
      lib = forAllSystems (
        { pkgs, ... }:
        {
          claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
          agyLib = import "${antigravity-cli-nix}/lib" {
            inherit pkgs;
            lib = pkgs.lib;
          };
          codexLib = import "${codex-nix}/lib" {
            inherit pkgs;
            lib = pkgs.lib;
          };
          piLib = import "${pi-nix}/lib" {
            inherit pkgs;
            lib = pkgs.lib;
          };
        }
      );

      # ── Positive list of claude-targeted plugin packages ──
      # Same set the homeManagerModules.claude wires into
      # programs.claude-nix.plugins. Exposed so downstream consumers
      # (claude-container's image build) can take the canonical list
      # without filtering by name suffix — a future skill named
      # `something-claude` would otherwise sneak into the container
      # under that pattern.
      claudePlugins = nixpkgs.lib.genAttrs systems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          build = import ./lib/default.nix {
            inherit pkgs;
            lib = pkgs.lib;
            claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
          };
          discoveredPlugins = build.discoverPlugins ./plugins;
        in
        [ self.packages.${system}.claude-plugin ]
        ++ map (p: self.packages.${system}."${p.name}-claude") discoveredPlugins
      );
    };
}
