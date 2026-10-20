# 编译说明（A17 SSI + A14 GRF 融合）

[English](BUILD-FLOW.md) | 简体中文

两个开发板共用 `BASE_SDK` 指定的 A14 vendor SDK 和 A17 system SDK，但分别使用自己的产品配置。先编译 A17，再在 A14 中编译并融合，最终在 A14 生成 `update.img`。以下为操作说明；本次文档更新未执行编译。

## 1. 准备 SDK 与 overlay

准备匹配 [BASE_SDK](../BASE_SDK) 的两份 SDK 和标准 AOSP Linux 编译环境。建议两棵树预留约 600 GB 空间，安装 `git`、`repo`、`rsync`、`unzip` 并配置 Git 用户名及邮箱。SDK 的具体主机依赖以随附 Rockchip 编译指南为准。

目录示例：

```text
/path/work/
├── a14/
├── a17/
└── seeed-android-rockchip/
```

```bash
cd /path/work/seeed-android-rockchip
./setup.sh --vendor-sdk /path/work/a14 --system-sdk /path/work/a17
```

### 使用编译脚本

完成 `setup.sh` 集成后，可以在本仓库运行脚本，按菜单选择产品并依次完成 A17 编译、A14 编译、融合和打包：

```bash
./seeed_android_build.sh
# 或直接指定产品、并行数与 SDK 路径
./seeed_android_build.sh --product rk3576 -j 16
./seeed_android_build.sh --product rk3588 --system-sdk /path/work/a17 --vendor-sdk /path/work/a14
# 仅检查路径和显示命令，不加载 SDK 环境、不执行编译
./seeed_android_build.sh --product rk3576 --dry-run
```

默认使用仓库同级的 `a17/`、`a14/`，构建变体为 `userdebug`；可用 `--variant user` 切换。脚本使用 SDK 默认的 `out/` 目录，分别在独立 shell 中构建两侧，并按 A17 的 `out/file_name_tag.txt` 定位当前 target-files ZIP、核对包内产品与变体。每侧编译前核对 SDK 根目录和 lunch 环境，最终拒绝未更新的 `update.img`；允许 A17 在 `make dist` 成功后复用有效的增量构建产物。脚本不会自动运行 `setup.sh`；遇到失败会停止。不要在相同 SDK 树中同时运行多个构建。完整选项见 `./seeed_android_build.sh --help`。

## 2. 选择开发板

| 开发板 | A17 lunch | A14 lunch | A14 固件目录 |
|---|---|---|---|
| `recomputer_rk3576_devkit` | `recomputer_rk3576_ssi-cp2a-userdebug` | `recomputer_rk3576_devkit-userdebug` | `rockdev/Image-recomputer_rk3576_devkit/` |
| `recomputer_rk3588_devkit` | `recomputer_rk3588_ssi-cp2a-userdebug` | `recomputer_rk3588_devkit-userdebug` | `rockdev/Image-recomputer_rk3588_devkit/` |

## 3. reComputer RK3576 DevKit

在第一个终端编译 A17 system：

```bash
cd /path/work/a17
source build/envsetup.sh
lunch recomputer_rk3576_ssi-cp2a-userdebug
make dist -j$(nproc)
```

成功后，在第二个终端编译 A14 vendor 并融合。将 `SSI_TARGET_FILES` 改为本次 A17 构建产生的实际文件路径，不要直接传入通配符或选用另一个开发板的产物：

```bash
cd /path/work/a14
source build/envsetup.sh
lunch recomputer_rk3576_devkit-userdebug
SSI_TARGET_FILES="/path/work/a17/out/dist/recomputer_rk3576_ssi-target_files-<build>.zip"
./build.sh -AKUou \
    -M /path/work/a17/out/host/linux-x86/bin/merge_target_files \
    -T "$SSI_TARGET_FILES"
```

## 4. reComputer RK3588 DevKit

在第一个终端编译 A17 system：

```bash
cd /path/work/a17
source build/envsetup.sh
lunch recomputer_rk3588_ssi-cp2a-userdebug
make dist -j$(nproc)
```

成功后，在第二个终端编译 A14 vendor 并融合。将 `SSI_TARGET_FILES` 改为本次 A17 构建产生的实际文件路径，不要直接传入通配符或选用另一个开发板的产物：

```bash
cd /path/work/a14
source build/envsetup.sh
lunch recomputer_rk3588_devkit-userdebug
SSI_TARGET_FILES="/path/work/a17/out/dist/recomputer_rk3588_ssi-target_files-<build>.zip"
./build.sh -AKUou \
    -M /path/work/a17/out/host/linux-x86/bin/merge_target_files \
    -T "$SSI_TARGET_FILES"
```

## 5. 参数与产物

`-A` 编译 Android vendor，`-K` 编译 kernel，`-U` 编译 U-Boot，`-o` 生成 OTA / vendor target-files，`-u` 打包 `update.img`。融合需要 `-o`，否则可能缺少本次 vendor target-files 或误用旧产物。

`-M` 指向 A17 编译生成的 host 可执行文件；不要指向源码目录中的 `merge_target_files.py`。`-T` 指向对应开发板的 A17 target-files ZIP。A17 本身不生成最终 `update.img`。

A14 脚本提取 SSI 配置、编译 vendor、生成 vendor target-files，再执行 `rk_merge_target_files`，合并 framework 与 vendor，并打包固件。产物位于上表的开发板目录：

- `update.img`：SDDiskTool 和 upgrade_tool 使用的完整固件。
- `MiniLoaderAll.bin`：对应开发板的 USB 下载 Loader，供清空 NOR 和切换存储时使用。
- `super.img`、`*-target-files-merged.zip`、`*-images-merged-fastboot.zip`：融合产物。

两侧必须使用同一 overlay 版本和 `BASE_SDK` 指定的 SDK，不要混用 RK3576 / RK3588 的 Loader 或镜像。切换开发板时重新执行对应的 lunch，并保留每块板自己的 A17 target-files。RK3588 SSI 配置启用了 HDMI-RX，应使用其专属 SSI 产品。

## 6. 烧录与参考

下一步见 [SD 卡 / eMMC 烧录说明](FLASHING_zh.md)，**eMMC 启动前必须清空 NOR Flash**。

融合实现参见 A14 的 `device/rockchip/common/build/rockchip/build.sh` 和 `mkimage.sh`，以及 A17 的 `RKDocs/android/Rockchip_Developer_Guide_Android17_SSI_SDK_{CN,EN}.pdf` §4.4.6 Method 2。也可按 Rockchip 指南从 A17 使用 `rkbuild` 驱动两侧构建（Method 1）；本说明采用 A14 驱动融合的方式。

A17 SSI 保持 `PRODUCT_EXTRA_VNDK_VERSIONS := 34` 以兼容 A14 vendor API；更改 vendor API / VINTF 接口后应重新验证融合。
