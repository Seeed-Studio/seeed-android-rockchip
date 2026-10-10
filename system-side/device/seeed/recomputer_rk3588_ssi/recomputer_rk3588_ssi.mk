#
# Copyright (C) 2026 Seeed Studio
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
# System-side (SSI) product for the Seeed reComputer rk3588 devkit fusion
# firmware, derived from the SDK skeleton product
# device/rockchip/rockchip_generic/ssi_17_arm64/ssi_17_arm64.mk.
#

DEVICE_IS_64BIT_ONLY := true

# Add VNDK support for GRF Vendor API Freeze A14
PRODUCT_EXTRA_VNDK_VERSIONS := 34

# First lunching is A17, api_level is 37
PRODUCT_SHIPPING_API_LEVEL := 37

PRODUCT_CHARACTERISTICS := tablet

PRODUCT_NAME := recomputer_rk3588_ssi
PRODUCT_DEVICE := recomputer_rk3588_ssi
PRODUCT_BRAND := seeed
PRODUCT_MODEL := reComputer RK3588 DevKit
PRODUCT_MANUFACTURER := seeed

BUILD_WITH_GOOGLE_MARKET ?= false
BUILD_WITH_GOOGLE_MARKET_ALL ?= false
BUILD_WITH_GOOGLE_GMS_EXPRESS ?= false
BUILD_WITH_EEA ?= false
BUILD_WITH_EEA_TYPE ?= v2_type4c

# RK3588 native HDMI-RX input. Vendor-side counterpart is
# vendor-side/device/seeed/recomputer_rk3588_devkit/BoardConfig.mk
# (BOARD_HDMI_IN_SUPPORT := true, hdmirx_ctrler + tv_input HAL).
BOARD_HDMI_IN_SUPPORT := true

include $(wildcard device/rockchip/rockchip_generic/configs/*.mk)

$(call inherit-product, device/rockchip/rockchip_generic/ssi_17_arm64/device.mk)
