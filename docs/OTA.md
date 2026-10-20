# Validate A/B OTA updates

English | [简体中文](OTA_zh.md)

Applies to boards already running Seeed RK3576 / RK3588 Android 17 SSI + A14 Vendor fusion **A/B firmware**. The repository's [ota_update.py](../tools/ota/ota_update.py) needs only a prebuilt OTA ZIP, Python and `adb`. No SDK checkout, `setup.sh`, envsetup/lunch or compilation is needed.

## 1. Prerequisites

- Install **Python 3.8+** and standalone **Android Platform-Tools**. Check `python3 --version` and `adb version`. On Windows, replace `python3` with `py -3` if needed.
- Boot Android, enable USB debugging and authorize the host. This development tool requires `adb root` on `userdebug` / `eng` firmware; locked production `user` builds are unsupported.
- Obtain the exact board's fusion full OTA, or an incremental OTA matching the installed source build. **Do not use `update.img`, `*-images-merged-fastboot.zip`, `*-target_files-merged.zip` or a Vendor-only OTA.** The tool checks contents rather than filenames.
- Keep power and USB stable, save important data, and leave enough `/data` space for the OTA ZIP and Virtual A/B snapshots. The tool does not wipe data, change SELinux mode or replace verification keys.

Run these commands from this repository's root. The OTA can be anywhere on the host:

```bash
python3 tools/ota/ota_update.py --help
adb devices
```

`install` / `status` accept `--adb /path/to/adb` and `-s SERIAL`. Without a serial, exactly one authorized online device must be connected. All subsequent commands are pinned to that device.

## 2. Check the package offline

```bash
python3 tools/ota/ota_update.py check /path/to/ota-merged.zip
```

This does not invoke `adb`. It checks A/B metadata and target identity, rejects data-wipe requests, requires unique payload/metadata entries and an uncompressed payload, and verifies payload magic, sizes, `FILE_HASH` and `METADATA_HASH`.

`PASS` confirms structure and payload hash consistency, **not signature authenticity or device compatibility**. Device `update_engine` still performs payload signature, source partition, rollback and installation checks. Obtain packages from a trusted release channel.

## 3. Upload and install

```bash
python3 tools/ota/ota_update.py install /path/to/ota-merged.zip \
  -s DEVICE_SERIAL --log ota-install.log
```

The tool rechecks the whole package, reads the current A/B slot, device name, build and update service state. `pre-device` must match `ro.product.device`; incremental `pre-build` and `pre-build-incremental` constraints must match when present. A mismatch stops before requesting root or uploading.

It then requests `adb root`, uploads the ZIP to `/data/ota_package/seeed-ota-<random-id>.zip`, sets ownership, permissions and SELinux labels, calculates the payload offset and length from the ZIP local header, and runs device `update_engine_client --update --follow`. No manual extraction, HTTP server or network connection is needed.

If present, `care_map.pb` is installed at `/data/ota_package/care_map.pb` for post-reboot `update_verifier`; otherwise an old care map is removed. Do not run another OTA client or a concurrent invocation during installation.

Success requires both exit code 0 and:

```text
onPayloadApplicationComplete(ErrorCode::kSuccess (0))
```

Normally `UPDATE_STATUS_UPDATED_NEED_REBOOT` also appears. **There is no automatic reboot by default.** The tool prints a reboot command pinned to the device serial. To reboot explicitly after success:

```bash
python3 tools/ota/ota_update.py install /path/to/ota-merged.zip \
  -s DEVICE_SERIAL --log ota-install.log --reboot
```

Failures, missing success callbacks and completion code 52 (installed but not activated) produce a nonzero exit and do not request reboot. `--log` saves client output and replaces the named host log file. The device ZIP remains available for diagnosis; after installation, reboot and snapshot merging finish, remove only the exact path printed by the tool if desired. Do not delete the whole OTA directory.

## 4. Verify after reboot

After Android starts:

```bash
python3 tools/ota/ota_update.py status /path/to/ota-merged.zip -s DEVICE_SERIAL
```

The command shows device name, slot, fingerprint, incremental version, boot completion and update service state. It reports `PASS` only when the running build matches `post-build` and `post-build-incremental`, and `sys.boot_completed=1`. It reads package metadata without rehashing the large payload.

To display current state without checking an expected OTA version:

```bash
python3 tools/ota/ota_update.py status -s DEVICE_SERIAL
```

`status` verifies the booted target version, not completion of Virtual A/B snapshot merging. After a Virtual A/B device boots the new build, request cleanup and wait for merging:

```bash
adb -s DEVICE_SERIAL root
adb -s DEVICE_SERIAL wait-for-device
adb -s DEVICE_SERIAL shell update_engine_client --merge
```

Check its success callback too. Finish merging before starting another OTA. Verify important functions and user data separately; matching the version does not establish functional correctness.

## 5. Troubleshooting

```bash
adb -s DEVICE_SERIAL logcat -d -s update_engine
adb -s DEVICE_SERIAL shell getprop ro.boot.slot_suffix
adb -s DEVICE_SERIAL shell getprop ro.build.fingerprint
adb -s DEVICE_SERIAL shell df -h /data
```

| Symptom | Check |
|---|---|
| Missing adb / offline / unauthorized | Platform-Tools, USB authorization, cable and `-s` |
| UID remains nonzero after `adb root` | Use development firmware that supports root; this tool cannot elevate production firmware |
| Device/source version mismatch | Exact board and incremental source fusion build |
| Signature, source hash or timestamp error | Trusted release keys, modified partitions or a downgrade; do not disable verification |
| Space/snapshot error | Free `/data` space and completion of the previous merge |
| Interrupted command / disconnected adb | The device may still be updating; inspect logs and state before retrying; the tool does not reset/cancel automatically |

This tool does not migrate partition layouts or convert stock non-A/B A14 to A17 A/B. Production updates need a system-privileged application using `UpdateEngine` and a release management service.

## 6. Tool tests

```bash
python3 -B -m unittest discover -s tools/ota -p 'test_*.py' -v
```

Tests use synthetic OTAs and fake adb, without accessing a real device. Validate physical installation, reboot and snapshot merging using the procedure above.
