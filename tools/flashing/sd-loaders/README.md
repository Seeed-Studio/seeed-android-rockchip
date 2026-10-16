# USB-to-SD flashing Loaders

Prebuilt files supplied in the workspace and copied without modification:

| Board | Loader for `db` |
|---|---|
| `recomputer_rk3576_devkit` | `rk3576_loader_tf_usbplug.bin` |
| `recomputer_rk3588_devkit` | `rk3588_MiniLoaderAll.bin` |

These Loaders support writing firmware directly to the SD card installed in the
board after entering Maskrom and downloading the matching Loader with `db`.
Use the matching board's `update.img`. Check the reported storage capacity against
the inserted SD card before writing; do not assume a generic SDK Loader has the
same target storage behavior.

SD flashing and persistent boot preparation are separate operations. RK3576
still needs its NOR SD boot idblock because its BROM cannot boot SD directly.
The earlier RK3576 Loader used by the NOR procedure is retained separately as
`../rk3576-sd-boot/rk3576_loader_src_usbplug.bin`; it is not this updated SD Loader.

Instructions: [English](../../../docs/FLASHING.md) /
[简体中文](../../../docs/FLASHING_zh.md).

Verify from this directory with `sha256sum -c SHA256SUMS`.
No compilation or hardware flashing was performed when adding these files.
