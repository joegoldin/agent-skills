---
name: android-re
description: Use when reverse engineering an Android target — APK, XAPK, AAB, DEX bytecode, smali, AndroidManifest, or a native .so from an app. Triggers on decompiling an app to Java, jadx/apktool/dex2jar, ADB or fastboot device work, Frida on Android, JNI tracing, APK malware or vulnerability scanning, certificate-pinning bypass, or extracting OTA/system images (payload.bin, sparse images). Builds on the reverse-engineering skill for the shared toolchain.
---

# Android Reverse Engineering

Android-specific tools in the `re-shell` devShell. For the shared toolchain
(Ghidra, radare2, rizin, binwalk, Frida, YARA, mitmproxy, the output-directory
conventions, and the Python/Node environments), see the **reverse-engineering**
skill.

## APK disassembly and manipulation

| Command | What it does |
|---------|--------------|
| `apktool d app.apk -o tmp/apktool_<pkg>/` | Decode to smali + resources; rebuild with `apktool b` |
| `APKEditor` | Edit APK resources directly |
| `apksigner sign --ks key.jks app.apk` | Sign and verify APK signatures |
| `apksigcopier` | Copy, extract, or patch APK signature blocks between files |
| `apkid app.apk` | Identify the compiler, packer, and obfuscator used to build an APK |
| `aapt2 dump badging app.apk` | Inspect APK metadata, resources, and manifest |
| `bundletool build-apks --bundle=app.aab --output=out.apks` | Convert an App Bundle to an APK set |

## Java / DEX decompilation

| Command | What it does |
|---------|--------------|
| `jadx -d tmp/jadx_<pkg>/ app.apk` | Decompile DEX/APK straight to Java source (GUI: `jadx-gui`) |
| `d2j-dex2jar app.apk` | Convert DEX to a standard JAR for other Java decompilers |
| `bytecode-viewer` | GUI combining Procyon, CFR, FernFlower, and others |

## Dynamic instrumentation

| Command | What it does |
|---------|--------------|
| `frida -U -f com.app.pkg -l script.js --no-pause` | Inject JavaScript into an app over USB |
| `frida-ps -U` | List processes on a USB-connected device |
| `frida-trace -U -f com.app.pkg -i "open*"` | Auto-generate handler stubs on device |
| `jnitrace -l libnative.so com.app.pkg` | Trace every JNI API call a native library makes |

## Static analysis and security scanning

| Command | What it does |
|---------|--------------|
| `trueseeing app.apk` | Scan an APK for vulnerabilities without decompiling |
| `quark -a app.apk -s` | Score and analyze an APK for malware behaviors |
| `koodousfinder` | Search for and analyze Android applications |

## Device interaction

| Command | What it does |
|---------|--------------|
| `adb devices` / `adb shell` / `adb pull` | Android Debug Bridge |
| `fastboot flash` | Flash device partitions |
| `scrcpy` | Mirror and control a device screen over USB or TCP/IP |

## Image and OTA tools

| Command | What it does |
|---------|--------------|
| `simg2img system.img system.raw.img` | Android sparse image → raw ext4 |
| `sdat2img system.transfer.list system.new.dat system.img` | `.dat` sparse data → ext4 |
| `payload-dumper-go payload.bin` | Extract partition images from an OTA `payload.bin` |
| `ApplyPatch` / `BlockImageUpdate` / `imgdiff` (imgpatchtools) | Apply and manipulate OTA incremental patches |

## Python and Node libraries

| Import / command | Use |
|------------------|-----|
| `pyaxmlparser` | Parse AndroidManifest.xml and extract app metadata |
| `hermes_dec` | Decompile React Native Hermes bytecode |
| `apk-mitm app.apk` | Patch an APK to bypass certificate pinning for MITM |

## Workflows

### Full APK static analysis

```sh
apkid app.apk                                  # build toolchain + protections
apktool d app.apk -o tmp/apktool_com.example.app/   # smali + resources
jadx -d tmp/jadx_com.example.app/ app.apk      # Java source
trueseeing app.apk                             # vulnerabilities
quark -a app.apk -s                            # malware behaviors
```

### Native library analysis

```sh
unzip app.apk -d tmp/extracted_com.example.app/
r2 -A tmp/extracted_com.example.app/lib/arm64-v8a/libnative.so   # quick CLI
# or import the .so into Ghidra for the decompiler
```

### Runtime hooking with Frida

```sh
frida-ps -U
frida -U -f com.target.app -l hook.js --no-pause
jnitrace -l libnative.so com.target.app
```

### Extract OTA / system images

```sh
payload-dumper-go payload.bin
simg2img system.img system.raw.img
mkdir tmp/mnt && sudo mount -o loop system.raw.img tmp/mnt/
```

### Bypass certificate pinning

```sh
apk-mitm app.apk               # patch out pinning
adb install app-patched.apk
mitmproxy --listen-port 8080   # then intercept
```

## Notes

- `frida` requires a `frida-server` on the device matching the frida-tools
  version.
- For HTTPS interception, push the mitmproxy CA to the device:
  `adb push ~/.mitmproxy/mitmproxy-ca-cert.cer /sdcard/` and install it.
- `bytecode-viewer` and `jadx-gui` need a display server; use the CLI
  equivalents on headless hosts.
- `androguard` is excluded from the environment: its `dataset` dependency is
  currently broken in nixpkgs. `pyaxmlparser` is the lightweight substitute for
  manifest parsing. Re-add androguard when the upstream issue is resolved.
