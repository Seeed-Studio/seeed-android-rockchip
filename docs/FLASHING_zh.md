# SD 卡与 eMMC 烧录说明

[English](FLASHING.md) | 简体中文

适用 `recomputer_rk3576_devkit` 和 `recomputer_rk3588_devkit`。必须使用各自的固件和 Loader；RK3576 的 SD 启动还需要下述 NOR 引导准备。编译方法见 [编译说明](BUILD-FLOW_zh.md)；也可使用已构建好的匹配固件。

## 1. 固件与工具

| 开发板 | 完整固件 | USB 下载 Loader |
|---|---|---|
| RK3576 | `a14/rockdev/Image-recomputer_rk3576_devkit/update.img` | 同目录 `MiniLoaderAll.bin` |
| RK3588 | `a14/rockdev/Image-recomputer_rk3588_devkit/update.img` | 同目录 `MiniLoaderAll.bin` |

以下工具已原样收录在 [tools/flashing/](../tools/flashing/README.md)，也可从 SDK 原路径获取：

| 用途 | SDK 原路径 |
|---|---|
| Windows Rockusb 驱动 | `a14/RKTools/windows/AndroidTool/DriverAssitant_v5.14.zip` |
| Windows SD 卡 | `a14/RKTools/windows/SDDiskTool_v1.78.zip` |
| Linux eMMC / NOR | `a14/RKTools/linux/Linux_Upgrade_Tool/upgrade_tool_v2.55_for_linux.zip` |
| Windows eMMC / NOR | `a14/RKTools/windows/upgrade_tool_v2.33_for_window.zip` |

备份目标存储中的数据；制卡会覆盖 SD 卡，清空 NOR 会删除原有引导程序，烧录 eMMC 会覆盖原系统。烧录期间保持供电与 USB 连接稳定。

## 2. Windows 制作 SD 启动卡

1. 完整解压 `SDDiskTool_v1.78.zip`，以管理员身份启动 `SD_Firmware_Tool.exe`，保留同目录的 `config.ini`、`Language/` 等文件。
2. 用读卡器连接 SD 卡，在“选择可移动磁盘”中按容量和盘符确认目标卡。
3. 在功能模式中选择 **“SD 启动 / SD Boot”**，取消“固件升级 / Upgrade Firmware”和“PCBA 测试”。工具默认配置是固件升级，必须切换；固件升级卡用于升级板上存储，不是从 SD 卡运行系统。
4. 点击“选择固件 / Firmware”，选择对应开发板的完整 `update.img`，不是 `super.img` 或 target-files ZIP。
5. 点击“开始创建 / Create”，确认覆盖，等待成功提示后安全弹出 SD 卡。若 Windows 提示格式化新分区，取消操作。
6. RK3576 先完成下面第 2.1 节的 NOR 引导准备。开发板断电，插入 SD 卡，按正常启动方式上电，从 SD 卡启动 Android；不要按住 BOOT 按键。检查 HDMI 或串口启动输出。

RK3576 不能通过清空 NOR 来实现 SD 启动，必须保留下述 SD 引导镜像。卡无法识别时先检查读卡器、工具权限及所选固件是否匹配。

## 2.1 RK3576：向 NOR 写入 SD 启动引导（必做）

`recomputer_rk3576_devkit` 的硬件 Boot Mode 为 **FSPI0 → UFS → USB**，BROM 不支持直接从 SD 卡启动。必须先通过 USB 向 RAM 下载 `rk3576_loader_src_usbplug.bin`，再将 `rk3576_idblock_src_usbplug.img` 写入 NOR Flash，之后才能从已制作好的 SD 卡正常启动。

两个预编译文件已收入 [tools/flashing/rk3576-sd-boot/](../tools/flashing/rk3576-sd-boot/README.md)。这是 RK3576 专用步骤，不适用于 RK3588；不能用普通 `MiniLoaderAll.bin` 替代这里指定的下载 Loader。

先按第 3 节按住 **BOOT** 键上电进入 Maskrom（Windows 还需安装 Rockusb 驱动）。取出 SD 卡，进入已解压的 upgrade_tool 目录，然后执行：

Linux：

```bash
SD_BOOT_DIR=/absolute/path/seeed-android-rockchip/tools/flashing/rk3576-sd-boot
sudo ./upgrade_tool ld
sudo ./upgrade_tool db "$SD_BOOT_DIR/rk3576_loader_src_usbplug.bin"
sudo ./upgrade_tool ssd
# 选择 SPINOR
sudo ./upgrade_tool ssd
# 确认 * 标记位于 SPINOR，输入 Q 退出
sudo ./upgrade_tool rfi
# 确认目标是 NOR 后，从 NOR 的 LBA 0 写入专用引导镜像
sudo ./upgrade_tool wl 0 "$SD_BOOT_DIR/rk3576_idblock_src_usbplug.img"
# 仅在写入成功后重启
sudo ./upgrade_tool rd
```

Windows PowerShell：

```powershell
$SdBootDir = 'C:\path\seeed-android-rockchip\tools\flashing\rk3576-sd-boot'
.\upgrade_tool.exe ld
.\upgrade_tool.exe db "$SdBootDir\rk3576_loader_src_usbplug.bin"
.\upgrade_tool.exe ssd
# 选择 SPINOR
.\upgrade_tool.exe ssd
# 确认 * 标记位于 SPINOR，输入 Q 退出
.\upgrade_tool.exe rfi
# 确认目标是 NOR 后写入专用引导镜像
.\upgrade_tool.exe wl 0 "$SdBootDir\rk3576_idblock_src_usbplug.img"
# 仅在写入成功后重启
.\upgrade_tool.exe rd
```

`db` 只向 RAM 下载用于烧录的 Loader，`wl` 才将引导镜像写入所选 NOR。不要将 idblock 镜像写入 EMMC 或 SD 卡，也不要使用 `uf` 烧录这个文件。若 SPINOR 不可选或写入失败，停止并检查连接、下载 Loader 和工具日志。

成功后断电，插入第 2 节制作好的 SD 卡，松开 BOOT 键，正常上电并检查启动输出。**SD 启动时保留 NOR 内的此引导镜像；切换到 eMMC 启动时再按第 4 节清空 NOR。** 从 eMMC 切回 SD 时，需要重新写入此 NOR 引导镜像。

## 3. USB 烧录准备：进入 Maskrom

**eMMC 烧录后要正常启动，必须先清空板载 NOR Flash。仅重新烧录 eMMC 不会清除 NOR 中的旧引导程序。**

1. 断电并取出 SD 卡，使用支持数据传输的 USB 线将开发板的 USB OTG 口连接到主机。
2. 按住板上丝印为 **BOOT** 的按键（用于进入 Maskrom 模式），再给开发板上电，然后松开按键。不同硬件版本的接口和按键位置以板上标识为准；不要把 Recovery 按键当作 BOOT 按键。
3. 使用下面的 `ld` 命令确认仅连接了一块目标板，显示 `Maskrom` 后再继续。若显示 `Loader`，可执行 `rd 3` 切到 Maskrom，再用 `ld` 检查。
4. Windows 先解压并安装仓库内 [DriverAssitant_v5.14.zip](../tools/flashing/DriverAssitant_v5.14.zip) 的 Rockusb 驱动（SDK 原路径见上表），以管理员身份打开 PowerShell。设备管理器中应能识别 Rockusb 设备。Windows 指定工具包内是 **命令行程序 `upgrade_tool.exe`**，不是 RKDevTool 图形界面。

Seeed 的 [RK3576 硬件接口说明](https://sensecraft.seeed.cc/ai-lab/en/tutorials/rk/edge-ai-computer/rk3576/interface-usage-guidelines/use-recomputer-rk3576-hardware-interfaces-and-fan-control)可用于定位其 Type-C OTG 和按键。RK3588 请按对应板卡丝印定位。

## 4. 清空 NOR Flash（eMMC 启动必做）

先用匹配开发板的 `MiniLoaderAll.bin` 下载 Boot 到 RAM，再用 `ssd` 选择 `SPINOR`。`ssd` 是交互命令：按当前输出输入 `SPINOR` 前面的编号，不要假定编号固定。带 `*` 的条目为当前存储；执行后再次运行 `ssd` 检查，按 `Q` 退出。

`rfi` 用于读取所选 NOR 的容量。`el` 的参数是起始扇区和扇区数量，每扇区 512 字节。清空整个 NOR 的扇区数为 **NOR 字节容量 / 512**。例如，只有确认 NOR 是 **16 MiB** 时才使用 `32768`（`0x8000`）扇区；32 MiB 应使用 `65536`（`0x10000`）。下面的值需按实际容量填写，不能按 eMMC 容量填写。

### Linux

完整解压 Linux 工具包，进入其目录后设置匹配固件目录的绝对路径（下面以 RK3576 为例；RK3588 改为 `Image-recomputer_rk3588_devkit`）：

```bash
unzip upgrade_tool_v2.55_for_linux.zip
cd upgrade_tool_v2.55_for_linux
chmod +x upgrade_tool
IMAGE_DIR=/absolute/path/a14/rockdev/Image-recomputer_rk3576_devkit
sudo ./upgrade_tool ld
sudo ./upgrade_tool db "$IMAGE_DIR/MiniLoaderAll.bin"
sudo ./upgrade_tool ssd
# 输入 SPINOR 的编号，确认切换成功
sudo ./upgrade_tool ssd
# 确认 * 标记位于 SPINOR，输入 Q 退出
sudo ./upgrade_tool rfi
```

**确认当前存储是 SPINOR 且容量正确后**，替换下方占位值并执行擦除：

```bash
NOR_SECTORS='<实际 NOR 容量字节数除以 512>'
sudo ./upgrade_tool el 0 "$NOR_SECTORS"
```

等待擦除成功。不要用 `ef MiniLoaderAll.bin` 代替上述流程：它会重新下载 Loader，不能据此保证擦除的仍是刚选择的 NOR。

### Windows PowerShell

完整解压 `upgrade_tool_v2.33_for_window.zip`，进入其中包含 `upgrade_tool.exe` 的目录：

```powershell
$ImageDir = 'C:\firmware\recomputer_rk3576_devkit'
# 将对应板卡的 update.img 和 MiniLoaderAll.bin 放在上述目录
.\upgrade_tool.exe ld
.\upgrade_tool.exe db "$ImageDir\MiniLoaderAll.bin"
.\upgrade_tool.exe ssd
# 输入 SPINOR 的编号，确认切换成功
.\upgrade_tool.exe ssd
# 确认 * 标记位于 SPINOR，输入 Q 退出
.\upgrade_tool.exe rfi
```

**确认当前存储和实际容量后**执行（示例只适用于已确认的 16 MiB NOR）：

```powershell
$NorSectors = 32768  # 按实际 NOR 容量修改：容量字节数 / 512
.\upgrade_tool.exe el 0 $NorSectors
```

若 `ssd` 没有 `SPINOR`、容量异常、下载 Boot 失败或擦除失败，应停止并检查 Loader 是否匹配当前芯片和 DDR、是否进入 Maskrom，以及 NOR 是否被 Loader 支持。不要在存储类型未确认时执行擦除。

## 5. 切换到 eMMC 并烧录

NOR 擦除成功后，在同一次连接中运行 `ssd`，按输出输入 **EMMC** 的编号；再次检查 `*` 标记和 `rfi` 的 eMMC 容量，然后烧录 `update.img`。如果中途断电或重连，须重新进入 Maskrom、下载 Boot、选择并确认 EMMC。

Linux（沿用前面的 `IMAGE_DIR`）：

```bash
sudo ./upgrade_tool ssd
# 选择 EMMC
sudo ./upgrade_tool ssd
# 确认 * 标记位于 EMMC，输入 Q 退出
sudo ./upgrade_tool rfi
sudo ./upgrade_tool uf "$IMAGE_DIR/update.img" -noreset
# 等待完整升级成功后再重启
sudo ./upgrade_tool rd
```

Windows PowerShell（沿用前面的 `$ImageDir`）：

```powershell
.\upgrade_tool.exe ssd
# 选择 EMMC
.\upgrade_tool.exe ssd
# 确认 * 标记位于 EMMC，输入 Q 退出
.\upgrade_tool.exe rfi
.\upgrade_tool.exe uf "$ImageDir\update.img" -noreset
# 等待完整升级成功后再重启
.\upgrade_tool.exe rd
```

完成后断电，移除烧录 USB 连接，保持 SD 卡取出，松开 BOOT 按键，再按正常方式上电。从 HDMI 或串口确认 Android 从 eMMC 启动。若仍进入旧引导程序，首先复查 NOR 是否已成功清空；若无法识别 eMMC，检查所选存储、Loader 和供电。

## 6. 命令依据与验证范围

工具压缩包自带 Rockchip 命令手册与 `revision.txt`：`db` 只向 RAM 下载 Boot；`ssd` 选择存储；`rfi` 查看容量；`el` 按扇区擦除；`uf` 烧录完整固件。Windows 手册 §1.8 明确列出 `el` 支持 SPI NOR，§1.10 说明交互存储选择；Linux 手册较旧，应结合工具版本记录阅读。

本次更新核对了产品配置、SDK 构建脚本、工具包内容与命令文档，未执行编译、擦除或实机烧录。首次在具体硬件版本上操作时应核对实际存储枚举和容量，并检查工具成功日志及启动结果。
