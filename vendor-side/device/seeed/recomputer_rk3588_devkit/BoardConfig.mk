#
# Copyright (C) 2024 Seeed Studio
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Board configuration for the Seeed reComputer rk3588 devkit, derived from
# device/rockchip/rk3588/rk3588_u/BoardConfig.mk (reference EVB, GKI).
#
BUILD_WITH_GO_OPT := false
BOARD_BUILD_GKI := false
BOARD_USES_AB_IMAGE := true

DEVICE_IS_64BIT_ONLY := true

BOARD_GRAVITY_SENSOR_SUPPORT := true
BOARD_COMPASS_SENSOR_SUPPORT := true
BOARD_SENSOR_COMPASS_AK8963-64 := true
BOARD_GYROSCOPE_SENSOR_SUPPORT := true
BOARD_PROXIMITY_SENSOR_SUPPORT := true
BOARD_LIGHT_SENSOR_SUPPORT := true

# Product kernel: devkit device tree + config fragment, both carried as
# untracked TREE files (vendor-side/TREE/kernel-6.1/) in this overlay.
PRODUCT_KERNEL_DTS := rk3588-recomputer-rk3588-devkit
PRODUCT_KERNEL_CONFIG += recomputer-rk3588-devkit.config
BOARD_GSENSOR_MXC6655XA_SUPPORT := true
BOARD_CAMERA_SUPPORT_EXT := true
BOARD_HS_ETHERNET := true

# GKI forces A/B, but rk3588_defconfig carries no CONFIG_ANDROID_AB — enable
# it through a u-boot config fragment instead of patching the shared defconfig.
# The fragment is a TREE file (vendor-side/TREE/u-boot/). Must be set before
# the include below — the parent assigns it with ?=.
PRODUCT_UBOOT_CONFIG := rk3588_defconfig recomputer-rk3588-devkit.config

# Set before common/BoardConfig.mk uses its chip-directory default.
BOARD_BLUETOOTH_BDROID_BUILDCFG_INCLUDE_DIR := device/seeed/recomputer_rk3588_devkit/rk3588/bluetooth

include device/seeed/recomputer_rk3588_devkit/rk3588/BoardConfig.mk
# The parent assigns PRODUCT_BOOT_DEVICE with :=, so override it here (after
# the include). Keep the SD card controller (fe2c0000.mmc) alongside eMMC —
# without it the SD-boot image has no /dev/block/by-name and recovery loops.
PRODUCT_BOOT_DEVICE := fe2e0000.mmc,fe2c0000.mmc

# Product inheritance loads common/android_sepolicy.mk lazily. Android reads
# this BoardConfig again after importing all product nodes; redirect the
# final policy list here, retaining common and feature policies.
BOARD_SEPOLICY_DIRS := $(filter-out device/rockchip/$(TARGET_BOARD_PLATFORM)/sepolicy_vendor,$(BOARD_SEPOLICY_DIRS))
BOARD_SEPOLICY_DIRS += device/seeed/recomputer_rk3588_devkit/rk3588/sepolicy_vendor \
    device/seeed/recomputer_rk3588_devkit/sepolicy
# The reference RK3588 tree has no system-private sepolicy directory.
# Leave the variable undefined on the initial read so common's ?= still runs.
ifdef SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS
SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS := $(filter-out device/rockchip/$(TARGET_BOARD_PLATFORM)/sepolicy,$(SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS))
endif

# Fusion can enable GKI through BOARD_BUILD_GKI_OVERRIDE. The common GKI
# configuration assigns the chip-directory path; the final BoardConfig read
# redirects it before AndroidBoard.mk generates the image.
ifeq ($(BOARD_BUILD_GKI),true)
DTBO_APPEND_FIX := device/seeed/recomputer_rk3588_devkit/rk3588/dtbo_gki_fix.dts
endif
