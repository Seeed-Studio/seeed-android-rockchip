# Product sepolicy additions for recomputer_rk3588_devkit.

# Wired in via `BOARD_SEPOLICY_DIRS` in BoardConfig.mk, on its final read
# after common/device.mk resets the policy list; currently empty (rk3588_u ships none
# either). Bring-up entries (genfs_contexts for wakeup/battery sysfs, file
# contexts for new firmware, etc.) go here as plain `*.te`/contexts files —
# with the symlinked install they are picked up by the next build without
# re-running setup.sh.
