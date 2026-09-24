# Fusion build flow (SSI + GRF)

How the two SDK trees are turned into one firmware. This mirrors RK's
official guide (`Rockchip_Developer_Guide_Android17_SSI_SDK_{CN,EN}.pdf` in
the A17 SDK's `RKDocs/android/`, §4.4.6 "Method 2" — fusion build from the
vendor SDK) — that document is
authoritative if anything here drifts.

## Overview

```
┌─────────────────────────────────────┐
│ system side (A17 SSI SDK)           │
│   source build/envsetup.sh          │
│   lunch <SYSTEM_LUNCH>              │
│   make dist -j$(nproc)              │
│ produces TWO fusion inputs:         │
│   out/dist/ssi_17_arm64-target_files-*.zip        (framework target-files)
│   out/host/linux-x86/bin/merge_target_files       (merge tool, -M)
└──────────────────┬──────────────────┘
                   │  -T (zip)   -M (merge tool)
                   ▼
┌─────────────────────────────────────┐
│ vendor side (A14 SDK)               │
│   source build/envsetup.sh          │
│   lunch <VENDOR_LUNCH>              │
│   ./build.sh -AKUu -M <tool> -T <zip>    │
│   1. extract_ssi_config             │
│   2. make installclean + make -j    │
│   3. make dist  (vendor target-files)    │
│   4. rk_merge_target_files (fuse)   │
│ outputs: rockdev/Image-<product>/    │
│   *-target-files-merged.zip,         │
│   *-images-merged-fastboot.zip,      │
│   super.img, update.img              │
└─────────────────────────────────────┘
```

## Phase 1 — system side (A17 SSI)

```bash
cd <a17-tree>
source build/envsetup.sh
lunch <SYSTEM_LUNCH>          # stock RK SSI target for now (see BASE_SDK);
                              # becomes the product SSI config once derived
make dist -j$(nproc)
# -> out/dist/ssi_17_arm64-target_files-<date>.zip
# -> out/host/linux-x86/bin/merge_target_files
```

The SSI side does **not** produce `update.img` — final image packing happens
on the vendor side.

> Note on `-M`: RK's guide quotes the merge tool as
> `build/make/tools/releasetools/merge/merge_target_files`, but that
> directory ships **Python source** (`merge_target_files.py` + `Android.bp`).
> The Soong-built host binary lands in `out/host/linux-x86/bin/` — that is
> the path that actually works with `build.sh -M` (verified on this SDK
> drop). RK's prebuilt drops (guide "Option B") ship the binary under the doc's path,
> which is where the discrepancy comes from.

What ends up in the SSI is controlled by the product config in
`system-side/device/seeed/` (derived from
`device/rockchip/rockchip_generic/ssi_17_arm64`).

## Phase 2 — vendor side (A14 GRF) and fusion

`build.sh` is a one-key script that drives the vendor build itself, but it
runs on top of a chosen lunch environment — set it first (see
`RK3576_Developer_Guide_Android14_SDK_EN.pdf` in the A14 SDK's
`RKDocs/android/`, "Code compiling"):

```bash
cd <a14-tree>
source build/envsetup.sh
lunch <VENDOR_LUNCH>          # product device tree installed by this overlay
./build.sh -AKUu \
    -M <a17-tree>/out/host/linux-x86/bin/merge_target_files \
    -T <a17-tree>/out/dist/ssi_17_arm64-target_files-<date>.zip
#          │  │  ││
#          │  │  ││ └─ update.img packing
#          │  │  │└── OTA package / vendor target-files
#          │  │  └─── u-boot
#          │  └────── kernel
#          └───────── android (vendor side)
```

`build.sh` at the tree root is a symlink to
`device/rockchip/common/build/rockchip/build.sh` — the `-M`/`-T` fusion
support is **stock Rockchip content** in the `device/rockchip/common` repo,
so customers get it with the SDK; this overlay needs no patch for it.
(Verify the symlink target on SDK rebases.)

With `-M` and `-T` present, build.sh automatically:

1. `extract_ssi_config` — pulls AVB / super partition size / GKI /
   shipping API level / 64-bit-only out of the A17 target-files and applies
   them as overrides to the A14 vendor build configuration
2. `make installclean` + `make -j` — rebuilds vendor with the aligned config
3. `make dist` — produces the vendor target-files
4. `rk_merge_target_files` — fuses A17 framework + A14 vendor target-files:
   rebuilds `super.img` with `lpmake`, emits
   `*-target-files-merged.zip` and `*-images-merged-fastboot.zip`, and
   extracts all images to `rockdev/Image-<product>/`

Note: `-M` and `-T` require `-o` (OTA/target-files mode) per build.sh usage.

## Rules

- Vendor-API freeze: the A17 SSI carries `PRODUCT_EXTRA_VNDK_VERSIONS := 34`
  (GRF for A14 vendor). Any vendor-side change that bumps the vendor API or
  VINTF manifest version breaks the fusion contract — test the fusion after
  any interface-touching change.
- Both sides' inputs must come from the same overlay tag + the SDK snapshots
  in `BASE_SDK`. Mixing sides from different tags is unsupported.

## Alternatives (reference)

- RK's guide also documents "Method 1": drive **both** trees from the A17 side
  with `rkbuild` (`device/rockchip/rockchip_generic/tools/rkbuild.py`:
  `rkbuild_setup` links the Vendor SDK, `rkbuild_build all -p` builds
  ssi/vendor/kernel/uboot and packs `update.img` under the A17 tree's
  `rockdev/Image-<product>/`). Same artifacts, different driver — the
  overlay does not depend on which one you use.
- "Option B" in the guide (prebuilt framework files from RK's internal server)
  is an internal-only shortcut; the open-source flow is always "Option A"
  (build the SSI yourself).
