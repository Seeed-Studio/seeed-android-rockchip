# system-side/packages/apps/

Seeed applications that ship in the **system/product partitions** of the SSI
(built by the A17 tree). Source form is preferred; prebuilt APKs are
acceptable for third-party components.

Naming: prefix modules and directories with `Seeed`/`seeed_` so they cannot
collide with AOSP or Rockchip module names — `setup.sh --uninstall` removes
exactly the top-level directories present here, so a collision would also
break uninstall.

Apps that must live on the vendor side (HAL companions, daemons talking to
vendor processes) go to `../../vendor-side/packages/apps/` instead.
