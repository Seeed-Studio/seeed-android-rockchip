# RK3576 SD boot support

These two prebuilt files were supplied in the workspace and copied unchanged.
They are specific to `recomputer_rk3576_devkit`; do not use them on RK3588.
No compilation was performed to produce these copies.

- `rk3576_loader_src_usbplug.bin`: download to RAM using `upgrade_tool db`.
- `rk3576_idblock_src_usbplug.img`: write to SPI NOR to enable SD boot.

The RK3576 board boot mode is `FSPI0 -> UFS -> USB`; its BROM does not boot
SD directly. Keep the NOR SD boot image installed when using SD. Erase NOR
when switching to the eMMC boot procedure.

See [English instructions](../../../docs/FLASHING.md) /
[中文说明](../../../docs/FLASHING_zh.md) for storage selection and commands.

Verify from this directory with `sha256sum -c SHA256SUMS`.
