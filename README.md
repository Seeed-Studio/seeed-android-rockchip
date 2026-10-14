# Seeed Android Rockchip overlay (SSI + GRF fusion)

English | [简体中文](README_zh.md)

This repository carries Seeed's product adaptation for Rockchip-based
devices — RK3576 and RK3588, both built from the shared A14 vendor SDK;
each product lives in its own directory under `vendor-side/device/seeed/`.
It is **not** a standalone Android source tree. The product firmware is a
fusion of two Rockchip SDKs:

- **system side — A17 SSI SDK**: framework / system image (`ssi_17_arm64`,
  Android 17)
- **vendor side — A14 SDK**: u-boot, `kernel-6.1`, `vendor/`, RK3576 / RK3588 device
  trees (GRF, vendor API frozen at A14)

Both SDKs are obtained from Rockchip; this overlay is applied on top of both
with a single command, and the two sides are then fused (see
[docs/BUILD-FLOW.md](docs/BUILD-FLOW.md)).

## What is inside

| Path                          | Installed into | Contents                                        |
|-------------------------------|----------------|-------------------------------------------------|
| `vendor-side/device/seeed/`   | A14 tree       | product device trees (any Rockchip SoC), `BoardConfig`, sepolicy |
| `vendor-side/vendor/seeed/`   | A14 tree       | vendor configs, prebuilt proprietary blobs      |
| `vendor-side/packages/apps/`  | A14 tree       | vendor-side Seeed applications                  |
| `vendor-side/PATCHES/`        | A14 tree       | commits for A14 SDK repos modified in place     |
| `vendor-side/TREE/`           | A14 tree       | new files for A14 SDK repos                     |
| `system-side/device/seeed/`   | A17 tree       | product SSI configuration (derived from `ssi_17_arm64`) |
| `system-side/packages/apps/`  | A17 tree       | system/product Seeed applications               |
| `system-side/PATCHES/`        | A17 tree       | commits for A17 SDK repos modified in place     |
| `system-side/TREE/`           | A17 tree       | new files for A17 SDK repos                     |
| `BASE_SDK`                    | —              | the exact SDK snapshots both sides target — **read this first** |
| `setup.sh`                    | —              | one-command integration into both SDK trees    |
| `tools/`                      | —              | patch export helper, fallback restore body     |

## Requirements

- Both Rockchip SDK snapshots named in [`BASE_SDK`](BASE_SDK). Obtain them
  from Rockchip or your Seeed contact. A different snapshot will most likely
  fail patch application.
- Linux build host with the standard AOSP build packages installed,
  ~600 GB free disk space for two trees.
- `git`, `repo`, `rsync`, and a configured git identity
  (`user.name` / `user.email` — the patch step uses `git am`).

## Build and flash

- [Build guide](docs/BUILD-FLOW.md): complete commands for `recomputer_rk3576_devkit` and `recomputer_rk3588_devkit`, fusion flow and output paths.
- [Flashing guide](docs/FLASHING.md): Windows SD boot cards, RK3576 NOR preparation for SD boot, Linux / Windows eMMC flashing, and the required NOR Flash erase before eMMC boot.
- [Bundled flashing tools](tools/flashing/README.md): the four original tool and driver archives and SHA-256 checksums.

## Quick start

```bash
# 1. Sync/unpack both Rockchip SDKs matching BASE_SDK (a14 + a17 trees).

# 2. Get this overlay and integrate it into both trees:
git clone <repo-url> seeed-android-rockchip
cd seeed-android-rockchip
./setup.sh                          # auto-detects sibling SDK trees, or:
./setup.sh --vendor-sdk /path/a14 --system-sdk /path/a17

# 3. Build both sides and fuse them — see docs/BUILD-FLOW.md:
#    system side:  lunch recomputer_rk3576_ssi-cp2a-userdebug && make dist
#    RK3588 uses recomputer_rk3588_ssi-cp2a-userdebug; see the full guide.
#    vendor side:  ./build.sh -AKUou -M <a17>/out/host/linux-x86/bin/merge_target_files \
#                          -T <a17>/out/dist/<system-product>-target_files-<build>.zip
```

`setup.sh` copies (or with `--symlink`, links) each side's overlay
directories into its SDK tree, installs the new-file content from `TREE/`
into the SDK git repositories, verifies that every patch base commit
exists, applies the patches via the SDKs' own `restore_patches.sh`
mechanism, and verifies the result. Use `--vendor-only` / `--system-only`
to integrate one side.

### Developing with `--symlink`

For working trees (especially with several products in flight) prefer
`./setup.sh --symlink`: overlay content is then edited directly in this
repository and picked up by the next build — no re-run of `setup.sh` after
content changes. Soong does not discover build files through symlinks, so
the install is *hybrid*: `AndroidProducts.mk` / `Android.mk` are real copies
inside the SDK tree (tiny, structural — refreshed by re-running `setup.sh`),
everything else (BoardConfig, product `.mk`, sepolicy, vendor data) is
linked. Consequences:

- files installed from `TREE/` are linked individually — edit them in this
  repository and the next build picks them up;
- changes to existing files, and new files *inside* an already-linked
  directory (e.g. a new camera IQ file, a new sepolicy file), take effect
  immediately;
- re-run `setup.sh --symlink` after adding a new product directory or a new
  top-level file inside one;
- app directories that carry `Android.bp`/`Android.mk` under `packages/apps`
  cannot be symlinked (module discovery again) — `setup.sh` refuses and you
  drop `--symlink` for that side;
- switching between copy and symlink mode: run `--uninstall` first.

## How patching works

Each side has its own `PATCHES/` directory mirroring that SDK's root. Every
tracked SDK project has:

```
vendor-side/PATCHES/kernel-6.1/
├── git-merge-base.txt   # one line: "commit <sha>" — the base the patches apply to
├── 0001-*.patch         # numbered git format-patch files, applied with git am
└── local_diff.diff      # optional: uncommitted changes, applied with git apply
```

The application logic lives in the SDKs (`restore_patches.sh`, shipped by
Rockchip); this repo only carries the data and a fallback copy of the body
script. If a base commit is missing from your SDK, your SDK snapshot does not
match this overlay — get the snapshot listed in `BASE_SDK`.

Re-running `setup.sh` never resets a project whose HEAD has already moved
past its recorded base (e.g. you committed work in the SDK since the last
run): such projects are skipped with a notice instead of being re-patched
from base, so commits not yet exported to this repo survive repeated runs.
Export them with `tools/export_patches.sh` as usual.

## New files vs. patches (`TREE/`)

New files the product adds to an SDK git repository — kernel DTS/DTSI and
drivers, kernel/u-boot config fragments — are carried as real, readable
files under `<side>/TREE/<repo>/...` (mirroring the SDK layout) and
installed by `setup.sh` as *untracked* files inside that repository. Being
untracked is what makes the two mechanisms interlock: `git stash`,
`git diff HEAD` and the restore branches never touch them, so TREE files
survive patch application and never leak into exported patches. Modifying a
file the SDK already ships remains a patch — `setup.sh` refuses a TREE
entry that is tracked in the SDK. Rules and caveats (never `git add` an
installed file, `git clean` deletes them, patches may reference TREE files):
see [`vendor-side/TREE/README.md`](vendor-side/TREE/README.md).

## Versioning

Tags in this repository match firmware releases. `BASE_SDK` pins **both** SDK
snapshots each tag was built against. When Rockchip ships new SDKs, the
overlay is rebased onto them and re-released; older tags keep pointing at
older SDKs.

## Uninstall

```bash
./setup.sh --uninstall [--vendor-only | --system-only]
```

Removes the overlay directories and the files installed from `TREE/`
(tracked in `.seeed-tree-files` at the SDK root) from the SDK tree(s).
Patches already applied to SDK git repositories are **not** reverted (the
patch step works on its own `restore_<date>` branches); re-sync the SDK for
a clean state.
