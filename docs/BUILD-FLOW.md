# Build guide (A17 SSI + A14 GRF fusion)

English | [简体中文](BUILD-FLOW_zh.md)

Both boards share the A14 vendor SDK and A17 system SDK pinned in [BASE_SDK](../BASE_SDK), with separate product configurations. Build A17 first, then build and fuse on A14 to produce `update.img`. No compilation was performed for this documentation update.

## 1. Prepare SDKs and overlay

Obtain both matching SDK snapshots, install the standard AOSP Linux build dependencies, and reserve approximately 600 GB for the two trees. Install `git`, `repo`, `rsync`, `unzip`, and configure Git user name/email. Follow the SDK's Rockchip build guide for host package requirements.

Example directory layout:

```text
/path/work/
├── a14/
├── a17/
└── seeed-android-rockchip/
```

```bash
cd /path/work/seeed-android-rockchip
./setup.sh --vendor-sdk /path/work/a14 --system-sdk /path/work/a17
```

## 2. Choose a board

| Board | A17 lunch | A14 lunch | A14 firmware directory |
|---|---|---|---|
| `recomputer_rk3576_devkit` | `recomputer_rk3576_ssi-cp2a-userdebug` | `recomputer_rk3576_devkit-userdebug` | `rockdev/Image-recomputer_rk3576_devkit/` |
| `recomputer_rk3588_devkit` | `recomputer_rk3588_ssi-cp2a-userdebug` | `recomputer_rk3588_devkit-userdebug` | `rockdev/Image-recomputer_rk3588_devkit/` |

## 3. reComputer RK3576 DevKit

Build the A17 system in the first terminal:

```bash
cd /path/work/a17
source build/envsetup.sh
lunch recomputer_rk3576_ssi-cp2a-userdebug
make dist -j$(nproc)
```

After success, build and fuse the A14 vendor in a second terminal. Replace `SSI_TARGET_FILES` with the exact file produced by this A17 build; do not pass a wildcard or use the other board's artifact:

```bash
cd /path/work/a14
source build/envsetup.sh
lunch recomputer_rk3576_devkit-userdebug
SSI_TARGET_FILES="/path/work/a17/out/dist/recomputer_rk3576_ssi-target_files-<build>.zip"
./build.sh -AKUou \
    -M /path/work/a17/out/host/linux-x86/bin/merge_target_files \
    -T "$SSI_TARGET_FILES"
```

## 4. reComputer RK3588 DevKit

Build the A17 system in the first terminal:

```bash
cd /path/work/a17
source build/envsetup.sh
lunch recomputer_rk3588_ssi-cp2a-userdebug
make dist -j$(nproc)
```

After success, build and fuse the A14 vendor in a second terminal. Replace `SSI_TARGET_FILES` with the exact file produced by this A17 build; do not pass a wildcard or use the other board's artifact:

```bash
cd /path/work/a14
source build/envsetup.sh
lunch recomputer_rk3588_devkit-userdebug
SSI_TARGET_FILES="/path/work/a17/out/dist/recomputer_rk3588_ssi-target_files-<build>.zip"
./build.sh -AKUou \
    -M /path/work/a17/out/host/linux-x86/bin/merge_target_files \
    -T "$SSI_TARGET_FILES"
```

## 5. Flags and outputs

`-A` builds Android vendor, `-K` the kernel, `-U` U-Boot, `-o` OTA / vendor target-files, and `-u` packs `update.img`. Fusion needs `-o`; omitting it can leave vendor target-files missing or reuse stale artifacts.

`-M` is the A17-built host executable, not the source `merge_target_files.py`. `-T` is the matching board's A17 target-files ZIP. A17 alone does not produce the final `update.img`.

The A14 script extracts SSI configuration, builds vendor and vendor target-files, runs `rk_merge_target_files` to fuse framework and vendor, then packs firmware. Outputs are in the board directory listed above:

- `update.img`: complete firmware for SDDiskTool and upgrade_tool.
- `MiniLoaderAll.bin`: the matching board's USB download Loader for NOR erasing and storage selection.
- `super.img`, `*-target-files-merged.zip`, `*-images-merged-fastboot.zip`: fusion outputs.

Use the same overlay version and pinned SDKs for both sides. Never mix RK3576 and RK3588 Loaders or images. When switching boards, lunch the corresponding products again and retain each board's A17 target-files separately. The RK3588 SSI enables HDMI-RX and should use its own SSI product.

## 6. Flashing and references

Continue with [SD / eMMC flashing](FLASHING.md). **Erase NOR Flash before booting from eMMC.**

Implementation references: A14 `device/rockchip/common/build/rockchip/build.sh` and `mkimage.sh`; A17 `RKDocs/android/Rockchip_Developer_Guide_Android17_SSI_SDK_{CN,EN}.pdf` §4.4.6 Method 2. Rockchip also documents driving both builds from A17 using `rkbuild` (Method 1); this guide uses vendor-driven fusion.

The A17 SSI keeps `PRODUCT_EXTRA_VNDK_VERSIONS := 34` for the A14 vendor API freeze. Revalidate fusion after vendor API / VINTF interface changes.
