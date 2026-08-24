---
name: reverse-engineering
description: Use when reverse engineering a binary, firmware image, executable, or hardware device — disassembly, decompilation, unpacking, dynamic instrumentation, or protocol recovery. Triggers on Ghidra, radare2, rizin, binwalk, Frida, YARA, dropping an unknown file to analyze, extracting firmware, USB/HID/I2C/DDC device probing, EDID, FPGA bitstreams, RP2040/Pico firmware, password/hash cracking, or mitmproxy/tshark network capture. Android, Windows, and web targets have their own skills (android-re, windows-re, web-re) that build on this one.
---

# Reverse Engineering

The cross-discipline foundation for reverse engineering: the general-purpose
toolchain, the scripting environments, and the conventions that keep an
analysis reproducible. Discipline-specific tooling lives in the companion
skills (**android-re**, **windows-re**, **web-re**), each of which assumes
this skill for the shared tools below.

## The environment

The toolchain is a Nix devShell shipped by this repo. Enter it before you start:

```sh
nix develop github:joegoldin/agent-skills#re-shell   # or `.#re-shell` from a checkout
```

The shell is x86_64-linux only and pulls a large unfree closure on first use
(Ghidra alone is ~2 GB). It sets the environment variables the
tools need (`GHIDRA_INSTALL_DIR`, `GHIDRA_JAVA_HOME`, `PICO_SDK_PATH`,
`LIBUSB1_SO`, `_JAVA_OPTIONS`, with JVM scratch redirected into `tmp/jtmp`), and
links a `wordlists/` directory into your working directory.

## Output conventions

Every work product goes in one of two directories, relative to where you
launched the shell. Never leave tool output in the repo root or in ad-hoc
locations.

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

## Display and monitor firmware

| Command | What it does |
|---------|--------------|
| `edid-decode slot.bin` | Parse and validate EDID base blocks + CTA-861 / DisplayID extensions |
| `ddcutil capabilities` / `ddcutil getvcp 0x60` | Query/set monitor settings over DDC/CI (VCP codes); needs a real attached display |
| `i2ctransfer -y N w5@0x37 ...` | Raw I2C frames, needed for 16-bit/vendor DDC/CI opcodes `ddcutil` won't emit |

Both need the `i2c-dev` kernel module (`sudo modprobe i2c-dev`) and RW access to
`/dev/i2c-*`. On NixOS, `hardware.i2c.enable = true;` loads it and grants the
`i2c` group access.

## USB and HID

| Command | What it does |
|---------|--------------|
| `lsusb -v -d 2e1a:` | Dump USB descriptors (configs, interfaces, endpoints) |
| `usbhid-dump -d 2e1a:` | Dump raw HID report descriptors from the device |
| `hid-decode <report_descriptor>` | Decode a HID report descriptor into named usages |
| `hid-recorder /dev/hidraw0` | Record descriptor + timestamped live traffic |
| `hid-replay recording.hid` | Replay a recording through a virtual uhid device |

A vendor device often exposes several `/dev/hidraw*` nodes; pick the one whose
descriptor starts with a vendor-defined usage page (`06 XX ff`); `hid-decode`
names it. hidraw I/O needs permission on the node: run as root, or add a udev
rule like `SUBSYSTEM=="hidraw", ATTRS{idVendor}=="14ed", ATTRS{idProduct}=="1012", MODE="0660", GROUP="users"`.
Plain `open()` + `select()` on the node is enough for feature-free report I/O.

Raw USB from Python uses `pyusb` over the libusb-1.0 backend.
`ctypes.util.find_library` finds nothing on NixOS, so the shell exports
`LIBUSB1_SO`; pass it explicitly:

```python
import os, usb.core, usb.backend.libusb1 as lb
be = lb.get_backend(find_library=lambda _: os.environ["LIBUSB1_SO"])
dev = usb.core.find(idVendor=0x1234, idProduct=0x5678, backend=be)
```

Control and bulk transfers need write access to `/dev/bus/usb/*`. Note a vendor
device often changes VID:PID when it switches USB modes, so match on every
identity it can present.

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

## FPGA bitstream and netlist analysis

| Command | What it does |
|---------|--------------|
| `ecpunpack in.bit out.config` | Unpack a Lattice ECP5 bitstream into a text config naming every tile, arc, and config word |
| `ecppack in.config out.bit` | Repack a text config into a bitstream |
| `ecpbram`, `ecppll` | Patch block-RAM contents; compute PLL parameters |
| `yosys -p "read_verilog nl.v; ..."` | Netlist navigation: `select` cones (`%cie` stops at FFs = one pipeline stage), `submod`, `techmap`, `eval`, `sat` |
| `hal` | Netlist RE framework: DANA register grouping, `resynthesis`, `solve_fsm` |

The text config gives resource usage, I/O standards, and primitive modes with
no netlist work. I/O standards identify external interfaces fastest: SSTL15
implies DDR3, and the absence of differential inputs proves a part cannot
receive TMDS. The config carries block-RAM *settings* (`WID`, `CSDECODE`) but
not *contents*.

**Never count instances by counting `enum:` lines**: one block RAM or pin
spans several tiles and each repeats the setting (gives 116 BRAMs on a 56-BRAM
part). Count real hardware via the `pytrellis` routing graph instead;
`pytrellis` is built for one Python version and needs its own database or it
fails with `RuntimeError: No such node`. HAL needs structural Verilog plus a
gate library (no BLIF/JSON frontend) and ships no Lattice library; its
`module_identification` plugin supports iCE40 and Xilinx only. yosys
`fsm_detect`/`fsm_extract`/`memory_collect` produce zero output on a flattened
netlist. Use `sat` as a fast falsifier, not a prover.

## Embedded / RP2040–RP2350 (Pico) firmware

| Command | What it does |
|---------|--------------|
| `picotool info -a firmware.uf2` | Inspect/convert RP2 UF2 firmware, read binary info and chip details |
| (via `PICO_SDK_PATH`) | Pico SDK; `PICO_SDK_PATH` is set automatically |
| `cmake -B build` | Build system for pico-sdk projects |
| `arm-none-eabi-gcc` | ARM cross toolchain (`arm-none-eabi-{gcc,objcopy,gdb,...}`) |

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
| `usb.core` (pyusb) | Raw USB transfers (see USB section for the backend) |
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
  matching category comment, then re-enter.

npm packages whose install scripts download binaries (e.g. the `frida` npm
package) fail in the Nix sandbox, so use the nixpkgs equivalent. After adding a
tool, confirm the binary name on PATH with `which` before documenting it: Nix
package names often differ from binary names.

## Notes

- Ghidra and the GUI decompilers need a display server. On headless hosts use
  the headless analyzer, pyghidra, or the CLI tools.
- Frida needs a matching `frida-server` on the target device.
