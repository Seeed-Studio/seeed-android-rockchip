#!/usr/bin/env python3
# Copyright 2026 Seeed Studio
# SPDX-License-Identifier: Apache-2.0
"""Check and install A/B OTA ZIPs using Python's standard library and adb."""

import argparse
import base64
import hashlib
from pathlib import Path
import re
import shlex
import shutil
import struct
import subprocess
import sys
import tempfile
import uuid
import zipfile


class OTAError(Exception):
    """A package, device or installation error."""


def require(condition, message):
    if not condition:
        raise OTAError(message)


def read_pairs(data):
    result = {}
    for line in data.decode("utf-8").splitlines():
        if not line.strip():
            continue
        key, sep, value = line.partition("=")
        require(sep and key not in result, "Invalid or duplicate metadata key: " + key)
        result[key] = value
    return result


def file_identity(path):
    stat = path.stat()
    return stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns


def inspect_package(filename, verify=True):
    path = Path(filename).expanduser().resolve()
    require(path.is_file(), "OTA file not found: " + str(path))
    before = file_identity(path)
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        for name in ("payload.bin", "payload_properties.txt", "META-INF/com/android/metadata"):
            require(names.count(name) == 1, "Expected exactly one " + name + "; use an A/B OTA ZIP.")
        require(names.count("care_map.pb") <= 1, "Duplicate care_map.pb entries.")
        metadata = read_pairs(archive.read("META-INF/com/android/metadata"))
        properties = read_pairs(archive.read("payload_properties.txt"))
        require(metadata.get("ota-type") == "AB", "Only A/B OTA packages are supported.")
        require(metadata.get("ota-wipe", "no") != "yes", "Packages requesting a data wipe are not supported.")
        for key in ("pre-device", "post-build", "post-build-incremental"):
            require(metadata.get(key), "Missing OTA metadata: " + key)
        for key in ("FILE_SIZE", "FILE_HASH", "METADATA_SIZE", "METADATA_HASH"):
            require(properties.get(key), "Missing payload property: " + key)
        payload = archive.getinfo("payload.bin")
        require(payload.compress_type == zipfile.ZIP_STORED, "payload.bin must be stored uncompressed in the ZIP.")
        require(not payload.flag_bits & 1, "Encrypted OTA payloads are not supported.")
        size = int(properties["FILE_SIZE"])
        metadata_size = int(properties["METADATA_SIZE"])
        require(size == payload.file_size and 0 < metadata_size <= size, "Invalid payload sizes.")
        with path.open("rb") as raw:
            raw.seek(payload.header_offset)
            header = raw.read(30)
            require(header[:4] == b"PK\x03\x04", "Invalid payload ZIP header.")
            name_size, extra_size = struct.unpack("<HH", header[26:30])
            offset = payload.header_offset + 30 + name_size + extra_size
            raw.seek(offset)
            require(raw.read(4) == b"CrAU", "Invalid payload magic or ZIP offset.")
        if verify:
            full_hash, meta_hash = hashlib.sha256(), hashlib.sha256()
            remaining = metadata_size
            with archive.open(payload) as stream:
                while True:
                    chunk = stream.read(4 * 1024 * 1024)
                    if not chunk:
                        break
                    full_hash.update(chunk)
                    if remaining:
                        meta_hash.update(chunk[:remaining])
                        remaining = max(0, remaining - len(chunk))
            for key, digest in (("FILE_HASH", full_hash), ("METADATA_HASH", meta_hash)):
                require(base64.b64encode(digest.digest()).decode() == properties[key], key + " mismatch; OTA is corrupt.")
        # Pass only the payload verification properties, never arbitrary install options.
        headers = "\n".join(key + "=" + properties[key] for key in
                            ("FILE_SIZE", "FILE_HASH", "METADATA_SIZE", "METADATA_HASH"))
        require(file_identity(path) == before, "OTA file changed while being checked.")
        return {"path": path, "stat": before, "metadata": metadata, "headers": headers,
                "offset": offset, "size": size, "care_map": "care_map.pb" in names}


def show_package(package):
    meta = package["metadata"]
    print("OTA:", package["path"])
    print("Device:", meta["pre-device"])
    print("Target:", meta["post-build"])
    print("Source:", meta.get("pre-build", "full OTA (no source fingerprint constraint)"))
    print("Payload: offset={}, size={}".format(package["offset"], package["size"]))


class Adb:
    def __init__(self, executable, serial):
        executable = shutil.which(executable)
        require(executable, "adb not found. Install Android Platform-Tools or use --adb PATH.")
        self.command = [executable]
        if not serial:
            output = self.run("devices")
            devices = [line.split()[0] for line in output.splitlines() if len(line.split()) == 2 and line.split()[1] == "device"]
            require(len(devices) == 1, "Connect one authorized device, or select one with -s SERIAL.")
            serial = devices[0]
        self.command += ["-s", serial]
        require(self.run("get-state").strip() == "device", "Device is not available: " + serial)
        print("ADB device:", serial)

    def run(self, *args, timeout=60):
        result = subprocess.run(self.command + list(args), stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, errors="replace", timeout=timeout)
        require(result.returncode == 0, "adb {} failed:\n{}".format(args[0], result.stdout.strip()))
        return result.stdout

    def shell(self, *args):
        return self.run("shell", " ".join(shlex.quote(str(arg)) for arg in args)).strip()

    def prop(self, name):
        return self.shell("getprop", name)

    def root(self):
        print(self.run("root").strip())
        self.run("wait-for-device")
        require(self.shell("id", "-u") == "0", "This tool requires adb root (userdebug/eng firmware); production user builds are unsupported.")


def check_device(adb, metadata):
    require(adb.prop("ro.boot.slot_suffix") in ("_a", "_b"), "Device does not report an A/B boot slot.")
    for key, prop in (("pre-device", "ro.product.device"),
                      ("pre-build", "ro.build.fingerprint"),
                      ("pre-build-incremental", "ro.build.version.incremental")):
        if metadata.get(key):
            actual = adb.prop(prop)
            require(actual in metadata[key].split("|"), "OTA {} mismatch: device reports {!r}, package requires {!r}.".format(key, actual, metadata[key]))
    require(adb.shell("test", "-x", "/system/bin/update_engine_client") == "", "update_engine_client is missing.")
    require(adb.prop("init.svc.update_engine") == "running", "update_engine service is not running.")


def install(package, adb, reboot=False, log_path=None):
    if log_path:
        log_path = Path(log_path).expanduser().resolve()
        require(log_path != package["path"] and
                (not log_path.exists() or not log_path.samefile(package["path"])),
                "The log file must not overwrite the OTA package.")
    check_device(adb, package["metadata"])
    adb.root()
    token = uuid.uuid4().hex
    staging = "/data/local/tmp/seeed-ota-" + token + ".zip"
    destination = "/data/ota_package/seeed-ota-" + token + ".zip"
    require(file_identity(package["path"]) == package["stat"], "OTA file changed after validation.")
    adb.shell("mkdir", "-p", "/data/ota_package")
    print("Uploading OTA ZIP...", flush=True)
    adb.run("push", str(package["path"]), staging, timeout=None)
    require(file_identity(package["path"]) == package["stat"], "OTA file changed during upload; installation was not started.")
    adb.shell("mv", staging, destination)
    files = [destination]
    if package["care_map"]:
        # update_verifier expects care_map.pb at this fixed location after reboot.
        with tempfile.TemporaryDirectory(prefix="seeed-ota-") as directory:
            local_map = Path(directory) / "care_map.pb"
            with zipfile.ZipFile(package["path"]) as archive:
                local_map.write_bytes(archive.read("care_map.pb"))
            adb.run("push", str(local_map), staging + ".care_map")
        adb.shell("mv", staging + ".care_map", "/data/ota_package/care_map.pb")
        files.append("/data/ota_package/care_map.pb")
    else:
        # A care map from an earlier update must not verify this update's partitions.
        adb.shell("rm", "-f", "/data/ota_package/care_map.pb")
    adb.shell("chown", "system:cache", *files)
    adb.shell("chmod", "0660", *files)
    adb.shell("restorecon", *files)
    command = ["update_engine_client", "--update", "--follow", "--payload=file://" + destination,
               "--offset=" + str(package["offset"]), "--size=" + str(package["size"]),
               "--headers=" + package["headers"]]
    print("Device package (retained for diagnosis/resume):", destination, flush=True)
    log = open(log_path, "w", encoding="utf-8") if log_path else None
    completion = None
    try:
        with subprocess.Popen(adb.command + ["shell", " ".join(shlex.quote(arg) for arg in command)],
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              text=True, errors="replace") as process:
            try:
                for line in process.stdout:
                    print(line, end="", flush=True)
                    if log:
                        log.write(line)
                        log.flush()
                    match = re.search(r"onPayloadApplicationComplete\([^\r\n]*\((-?\d+)\)\)", line)
                    if match:
                        completion = int(match.group(1))
                result = process.wait()
            except KeyboardInterrupt:
                process.terminate()
                raise
        require(result == 0 and completion == 0,
                "OTA was not confirmed successful (adb exit={}, completion={}). No reboot requested. Check update_engine logs.".format(result, completion))
    finally:
        if log:
            log.close()
    print("OTA installed successfully; reboot is required to start the new system.")
    if reboot:
        adb.run("reboot")
        print("Reboot requested. Run the status command after Android has started.")
    else:
        print("Reboot when ready: " + " ".join(shlex.quote(arg) for arg in adb.command + ["reboot"]))


def status(adb, package):
    for prop in ("ro.product.device", "ro.boot.slot_suffix", "ro.build.fingerprint",
                 "ro.build.version.incremental", "sys.boot_completed", "ro.virtual_ab.enabled",
                 "init.svc.update_engine"):
        print(prop + "=" + adb.prop(prop))
    if package:
        for key, prop in (("post-build", "ro.build.fingerprint"),
                          ("post-build-incremental", "ro.build.version.incremental")):
            require(adb.prop(prop) in package["metadata"][key].split("|"), "Device has not booted the OTA target: " + key + " mismatch.")
        require(adb.prop("sys.boot_completed") == "1", "Android has not finished booting.")
        print("PASS: Android booted the expected OTA target version.")
        print("For Virtual A/B, snapshot merging may still be in progress; see the OTA guide.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)
    check = subcommands.add_parser("check", help="Check OTA metadata and payload hashes; no adb required")
    check.add_argument("ota", help="A/B OTA ZIP, not update.img or target-files")
    apply = subcommands.add_parser("install", help="Validate, upload and install using adb root")
    apply.add_argument("ota")
    apply.add_argument("--reboot", action="store_true", help="Reboot only after a successful completion callback")
    apply.add_argument("--log", help="Save update_engine_client output to a host file")
    query = subcommands.add_parser("status", help="Show running firmware; optionally check the target OTA version")
    query.add_argument("ota", nargs="?")
    for command in (apply, query):
        command.add_argument("-s", "--serial", help="ADB serial; required when multiple devices are connected")
        command.add_argument("--adb", default="adb", help="Path to adb (default: adb on PATH)")
    args = parser.parse_args(argv)
    try:
        package = inspect_package(args.ota, verify=args.command != "status") if args.ota else None
        if package:
            show_package(package)
        if args.command == "check":
            print("PASS: A/B package structure and payload hashes match (signature trust is checked by the device).")
            return 0
        adb = Adb(args.adb, args.serial)
        if args.command == "install":
            install(package, adb, args.reboot, args.log)
        else:
            status(adb, package)
        return 0
    except KeyboardInterrupt:
        print("\nInterrupted. The device may still be updating; inspect its status/logs before retrying.", file=sys.stderr)
    except (OTAError, OSError, ValueError, KeyError, RuntimeError, zipfile.BadZipFile, struct.error,
            subprocess.TimeoutExpired) as error:
        print("ERROR:", error, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
