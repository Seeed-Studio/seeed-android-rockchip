# PATCHES/ (vendor side, A14 SDK)

Commits for **A14 SDK** repositories (u-boot, kernel-6.1, vendor/, RK3576
device trees) that must be modified in place. Everything that *can* live in
`vendor-side/device/seeed/` or `vendor-side/vendor/seeed/` *should* live there
instead — every patch here is rework when Rockchip ships a new SDK snapshot.

The system side has its own equivalent under `system-side/PATCHES/`.

Both chips (RK3576, RK3588) share the single vendor SDK checkout, so repo
paths here (including `kernel-6.1`) are unique — chip-specific work hangs
off different paths (`device/rockchip/rk3576` vs `device/rockchip/rk3588`,
kernel DTS/config), and no per-chip split of this directory is needed.

## Format

This directory mirrors the A14 SDK root. Each tracked project has one
directory:

```
vendor-side/PATCHES/kernel-6.1/
├── git-merge-base.txt   # exactly one line: "commit <40-hex-sha>"
├── 0001-foo.patch       # git format-patch output, applied in order via git am
├── 0002-bar.patch
└── local_diff.diff      # optional; uncommitted changes, applied via git apply
```

The consumer is the SDK's own `restore_patches.sh` (Rockchip mechanism):
for every SDK project with a directory here, it creates a branch at the base
commit and applies the patches on top. `git-merge-base.txt` is therefore the
version anchor — the SDK snapshot must contain that exact commit.

## Workflow (internal)

All commands run from the **A14 SDK root**; the side is auto-detected and the
overlay is found automatically as a sibling directory or via `$SEEED_BSP_DIR`.

```bash
# right after unpacking a new SDK, for each project you are about to touch:
<overlay>/tools/export_patches.sh --init kernel-6.1
<overlay>/tools/export_patches.sh --init device/rockchip/rk3576

# ...hack in the SDK tree, commit your work in the SDK repos...

# refresh the overlay from your tree (any time):
<overlay>/tools/export_patches.sh

# adopting a project you already modified (base = the RK revision you started from):
<overlay>/tools/export_patches.sh --base kernel-6.1=<rk-tag-or-sha>
```

Rules:

- Prefer **committed work** (`*.patch`) over `local_diff.diff`. `local_diff.diff`
  is exported from uncommitted changes as a convenience — it carries no commit
  message, no authorship and no review trail, so treat it as a debt to be
  converted into proper patches before the next release. A release must have
  an empty (absent) `local_diff.diff` everywhere.
- Patches go public as-is: they carry author names, emails, commit messages
  and the entire diff. Review before committing.
- When rebasing to a new SDK snapshot: re-run `--init` for every project on
  the fresh tree, replay your patches, re-run the default export, and update
  `BASE_SDK` (vendor section).
