# device/seeed/ (vendor side, A14 SDK)

One subdirectory per product, for any Rockchip SoC — RK3576 and RK3588
products live side by side here (both built from the shared A14 tree with
an identical flow). E.g. `device/seeed/<product>/` containing the usual
Android device tree:

```
AndroidProducts.mk    # registers the lunch target(s)
BoardConfig.mk
device.mk
init.<product>.rc
overlay/              # framework resource overlays
sepolicy/             # product-specific sepolicy additions
```

Porting starts from the product's reference device tree in the A14 SDK —
`device/rockchip/rk3576/rk3576_u` for RK3576 products (the current product
line is based on it; lunch `rk3576_u-userdebug`), the
`device/rockchip/rk3588/` equivalents for RK3588: copy, strip what the
reference board needs but the product does not, then diverge.

## Fusion constraints (SSI + GRF)

This device tree builds the **vendor half** of a fusion firmware whose system
half is an A17 SSI (see `docs/BUILD-FLOW.md`). In practice:

- vendor API level stays frozen at A14 (GRF); do not bump
  `PRODUCT_SHIPPING_API_LEVEL` or VINTF manifest versions on this side
- VNDK/libvintf/SELinux expectations of the SSI must keep matching — test the
  fusion (`build.sh -T`) after any interface-touching change here

## Design rule

This directory is the preferred home for product adaptation on the vendor
side. Before touching an SDK file in place, check whether it can be expressed
here instead:

- config / feature differences → `device.mk`, `PRODUCT_COPY_FILES`, overlays
- sepolicy for new services/hals → `sepolicy/` (wired in via BoardConfig)
- kernel DTS/DTSI → referenced from the kernel build; the DTS source itself
  lives with the kernel patches under `../PATCHES/kernel-6.1/`
- new HALs/daemons → prebuilt or source modules under `../vendor/seeed/` or
  `../packages/apps/`

Only when a change genuinely requires modifying existing SDK sources does it
become a patch — and then it gets recorded via
`tools/export_patches.sh --init <repo>` first (see `../PATCHES/README.md`).
