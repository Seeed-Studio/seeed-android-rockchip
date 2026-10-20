# 验证 A/B OTA 升级

[English](OTA.md) | 简体中文

适用于已运行 Seeed RK3576 / RK3588 Android 17 SSI + A14 Vendor 融合 **A/B 固件**的开发板。使用本仓库的 [ota_update.py](../tools/ota/ota_update.py)，只需要现成 OTA ZIP、Python 3 和 `adb`，无需下载 SDK、运行 `setup.sh`、source/lunch 或编译。

## 1. 准备

- 主机安装 **Python 3.8+** 和独立的 **Android Platform-Tools**，确认 `python3 --version`、`adb version` 可用。Windows 下可将命令中的 `python3` 改为 `py -3`。
- 开发板正常启动 Android，开启 USB 调试并授权主机。此验证工具使用 `adb root`，要求支持 root 的 `userdebug` / `eng` 固件；不支持锁定的生产 `user` 固件。
- 获取对应开发板的融合 OTA 完整包，或与当前源版本对应的差分 OTA 包。**不要使用 `update.img`、`*-images-merged-fastboot.zip`、`*-target_files-merged.zip` 或仅 Vendor 工程的 OTA 包。** 文件名可变，工具按包内结构识别。
- 保持供电和 USB 连接稳定，保存重要数据，并为 OTA ZIP 及 Virtual A/B 快照保留足够的 `/data` 空间。工具不清数据、不修改 SELinux 模式、不替换验签密钥。

以下命令均在本仓库根目录执行。升级包可以放在任意主机目录：

```bash
python3 tools/ota/ota_update.py --help
adb devices
```

脚本默认使用 PATH 中的 `adb`。`install` / `status` 可通过 `--adb /path/to/adb` 指定程序，通过 `-s SERIAL` 指定设备。未指定序列号时，必须只有一台已授权、在线的设备；后续命令会固定使用该设备。

## 2. 离线检查升级包

```bash
python3 tools/ota/ota_update.py check /path/to/ota-merged.zip
```

此命令不调用 `adb`，检查：

- `ota-type=AB`、目标设备与目标版本元数据；拒绝请求清除用户数据的包。
- `payload.bin`、`payload_properties.txt` 和 Android OTA metadata 是否存在且唯一；payload 必须在 ZIP 中以不压缩方式存储。
- payload 标识、大小、`FILE_HASH` 和 `METADATA_HASH` 是否匹配。

输出 `PASS` 表示结构与 payload 哈希一致，**不代表已验证包的签名来源或设备兼容性**。设备上的 `update_engine` 继续负责 payload 签名、源分区数据、防回滚和安装相关检查。请从可信发布渠道获取升级包。

## 3. 上传并安装

```bash
python3 tools/ota/ota_update.py install /path/to/ota-merged.zip \
  -s DEVICE_SERIAL --log ota-install.log
```

工具重新完整检查包，读取设备当前启动槽、设备名、版本与升级服务状态。包的 `pre-device` 必须匹配 `ro.product.device`；差分包若声明 `pre-build` / `pre-build-incremental`，也必须匹配当前版本，否则在申请 root 或上传前退出。

随后工具请求 `adb root`，将 ZIP 上传到 `/data/ota_package/seeed-ota-<随机编号>.zip`，设置所属用户、权限和 SELinux 标签，并根据 ZIP 本地文件头计算 payload 的准确偏移与长度，调用设备上的 `update_engine_client --update --follow`。不需要手动解包，也不需要 HTTP 服务器或网络连接。

若包中包含 `care_map.pb`，会安装到 `/data/ota_package/care_map.pb`，供重启后的 `update_verifier` 使用；不包含时会移除旧 care map。安装期间不要启动另一个 OTA 客户端或并发运行本工具。

成功判据为客户端退出码为 0，且收到：

```text
onPayloadApplicationComplete(ErrorCode::kSuccess (0))
```

正常情况下还会出现 `UPDATE_STATUS_UPDATED_NEED_REBOOT`。**默认不自动重启**，成功后工具打印绑定当前序列号的重启命令。也可以显式要求成功后重启：

```bash
python3 tools/ota/ota_update.py install /path/to/ota-merged.zip \
  -s DEVICE_SERIAL --log ota-install.log --reboot
```

失败、没有成功回调，或返回 52（已安装但未激活）时，工具非零退出，不请求重启。`--log` 保存客户端输出，会覆盖指定的主机日志文件。设备中的随机命名 ZIP 会保留用于排查；升级、重启及快照合并全部完成后，可按工具打印的确切路径自行删除，不要批量删除整个 OTA 目录。

## 4. 重启后验证

Android 启动完成后执行：

```bash
python3 tools/ota/ota_update.py status /path/to/ota-merged.zip -s DEVICE_SERIAL
```

工具显示设备名、当前槽、fingerprint、incremental 版本、启动完成标志和升级服务状态。只有运行版本匹配包的 `post-build`、`post-build-incremental`，且 `sys.boot_completed=1` 时才输出 `PASS`。此步骤只读取包的元数据，不再重新计算大 payload 的哈希。

如果只是查看设备当前状态，可以不传 OTA：

```bash
python3 tools/ota/ota_update.py status -s DEVICE_SERIAL
```

`status` 验证的是已启动目标版本，不能据此判定 Virtual A/B 快照合并已经完成。Virtual A/B 设备重启到新版本后，可运行：

```bash
adb -s DEVICE_SERIAL root
adb -s DEVICE_SERIAL wait-for-device
adb -s DEVICE_SERIAL shell update_engine_client --merge
```

这会请求升级清理并等待快照合并结束；同样检查成功回调。合并完成前不要开始下一次 OTA。最后检查主要功能和用户数据是否正常；版本匹配本身不代表业务功能验证通过。

## 5. 失败排查

```bash
adb -s DEVICE_SERIAL logcat -d -s update_engine
adb -s DEVICE_SERIAL shell getprop ro.boot.slot_suffix
adb -s DEVICE_SERIAL shell getprop ro.build.fingerprint
adb -s DEVICE_SERIAL shell df -h /data
```

| 现象 | 检查项 |
|---|---|
| `adb` 找不到、设备 offline/unauthorized | Platform-Tools、USB 调试授权、线缆与 `-s` |
| `adb root` 后仍不是 UID 0 | 使用可 root 的开发固件；本工具不能为生产固件提权 |
| 设备/源版本不匹配 | 是否拿错板卡固件；差分包是否由设备当前版本的融合素材包制作 |
| 签名、源分区哈希或时间戳失败 | 设备信任的发布密钥、当前分区是否改动、是否在降级；不要关闭验签来绕过 |
| 空间不足或快照错误 | `/data` 空间、上一次 Virtual A/B 合并是否完成 |
| 命令被中断/ADB 断开 | 设备可能仍在升级；先检查日志与状态，再决定是否重试，不自动 reset/cancel |

工具不是跨分区布局迁移工具，不能将原生 A14 非 A/B 固件直接转换为 A17 A/B 固件。也不是生产环境更新客户端；正式产品应通过具有系统权限的升级应用调用 `UpdateEngine` 并管理版本发布。

## 6. 工具自测

```bash
python3 -B -m unittest discover -s tools/ota -p 'test_*.py' -v
```

自测使用合成 OTA 和模拟 `adb`，不访问真实设备。真实板卡上的安装、重启和快照合并仍需按上述流程验证。
