# Rockchip flashing tools

Original archives copied without modification from the A14 SDK:

| Archive | SDK source | Purpose |
|---|---|---|
| `DriverAssitant_v5.14.zip` | `a14/RKTools/windows/AndroidTool/DriverAssitant_v5.14.zip` | Windows Rockusb driver |
| `SDDiskTool_v1.78.zip` | `a14/RKTools/windows/SDDiskTool_v1.78.zip` | Windows SD boot card creation |
| `upgrade_tool_v2.55_for_linux.zip` | `a14/RKTools/linux/Linux_Upgrade_Tool/upgrade_tool_v2.55_for_linux.zip` | Linux NOR erase / eMMC flashing |
| `upgrade_tool_v2.33_for_window.zip` | `a14/RKTools/windows/upgrade_tool_v2.33_for_window.zip` | Windows command-line NOR erase / eMMC flashing |

Keep the extracted configuration files alongside the executables. Upgrade tool
archives include Rockchip's command-line manual and revision history; the newer
Windows manual documents `el` for SPI NOR in §1.8 and `ssd` in §1.10.
The Linux archive includes an older manual; consult its revision history too.
These vendor binaries are retained as supplied; this repository's Apache license
does not relicense third-party tools. The Windows Rockusb driver is included as `DriverAssitant_v5.14.zip`.

Verify archive integrity from this directory on Linux:

```bash
sha256sum -c SHA256SUMS
```

Instructions: [English](../../docs/FLASHING.md) / [简体中文](../../docs/FLASHING_zh.md).

RK3576 SD boot additionally requires the prebuilt Loader and NOR idblock in
[rk3576-sd-boot/](rk3576-sd-boot/README.md), with a separate checksum list.
These files enable SD boot for the board's `FSPI0 -> UFS -> USB` boot mode;
see the flashing guide before switching between SD and eMMC boot.
