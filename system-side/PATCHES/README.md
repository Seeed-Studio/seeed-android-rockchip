# system-side/PATCHES/

Commits for **A17 SSI SDK** repositories that must be modified in place.
Format and workflow are identical to the vendor side — see
`../../vendor-side/PATCHES/README.md`; `tools/export_patches.sh` detects the
side automatically when run from the A17 tree.

Everything that *can* be expressed in `system-side/device/seeed/` or
`system-side/packages/apps/` *should* live there instead — every patch here
is rework when Rockchip ships a new SDK snapshot.
