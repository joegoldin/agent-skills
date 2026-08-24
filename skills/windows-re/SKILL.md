---
name: windows-re
description: Use when reverse engineering a Windows target — a PE file (.exe, .dll, .sys), a .NET assembly, a driver, Windows malware, or an x86/x64 Windows binary. Triggers on PE header or import inspection, packer/protector detection, decompiling .NET to C#, extracting obfuscated strings, Windows memory-dump forensics, unpacking MSI/CAB/Inno/BitRock/NSIS installers, running a Windows binary under Wine, or verifying Authenticode signatures. Builds on the reverse-engineering skill for the shared toolchain.
---

# Windows Reverse Engineering

Windows-specific tools in the `re-shell` devShell. For the shared toolchain
(Ghidra, radare2, rizin, binwalk, Frida, YARA, the output-directory conventions,
and the Python/Node environments), see the **reverse-engineering** skill.

## PE analysis and inspection

| Command | What it does |
|---------|--------------|
| `PE-bear binary.exe` | GUI PE viewer: headers, sections, imports, exports, resources, overlays |
| `diec binary.exe` | Identify compiler, packer, protector, and linker (Detect It Easy) |
| `imhex binary.exe` | Hex editor with a pattern language, data inspector, and PE templates |

## .NET decompilation

| Command | What it does |
|---------|--------------|
| `ilspycmd -p -o tmp/src/ assembly.dll` | Decompile a .NET assembly to C# (CLI) |
| `ILSpy` | Cross-platform GUI .NET decompiler (Avalonia ILSpy) |

## String and capability analysis

`floss binary.exe > tmp/floss_output.txt` (FLARE-FLOSS) extracts obfuscated,
stack, and decoded strings that plain `strings` misses in malware.

## Memory forensics

| Command | What it does |
|---------|--------------|
| `vol -f memory.dmp windows.pslist` | List processes |
| `vol -f memory.dmp windows.malfind` | Detect injected code and suspicious regions |
| `vol -f memory.dmp windows.dlllist` | List loaded DLLs per process |
| `vol -f memory.dmp windows.netscan` | List network connections |

Volatility 3 Windows plugins live under the `windows.` namespace; `vol --help`
lists them all.

## Archive and installer extraction

| Command | What it does |
|---------|--------------|
| `cabextract archive.cab` | Extract Microsoft Cabinet archives |
| `innoextract setup.exe` | Extract Inno Setup installers without running them |
| `msiextract -C tmp/msi/ installer.msi` | Extract an MSI payload with real file names |
| `msiinfo tables installer.msi` / `msiinfo export installer.msi Property` | Read MSI database tables |

`7z x installer.msi` also extracts an MSI, but it hands you the internal stream
names, which vendors routinely mangle (`filUrdi_4VOhmE74tO5C.L675ZenTA`).
`msiextract` applies the `File` and `Directory` tables to write the real names
and tree. Use `msiinfo export` to read `Property` (version, product code) and
`CustomAction` (the code the installer runs).

## Running Windows binaries under Wine

| Command | What it does |
|---------|--------------|
| `WINEPREFIX=$PWD/tmp/wineprefix wine setup.exe` | Run a Windows executable (32- and 64-bit) |
| `wineboot -u` / `winecfg -v win11` | Create/update a prefix; set the reported Windows version |
| `wine reg add <key> /v <name> /d <value> /f` | Edit a prefix registry without a GUI |
| `winetricks vcrun2019 dotnet48` | Install redistributables and runtimes into a prefix |

Always point `WINEPREFIX` at a directory under `tmp/`, one prefix per target,
so a failed install is a `rm -rf` away and never touches `~/.wine`.
`WINEDEBUG=-all` silences the noise.

## Authenticode

`osslsigncode verify binary.exe` verifies, extracts, or manipulates
Authenticode signatures on PE files.

## Python libraries

| Import | Use |
|--------|-----|
| `pefile` | Parse/manipulate PE: headers, sections, imports, exports, resources |
| `dnfile` | Parse .NET PE metadata tables, streams, type references |
| `lief` | Multi-format binary parser (PE, ELF, Mach-O) with modification |
| `unicorn` | CPU emulator for x86/ARM/MIPS shellcode and malware snippets |
| `oletools` | Analyze OLE/Office files for macros, VBA, embedded objects (also CLI: `olevba`, `oleid`, `rtfobj`) |

## Workflows

### PE static analysis

```sh
diec binary.exe                                # compiler/packer/protector
floss binary.exe > tmp/floss_output.txt        # obfuscated strings
yara rules.yar binary.exe
python3 -c "import pefile; pe = pefile.PE('binary.exe'); pe.print_info()"
```

### .NET assembly analysis

```sh
ilspycmd -p -o tmp/ilspy_assembly/ assembly.dll
python3 -c "import dnfile; dn = dnfile.dnPE('assembly.dll'); print(dn.net.metadata)"
```

### Unpacking with UPX

```sh
diec packed.exe                       # confirm packing
upx -d packed.exe -o tmp/unpacked.exe
diec tmp/unpacked.exe                  # verify
```

### Unpacking a vendor installer under Wine

Carving an installer overlay gives you the file data but not the file names.
Running the installer in a throwaway prefix gives a correct tree, and is usually
faster:

```sh
export WINEPREFIX=$PWD/tmp/wineprefix WINEDEBUG=-all
wineboot -u && winecfg -v win11
wine setup.exe --mode unattended --unattendedmodeui none --eula_choice eula_accepted
find $WINEPREFIX/drive_c -maxdepth 4 -iname '*<product>*'
```

The `--mode unattended` flags are BitRock/InstallBuilder; NSIS uses `/S`, Inno
uses `/VERYSILENT` (prefer `innoextract` for Inno). Identify BitRock by the
string `::bitrock_tcl_is_using_only_s32_dll_path` in `.text`. Installers that
gate on the OS version read the registry rather than trusting `winecfg` —
Wine's `win11` still reports build 22000, so a Windows-11-only installer needs:

```sh
wine reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' /v CurrentBuild       /d 26100 /f
wine reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' /v CurrentBuildNumber /d 26100 /f
```

For an Electron product, unpack the payload and recover the sources if the build
shipped webpack source maps:

```sh
asar extract "$WINEPREFIX/drive_c/Program Files/<Vendor>/<App>/resources/app.asar" tmp/app/
python3 -c "
import json, pathlib
m = json.load(open('tmp/app/main.js.map'))
for name, src in zip(m['sources'], m['sourcesContent']):
    p = pathlib.Path('tmp/app_src') / name.lstrip('./')
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(src or '')
"
```

`sourcesContent` holds the pre-minification TypeScript verbatim, including any
endpoints and credentials the vendor compiled into the app config.

### Binary emulation with Unicorn

```python
from unicorn import *
from unicorn.x86_const import *

mu = Uc(UC_ARCH_X86, UC_MODE_32)
mu.mem_map(0x1000, 0x1000)
mu.mem_write(0x1000, code_bytes)
mu.reg_write(UC_X86_REG_ESP, 0x2000)
mu.emu_start(0x1000, 0x1000 + len(code_bytes))
```

## Notes

- PE-bear, Avalonia ILSpy, and ImHex need a display server; on headless hosts
  use `diec`, `ilspycmd`, and the Python libraries.
- `retdec` is not installed but is in nixpkgs (`pkgs.retdec`); it is
  memory-hungry, so prefer Ghidra's decompiler for most work.
