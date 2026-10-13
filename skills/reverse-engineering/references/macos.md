# re-shell on macOS

The shell cannot run natively on macOS: it is x86_64-linux, and wine, ddcutil,
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
- **USB is opt-in.** On macOS 27, `re-shell --usb` uses a locally signed vfkit
  app and the Mac's USB accessory menu. USB/IP is a separate fallback; the guest
  includes native `usbip` and loads `vhci-hcd`. Both paths are described below.
  Network targets also work through outbound NAT: `adb connect <host>:5555`.
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

## Native USB passthrough

`re-shell --usb` requires macOS 27 and a provisioned vfkit app. Ordinary
`re-shell` keeps using stock vfkit; `--usb` is rejected on Linux. The fork's
[USB documentation](https://github.com/joegoldin/vfkit/blob/usb-passthrough/doc/usage.md)
covers the underlying device option and build requirements.

The dotfiles configuration supplies the pinned vfkit build. Its activation
copies the app to `~/Applications/vfkit.app`, embeds the configured provisioning
profile, and signs it with the development identity in the Mac's keychain. The
profile is deployed through agenix; the private signing key stays in the
keychain. Signing happens locally after the Nix build, so neither the profile
nor the private key belongs in the Nix store.

For initial setup, configure an explicit macOS app ID with **Claim USB
Accessory**, then create a development provisioning profile for that app ID,
your signing certificate, and this Mac. Ad-hoc signing cannot use this
restricted entitlement. The profile and certificate are reusable until they
expire or their app/device configuration changes. Dotfiles activation signs
updated builds; launching another VM does not require another signature. If
codesign returns `errSecInternalComponent` over SSH, unlock the login keychain
and run activation in Terminal on the Mac so a key-access prompt can appear.

Outside these dotfiles, follow the fork's `make usb-app` instructions with the
macOS 27 SDK and install the signed app at the same path. Once the app is
installed:

```fish
re-shell --usb
# Use an app installed elsewhere:
env RE_SHELL_VFKIT_APP="$HOME/Applications/vfkit-test.app" re-shell --usb
```

The launcher opens the app through LaunchServices and preserves the terminal
console. Once the VM is running, open the USB accessory icon in the macOS menu
bar and assign the device to **vfkit**. A menu selection grants access; check enumeration in
the guest with `lsusb` and the expected device node before using a device tool.
Reassign the device on a later launch if its grant was not retained. The menu
can disappear when vfkit exits. Stopping the VM releases its devices to macOS.

An ESP32 USB JTAG/serial device was verified on macOS 27.0.1: Linux enumerated
`303a:1001` and created `/dev/ttyACM0`; stopping the VM released host ownership.
This verifies enumeration and driver binding, not serial communication or
flashing. The guest still needs the device's Linux driver, and mode switches
can require another menu selection after re-enumeration. Apple's framework
rejects devices with isochronous endpoints: an iPhone reached the grant callback
but failed attachment for that reason. A successful grant does not by itself
prove passthrough works.

## Import a USB device over USB/IP

Rebuild an existing cached runner with `re-shell -r` first. Inside the guest,
use a server address reachable through NAT (the Mac's LAN address or a remote
Linux host, not `localhost`). The console session already runs as root:

```sh
usbip list --remote 192.168.1.10
usbip attach --remote 192.168.1.10 --busid 1-2
usbip port
lsusb
# Use the imported port shown above, not the server's bus ID:
usbip detach --port 0
```

`usbip` comes from the guest's kernel package set and runs natively on aarch64.
Imports last until detached or the VM powers off; launching another session
requires attaching again. Mode switches that re-enumerate a device can require
listing and attaching its new bus ID. The Linux driver for the imported device
must also be available; USB/IP does not forward host I2C buses or display links.
These are the [Linux USB/IP client commands](https://github.com/torvalds/linux/blob/master/tools/usb/usbip/README).

### Mac server

[usbipd-mac](https://github.com/beriberikix/usbipd-mac) is experimental. Its
current documentation reports working debug probes and claimable vendor/serial
interfaces; HID, storage, audio and cameras held by macOS cannot be exported.
ADB can remain offline despite successful USB transfers. Check the installed
release's limitations against the actual device.

Install and explicitly export one device on the Mac:

```sh
brew tap beriberikix/usbipd-mac
# Homebrew 6 requires trusting the third-party tap before installation:
brew trust beriberikix/usbipd-mac
brew install usbip
sudo brew services start usbip
usbipd list
sudo usbipd bind 1-2
sudo brew services restart usbip
usbipd status
```

The daemon reads its allowlist at startup, so restart it after changing bindings.
After detaching in the guest, stop sharing the device on the Mac:

```sh
sudo usbipd unbind 1-2
sudo brew services restart usbip
# Stop the server entirely when finished:
sudo brew services stop usbip
```

This setup is explicit; `re-shell` does not install or start a Mac service or
export devices automatically.

### Linux server

A Linux server avoids the Mac's device-claiming restrictions. Install that
host's kernel-matched USB/IP tools (on NixOS, `config.boot.kernelPackages.usbip`),
then select a device:

```sh
sudo modprobe usbip-host
sudo usbipd -D
usbip list --local
sudo usbip bind --busid 1-2
# After detaching in the guest:
sudo usbip unbind --busid 1-2
```

Binding hands the device to USB/IP, so the server's ordinary driver loses it
until it is unbound. Keep TCP 3240 reachable only from trusted clients: USB/IP
has no transport authentication or encryption. Restrict the server's firewall
to the guest's source address as seen through NAT, or use a private VPN; do not
expose it publicly or disable the firewall.
