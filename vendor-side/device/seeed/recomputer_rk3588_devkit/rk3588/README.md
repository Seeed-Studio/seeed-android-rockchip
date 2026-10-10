# Bundled RK3588 platform support

This is the subset of `device/rockchip/rk3588` needed by
`recomputer_rk3588_devkit`. The customer needs the A14 vendor SDK named in
`BASE_SDK`; a separate RK3588 device repository is not required.

Source: Rockchip RK3588 Android 14 SDK, project `device/rockchip/rk3588`,
commit `893d5227331f680147b44ed7927e623a687fb5bf`. The files were taken from
the local `a14_rk3588` SDK and matched the copy in the development A14 SDK.
Original copyright notices are retained.

Included:

- `BoardConfig.mk`: architecture, GPU, boot-controller and platform defaults.
- `device.mk`: platform packages, properties and file copies.
- `init.*.rc`, performance XML and `public.libraries.txt`: runtime configuration.
- `overlay/`: framework and application resource defaults.
- `bluetooth/`: Bluetooth build configuration.
- `sepolicy_vendor/`: RK3588 file and sysfs labels.
- `init.gki.rc` and `dtbo_gki_fix.dts`: support when SSI fusion enables GKI.

The platform `device.mk` uses explicit product-local source paths and adds
the local GKI init file before inheriting common configuration. The product
`BoardConfig.mk` selects the local Bluetooth header directory. On Android's
final BoardConfig read, after all product nodes have been imported, it also
redirects the common SELinux and GKI DTBO paths to this directory. Changes
to the shared Rockchip build scripts are unnecessary.

Reference EVB products, their lunch registrations, OTA samples and the unused
`wifi_bt.mk` are omitted. Product-specific changes belong in the parent
directory; keep this platform subset close to its source. Its SELinux labels
still include reference-board nodes and should be reviewed during bring-up.

`setup.sh` installs this directory with the rest of `device/seeed`, in both
copy and `--symlink` modes. No extra installation step is needed. This only
bundles device configuration; kernel, U-Boot, HALs and proprietary libraries
continue to come from the pinned A14 SDK and the overlay's `TREE/`/`PATCHES/`.
