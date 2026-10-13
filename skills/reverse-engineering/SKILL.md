---
name: reverse-engineering
description: Use when reverse engineering an unknown binary, firmware image, hardware device, Android APK, Windows PE or .NET file, JavaScript/Electron bundle, or undocumented network API; also for disassembly, decompilation, instrumentation and protocol recovery.
---

# Reverse Engineering

The shared toolchain, the environment it runs in, and the conventions that keep
an analysis reproducible. Target-specific tools and workflows are in
references; read the one that matches the target before starting:

- [references/android.md](references/android.md): APKs, DEX and smali, native
  `.so` libraries, ADB and fastboot, OTA images, certificate pinning.
- [references/windows.md](references/windows.md): PE files, .NET assemblies,
  installers (MSI, Inno, BitRock), Wine, memory dumps, Authenticode.
- [references/web.md](references/web.md): JavaScript/Electron, protobuf and
  gRPC, HAR files, HTTP and WebSocket APIs, TLS-fingerprinted endpoints.
- [references/hardware.md](references/hardware.md): monitors over DDC/CI, USB
  and HID devices, logic-analyzer captures, FPGA bitstreams and netlists,
  RP2040/RP2350 firmware.
- [references/cracking.md](references/cracking.md): password/hash recovery and
  wordlists.

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

On macOS, read [references/macos.md](references/macos.md) for the microVM and its limits.

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

Save large Ghidra/r2 dumps to `tmp/` and use `rg -n` plus bounded excerpts to
read them. Keep the full output on disk rather than filling context with it.

Record `sha256sum` for the original and every unpacked, carved, or extracted
file in `artifacts/<identifier>/findings.md`. Keep the original unchanged. For
each derived file, record its parent hash and the extraction command or byte
range; cite the file/hash with addresses and offsets so evidence identifies
exact bytes.

## Route by target

If the user says "my app" without a name or path, ask which target they mean.
Do not choose an installed app for them.

For an unknown file, start with `file`, `diec` (Detect It Easy), `binwalk -E`
(entropy), and `strings -n 8`; save their output under `tmp/`. High entropy can
mean compression or encryption; it does not identify either by itself.

- **ELF/Mach-O or other native code:** inspect headers, imports, and entry
  points, then use Ghidra headless for the functions relevant to the question.
- **APK/DEX or Android bundle:** read [android.md](references/android.md);
  **PE/.NET:** read [windows.md](references/windows.md).
- **JavaScript/Electron:** extract `app.asar` with `asar`, then follow package
  entry points and source maps using [web.md](references/web.md) before
  analyzing native modules.
- **Container, packed image, or embedded filesystem:** carve/extract with
  `binwalk` or `unblob`, hash the results, and triage each relevant payload.
- **Headerless firmware:** establish architecture, endianness, and load address
  from the device or image structure before importing as raw binary below.

## Investigation method

Turn the request into a short question checklist in
`artifacts/<identifier>/findings.md`. Start with the smallest useful overview
(headers, sections, imports, strings); follow each question from its entry
point through relevant callers, callees, and data. Deepen analysis only where
it can answer a question. Split independent questions across parallel
subagents when available, giving each the sample identity, evidence paths,
and a bounded question; reconcile their evidence in the same ledger.

Distinguish these in every finding:

| Kind | What it supports |
|------|------------------|
| Observation | Bytes at an offset, a tool result, or behavior captured during a specified run |
| Inference | An interpretation of evidence, with assumptions and confidence |
| Unknown | What remains untested or could change the conclusion |

Static analysis does not observe execution. Decompiler output is pseudocode,
not recovered source. A bounded negative search does not prove absence;
record what was searched and its limits. Decompiling an unpacking stub does
not recover the unpacked program; extract or capture the payload before
attributing behavior to it.

Keep one line per claim in the findings ledger:

| Claim / kind | File / SHA-256 | Evidence (address, offset, command, or trace) | Confidence | Open unknowns |
|--------------|---------------|-----------------------------------------------------|------------|---------------|

Update the ledger as evidence changes. Before finishing, mark every question
**answered**, **partial**, or **unresolved**, and state which unknowns prevent
a stronger conclusion.

## Native binary analysis

| Tool | Command | What it does |
|------|---------|--------------|
| Ghidra | `ghidra` | Full SRE suite with a decompiler; x86, x64, ARM, ARM64, MIPS, and more |
| radare2 | `r2 -A binary` | CLI-first disassembly, analysis, patching, debugging |
| rizin | `rizin -A binary` | radare2 fork with cleaner APIs and Ghidra decompiler via rz-ghidra |
| GoReSym | `GoReSym binary` | Recover Go symbols, types, and build information |
| WABT | `wasm2wat module.wasm` / `wasm-objdump -x module.wasm` | Inspect WebAssembly code and structure |
| ipsw | `ipsw --help` | Apple firmware, Mach-O, and dyld shared cache tooling |

Ghidra's GUI needs a display server; on headless hosts use the headless
analyzer (`ghidra-analyzeHeadless tmp/proj Name -import binary -postScript s.java`)
or drive it from Python with pyghidra. A large image can take Ghidra over an
hour to auto-analyze, so reach for `capstone` first when you only need a handful
of instructions. Keep the project after analysis; reuse it with
`ghidra-analyzeHeadless tmp/proj Name -process binary -noanalysis -postScript s.java`
for later queries instead of re-importing and repeating auto-analysis.

## Dynamic instrumentation

| Command | What it does |
|---------|--------------|
| `gdb binary` / `gdb binary core` | Debug a process or inspect a core dump |
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

| Command | What it does |
|---------|--------------|
| `binwalk firmware.bin` | Identify embedded signatures before extraction |
| `unblob -e tmp/unblob firmware.bin` | Extract nested containers and filesystems |

For metadata and packaging: `file` identifies types, `exiftool` reads embedded metadata, `7z`/`unzip` handle archives,
`upx -d -o tmp/unpacked binary` unpacks UPX into a derived file, and
`strings -n 8` / `nm` / `objdump` / `readelf` (binutils) read symbols and structure. `innoextract` and `asar` unpack the
installer and Electron formats vendor update tools ship in.

For headerless firmware, choose the processor and load address from evidence;
record assumptions in the ledger. For example, a Cortex-M image known to load
at `0x08000000` can be imported without auto-analysis first:

```sh
mkdir -p tmp/ghidra_firmware
ghidra-analyzeHeadless tmp/ghidra_firmware Firmware -import firmware.bin \
  -loader BinaryLoader -loader-baseAddr 0x08000000 \
  -processor ARM:LE:32:Cortex -noanalysis > tmp/firmware-import.log 2>&1
```

Check the memory map and reset/vector addresses before enabling analysis.
A plausible disassembly alone does not validate the architecture or base.

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
| `usb.core` (pyusb) | Raw USB transfers (backend setup in [hardware.md](references/hardware.md)) |
| `pwn` (pwntools) | Process/socket interaction, ELF inspection, packing, and assembly |
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
