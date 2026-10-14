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
# System-side (SSI) product for the Seeed reComputer RK3576 devkit fusion
# firmware, derived from the SDK skeleton product
# device/rockchip/rockchip_generic/ssi_17_arm64/ssi_17_arm64.mk.
# Intentionally identical to the skeleton apart from product identity —
# the RK3576 needs no system-side customization yet (no hdmirx on RK3576,
# so BOARD_HDMI_IN_SUPPORT keeps the skeleton default), so this target is
# a drop-in replacement for the stock ssi_17_arm64 lunch.
#

DEVICE_IS_64BIT_ONLY := true

# Add VNDK support for GRF Vendor API Freeze A14
PRODUCT_EXTRA_VNDK_VERSIONS := 34

# First lunching is A17, api_level is 37
PRODUCT_SHIPPING_API_LEVEL := 37

PRODUCT_CHARACTERISTICS := tablet

PRODUCT_NAME := recomputer_rk3576_ssi
PRODUCT_DEVICE := recomputer_rk3576_ssi
PRODUCT_BRAND := seeed
PRODUCT_MODEL := reComputer-RK3576-DevKit
PRODUCT_MANUFACTURER := seeed

BUILD_WITH_GOOGLE_MARKET ?= false
BUILD_WITH_GOOGLE_MARKET_ALL ?= false
BUILD_WITH_GOOGLE_GMS_EXPRESS ?= false
BUILD_WITH_EEA ?= false
BUILD_WITH_EEA_TYPE ?= v2_type4c

BOARD_HDMI_IN_SUPPORT ?= false

include $(wildcard device/rockchip/rockchip_generic/configs/*.mk)

$(call inherit-product, device/rockchip/rockchip_generic/ssi_17_arm64/device.mk)
