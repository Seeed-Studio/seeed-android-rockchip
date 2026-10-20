# Copyright 2026 Seeed Studio
# SPDX-License-Identifier: Apache-2.0
"""Offline tests: synthetic OTA files and a fake adb; no device is accessed."""

import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shlex
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import zipfile


TOOL = Path(__file__).with_name("ota_update.py")
SPEC = importlib.util.spec_from_file_location("ota_update", TOOL)
ota = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ota)

FAKE_ADB = r'''#!/usr/bin/env python3
import json, os, shlex, sys
args = sys.argv[1:]
with open(os.environ["FAKE_ADB_LOG"], "a") as log:
    log.write(json.dumps(args) + "\n")
if args[:1] == ["-s"]:
    args = args[2:]
if args == ["devices"]:
    print("List of devices attached\nboard-01\tdevice")
elif args == ["get-state"]:
    print("device")
elif args == ["root"]:
    print("restarting adbd as root")
elif args[:1] == ["shell"]:
    cmd = shlex.split(args[1])
    if cmd[:1] == ["getprop"]:
        props = {"ro.product.device": "board", "ro.boot.slot_suffix": "_a",
                 "ro.build.fingerprint": "old", "ro.build.version.incremental": "1",
                 "init.svc.update_engine": "running", "sys.boot_completed": "1"}
        props.update(json.loads(os.environ.get("FAKE_PROPS", "{}")))
        print(props.get(cmd[1], ""))
    elif cmd == ["id", "-u"]:
        print(os.environ.get("FAKE_UID", "0"))
    elif cmd[:1] == ["update_engine_client"]:
        code = os.environ.get("FAKE_COMPLETION", "0")
        if code != "missing":
            print("onPayloadApplicationComplete(ErrorCode::test (" + code + "))")
        sys.exit(int(os.environ.get("FAKE_CLIENT_EXIT", "0")))
'''


class OTATest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ota-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.package = self.root / "firmware with ' quotes.zip"
        self.fake = self.root / "adb"
        self.fake.write_text(FAKE_ADB)
        self.fake.chmod(0o755)
        self.adb_log = self.root / "adb.jsonl"
        self.env = dict(os.environ, FAKE_ADB_LOG=str(self.adb_log))

    def make_package(self, metadata=None, properties=None, corrupt=False,
                     compressed=False, care_map=True, extra=b"", duplicate=False):
        payload = b"CrAU" + struct.pack(">QQI", 2, 20, 0) + b"m" * 20 + b"data" * 32
        meta = {"ota-type": "AB", "pre-device": "board", "post-build": "new",
                "post-build-incremental": "2"}
        meta.update(metadata or {})
        props = {"FILE_SIZE": str(len(payload)), "METADATA_SIZE": "44",
                 "FILE_HASH": base64.b64encode(hashlib.sha256(payload).digest()).decode(),
                 "METADATA_HASH": base64.b64encode(hashlib.sha256(payload[:44]).digest()).decode()}
        props.update(properties or {})
        def pairs(values):
            return "\n".join(k + "=" + v for k, v in values.items()) + "\n"
        with zipfile.ZipFile(self.package, "w") as archive:
            archive.writestr("META-INF/com/android/metadata", pairs(meta))
            archive.writestr("payload_properties.txt", pairs(props))
            info = zipfile.ZipInfo("payload.bin")
            info.extra = extra
            info.compress_type = zipfile.ZIP_DEFLATED if compressed else zipfile.ZIP_STORED
            archive.writestr(info, payload[:-1] + b"!" if corrupt else payload)
            if care_map:
                archive.writestr("care_map.pb", b"map")
            if duplicate:
                with mock.patch("warnings.warn"):
                    archive.writestr("payload_properties.txt", pairs(props))
        return payload

    def cli(self, command="install", options=(), env=None):
        return subprocess.run([sys.executable, str(TOOL), command, str(self.package),
                               *options, *([] if command == "check" else ["--adb", str(self.fake)])],
                              env=dict(self.env, **(env or {})), text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10)

    def commands(self):
        return [json.loads(line) for line in self.adb_log.read_text().splitlines()] if self.adb_log.exists() else []

    def remote_commands(self):
        return [shlex.split(cmd[-1]) for cmd in self.commands() if "shell" in cmd]

    def test_check_hashes_and_local_extra_field_offset_without_adb(self):
        payload = self.make_package(extra=b"\xfe\xca\x04\x00test")
        result = ota.inspect_package(self.package)
        with self.package.open("rb") as stream:
            stream.seek(result["offset"])
            self.assertEqual(stream.read(result["size"]), payload)
        checked = self.cli("check")
        self.assertEqual(checked.returncode, 0, checked.stdout)
        self.assertFalse(self.adb_log.exists())

    def test_invalid_packages_never_access_device(self):
        for kwargs in ({"corrupt": True}, {"compressed": True}, {"duplicate": True},
                       {"properties": {"METADATA_HASH": "bad"}},
                       {"metadata": {"ota-type": "BLOCK"}},
                       {"metadata": {"ota-wipe": "yes"}}):
            with self.subTest(kwargs=kwargs):
                self.make_package(**kwargs)
                result = self.cli()
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertFalse(self.adb_log.exists())

    def test_success_preserves_headers_and_defaults_to_no_reboot(self):
        self.make_package()
        log = self.root / "install.log"
        result = self.cli(options=("--log", str(log)))
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("onPayloadApplicationComplete", log.read_text())
        self.assertFalse(any("reboot" in cmd for cmd in self.commands()))
        update = next(cmd for cmd in self.remote_commands() if cmd[0] == "update_engine_client")
        headers = next(arg for arg in update if arg.startswith("--headers="))
        self.assertIn("\nMETADATA_HASH=", headers)
        self.assertFalse(any(arg.startswith("POWERWASH=") for arg in update))
        self.assertTrue(any("care_map.pb" in " ".join(cmd) and "mv" in cmd for cmd in self.remote_commands()))
        self.assertTrue(all(cmd[:2] == ["-s", "board-01"] for cmd in self.commands()[1:]))

    def test_reboot_only_on_successful_callback_and_exit(self):
        self.make_package()
        for env, success in (({}, True), ({"FAKE_COMPLETION": "10"}, False),
                             ({"FAKE_COMPLETION": "52"}, False),
                             ({"FAKE_COMPLETION": "missing"}, False),
                             ({"FAKE_CLIENT_EXIT": "1"}, False)):
            with self.subTest(env=env):
                self.adb_log.unlink(missing_ok=True)
                result = self.cli(options=("--reboot",), env=env)
                self.assertEqual(result.returncode == 0, success, result.stdout)
                self.assertEqual(any("reboot" in cmd for cmd in self.commands()), success)

    def test_device_and_incremental_constraints_before_root_or_push(self):
        for metadata, props in (({}, {"ro.product.device": "other"}),
                                ({}, {"ro.boot.slot_suffix": ""}),
                                ({"pre-build": "different"}, {}),
                                ({"pre-build-incremental": "0"}, {})):
            with self.subTest(metadata=metadata, props=props):
                self.adb_log.unlink(missing_ok=True)
                self.make_package(metadata=metadata)
                result = self.cli(env={"FAKE_PROPS": json.dumps(props)})
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertFalse(any("push" in cmd or "root" in cmd for cmd in self.commands()))

    def test_incremental_matching_source_and_no_care_map(self):
        self.make_package(metadata={"pre-build": "old|another", "pre-build-incremental": "1"}, care_map=False)
        result = self.cli()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn(["rm", "-f", "/data/ota_package/care_map.pb"], self.remote_commands())

    def test_root_refusal_prevents_upload(self):
        self.make_package()
        result = self.cli(env={"FAKE_UID": "2000"})
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse(any("push" in cmd for cmd in self.commands()))

    def test_status_checks_target_and_boot_completion(self):
        self.make_package()
        for props, success in (({}, False),
                               ({"ro.build.fingerprint": "new", "ro.build.version.incremental": "2"}, True),
                               ({"ro.build.fingerprint": "new", "ro.build.version.incremental": "2", "sys.boot_completed": "0"}, False)):
            with self.subTest(props=props):
                result = self.cli("status", env={"FAKE_PROPS": json.dumps(props)})
                self.assertEqual(result.returncode == 0, success, result.stdout)

    def test_multiple_devices_require_serial(self):
        with mock.patch.object(ota.Adb, "run", return_value="List of devices attached\na\tdevice\nb\tdevice\n"):
            with self.assertRaisesRegex(ota.OTAError, "select one"):
                ota.Adb(str(self.fake), None)

    def test_explicit_serial_skips_discovery(self):
        self.make_package()
        result = self.cli(options=("-s", "chosen-board"))
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue(all(cmd[:2] == ["-s", "chosen-board"] for cmd in self.commands()))

    def test_log_cannot_overwrite_package(self):
        self.make_package()
        original = self.package.read_bytes()
        result = self.cli(options=("--log", str(self.package)))
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.package.read_bytes(), original)
        self.assertFalse(any("root" in cmd or "push" in cmd for cmd in self.commands()))

    def test_install_refuses_package_modified_after_check(self):
        self.make_package()
        package = ota.inspect_package(self.package)
        with self.package.open("ab") as stream:
            stream.write(b"changed")
        adb = mock.Mock()
        adb.prop.side_effect = lambda name: {"ro.boot.slot_suffix": "_a", "ro.product.device": "board", "init.svc.update_engine": "running"}.get(name, "")
        adb.shell.return_value = ""
        with self.assertRaisesRegex(ota.OTAError, "changed after"):
            ota.install(package, adb)
        adb.run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
