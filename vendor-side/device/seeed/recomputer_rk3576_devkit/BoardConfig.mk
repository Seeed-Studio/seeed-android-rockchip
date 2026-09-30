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
# Board configuration for the Seeed reComputer rk3576 devkit, derived from
# device/rockchip/rk3576/rk3576_u/BoardConfig.mk (reference EVB).
#
BUILD_WITH_GO_OPT := false
BOARD_BUILD_GKI := false
BOARD_USES_AB_IMAGE := true

#64-bit onlye
DEVICE_IS_64BIT_ONLY := true

BOARD_GRAVITY_SENSOR_SUPPORT := true
BOARD_COMPASS_SENSOR_SUPPORT := true
BOARD_SENSOR_COMPASS_AK8963-64 := true
BOARD_GYROSCOPE_SENSOR_SUPPORT := true
BOARD_PROXIMITY_SENSOR_SUPPORT := true
BOARD_LIGHT_SENSOR_SUPPORT := true

# Product kernel: devkit device tree + config fragment, both carried by the
# kernel-6.1 patch set (vendor-side/PATCHES/kernel-6.1/).
PRODUCT_KERNEL_DTS := rk3576-recomputer-rk3576-devkit
PRODUCT_KERNEL_CONFIG += recomputer-rk3576-devkit.config
# Boot devices incl. the SD card controller (2a310000.mmc) — without it the
# SD-boot image has no /dev/block/by-name and recovery loops.
BOARD_GSENSOR_MXC6655XA_SUPPORT := true
BOARD_CAMERA_SUPPORT_EXT := true
BOARD_HS_ETHERNET := true

# A/B firmware: enable CONFIG_ANDROID_AB through a u-boot config fragment
# instead of patching the shared rk3576_defconfig (which stays pristine for
# the reference boards). The fragment itself is carried by the u-boot patch
# set (vendor-side/PATCHES/u-boot/). Must be set before the include below —
# the parent assigns it with ?=.
PRODUCT_UBOOT_CONFIG := rk3576_defconfig recomputer-rk3576-devkit.config

BOARD_SEPOLICY_DIRS += $(TARGET_DEVICE_DIR)/sepolicy

include device/rockchip/rk3576/BoardConfig.mk
PRODUCT_BOOT_DEVICE := 2a2d0000.ufs,2a330000.mmc,97800000.vdc,2a310000.mmc
