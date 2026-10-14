# SD card and eMMC flashing

English | [简体中文](FLASHING_zh.md)

Applies to `recomputer_rk3576_devkit` and `recomputer_rk3588_devkit`. Use the
firmware and Loader for the exact board. RK3576 SD boot also requires the NOR preparation below. See the [build guide](BUILD-FLOW.md)
or obtain matching prebuilt firmware.

## 1. Firmware and tools

| Board | Complete firmware | USB download Loader |
|---|---|---|
| RK3576 | `a14/rockdev/Image-recomputer_rk3576_devkit/update.img` | `MiniLoaderAll.bin` in the same directory |
| RK3588 | `a14/rockdev/Image-recomputer_rk3588_devkit/update.img` | `MiniLoaderAll.bin` in the same directory |

Original archives are bundled in [tools/flashing/](../tools/flashing/README.md),
with SHA-256 checksums. Their SDK source paths are:

| Purpose | SDK path |
|---|---|
| Windows Rockusb driver | `a14/RKTools/windows/AndroidTool/DriverAssitant_v5.14.zip` |
| Windows SD card | `a14/RKTools/windows/SDDiskTool_v1.78.zip` |
| Linux eMMC / NOR | `a14/RKTools/linux/Linux_Upgrade_Tool/upgrade_tool_v2.55_for_linux.zip` |
| Windows eMMC / NOR | `a14/RKTools/windows/upgrade_tool_v2.33_for_window.zip` |

Back up target storage first. Card creation overwrites the SD card, NOR erase
removes the previous bootloader, and eMMC flashing overwrites the existing OS.
Keep power and USB stable throughout flashing.

## 2. Create an SD boot card on Windows

1. Extract the entire `SDDiskTool_v1.78.zip` and run `SD_Firmware_Tool.exe` as
   Administrator. Keep its configuration and language files beside it.
2. Connect the SD card through a card reader. Identify the target by drive letter
   and capacity under “Choose removable disk”.
3. Select **SD Boot**, and deselect **Upgrade Firmware** and **PCBA Test**.
   The supplied configuration defaults to firmware upgrade. An upgrade card
   updates onboard storage; choose SD Boot to run Android from the card.
4. Click **Firmware** and select the board's complete `update.img`, not
   `super.img` or a target-files ZIP.
5. Click **Create**, confirm overwriting, wait for success, then safely eject.
   Cancel any Windows prompt to format the newly created partitions.
6. For RK3576, first complete NOR preparation in §2.1 below. Power off the board, insert the card, and power on normally without holding
   BOOT. Check the Android boot on HDMI or the serial console.

RK3576 needs the SD boot image in NOR; erasing NOR does not enable SD boot.
For card detection failures, check the reader, Administrator privileges and image.

## 2.1 RK3576: install SD boot support in NOR (required)

The `recomputer_rk3576_devkit` hardware Boot Mode is **FSPI0 → UFS → USB**.
Its BROM cannot boot directly from SD. First download
`rk3576_loader_src_usbplug.bin` to RAM via USB, then write
`rk3576_idblock_src_usbplug.img` to NOR Flash to enable booting the prepared SD card.

Both prebuilt files are bundled in
[tools/flashing/rk3576-sd-boot/](../tools/flashing/rk3576-sd-boot/README.md).
This procedure is RK3576-only; do not use it on RK3588 or substitute the ordinary
`MiniLoaderAll.bin` for the specified download Loader.

Remove the SD card and enter Maskrom by holding **BOOT** while applying power
as described in §3. Install Rockusb drivers on Windows. From the extracted
upgrade_tool directory, run:

Linux:

```bash
SD_BOOT_DIR=/absolute/path/seeed-android-rockchip/tools/flashing/rk3576-sd-boot
sudo ./upgrade_tool ld
sudo ./upgrade_tool db "$SD_BOOT_DIR/rk3576_loader_src_usbplug.bin"
sudo ./upgrade_tool ssd
# Select SPINOR
sudo ./upgrade_tool ssd
# Verify * marks SPINOR, then enter Q
sudo ./upgrade_tool rfi
# Confirm NOR is selected before writing its LBA 0
sudo ./upgrade_tool wl 0 "$SD_BOOT_DIR/rk3576_idblock_src_usbplug.img"
# Reset only after a successful write
sudo ./upgrade_tool rd
```

Windows PowerShell:

```powershell
$SdBootDir = 'C:\path\seeed-android-rockchip\tools\flashing\rk3576-sd-boot'
.\upgrade_tool.exe ld
.\upgrade_tool.exe db "$SdBootDir\rk3576_loader_src_usbplug.bin"
.\upgrade_tool.exe ssd
# Select SPINOR
.\upgrade_tool.exe ssd
# Verify * marks SPINOR, then enter Q
.\upgrade_tool.exe rfi
# Confirm NOR is selected before writing
.\upgrade_tool.exe wl 0 "$SdBootDir\rk3576_idblock_src_usbplug.img"
# Reset only after a successful write
.\upgrade_tool.exe rd
```

`db` downloads the flashing Loader to RAM; `wl` persists the boot image in the
selected NOR. Do not write this idblock to EMMC or SD, or flash it with `uf`.
Stop if SPINOR cannot be selected or writing fails; check the connection,
download Loader and tool logs.

After success, power off, insert the SD card created in §2, release BOOT and
power on normally. Check boot output. **Keep this image in NOR for SD boot;
erase NOR using §4 when switching to eMMC boot.** Reinstall the NOR boot image
when switching back from eMMC to SD.

## 3. Prepare USB flashing: enter Maskrom

**Erase onboard NOR Flash before booting the flashed eMMC. Reflashing eMMC
alone does not remove the old NOR bootloader.**

1. Power off and remove the SD card. Connect the board's USB OTG port to the host
   with a data-capable cable.
2. Hold the button labeled **BOOT** (used to enter Maskrom mode), apply board power, then release the button.
   Locate the port/button using the markings for your hardware revision;
   Recovery and BOOT are different buttons.
3. Run `ld` below and confirm one target device is connected in `Maskrom` mode.
   If it reports `Loader`, use `rd 3`, then check `ld` again.
4. On Windows, install the Rockusb driver from
   the bundled [DriverAssitant_v5.14.zip](../tools/flashing/DriverAssitant_v5.14.zip)
   (SDK source path listed above), check device
   recognition in Device Manager, and open PowerShell as Administrator.
   The specified Windows archive contains the **command-line**
   `upgrade_tool.exe`, not the RKDevTool GUI.

Seeed's [RK3576 hardware interface guide](https://sensecraft.seeed.cc/ai-lab/en/tutorials/rk/edge-ai-computer/rk3576/interface-usage-guidelines/use-recomputer-rk3576-hardware-interfaces-and-fan-control)
helps locate its Type-C OTG port and buttons. For RK3588 use the corresponding
board markings.

## 4. Erase NOR Flash (required for eMMC boot)

Download the matching `MiniLoaderAll.bin` to RAM with `db`, then select
**SPINOR** with `ssd`. This command is interactive: enter the number displayed
beside SPINOR. Numbers are not assumed to be fixed. Run `ssd` again to verify
that `*` marks SPINOR, then enter `Q` to exit.

Read NOR capacity with `rfi`. The `el` arguments are start sector and sector
count, with 512 bytes per sector. To erase the entire NOR, use **NOR capacity
in bytes / 512** sectors. Only a confirmed **16 MiB** NOR uses `32768`
(`0x8000`) sectors; 32 MiB uses `65536` (`0x10000`). Use the actual NOR capacity,
not the eMMC capacity.

### Linux

Extract the Linux archive and enter its directory. Set the absolute firmware
path below; RK3588 uses `Image-recomputer_rk3588_devkit` instead.

```bash
unzip upgrade_tool_v2.55_for_linux.zip
cd upgrade_tool_v2.55_for_linux
chmod +x upgrade_tool
IMAGE_DIR=/absolute/path/a14/rockdev/Image-recomputer_rk3576_devkit
sudo ./upgrade_tool ld
sudo ./upgrade_tool db "$IMAGE_DIR/MiniLoaderAll.bin"
sudo ./upgrade_tool ssd
# Select the number displayed beside SPINOR; require successful switching
sudo ./upgrade_tool ssd
# Verify * marks SPINOR, then enter Q
sudo ./upgrade_tool rfi
```

After confirming SPINOR and its capacity, replace the placeholder and erase:

```bash
NOR_SECTORS='<actual NOR capacity in bytes divided by 512>'
sudo ./upgrade_tool el 0 "$NOR_SECTORS"
```

Wait for successful erasure. Do not substitute `ef MiniLoaderAll.bin`: it
redownloads the Loader, so it does not establish that the previously selected
NOR remains the erase target.

### Windows PowerShell

Extract `upgrade_tool_v2.33_for_window.zip` and enter the directory containing
`upgrade_tool.exe`. Put the matching board's two firmware files in `$ImageDir`.

```powershell
$ImageDir = 'C:\firmware\recomputer_rk3576_devkit'
.\upgrade_tool.exe ld
.\upgrade_tool.exe db "$ImageDir\MiniLoaderAll.bin"
.\upgrade_tool.exe ssd
# Select SPINOR and require successful switching
.\upgrade_tool.exe ssd
# Verify * marks SPINOR, then enter Q
.\upgrade_tool.exe rfi
```

After checking storage type and capacity, erase. This example is only for a
confirmed 16 MiB NOR; adjust the count for the actual hardware:

```powershell
$NorSectors = 32768  # Actual NOR capacity in bytes / 512
.\upgrade_tool.exe el 0 $NorSectors
```

If SPINOR is absent, capacity is unexpected, Boot download fails or erase fails,
stop and check Maskrom mode and whether the Loader matches the SoC/DDR and
supports the NOR. Do not erase until the selected storage is confirmed.

## 5. Select eMMC and flash

After NOR erase succeeds, use `ssd` in the same connection to select **EMMC**.
Check the `*` marker and eMMC capacity again, then flash `update.img`. If power
or USB was disconnected, re-enter Maskrom, download Boot and select/verify EMMC
again before flashing.

Linux, using the previously set `IMAGE_DIR`:

```bash
sudo ./upgrade_tool ssd
# Select EMMC
sudo ./upgrade_tool ssd
# Verify * marks EMMC, then enter Q
sudo ./upgrade_tool rfi
sudo ./upgrade_tool uf "$IMAGE_DIR/update.img" -noreset
# Require complete upgrade success before resetting
sudo ./upgrade_tool rd
```

Windows PowerShell, using the previously set `$ImageDir`:

```powershell
.\upgrade_tool.exe ssd
# Select EMMC
.\upgrade_tool.exe ssd
# Verify * marks EMMC, then enter Q
.\upgrade_tool.exe rfi
.\upgrade_tool.exe uf "$ImageDir\update.img" -noreset
# Require complete upgrade success before resetting
.\upgrade_tool.exe rd
```

Power off, disconnect the flashing USB cable, leave the SD card removed, release
BOOT and power on normally. Confirm Android boots from eMMC using HDMI or the
serial console. If the old bootloader still appears, check NOR erase success;
if eMMC is not detected, check storage selection, Loader and power.

## 6. References and verification scope

The tool archives include Rockchip's command manual and revision history:
`db` downloads Boot to RAM; `ssd` selects storage; `rfi` reads capacity;
`el` erases sectors; `uf` flashes complete firmware. Windows manual §1.8
explicitly documents SPI NOR sector erasing and §1.10 interactive storage
selection. The Linux manual is older; also consult its revision history.

This documentation update checked product configurations, SDK build scripts,
archive contents and command documentation. No compilation, erasing or physical
flashing was performed. Verify storage enumeration/capacity, successful tool
logs and boot results on the actual hardware revision.
