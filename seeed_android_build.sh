#!/usr/bin/env bash
# Build the Seeed A17 SSI + A14 vendor firmware. Run setup.sh first.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SYSTEM_SDK="$SCRIPT_DIR/../a17"
VENDOR_SDK="$SCRIPT_DIR/../a14"
PRODUCT=""
VARIANT=userdebug
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '8')"
DRY_RUN=0

die() { printf '[build] ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '[build] %s\n' "$*"; }
usage() {
    cat <<'EOF'
Usage: ./seeed_android_build.sh [options]

Build A17 first, then build/fuse A14 and pack update.img.
Apply this overlay with setup.sh before building.

Options:
  -p, --product NAME   recomputer_rk3576_devkit or recomputer_rk3588_devkit
                      (also accepts rk3576 / rk3588; prompts if omitted)
  --system-sdk DIR    A17 SDK directory (default: sibling a17/)
  --vendor-sdk DIR    A14 SDK directory (default: sibling a14/)
  --variant NAME      userdebug (default) or user
  -j, --jobs N        Parallel jobs for both SDK builds (default: CPU count)
  --dry-run           Validate paths and print commands; do not source SDKs
                      or run compilation
  -h, --help          Show this help

Examples:
  ./seeed_android_build.sh
  ./seeed_android_build.sh --product rk3576 -j 16
  ./seeed_android_build.sh --product rk3588 --variant user --dry-run
  ./seeed_android_build.sh -p rk3588 --system-sdk /work/a17 --vendor-sdk /work/a14

Build outputs use each SDK's default out/ directory. OUT_DIR,
OUT_DIR_COMMON_BASE and DIST_DIR are unset in build subprocesses.
The A14 build script may run make installclean as part of its normal flow.
Do not run concurrent builds in the same SDK trees.
EOF
}

while (( $# )); do
    case "$1" in
        -p|--product|--system-sdk|--vendor-sdk|--variant|-j|--jobs)
            (( $# >= 2 )) && [[ -n "$2" && "$2" != -* ]] || die "$1 requires a value"
            case "$1" in
                -p|--product) PRODUCT="$2" ;;
                --system-sdk) SYSTEM_SDK="$2" ;;
                --vendor-sdk) VENDOR_SDK="$2" ;;
                --variant) VARIANT="$2" ;;
                -j|--jobs) JOBS="$2" ;;
            esac
            shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown argument: $1 (see --help)" ;;
    esac
done

case "$VARIANT" in userdebug|user) ;; *) die "Variant must be userdebug or user" ;; esac
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "Jobs must be a positive integer"
if [[ -z "$PRODUCT" ]]; then
    [[ -t 0 ]] || die "Use --product rk3576 or --product rk3588 in non-interactive mode"
    printf 'Select product / 选择产品:\n  1) recomputer_rk3576_devkit\n  2) recomputer_rk3588_devkit\n'
    read -r -p 'Selection [1/2]: ' PRODUCT || die "No product selected"
fi
case "$PRODUCT" in
    1|rk3576|recomputer_rk3576_devkit) PRODUCT=recomputer_rk3576_devkit; SSI_PRODUCT=recomputer_rk3576_ssi ;;
    2|rk3588|recomputer_rk3588_devkit) PRODUCT=recomputer_rk3588_devkit; SSI_PRODUCT=recomputer_rk3588_ssi ;;
    *) die "Unsupported product: $PRODUCT" ;;
esac
SYSTEM_LUNCH="$SSI_PRODUCT-cp2a-$VARIANT"
VENDOR_LUNCH="$PRODUCT-$VARIANT"

[[ -d "$SYSTEM_SDK" ]] || die "A17 SDK directory not found: $SYSTEM_SDK"
[[ -d "$VENDOR_SDK" ]] || die "A14 SDK directory not found: $VENDOR_SDK"
SYSTEM_SDK="$(cd -- "$SYSTEM_SDK" && pwd -P)"
VENDOR_SDK="$(cd -- "$VENDOR_SDK" && pwd -P)"
[[ "$SYSTEM_SDK" != "$VENDOR_SDK" ]] || die "A17 and A14 must be different SDK trees"
for sdk in "$SYSTEM_SDK" "$VENDOR_SDK"; do
    [[ -f "$sdk/build/envsetup.sh" ]] || die "Missing $sdk/build/envsetup.sh"
done
[[ -x "$VENDOR_SDK/build.sh" ]] || die "Missing executable: $VENDOR_SDK/build.sh"
[[ -f "$SYSTEM_SDK/device/seeed/$SSI_PRODUCT/AndroidProducts.mk" ]] ||
    die "A17 product is not installed; run setup.sh for these SDKs first"
[[ -f "$VENDOR_SDK/device/seeed/$PRODUCT/AndroidProducts.mk" ]] ||
    die "A14 product is not installed; run setup.sh for these SDKs first"

MERGE_TOOL="$SYSTEM_SDK/out/host/linux-x86/bin/merge_target_files"
IMAGE_DIR="$VENDOR_SDK/rockdev/Image-$PRODUCT"
info "Product: $PRODUCT ($VARIANT), jobs: $JOBS"
info "A17: $SYSTEM_SDK"
info "A14: $VENDOR_SDK"

# SDK envsetup/lunch scripts are not safe under nounset/errexit. Each SDK gets
# its own Bash process, explicit error checks, and default output directories.
run_sdk() {
    env -u OUT_DIR -u OUT_DIR_COMMON_BASE -u DIST_DIR \
        -u TARGET_PRODUCT -u TARGET_BUILD_VARIANT -u TARGET_RELEASE \
        -u ANDROID_BUILD_TOP -u ANDROID_PRODUCT_OUT -u OUT \
        -u BUILD_VAR_CACHE_READY -u TOP -u BASH_ENV \
        bash --noprofile --norc -c '
            set +e
            set +u
            set -o pipefail
            readonly seeed_sdk=$1 seeed_target=$2 seeed_product=$3
            readonly seeed_variant=$4 seeed_release=$5
            shift 5
            cd -- "$seeed_sdk" || exit $?
            export TOP="$seeed_sdk"
            source build/envsetup.sh || exit $?
            # In this A17 SDK lunch may return success after configuration
            # failure because saving .leftovers masks the original status.
            lunch "$seeed_target" || exit $?
            if [[ "$(gettop)" != "$seeed_sdk" ||
                  "$TARGET_PRODUCT" != "$seeed_product" ||
                  "$TARGET_BUILD_VARIANT" != "$seeed_variant" ||
                  ( -n "$seeed_release" && "$TARGET_RELEASE" != "$seeed_release" ) ]]; then
                printf "[build] ERROR: SDK root or lunch configuration does not match %s\n" "$seeed_target" >&2
                exit 1
            fi
            "$@"
            exit $?
        ' seeed-sdk-build "$@"
}

if (( DRY_RUN )); then
    info "Dry run: no SDK scripts will be sourced or executed."
    printf '(cd %q && source build/envsetup.sh && lunch %q && make dist -j%s)\n' \
        "$SYSTEM_SDK" "$SYSTEM_LUNCH" "$JOBS"
    printf 'Resolve and validate the current build ZIP using out/file_name_tag.txt: %s/out/dist/%s-target_files-<tag>.zip\n' \
        "$SYSTEM_SDK" "$SSI_PRODUCT"
    printf '(cd %q && source build/envsetup.sh && lunch %q && ./build.sh -AKUou -J %s -M %q -T <selected-target-files.zip>)\n' \
        "$VENDOR_SDK" "$VENDOR_LUNCH" "$JOBS" "$MERGE_TOOL"
    info "Expected firmware: $IMAGE_DIR/update.img"
    exit 0
fi

command -v python3 >/dev/null || die "python3 is required to validate target-files metadata"
command -v stat >/dev/null || die "stat is required to check firmware output freshness"

info "Building A17 SSI..."
run_sdk "$SYSTEM_SDK" "$SYSTEM_LUNCH" "$SSI_PRODUCT" "$VARIANT" cp2a \
    make dist "-j$JOBS" || die "A17 build failed; A14 was not started"
[[ -x "$MERGE_TOOL" ]] || die "A17 did not produce the executable merge tool: $MERGE_TOOL"

# Use the exact dist naming rule in this SDK, not the mtime of old ZIPs.
# A valid, unchanged incremental-build output is allowed after make succeeds.
[[ -s "$SYSTEM_SDK/out/file_name_tag.txt" ]] || die "A17 dist file-name tag is missing"
FILE_NAME_TAG="$(< "$SYSTEM_SDK/out/file_name_tag.txt")"
[[ -n "$FILE_NAME_TAG" && "$FILE_NAME_TAG" != */* && "$FILE_NAME_TAG" != *$'\n'* ]] ||
    die "Invalid A17 dist file-name tag"
TARGET_FILES="$SYSTEM_SDK/out/dist/$SSI_PRODUCT-target_files-$FILE_NAME_TAG.zip"
[[ -s "$TARGET_FILES" ]] || die "Current A17 target-files ZIP is missing: $TARGET_FILES"
python3 - "$TARGET_FILES" "$SSI_PRODUCT" "$VARIANT" <<'PY' || die "SSI target-files validation failed; A14 was not started"
import sys
import zipfile

path, product, variant = sys.argv[1:]
try:
    with zipfile.ZipFile(path) as archive:
        # Parse the ZIP directory and CRC-check the build properties when read.
        # Avoid decompressing all image payloads merely for metadata checks.
        names = set(archive.namelist())
        prop_path = next((name for name in (
            "SYSTEM/etc/build.prop", "SYSTEM/build.prop"
        ) if name in names), None)
        if prop_path is None or "META/misc_info.txt" not in names:
            raise ValueError("Missing system build properties or META/misc_info.txt")
        props = {}
        for line in archive.read(prop_path).decode("utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                props[key.strip()] = value.strip()
        expected = {
            "ro.product.system.name": product,
            "ro.build.type": variant,
        }
        for key, value in expected.items():
            if props.get(key) != value:
                raise ValueError(f"{key}: expected {value!r}, got {props.get(key)!r}")
except (OSError, ValueError, RuntimeError, zipfile.BadZipFile) as error:
    sys.exit(f"[build] ERROR: Invalid SSI target-files: {error}")
PY
info "SSI target-files: $TARGET_FILES"

# The vendor packer always writes update.img. Detect a stale image left behind
# even if the SDK script incorrectly returns success. Nanosecond timestamps
# and inode identity also cover same-size replacements and rapid runs.
image_signature() {
    if [[ -e "$IMAGE_DIR/update.img" ]]; then
        stat -c '%d:%i:%s:%y:%z' -- "$IMAGE_DIR/update.img"
    else
        printf 'missing\n'
    fi
}
OLD_IMAGE_SIGNATURE="$(image_signature)"
info "Building A14 vendor, fusing and packing firmware..."
run_sdk "$VENDOR_SDK" "$VENDOR_LUNCH" "$PRODUCT" "$VARIANT" "" ./build.sh -AKUou -J "$JOBS" \
    -M "$MERGE_TOOL" -T "$TARGET_FILES" || die "A14 build/fusion failed"
[[ -s "$IMAGE_DIR/update.img" ]] || die "Build returned success but firmware is missing: $IMAGE_DIR/update.img"
[[ "$(image_signature)" != "$OLD_IMAGE_SIGNATURE" ]] || die "A14 did not update firmware; refusing the existing update.img"
info "Build complete: $IMAGE_DIR/update.img"
