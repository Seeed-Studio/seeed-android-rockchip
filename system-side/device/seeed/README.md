# system-side/device/seeed/

> Status: not derived yet — no system-side code has been modified so far,
> and builds use the stock RK SSI target (`ssi_17_arm64-cp2a-userdebug`)
> directly. Populate this directory when the first system-side
> customization actually lands; until then the fusion firmware is
> stock-SSI + Seeed vendor side.

Product SSI configuration, installed into the **A17 SSI SDK** tree. One
subdirectory per product, e.g. `device/seeed/<product>_ssi/`:

```
AndroidProducts.mk        # registers the lunch target
<product>_ssi.mk          # PRODUCT_NAME/PACKAGE etc., derived from
                          # device/rockchip/rockchip_generic/ssi_17_arm64/ssi_17_arm64.mk
device.mk                 # product additions on top of the SSI skeleton
```

Porting: copy `device/rockchip/rockchip_generic/ssi_17_arm64/` from the A17
SDK as the starting point, then change identity (PRODUCT_NAME / DEVICE /
BRAND / MODEL) and keep:
- `PRODUCT_SHIPPING_API_LEVEL := 37` (A17 launch)
- `PRODUCT_EXTRA_VNDK_VERSIONS := 34` — **the GRF contract**: this is what
  allows the SSI to boot on the A14 vendor side. Removing it breaks the
  fusion firmware.
- `DEVICE_IS_64BIT_ONLY := true`, `PRODUCT_CHARACTERISTICS := tablet` per RK's
  generic skeleton (adjust only with RK's guidance)

Lunch naming: RK's `COMMON_LUNCH_CHOICES` carry a build-id variant
(`ssi_17_arm64-cp2a-userdebug`); keep the same scheme for the product
(`<product>-cp2a-userdebug`), matching `SYSTEM_LUNCH` in `BASE_SDK`.

System-side product content (apps, overlays, product-partition files) hangs
off this config; see `../packages/apps/`.

In-place modifications of the A17 SDK belong in `system-side/PATCHES/`
(format and workflow: see `vendor-side/PATCHES/README.md`; the side is
auto-detected by `tools/export_patches.sh`).
