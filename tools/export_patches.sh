#!/bin/bash
#
# export_patches.sh — regenerate <side>-side/PATCHES/ from your current SDK tree.
#
# Run from either SDK root (vendor/A14 or system/A17); the side is detected
# from the tree's markers, or forced with --side. The overlay repo is
# discovered from $SEEED_BSP_DIR or as a sibling of the SDK directory.
#
# Usage:
#   export_patches.sh [--sdk DIR] [--side vendor|system]
#                     [--init PATH]... [--base PATH=REV]... [OVERLAY_DIR]
#
# Modes:
#   default         For every project already tracked under <side>-side/PATCHES/:
#                   refresh *.patch from <base>..HEAD and local_diff.diff from
#                   the uncommitted changes. Safe to run any time.
#   --init PATH     Start tracking SDK project PATH: adopt its current HEAD as
#                   the base, no patches recorded yet. Run this for every
#                   project you are about to modify, right after unpacking a
#                   new SDK snapshot.
#   --base PATH=REV Start (or reset) tracking of PATH at revision REV and
#                   export patches REV..HEAD immediately. REV is typically the
#                   original RK tag/commit the project sat at before your
#                   changes — use this to adopt projects you already modified.
#
# Review the result before committing: patches carry author names/emails and
# any content you export leaves the company through the public repo.
#
set -uo pipefail

OVERLAY_DIR=""
SDK_DIR=""
SIDE=""
INIT_PATHS=()
BASE_PAIRS=()

info() { echo "[export] $*"; }
warn() { echo "[export] WARNING: $*" >&2; }
die()  { echo "[export] ERROR: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sdk)   [[ $# -ge 2 ]] || die "--sdk needs a value"; SDK_DIR="$2"; shift 2 ;;
        --side)  [[ $# -ge 2 ]] || die "--side needs vendor or system"; SIDE="$2"; shift 2 ;;
        --init)  [[ $# -ge 2 ]] || die "--init needs a PATH value"; INIT_PATHS+=("$2"); shift 2 ;;
        --base)  [[ $# -ge 2 ]] || die "--base needs a PATH=REV value"; BASE_PAIRS+=("$2"); shift 2 ;;
        -h|--help) sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        --*)     die "unknown option: $1" ;;
        *)       [[ -z "$OVERLAY_DIR" ]] || die "unexpected extra argument: $1"; OVERLAY_DIR="$1"; shift ;;
    esac
done

[[ -n "$SDK_DIR" ]] || SDK_DIR="$PWD"
[[ -f "$SDK_DIR/build/envsetup.sh" ]] || die "$SDK_DIR is not an SDK tree (no build/envsetup.sh)"
SDK_DIR="$(cd "$SDK_DIR" && pwd)"

# Side detection: the A17 SSI tree carries device/rockchip/rockchip_generic,
# per-chip vendor trees (RK3576, RK3588, ...) carry device/rockchip/rk35xx.
if [[ -z "$SIDE" ]]; then
    if [[ -d "$SDK_DIR/device/rockchip/rockchip_generic" ]]; then
        SIDE=system
    elif compgen -G "$SDK_DIR/device/rockchip/rk*" >/dev/null; then
        SIDE=vendor
    else
        die "cannot tell vendor/system side from $SDK_DIR; pass --side explicitly"
    fi
fi
[[ "$SIDE" == vendor || "$SIDE" == system ]] || die "--side must be vendor or system"

if [[ -z "$OVERLAY_DIR" ]]; then
    for candidate in "${SEEED_BSP_DIR:-}" "$SDK_DIR/../seeed-android-rockchip"; do
        [[ -n "$candidate" && -f "$candidate/setup.sh" ]] && { OVERLAY_DIR="$candidate"; break; }
    done
fi
[[ -n "$OVERLAY_DIR" && -f "$OVERLAY_DIR/setup.sh" ]] || die "overlay repo not found; pass it as an argument or set SEEED_BSP_DIR"
OVERLAY_DIR="$(cd "$OVERLAY_DIR" && pwd)"

PATCHES_DIR="$OVERLAY_DIR/$SIDE-side/PATCHES"

sha_of_file() { awk '$1 == "commit" { print $2; exit }' "$1"; }

write_base() {  # repo_path sha
    local d="$PATCHES_DIR/$1"
    mkdir -p "$d"
    printf 'commit %s\n' "$2" > "$d/git-merge-base.txt"
}

resolve_rev() {  # repo_path rev -> sha
    local sha
    sha="$(git -C "$SDK_DIR/$1" rev-parse --verify "$2^{commit}" 2>/dev/null)" \
        || die "revision '$2' not found in $1"
    printf '%s' "$sha"
}

# Export one tracked project: refresh patches and local diff from the tree.
export_project() {  # repo_path
    local p="$1" pd="$PATCHES_DIR/$1" base head n extra=""
    base="$(sha_of_file "$pd/git-merge-base.txt")"
    if [[ -z "$base" ]]; then
        warn "$p: no base recorded in git-merge-base.txt; run with --base $p=<rev>"; return
    fi
    if ! git -C "$SDK_DIR/$p" rev-parse --verify "$base^{commit}" >/dev/null 2>&1; then
        warn "$p: base $base not found in the SDK (rebased SDK?); run with --base $p=<rev>"; return
    fi
    rm -f "$pd"/*.patch "$pd/local_diff.diff"
    head="$(git -C "$SDK_DIR/$p" rev-parse HEAD)"
    if [[ "$head" != "$base" ]]; then
        (cd "$SDK_DIR/$p" && git format-patch --no-signature -o "$pd" "$base..$head" >/dev/null) \
            || { warn "$p: git format-patch failed"; return; }
    fi
    (cd "$SDK_DIR/$p" && git diff HEAD) > "$pd/local_diff.diff"
    if [[ ! -s "$pd/local_diff.diff" ]]; then
        rm -f "$pd/local_diff.diff"
    else
        extra=" + local_diff.diff (UNCOMMITTED — commit it in the SDK, see PATCHES/README.md)"
    fi
    n="$(find "$pd" -maxdepth 1 -name '*.patch' | wc -l)"
    info "[$SIDE] $p: $n patch(es)$extra"
    n="$(git -C "$SDK_DIR/$p" ls-files --others --exclude-standard 2>/dev/null | wc -l)"
    (( n > 0 )) && info "[$SIDE] note: $p also has $n untracked file(s) — not part of the export (new files belong in TREE/, see TREE/README.md)"
}

# --init: adopt current HEAD as pristine base
for p in "${INIT_PATHS[@]:-}"; do
    [[ -n "$p" ]] || continue
    [[ -d "$SDK_DIR/$p/.git" || -f "$SDK_DIR/$p/.git" ]] || die "--init: $p is not a git project in the SDK"
    if [[ -f "$PATCHES_DIR/$p/git-merge-base.txt" ]]; then
        die "--init: $p is already tracked (base $(sha_of_file "$PATCHES_DIR/$p/git-merge-base.txt")); to reset the base use --base $p=<rev>"
    fi
    write_base "$p" "$(git -C "$SDK_DIR/$p" rev-parse HEAD)"
    info "[$SIDE] $p: tracking started, base = current HEAD (no patches yet)"
done

# --base PATH=REV: set/replace base and export immediately
for pair in "${BASE_PAIRS[@]:-}"; do
    [[ -n "$pair" ]] || continue
    [[ "$pair" == *=* ]] || die "--base expects PATH=REV, got '$pair'"
    p="${pair%%=*}"; rev="${pair#*=}"
    write_base "$p" "$(resolve_rev "$p" "$rev")"
    export_project "$p"
done

# default pass over everything already tracked
while IFS= read -r f; do
    export_project "$(dirname "${f#"$PATCHES_DIR"/}")"
done < <(find "$PATCHES_DIR" -type f -name git-merge-base.txt 2>/dev/null)

manifest_repo="$SDK_DIR/.repo/manifests"
if [[ "$SIDE" == vendor ]]; then key=VENDOR_MANIFEST_SHA; else key=SYSTEM_MANIFEST_SHA; fi
info "done. If the SDK snapshot changed, also refresh BASE_SDK ($key):"
info "  git -C $manifest_repo rev-parse HEAD"
