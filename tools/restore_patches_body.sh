#!/bin/bash
# Fallback replacement for system/tools/release_tools/restore_patches_body.sh,
# used by setup.sh when the SDK does not ship Rockchip's own copy.
#
# Contract identical to RK's script: executed by `repo forall` once per SDK
# project, with $REPO_PATH, $PATCHES_PATH and $DATE set in the environment.
# One addition: a project already sitting on a restore_* branch past its base
# is skipped instead of being reset — re-applying from base there would drop
# commits that were never exported (setup.sh pre-filters these too; this
# guard protects direct restore_patches.sh invocations).
if test -d "${PATCHES_PATH}/${REPO_PATH}"; then
    GIT_HEAD=$(grep commit "${PATCHES_PATH}/${REPO_PATH}/git-merge-base.txt" | cut -c8-47)
    CUR_BRANCH=$(git branch --show-current 2>/dev/null)
    if [ -n "$CUR_BRANCH" ] && [ "${CUR_BRANCH#restore_}" != "$CUR_BRANCH" ] \
       && [ "$(git rev-parse HEAD)" != "$GIT_HEAD" ]; then
        echo "Skip ${REPO_PATH}: already on ${CUR_BRANCH} past base ${GIT_HEAD} — export your changes (tools/export_patches.sh) before re-applying"
        exit 0
    fi
    if git rev-parse --verify "restore_${DATE}" >/dev/null 2>&1; then
        echo "Skip ${REPO_PATH}: branch restore_${DATE} already exists"
        exit 0
    fi
    git stash >/dev/null 2>&1
    if ! git checkout -b "restore_${DATE}" "$GIT_HEAD"; then
        echo "FAIL ${REPO_PATH}: cannot checkout base commit $GIT_HEAD" >&2
        exit 1
    fi
    HAVE_PATCH=$(find "${PATCHES_PATH}/${REPO_PATH}" -maxdepth 1 -name '*.patch')
    HAVE_DIFF=$(find "${PATCHES_PATH}/${REPO_PATH}" -maxdepth 1 -name local_diff.diff)
    if [ -n "$HAVE_PATCH" ]; then
        git am "${PATCHES_PATH}/${REPO_PATH}"/*.patch || {
            git am --abort 2>/dev/null
            echo "FAIL ${REPO_PATH}: git am error" >&2
            exit 1
        }
    fi
    if [ -n "$HAVE_DIFF" ]; then
        git apply "${PATCHES_PATH}/${REPO_PATH}/local_diff.diff" || {
            echo "FAIL ${REPO_PATH}: git apply local_diff.diff error" >&2
            exit 1
        }
    fi
    if [ -n "$HAVE_PATCH" ] || [ -n "$HAVE_DIFF" ]; then
        echo "Restore patch for ${REPO_PATH} done"
    fi
fi
