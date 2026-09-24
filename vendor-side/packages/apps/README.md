# packages/apps/ (vendor side, A14 SDK)

Seeed applications that ship in the **vendor partitions** (built by the A14
tree): HAL companions, daemons talking to vendor processes, tools needed
before the system side boots. Source form is preferred; prebuilt APKs are
acceptable for third-party components.

Apps that belong to the system/product partitions go to
`../../../system-side/packages/apps/` instead.

Naming: prefix modules and directories with `Seeed`/`seeed_` so they cannot
collide with AOSP or Rockchip module names — `setup.sh --uninstall` removes
exactly the top-level directories present here, so a collision would also
break uninstall.
