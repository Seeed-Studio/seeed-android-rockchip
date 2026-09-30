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
# Full product configuration for the Seeed reComputer rk3576 devkit,
# derived from the SDK reference product device/rockchip/rk3576/rk3576_u.
#

# First lunching is U, api_level is 34
# GRF contract with the A17 SSI system side — do not bump.
PRODUCT_SHIPPING_API_LEVEL := 34
PRODUCT_DTBO_TEMPLATE := $(LOCAL_PATH)/dt-overlay.in

# Camera tuning: PRODUCT_COPY_FILES resolves first-wins, and inherit-product
# expands inherited content at the point of the call — so these entries MUST
# stay ABOVE the inherit-product calls below to override the wildcard copies
# made by hardware/rockchip/camera/etc/camera_etc.mk. The tuned profiles and
# the imx708 IQ file live in this overlay instead of patching the SDK repos;
# camera3_profiles.xml and camera3_profiles_rk3576.xml must carry the same
# content (the HAL reads both names).
PRODUCT_COPY_FILES += \
    vendor/seeed/recomputer_rk3576_devkit/etc/camera/camera3_profiles_rk3576.xml:$(TARGET_COPY_OUT_VENDOR)/etc/camera/camera3_profiles.xml \
    vendor/seeed/recomputer_rk3576_devkit/etc/camera/rkisp2/imx708_rpi-camera-v3_default.json:$(TARGET_COPY_OUT_VENDOR)/etc/camera/rkisp2/imx708_rpi-camera-v3_default.json

include device/rockchip/common/build/rockchip/DynamicPartitions.mk
include device/seeed/recomputer_rk3576_devkit/BoardConfig.mk
include device/rockchip/common/BoardConfig.mk
$(call inherit-product, device/rockchip/rk3576/device.mk)
$(call inherit-product, device/rockchip/common/device.mk)
$(call inherit-product, frameworks/native/build/tablet-10in-xhdpi-2048-dalvik-heap.mk)

# RK's rk3576 framework resource overlay (the reference product reaches it via
# $(LOCAL_PATH)/../overlay; spelled out here because this product lives in a
# different directory).
DEVICE_PACKAGE_OVERLAYS += device/rockchip/rk3576/overlay

PRODUCT_CHARACTERISTICS := tablet

PRODUCT_NAME := recomputer_rk3576_devkit
PRODUCT_DEVICE := recomputer_rk3576_devkit
PRODUCT_BRAND := seeed
PRODUCT_MODEL := reComputer-RK3576-DevKit
PRODUCT_MANUFACTURER := seeed
PRODUCT_AAPT_PREF_CONFIG := mdpi
#
## add Rockchip properties
#
PRODUCT_PROPERTY_OVERRIDES += ro.sf.lcd_density=320
PRODUCT_PROPERTY_OVERRIDES += ro.wifi.sleep.power.down=true
PRODUCT_PROPERTY_OVERRIDES += persist.wifi.sleep.delay.ms=0
PRODUCT_PROPERTY_OVERRIDES += persist.bt.power.down=true
PRODUCT_PROPERTY_OVERRIDES += vendor.hwc.device.primary=DSI
PRODUCT_PROPERTY_OVERRIDES += vendor.hwc.device.extend=HDMI-A,eDP
