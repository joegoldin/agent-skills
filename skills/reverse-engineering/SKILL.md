---
name: reverse-engineering
description: Toolchain and method for reverse engineering binaries, firmware, devices, Android apps, Windows executables and web protocols. Use when analysing an unknown binary, firmware image, device, APK, PE or .NET file, or an undocumented network API.
---

# Reverse Engineering

The shared toolchain, the environment it runs in, and the conventions that keep
an analysis reproducible. Target-specific tools and workflows are in
references; read the one that matches the target before starting:

- [references/android.md](references/android.md): APKs, DEX and smali, native
  `.so` libraries, ADB and fastboot, OTA images, certificate pinning.
- [references/windows.md](references/windows.md): PE files, .NET assemblies,
  installers (MSI, Inno, BitRock), Wine, memory dumps, Authenticode.
- [references/web.md](references/web.md): protobuf and gRPC, HAR files,
  undocumented HTTP and WebSocket APIs, TLS-fingerprinted endpoints.
- [references/hardware.md](references/hardware.md): monitors over DDC/CI, USB
  and HID devices, FPGA bitstreams and netlists, RP2040/RP2350 firmware.

## The environment

The toolchain is a Nix devShell shipped by this repo. Enter it before you start
with the `re-shell` launcher, which is on PATH wherever this skill is installed:

```sh
re-shell              # interactive shell, in the current directory
re-shell <command>    # run one command in it, exit with the command's status
re-shell -f .         # take the shell from a local agent-skills checkout
```

`nix develop github:joegoldin/agent-skills#re-shell` does the same thing on
Linux and is what the launcher runs there.

The shell is x86_64-linux and pulls a large unfree closure on first use (Ghidra
alone is ~2 GB). It sets the environment variables the tools need
(`GHIDRA_INSTALL_DIR`, `GHIDRA_JAVA_HOME`, `PICO_SDK_PATH`, `LIBUSB1_SO`,
`_JAVA_OPTIONS`, with JVM scratch redirected into `tmp/jtmp`), and links a
`wordlists/` directory into your working directory.

### On macOS

The shell cannot run natively there: it is x86_64-linux, and wine, ddcutil,
i2c-tools, edid-decode, hid-tools, and pe-bear need Linux kernel interfaces that
macOS does not have. `re-shell` therefore boots a disposable NixOS microVM
(vfkit, on Virtualization.framework) and enters the same shell inside it.

- **Only the launch directory is shared, as `/work`**, read-write, and it is the
  shell's working directory. The guest cannot see the rest of the Mac — which is
  the point when the sample is untrusted.
- **x86_64 binaries run under Rosetta**, so the toolchain is the one Linux gets,
  not a macOS subset.
- **The guest's Nix store persists** in `~/.local/share/re-shell`, so the
  multi-GB download happens once. Everything else in the guest is discarded: the
  VM powers off when the shell exits.
- **One session, and no display.** The terminal that ran `re-shell` *is* the
  VM's console: the guest runs no sshd, and microvm.nix's vfkit backend wires up
  neither port forwarding nor vsock (it throws on both), so there is no second
  way in. Drive Ghidra headless (`ghidra-analyzeHeadless`, pyghidra); the GUI
  tools are unusable in there.
- **Ctrl-C interrupts the tool; Ctrl-] kills the VM.** The console is the
  terminal's own tty, so the launcher hands the interrupt key to the guest —
  otherwise Ctrl-C would reach vfkit and shut the machine down mid-analysis.
- **No AVX.** Rosetta translates x86_64 userspace without AVX, AVX2, AVX-512,
  BMI1/2, or F16C, and there is no 32-bit x86 at all. A sample or tool that
  requires them dies with SIGILL rather than a clear message.
- **No USB.** vfkit passes no USB devices through, so nothing that talks to
  attached hardware — adb over USB, `lsusb`, hid-tools, ddcutil, i2c — can see
  it. Network-reachable targets still work: the guest has outbound NAT, so
  `adb connect <host>:5555` and a remote frida-server are the way in.
- **Frida is the one tool Rosetta cannot run.** The x86_64 build dies on an
  unimplemented `eventfd` syscall, for the Python module and every CLI. The
  guest carries a native aarch64 build outside the shell: call it by path,
  `/run/current-system/sw/bin/frida{,-ps,-trace}`, since the shell's broken
  x86_64 copy comes first on PATH. Everything else in the toolchain — Ghidra,
  radare2, wine, jadx, apktool, floss, diec, pyghidra, capstone, unicorn, lief,
  yara — runs under Rosetta.

Tunable with `RE_SHELL_CPUS` (default 6), `RE_SHELL_MEM` in MiB (8192),
`RE_SHELL_STORE_SIZE` in MiB (81920), and `RE_SHELL_STATE_DIR`. Use `re-shell -r`
to rebuild the VM runner after changing the flake.

## Output conventions

Every work product goes in one of two directories, relative to where you
launched the shell, rather than the repo root or ad-hoc locations.

- **`tmp/`**: intermediate and throwaway output: decompiled source,
  disassembly, extracted contents, Ghidra projects, scratch scripts. Gitignored.
  Make subdirectories freely (`tmp/ghidra_<sample>/`, `tmp/binwalk_firmware/`).
- **`artifacts/<identifier>/`**: final deliverables you were asked to keep:
  reports, annotated snippets, hook scripts, YARA rules, patches. Also
  gitignored; the difference from `tmp/` is durability, not tracking. Name the
  subdirectory meaningfully: a package id, a sample hash, a firmware family.

Direct tool output into `tmp/` explicitly: `binwalk -e firmware.bin -C tmp/binwalk_firmware/`.

## Native binary analysis

| Tool | Command | What it does |
|------|---------|--------------|
| Ghidra | `ghidra` | Full SRE suite with a decompiler; x86, x64, ARM, ARM64, MIPS, and more |
| radare2 | `r2 -A binary` | CLI-first disassembly, analysis, patching, debugging |
| rizin | `rizin -A binary` | radare2 fork with cleaner APIs and Ghidra decompiler via rz-ghidra |
| binwalk | `binwalk firmware.bin` | Find and extract embedded files, compressed streams, filesystems |

Ghidra's GUI needs a display server; on headless hosts use the headless
analyzer (`ghidra-analyzeHeadless tmp/proj Name -import binary -postScript s.java`)
or drive it from Python with pyghidra. A large image can take Ghidra over an
hour to auto-analyze, so reach for `capstone` first when you only need a handful
of instructions.

## Dynamic instrumentation

| Command | What it does |
|---------|--------------|
| `frida -p <pid> -l script.js` | Inject JavaScript into a running process |
| `frida-ps` (`-U` USB, `-R` remote) | List processes |
| `frida-trace -p <pid> -i "open*"` | Generate handler stubs for matched functions |

Frida needs a matching `frida-server` running on the target when you attach to a
device rather than a local process.

## Static pattern matching

`yara rules.yar target/` matches files against YARA rules, the standard way to
identify malware families and flag known code. `yara-python` exposes the same
engine for scripting.

## Firmware extraction and inspection

`binwalk` carves most firmware. For metadata and packaging: `file` identifies
types, `exiftool` reads embedded metadata, `7z`/`unzip` handle archives,
`upx -d` unpacks UPX, and `strings -n 8` / `nm` / `objdump` / `readelf`
(binutils) read symbols and structure. `innoextract` and `asar` unpack the
installer and Electron formats vendor update tools ship in.

## Password and hash cracking

Wordlists and rules are exposed as a stable dir-of-symlinks at `wordlists/` in
your working directory (gitignored, points into the Nix store), so no
`/nix/store` spelunking. Contents: `wordlists/rockyou.txt`,
`wordlists/seclists/` (full SecLists tree), `wordlists/best64.rule`,
`wordlists/hashcat-rules/`, `wordlists/john-rules/`, `wordlists/john-password.lst`.
To add more, edit the `wordlists` linkFarm in `flake.nix`.

| Command | What it does |
|---------|--------------|
| `hashcat -m 0 -a 0 hash.txt wordlists/rockyou.txt -r wordlists/best64.rule` | GPU/CPU password recovery |
| `john --wordlist=wordlists/rockyou.txt hash.txt` | John the Ripper (Jumbo); bundles `*2john` converters like `zip2john` |

## Network interception and discovery

| Command | What it does |
|---------|--------------|
| `mitmproxy` / `mitmweb` / `mitmdump` | Intercept, inspect, and modify HTTPS traffic |
| `tshark -i any -f "host 10.0.0.1"` | Capture and analyze packets (Wireshark CLI) |
| `nmap -p 9123 --open 10.42.0.0/22` | Host, port, and service discovery |
| `avahi-browse -rt _elg._tcp` | Browse mDNS/DNS-SD services and resolve address + port |

Find a network device before you scan for it: most consumer hardware advertises
over mDNS, so `avahi-browse -art` names the device and its port in one step.
Fall back to `nmap` when the device doesn't advertise. `avahi-browse` needs the
avahi daemon on the host (`services.avahi.enable = true;` on NixOS).

## Python scripting environment

The shell provides a Nix-built virtualenv. General-purpose libraries:

| Import | Use |
|--------|-----|
| `frida` | Python API for Frida instrumentation |
| `pyghidra` | Drive Ghidra headless from Python (decompiler, Flat API) via JPype |
| `yara` | Compile and apply YARA rules |
| `capstone` | Disassemble a few bytes without a full Ghidra run (x86/x64/ARM/ARM64/MIPS/...) |
| `numpy`, `scipy` | Byte-array math, entropy, FFT, signal processing |
| `PIL` (Pillow) | Extracted textures, QR, framebuffers |
| `usb.core` (pyusb) | Raw USB transfers (references/hardware.md covers the backend) |
| `cryptography` | Ed25519/ECDSA/RSA/AES for firmware signature checks |

pyghidra needs a couple of things set before `pyghidra.start()`. The shell
handles `GHIDRA_INSTALL_DIR`, `GHIDRA_JAVA_HOME`, and `_JAVA_OPTIONS` (JVM
scratch off the small `/tmp` tmpfs, so every `java` process then prints a
`Picked up _JAVA_OPTIONS:` line to stderr; ignore it). The one thing the shell
cannot set is the recursion limit, so raise it before `start()` or JPype's type
construction aborts:

```python
import sys
sys.setrecursionlimit(100000)

import pyghidra
pyghidra.start()  # once per session

with pyghidra.open_program("binary", project_location="tmp/ghidra_project") as flat_api:
    program = flat_api.getCurrentProgram()
    listing = program.getListing()
    # iterate functions, read decompiled code, etc.
```

## Extending the environment

When a task needs a tool that isn't in the shell:

- **One-off Python**: `uv run --with <pkg> script.py`, or `uv run --with <pkg> ipython`.
- **One-off Node CLI**: `npx <pkg>@latest`.
- **Permanent Python**: `uv add <pkg>`, then re-enter the shell. Add build
  fixups to the overlay in `flake.nix` if the package needs native libs.
- **Permanent Node**: `npm install <pkg>` (the `.npmrc` keeps it lock-only),
  then re-enter the shell.
- **Permanent system tool**: search nixpkgs (the `nixos` MCP is faster than
  `nix search`), add it to the `re-shell` devShell in `flake.nix` under the
  matching category comment, then re-enter (on macOS, `re-shell -r -f <checkout>`,
  which rebuilds the VM runner against your change).

npm packages whose install scripts download binaries (e.g. the `frida` npm
package) fail in the Nix sandbox, so use the nixpkgs equivalent. After adding a
tool, confirm the binary name on PATH with `which` before documenting it: Nix
package names often differ from binary names.

