# TREE/ (vendor side, A14 SDK)

New files this product adds to SDK git repositories — kernel DTS/DTSI,
drivers, kernel and u-boot config fragments — carried here as **real,
readable files** mirroring the SDK tree, so they can be read, diffed and
reviewed directly in this repository:

```
vendor-side/TREE/kernel-6.1/arch/arm64/boot/dts/rockchip/<product>.dts
vendor-side/TREE/kernel-6.1/arch/arm64/configs/<product>.config
vendor-side/TREE/kernel-6.1/drivers/<subsystem>/<driver>.c
vendor-side/TREE/u-boot/configs/<product>.config
```

`setup.sh` installs every file into its SDK repository — a real copy by
default, a symlink with `--symlink` (edits in this repo then take effect on
the next build). `--uninstall` removes exactly what was installed; the list
is tracked in `.seeed-tree-files` at the SDK root, which also drives the
removal of files dropped from this directory since the last run.

## Rules

- **New files only.** Anything the SDK already ships must be modified via
  `../PATCHES/` instead: a patch keeps the delta visible and re-applies on
  SDK rebases, a full-file copy does neither. `setup.sh` refuses a TREE
  entry that is tracked in the SDK.
- **TREE files stay untracked.** Never `git add` an installed file inside
  the SDK repository, and never commit it there. Being untracked is what
  makes the mechanisms interlock: `git stash`, `git diff HEAD` and the
  restore branches never touch these files, so they survive patch
  re-application and cannot leak into exported patches. If a file must
  become part of a patch series, move it to `../PATCHES/` and delete it
  here.
- `git clean` inside an SDK repository deletes TREE files (they are
  untracked); re-run `./setup.sh` to restore them.
- Edits belong in this repository. In copy mode re-run `./setup.sh` after
  changing files here; with `--symlink` the next build picks them up.
- `../PATCHES/` series may reference TREE files (e.g. a Kconfig/Makefile
  hookup for a TREE-carried driver, or `PRODUCT_KERNEL_DTS` selecting a
  TREE-carried DTS): patches alone are not self-contained — TREE + PATCHES
  together are the product's in-tree changes.

Kernel and u-boot files here are derivative works of the upstream sources
they build on and carry their licenses (GPLv2 for the kernel — see the file
headers).
