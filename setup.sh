#!/bin/bash
#
# setup.sh — integrate the Seeed Android Rockchip overlay into the two
# Rockchip SDK trees that make up an SSI + GRF fusion firmware:
#
#   vendor side   A14 SDK: u-boot, kernel-6.1, vendor/, device/rockchip/rk35xx
#                 (one checkout shared by RK3576, RK3588, ...)
#   system side   A17 SSI SDK: device/rockchip/rockchip_generic (ssi_17_arm64 ...)
#
# Usage (from this repo):
#   ./setup.sh [--vendor-sdk DIR] [--system-sdk DIR] [options]
#
# SDK directories are auto-detected among the siblings of this repo when not
# given explicitly:
#   vendor side = tree containing a device/rockchip/rk35xx directory (any SoC)
#   system side = tree containing device/rockchip/rockchip_generic
#
# Options:
#   --vendor-sdk DIR  Vendor-side (A14 GRF) SDK tree
#   --system-sdk DIR  System-side (A17 SSI) SDK tree
#   --vendor-only     Only integrate the vendor side
#   --system-only     Only integrate the system side
#   --symlink         Dev install: link overlay content into the SDK trees so
#                     edits here take effect immediately (build-discovery
#                     files like AndroidProducts.mk stay real copies; apps
#                     with Android.bp cannot be linked)
#   --no-patches      Skip applying the SDK patches from */PATCHES/
#                     (new-file content from */TREE/ is still installed)
#   --uninstall       Remove what a previous run installed (see README caveats)
#   -h, --help        Show this help
#
set -uo pipefail

OVERLAY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info() { echo "[setup] $*"; }
warn() { echo "[setup] WARNING: $*" >&2; }
die()  { echo "[setup] ERROR: $*" >&2; exit 1; }

# Filtered patch sets built by apply_patches(); removed on exit.
FILTERED_DIRS=()
cleanup_filtered() {
    local d
    for d in "${FILTERED_DIRS[@]+"${FILTERED_DIRS[@]}"}"; do rm -rf "$d"; done
}
trap cleanup_filtered EXIT

usage() { sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# ---------------------------------------------------------------------------
# Side definitions: everything that differs between the two SDK trees
# ---------------------------------------------------------------------------
side_root()      { echo "$OVERLAY_ROOT/$1-side"; }
side_label()     { case "$1" in vendor) echo "vendor (A14 GRF)";; system) echo "system (A17 SSI)";; esac; }
side_manifest_key() { case "$1" in vendor) echo VENDOR_MANIFEST_SHA;; system) echo SYSTEM_MANIFEST_SHA;; esac; }
side_lunch_key() { case "$1" in vendor) echo VENDOR_LUNCH;; system) echo SYSTEM_LUNCH;; esac; }
side_expect()    { case "$1" in vendor) echo "a device/rockchip/rk35xx directory (RK3576/RK3588 vendor SDK)";; system) echo "device/rockchip/rockchip_generic (SSI SDK)";; esac; }

# The vendor side is ONE A14 SDK checkout shared by all supported chips;
# it carries the per-chip product directories under device/rockchip/rk35xx.
has_side_marker() {  # sdk_dir side
    local sdk="$1" d
    case "$2" in
        system) [[ -d "$sdk/device/rockchip/rockchip_generic" ]] ;;
        vendor)
            for d in "$sdk"/device/rockchip/rk*/; do
                [[ -d "$d" ]] && return 0
            done
            return 1
            ;;
    esac
}

side_overlay_dirs() {
    case "$1" in
        vendor) echo "device/seeed vendor/seeed packages/apps" ;;
        system) echo "device/seeed packages/apps" ;;
    esac
}
side_owned_dirs() {
    case "$1" in
        vendor) echo "device/seeed vendor/seeed" ;;
        system) echo "device/seeed" ;;
    esac
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
MODE=copy
APPLY_PATCHES=1
UNINSTALL=0
WANT_VENDOR=1
WANT_SYSTEM=1
VENDOR_SDK_DIR=""
SYSTEM_SDK_DIR=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --vendor-sdk)   [[ $# -ge 2 ]] || die "--vendor-sdk needs a value"; VENDOR_SDK_DIR="$2"; shift 2 ;;
        --system-sdk)   [[ $# -ge 2 ]] || die "--system-sdk needs a value"; SYSTEM_SDK_DIR="$2"; shift 2 ;;
        --vendor-only)  WANT_VENDOR=1; WANT_SYSTEM=0; shift ;;
        --system-only)  WANT_VENDOR=0; WANT_SYSTEM=1; shift ;;
        --symlink)      MODE=symlink; shift ;;
        --no-patches)   APPLY_PATCHES=0; shift ;;
        --uninstall)    UNINSTALL=1; shift ;;
        -h|--help)      usage; exit 0 ;;
        --*)            die "unknown option: $1" ;;
        *)              die "unexpected argument: $1 (use --vendor-sdk/--system-sdk)" ;;
    esac
done

# ---------------------------------------------------------------------------
# SDK detection / validation
# ---------------------------------------------------------------------------
is_sdk_tree()     { [[ -f "$1/build/envsetup.sh" && -d "$1/.repo" ]]; }

resolve_sdk_dir() {  # side given -> prints absolute dir, nonzero if not found
    local side="$1" given="$2" candidate dir
    for dir in "$given" "${RK_SDK_DIR:-}"; do
        [[ -n "$dir" ]] || continue
        [[ -d "$dir" ]] || die "$side SDK directory not found: $dir"
        dir="$(cd "$dir" && pwd)"
        if is_sdk_tree "$dir" && has_side_marker "$dir" "$side"; then
            echo "$dir"; return 0
        fi
        die "$dir does not look like the $side SDK tree (expected $(side_expect "$side"))"
    done
    for candidate in "$OVERLAY_ROOT"/../*/; do
        [[ -d "$candidate" ]] || continue
        if is_sdk_tree "$candidate" && has_side_marker "$candidate" "$side"; then
            (cd "$candidate" && pwd); return 0
        fi
    done
    return 1
}

VENDOR_SDK_DIR="$(resolve_sdk_dir vendor "$VENDOR_SDK_DIR")" \
    || die "vendor SDK not found; pass --vendor-sdk DIR (A14 tree with device/rockchip/rk35xx)"
SYSTEM_SDK_DIR="$(resolve_sdk_dir system "$SYSTEM_SDK_DIR")" \
    || die "system SDK not found; pass --system-sdk DIR (A17 tree with device/rockchip/rockchip_generic)"

declare -A SDK_DIR=( [vendor]="$VENDOR_SDK_DIR" [system]="$SYSTEM_SDK_DIR" )

for side in vendor system; do
    if [[ "$side" == vendor && "$WANT_VENDOR" == 0 ]] || [[ "$side" == system && "$WANT_SYSTEM" == 0 ]]; then
        continue
    fi
    sdk="${SDK_DIR[$side]}"
    is_sdk_tree "$sdk" || die "$sdk is not a repo-managed Android SDK tree (build/envsetup.sh + .repo)"
    info "$side SDK ($(side_label "$side")): $sdk"
done
[[ "$WANT_VENDOR" == 1 || "$WANT_SYSTEM" == 1 ]] || die "nothing selected"

base_sdk_value() { sed -n "s/^$1=//p" "$OVERLAY_ROOT/BASE_SDK" 2>/dev/null | head -1; }

# ---------------------------------------------------------------------------
# Per-side operations
# ---------------------------------------------------------------------------
check_base_sdk() {  # side sdk
    local side="$1" sdk="$2" want_sha have_sha
    want_sha="$(base_sdk_value "$(side_manifest_key "$side")")"
    if [[ -n "$want_sha" && "$want_sha" != "<fill-in"* && -d "$sdk/.repo/manifests" ]]; then
        have_sha="$(git -C "$sdk/.repo/manifests" rev-parse HEAD 2>/dev/null || true)"
        if [[ -n "$have_sha" && "$have_sha" != "$want_sha" ]]; then
            warn "$side SDK manifest $have_sha differs from BASE_SDK ($want_sha) — snapshot may not match."
        fi
    fi
}

# Overlay directories the SDK tree does not otherwise carry: installed (and
# uninstalled) as whole directories. Other overlay dirs (packages/apps) exist
# in the SDK, so they are synced entry by entry instead — see install_overlay().
owned_dir() {  # side d
    local d
    for d in $(side_owned_dirs "$1"); do
        [[ "$d" == "$2" ]] && return 0
    done
    return 1
}

# Files the build system locates by walking the tree: soong's source finder
# does not follow symlinks (and forcing ALLOW_BP_UNDER_SYMLINKS makes it scan
# the entire tree through every link — minutes to hours), so these must exist
# as REAL files inside the SDK tree. Everything else can be a symlink and is
# edited directly in this repository. Keep in sync with the soong finder's
# IncludeFiles list (build/soong/ui/build/finder.go) as needed.
DISCOVERY_FILES="AndroidProducts.mk Android.mk"

# --symlink install of a directory that carries build-discoverable content
# (e.g. device/seeed/<product>/AndroidProducts.mk): real directory with real
# copies of the discovery files, everything else linked from the overlay.
install_hybrid_dir() {  # side rel src dst
    local side="$1" rel="$2" src="$3" dst="$4" entry name sub sname bad=""
    if [[ -L "$dst" ]]; then rm "$dst"; fi   # replace a previous whole-dir link
    if [[ -d "$dst" ]]; then
        # A previous hybrid install may be re-run; anything else must go
        # through --uninstall first so no foreign content gets mixed in.
        for entry in "$dst"/* "$dst"/.[!.]*; do
            [[ -e "$entry" ]] || continue
            name="$(basename "$entry")"
            [[ -L "$entry" ]] && continue
            [[ " $DISCOVERY_FILES " == *" $name "* ]] && continue
            # our own hybrid product directory from a previous run
            [[ -d "$entry" && -f "$src/$name/AndroidProducts.mk" ]] && continue
            bad="$bad $name"
        done
        [[ -z "$bad" ]] || die "$dst contains non-overlay content ($bad); run ./setup.sh --uninstall first"
    elif [[ -e "$dst" ]]; then
        die "$dst exists and is not a directory; remove it or use copy mode"
    fi
    mkdir -p "$dst"
    for entry in "$src"/* "$src"/.[!.]*; do
        [[ -e "$entry" ]] || continue
        name="$(basename "$entry")"
        if [[ -d "$entry" ]] && [[ -f "$entry/AndroidProducts.mk" ]]; then
            # product directory: one level deeper, same split
            mkdir -p "$dst/$name"
            for sub in "$entry"/* "$entry"/.[!.]*; do
                [[ -e "$sub" ]] || continue
                sname="$(basename "$sub")"
                if [[ -f "$sub" && " $DISCOVERY_FILES " == *" $sname "* ]]; then
                    cp -a "$sub" "$dst/$name/$sname"
                    info "[$side] copied  $rel/$name/$sname (build discovery)"
                else
                    ln -sfn "$sub" "$dst/$name/$sname"
                    info "[$side] linked  $rel/$name/$sname"
                fi
            done
        else
            ln -sfn "$entry" "$dst/$name"
            info "[$side] linked  $rel/$name"
        fi
    done
}

# Install one directory (whole overlay dir or a single entry of a merged dir).
# Copy mode mirrors the source exactly (--delete): files removed from the
# overlay must not linger in the SDK tree as ghosts.
install_path() {  # side rel src dst
    local side="$1" rel="$2" src="${3%/}" dst="$4"
    if [[ "$MODE" == symlink ]]; then
        if [[ -n "$(find "$src" -mindepth 2 -maxdepth 2 -name AndroidProducts.mk -print -quit 2>/dev/null)" ]]; then
            install_hybrid_dir "$side" "$rel" "$src" "$dst"
        else
            if [[ -e "$dst" && ! -L "$dst" ]]; then
                die "$dst already exists and is not a symlink; remove it or use copy mode"
            fi
            ln -sfn "$src" "$dst"
            info "[$side] linked  $rel"
        fi
    else
        mkdir -p "$dst"
        if command -v rsync >/dev/null 2>&1; then
            rsync -a --delete "$src/" "$dst/"
        else
            cp -a "$src/." "$dst/"
        fi
        info "[$side] copied  $rel"
    fi
}

install_overlay() {  # side sdk
    local side="$1" sdk="$2" d src dst entry name
    for d in $(side_overlay_dirs "$side"); do
        src="$(side_root "$side")/$d"
        [[ -d "$src" ]] || { info "[$side] skip $d (not present in overlay)"; continue; }
        dst="$sdk/$d"
        mkdir -p "$(dirname "$dst")"
        if owned_dir "$side" "$d"; then
            install_path "$side" "$d" "$src" "$dst"
        else
            # Merged directory shared with the SDK: sync only our top-level
            # entries, never the directory itself — the SDK's own content
            # lives next to ours. (Also why symlink mode links per entry:
            # linking the whole directory would shadow the SDK's apps.)
            for entry in "$src"/*/; do
                [[ -d "$entry" ]] || continue
                name="$(basename "$entry")"
                if [[ "$MODE" == symlink ]] && \
                   find "$entry" -maxdepth 2 \( -name Android.bp -o -name Android.mk \) -print -quit 2>/dev/null | grep -q .; then
                    die "$d/$name carries Android.bp/Android.mk — soong does not discover modules through symlinks; install apps with copy mode (drop --symlink)"
                fi
                install_path "$side" "$d/$name" "$entry" "$dst/$name"
            done
            if [[ -f "$src/README.md" ]]; then
                if [[ -e "$dst/README.md" ]]; then
                    info "[$side] left existing $d/README.md in place"
                elif [[ "$MODE" == symlink ]]; then
                    ln -sfn "$src/README.md" "$dst/README.md"
                    info "[$side] linked  $d/README.md"
                else
                    cp -a "$src/README.md" "$dst/README.md"
                    info "[$side] copied  $d/README.md"
                fi
            fi
        fi
    done
}

uninstall_side() {  # side sdk
    local side="$1" sdk="$2" d sub name readme_src readme_dst
    uninstall_tree "$side" "$sdk"
    for d in $(side_owned_dirs "$side"); do
        if [[ -e "$sdk/$d" || -L "$sdk/$d" ]]; then
            rm -rf "${sdk:?}/$d"
            info "[$side] removed $d"
        fi
    done
    local merged="packages/apps"
    if [[ -d "$(side_root "$side")/$merged" ]]; then
        for sub in "$(side_root "$side")/$merged"/*/; do
            [[ -d "$sub" ]] || continue
            name="$(basename "$sub")"
            if [[ -e "$sdk/$merged/$name" || -L "$sdk/$merged/$name" ]]; then
                rm -rf "${sdk:?}/$merged/$name"
                info "[$side] removed $merged/$name"
            fi
        done
        # Only remove a README.md we installed (our symlink, or a copy that
        # still matches the overlay's); the SDK may ship one of its own.
        readme_src="$(side_root "$side")/$merged/README.md"
        readme_dst="$sdk/$merged/README.md"
        if [[ -L "$readme_dst" ]] || { [[ -f "$readme_dst" ]] && cmp -s "$readme_src" "$readme_dst"; }; then
            rm -f "$readme_dst"
            info "[$side] removed $merged/README.md"
        elif [[ -e "$readme_dst" ]]; then
            warn "[$side] left $merged/README.md in place (not installed by this overlay)"
        fi
    fi
}

# ---------------------------------------------------------------------------
# TREE/: new files carried as real, readable files in this repo and installed
# verbatim into SDK git projects as *untracked* files — kernel DTS/DTSI,
# drivers, kernel/u-boot config fragments, anything the SDK does not carry.
# Existing (tracked) SDK files must go through PATCHES/ instead; setup.sh
# enforces the split. Untracked placement is what makes the two mechanisms
# interlock: git stash / git diff / restore branches never touch these files.
# ---------------------------------------------------------------------------
tree_dir_of() { echo "$(side_root "$1")/TREE"; }

tree_files() {  # side -> "<repo>/<path>" per carried file, sorted
    local prefix
    prefix="$(tree_dir_of "$1")"
    [[ -d "$prefix" ]] || return 0
    find "$prefix" -type f | sort | sed "s|^$prefix/||" | grep -vx 'README.md' || true
}

# Delete one installed TREE file (if the SDK repo has not adopted it) and
# prune the empty parent directories it leaves behind.
tree_remove_path() {  # sdk rel
    local sdk="$1" rel="$2" repo d
    repo="${rel%%/*}"
    if git -C "$sdk/$repo" ls-files --error-unmatch "${rel#"$repo"/}" >/dev/null 2>&1; then
        warn "TREE: $rel has become tracked in the SDK — leaving it in place"
        return 0
    fi
    rm -f "$sdk/$rel"
    d="$(dirname "$sdk/$rel")"
    while [[ "$d" == "$sdk/$repo/"* && -d "$d" ]]; do
        rmdir --ignore-fail-on-non-empty "$d" 2>/dev/null || break
        d="$(dirname "$d")"
    done
}

install_tree() {  # side sdk
    local side="$1" sdk="$2" rel src dst repo manifest tmp stale
    manifest="$sdk/.seeed-tree-files"
    tmp="$(mktemp)"
    tree_files "$side" > "$tmp"
    # Drop files a previous run installed that the overlay no longer carries.
    if [[ -f "$manifest" ]]; then
        while IFS= read -r stale; do
            [[ -n "$stale" ]] || continue
            tree_remove_path "$sdk" "$stale"
            info "[$side] removed stale TREE file $stale"
        done < <(comm -23 <(sort "$manifest") "$tmp")
    fi
    while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        repo="${rel%%/*}"
        if [[ ! -e "$sdk/$repo/.git" ]]; then
            die "TREE carries $rel but $repo is not a git project in the $side SDK tree"
        fi
        if git -C "$sdk/$repo" ls-files --error-unmatch "${rel#"$repo"/}" >/dev/null 2>&1; then
            die "TREE file $rel is tracked in the SDK — existing files must be patched via PATCHES/, not carried in TREE/"
        fi
        src="$(tree_dir_of "$side")/$rel"
        dst="$sdk/$rel"
        if [[ -e "$dst" && ! -L "$dst" ]] && ! cmp -s "$src" "$dst"; then
            die "$dst already exists with different content; remove it or reconcile it with TREE/$rel"
        fi
        if [[ "$MODE" == symlink ]]; then
            mkdir -p "$(dirname "$dst")"
            ln -sfn "$src" "$dst"
            info "[$side] linked  TREE/$rel"
        else
            rm -f "$dst"
            mkdir -p "$(dirname "$dst")"
            cp -a "$src" "$dst"
            info "[$side] copied  TREE/$rel"
        fi
    done < "$tmp"
    if [[ -s "$tmp" ]]; then
        cp "$tmp" "$manifest"
    elif [[ -f "$manifest" ]]; then
        rm -f "$manifest"
    fi
    rm -f "$tmp"
}

uninstall_tree() {  # side sdk
    local side="$1" sdk="$2" manifest rel
    manifest="$sdk/.seeed-tree-files"
    [[ -f "$manifest" ]] || return 0
    while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        tree_remove_path "$sdk" "$rel"
        info "[$side] removed TREE file $rel"
    done < "$manifest"
    rm -f "$manifest"
}

patches_dir_of() { echo "$(side_root "$1")/PATCHES"; }

patched_projects() {  # patches_dir
    local f prefix="$1"
    while IFS= read -r f; do
        dirname "${f#"$prefix"/}"
    done < <(find "$prefix" -type f -name git-merge-base.txt 2>/dev/null)
}

base_sha_of() {  # patches_dir repo_path
    awk '$1 == "commit" { print $2; exit }' "$1/$2/git-merge-base.txt" 2>/dev/null
}

has_patch_content() {  # patches_dir repo_path
    find "$1/$2" -maxdepth 1 \( -name '*.patch' -o -name 'local_diff.diff' \) -print -quit 2>/dev/null | grep -q .
}

check_git_identity() {
    if [[ -z "${GIT_COMMITTER_EMAIL:-}${GIT_AUTHOR_EMAIL:-}" ]] \
       && ! git config --global --get user.email >/dev/null 2>&1; then
        die "git identity is not configured, but 'git am' (patch step) needs it. Run:
  git config --global user.name  \"Your Name\"
  git config --global user.email \"you@example.com\""
    fi
}

verify_patch_bases() {  # side sdk
    local side="$1" sdk="$2" pd failures=0 p sha
    pd="$(patches_dir_of "$side")"
    while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        sha="$(base_sha_of "$pd" "$p")"
        if [[ -z "$sha" || ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
            warn "[$side] cannot read a valid base commit for $p from git-merge-base.txt"
            failures=$((failures + 1)); continue
        fi
        if ! git -C "$sdk/$p" cat-file -e "${sha}^{commit}" 2>/dev/null; then
            echo "  [$side] MISSING: $p needs base commit $sha, which is not present in your SDK." >&2
            failures=$((failures + 1)); continue
        fi
        if [[ -n "$(git -C "$sdk/$p" status --porcelain 2>/dev/null | grep -v '^??' || true)" ]]; then
            warn "[$side] $p has local modifications; the patch step will stash them."
        fi
    done < <(patched_projects "$pd")
    (( failures == 0 )) || die "$side SDK snapshot does not match the one this overlay targets (see above). Obtain the SDK listed in BASE_SDK."
}

# Split tracked projects into those still sitting at their recorded base
# (PATCH_TODO — patch application needed) and those whose HEAD has already
# moved past it (PATCH_SKIP — somebody worked there since; re-applying from
# base would drop commits that were never exported, so they are left alone).
partition_patch_state() {  # side sdk
    local side="$1" sdk="$2" pd p sha head
    pd="$(patches_dir_of "$side")"
    PATCH_TODO=()
    PATCH_SKIP=()
    while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        has_patch_content "$pd" "$p" || continue
        sha="$(base_sha_of "$pd" "$p")"
        head="$(git -C "$sdk/$p" rev-parse HEAD 2>/dev/null || true)"
        if [[ -n "$head" && "$head" != "$sha" ]]; then
            PATCH_SKIP+=("$p")
        else
            PATCH_TODO+=("$p")
        fi
    done < <(patched_projects "$pd")
}

apply_patches() {  # side sdk
    local side="$1" sdk="$2" pd target body p
    pd="$(patches_dir_of "$side")"
    # Hand the restore step a filtered copy containing only the projects it
    # may touch — skipped projects are invisible to it, and --init-only
    # projects (no patch content yet) do not get pointless restore branches.
    target="$(mktemp -d "${TMPDIR:-/tmp}/seeed-patches.XXXXXX")"
    FILTERED_DIRS+=("$target")
    for p in "${PATCH_TODO[@]}"; do
        mkdir -p "$target/$p"
        cp -a "$pd/$p/." "$target/$p/"
    done
    body="$sdk/system/tools/release_tools/restore_patches_body.sh"
    if [[ -f "$sdk/restore_patches.sh" && -f "$body" ]]; then
        info "[$side] applying patches via the SDK's restore_patches.sh"
        (cd "$sdk" && ./restore_patches.sh "$target")
    else
        warn "[$side] SDK restore scripts not found; using bundled fallback body"
        (cd "$sdk" \
            && export PATCHES_PATH="$target" DATE="$(date +%Y%m%d.%H%M)" \
            && .repo/repo/repo forall -pc "bash $OVERLAY_ROOT/tools/restore_patches_body.sh")
    fi
}

verify_applied() {  # side sdk
    local side="$1" sdk="$2" pd bad=0 p sha
    pd="$(patches_dir_of "$side")"
    while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        has_patch_content "$pd" "$p" || continue
        sha="$(base_sha_of "$pd" "$p")"
        if [[ "$(git -C "$sdk/$p" rev-parse HEAD 2>/dev/null)" == "$sha" ]] \
           && [[ -z "$(git -C "$sdk/$p" status --porcelain 2>/dev/null | grep -v '^??' || true)" ]]; then
            echo "  [$side] NOT APPLIED: $p (HEAD still at base and tree clean)" >&2
            bad=1
        fi
    done < <(patched_projects "$pd")
    (( bad == 0 )) || die "[$side] patch verification failed — check the restore_patches.sh output above."
}

do_side() {  # side
    local side="$1" sdk="${SDK_DIR[$1]}" p
    if [[ "$UNINSTALL" == 1 ]]; then
        uninstall_side "$side" "$sdk"
        return
    fi
    check_base_sdk "$side" "$sdk"
    install_overlay "$side" "$sdk"
    install_tree "$side" "$sdk"
    if [[ "$APPLY_PATCHES" == 1 ]]; then
        if [[ -n "$(patched_projects "$(patches_dir_of "$side")" | head -1)" ]]; then
            check_git_identity
            info "[$side] verifying patch bases against the SDK..."
            verify_patch_bases "$side" "$sdk"
            partition_patch_state "$side" "$sdk"
            for p in "${PATCH_SKIP[@]+"${PATCH_SKIP[@]}"}"; do
                info "[$side] $p: HEAD is past the recorded base — leaving it untouched (export with tools/export_patches.sh if you changed it)"
            done
            if [[ -z "${PATCH_TODO[@]+"${PATCH_TODO[@]}"}" ]]; then
                info "[$side] every tracked project is already past its base — patch step skipped"
            else
                apply_patches "$side" "$sdk"
                verify_applied "$side" "$sdk"
                info "[$side] patches applied"
            fi
        else
            info "[$side] no SDK projects tracked under $(basename "$(side_root "$side")")/PATCHES yet — nothing to patch"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [[ "$UNINSTALL" == 1 ]]; then
    info "uninstalling overlay"
    [[ "$WANT_VENDOR" == 1 ]] && do_side vendor
    [[ "$WANT_SYSTEM" == 1 ]] && do_side system
    info "note: patches applied to SDK repos (restore_YYYYMMDD.HHMM branches) were NOT reverted."
    info "      on a pristine SDK simply re-sync; otherwise reset each patched project manually."
    exit 0
fi

[[ "$WANT_VENDOR" == 1 ]] && do_side vendor
[[ "$WANT_SYSTEM" == 1 ]] && do_side system

echo
info "next steps (see docs/BUILD-FLOW.md for the full fusion build):"
if [[ "$WANT_VENDOR" == 1 ]]; then
    lt="$(base_sdk_value "$(side_lunch_key vendor)")"
    [[ "$lt" == "<fill-in"* ]] && lt=""
    echo "  # vendor side (A14): set the build environment"
    echo "  cd ${SDK_DIR[vendor]} && source build/envsetup.sh && lunch ${lt:-<vendor-lunch-target>}"
fi
if [[ "$WANT_SYSTEM" == 1 ]]; then
    lt="$(base_sdk_value "$(side_lunch_key system)")"
    [[ "$lt" == "<fill-in"* ]] && lt=""
    echo "  # system side (A17 SSI):"
    echo "  cd ${SDK_DIR[system]} && source build/envsetup.sh && lunch ${lt:-<system-lunch-target>} && make dist -j\$(nproc)"
    echo "  # then fuse (in the vendor shell above): ./build.sh -AKUu \\"
    echo "  #      -M ${SDK_DIR[system]}/out/host/linux-x86/bin/merge_target_files \\"
    echo "  #      -T ${SDK_DIR[system]}/out/dist/ssi_17_arm64-target_files-*.zip   (see docs/BUILD-FLOW.md)"
fi
