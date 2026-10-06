# Hardware targets

Monitors over DDC/CI, USB and HID devices, FPGA bitstreams and netlists, and
RP2040/RP2350 firmware. Most of this needs the device attached, so on macOS,
where the shell runs in a VM without USB passthrough, run it on a Linux host.

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
