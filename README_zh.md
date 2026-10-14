# Seeed Android Rockchip overlay(SSI + GRF 融合)

[English](README.md) | 简体中文

本仓库承载 Seeed 基于 Rockchip 平台的产品适配 —— RK3576 与 RK3588,二者均构建自
共享的 A14 vendor SDK;每个产品在 `vendor-side/device/seeed/` 下拥有独立目录。
它**不是**一份独立的 Android 源码树。产品固件由两个 Rockchip SDK 融合(fusion)
而成:

- **system 侧 —— A17 SSI SDK**:framework / system 镜像(`ssi_17_arm64`,
  Android 17)
- **vendor 侧 —— A14 SDK**:u-boot、`kernel-6.1`、`vendor/`、RK3576 / RK3588 设备树
  (GRF,vendor API 冻结在 A14)

两个 SDK 均需向 Rockchip 获取;本 overlay 通过一条命令叠加到两棵 SDK 树上,
随后两侧融合(参见 [docs/BUILD-FLOW.md](docs/BUILD-FLOW.md))。

## 仓库内容

| 路径                          | 安装位置 | 内容                                              |
|-------------------------------|----------|---------------------------------------------------|
| `vendor-side/device/seeed/`   | A14 树   | 产品设备树(任意 Rockchip SoC)、`BoardConfig`、sepolicy |
| `vendor-side/vendor/seeed/`   | A14 树   | vendor 配置、预编译专有二进制                     |
| `vendor-side/packages/apps/`  | A14 树   | vendor 侧 Seeed 应用                              |
| `vendor-side/PATCHES/`        | A14 树   | 原地修改 A14 SDK 仓库所需的提交                   |
| `vendor-side/TREE/`           | A14 树   | A14 SDK 仓库的新增文件                          |
| `system-side/device/seeed/`   | A17 树   | 产品 SSI 配置(派生自 `ssi_17_arm64`)            |
| `system-side/packages/apps/`  | A17 树   | system/product 分区的 Seeed 应用                  |
| `system-side/PATCHES/`        | A17 树   | 原地修改 A17 SDK 仓库所需的提交                   |
| `system-side/TREE/`           | A17 树   | A17 SDK 仓库的新增文件                          |
| `BASE_SDK`                    | —        | 两侧所锚定的确切 SDK 快照 —— **请先阅读**         |
| `setup.sh`                    | —        | 一条命令集成进两棵 SDK 树                         |
| `tools/`                      | —        | 补丁导出辅助脚本、兜底 restore body               |

## 环境要求

- 两份 [`BASE_SDK`](BASE_SDK) 所列的 Rockchip SDK 快照。请向 Rockchip 或你的
  Seeed 对接人获取;快照不符时,补丁应用极可能失败。
- 装有标准 AOSP 构建依赖的 Linux 构建主机,约 600 GB 空闲磁盘空间(两棵树)。
- `git`、`repo`、`rsync`,以及已配置的 git 身份
  (`user.name` / `user.email` —— 补丁步骤依赖 `git am`)。

## 编译与烧录

- [编译说明](docs/BUILD-FLOW_zh.md)：`recomputer_rk3576_devkit` 与 `recomputer_rk3588_devkit` 的完整命令、融合流程和产物路径。
- [烧录说明](docs/FLASHING_zh.md)：Windows SD 启动卡、RK3576 的 NOR SD 引导准备、Linux / Windows eMMC 烧录，以及烧录 eMMC 前必须完成的 NOR Flash 清空步骤。
- [随仓库提供的烧录工具](tools/flashing/README.md)：四个工具与驱动的原始压缩包与 SHA-256 校验值。

## 快速开始

```bash
# 1. 同步/解包两份与 BASE_SDK 匹配的 Rockchip SDK(a14 + a17 两棵树)。

# 2. 获取本 overlay 并集成进两棵 SDK 树:
git clone <repo-url> seeed-android-rockchip
cd seeed-android-rockchip
./setup.sh                          # 自动探测同级 SDK 树,或:
./setup.sh --vendor-sdk /path/a14 --system-sdk /path/a17

# 3. 构建两侧并融合 —— 见 docs/BUILD-FLOW.md:
#    system 侧:  lunch recomputer_rk3576_ssi-cp2a-userdebug && make dist
#    RK3588 使用 recomputer_rk3588_ssi-cp2a-userdebug；完整命令见编译说明。
#    vendor 侧:  ./build.sh -AKUou -M <a17>/out/host/linux-x86/bin/merge_target_files \
#                          -T <a17>/out/dist/<system-product>-target_files-<build>.zip
```

`setup.sh` 把每侧的 overlay 目录拷贝(或加 `--symlink` 以软链方式)进对应 SDK
树,把 `TREE/` 承载的新增文件装进 SDK 的 git 仓库,校验每个补丁的 base
commit 都存在,通过 SDK 自带的 `restore_patches.sh` 机制应用补丁并校验结果。
使用 `--vendor-only` / `--system-only` 可只集成一侧。

### 用 `--symlink` 日常开发

日常开发(尤其多产品并行)推荐 `./setup.sh --symlink`:overlay 内容直接在本仓库
修改,下一次构建即生效——内容变更后无需重跑 `setup.sh`。由于 soong 不透过软链
发现构建文件,安装采用**混合**方式:`AndroidProducts.mk` / `Android.mk` 在 SDK
树内是真拷贝(体量小、结构性文件,重跑 `setup.sh` 即刷新),其余(BoardConfig、
产品 `.mk`、sepolicy、vendor 数据)全部软链。因此:

- 从 `TREE/` 安装的文件逐个软链 —— 在本仓库里改,下一次构建即生效;
- 修改已有文件、以及在已软链目录**内部**新增文件(如新 IQ 文件、新 sepolicy
  文件)立即生效;
- 新增产品目录、或在产品目录顶层新增文件后,需重跑一次 `setup.sh --symlink`;
- `packages/apps` 下带 `Android.bp`/`Android.mk` 的应用目录不能软链(同样是模块
  发现问题)——`setup.sh` 会拒绝,该侧请去掉 `--symlink`;
- copy 与 symlink 模式互切前先执行 `--uninstall`。

## 补丁机制

每侧各有一个 `PATCHES/` 目录,与该 SDK 的根目录一一对应。每个被跟踪的 SDK 项目:

```
vendor-side/PATCHES/kernel-6.1/
├── git-merge-base.txt   # 一行:"commit <sha>" —— 补丁应用所基于的 base
├── 0001-*.patch         # 编号的 git format-patch 文件,按序经 git am 应用
└── local_diff.diff      # 可选:未提交的改动,经 git apply 应用
```

应用逻辑位于 SDK 内(`restore_patches.sh`,由 Rockchip 提供);本仓库只承载数据
与一份兜底 body 脚本副本。如果你的 SDK 中缺少某个 base commit,说明 SDK 快照
与本 overlay 不匹配 —— 请获取 `BASE_SDK` 所列的快照。

重复运行 `setup.sh` 不会重置 HEAD 已越过所记录 base 的项目(例如上次运行之后
你在 SDK 里提交过工作):这些项目会被跳过并打印提示,而不是从 base 重新打补丁,
因此尚未导出到本仓库的提交不会在反复运行中丢失。照常使用
`tools/export_patches.sh` 导出即可。

## 新增文件与补丁(`TREE/`)

产品向 SDK git 仓库**新增**的文件 —— 内核 DTS/DTSI 与驱动、内核/u-boot 的
config 片段 —— 以真实可读的文件形式承载在 `<side>/TREE/<repo>/...`(镜像
SDK 布局),由 `setup.sh` 以**未跟踪**文件的方式装进对应仓库。"未跟踪"正是
两套机制咬合的关键:`git stash`、`git diff HEAD` 和 restore 分支都不会碰它们,
因此 TREE 文件在补丁应用后原样存活,也不会漏进导出的补丁。修改 SDK 已有文件
仍然走补丁 —— `setup.sh` 会拒绝已跟踪的 TREE 条目。规则与注意事项(安装后的
文件绝不要 `git add`、`git clean` 会清掉它们、补丁可以引用 TREE 文件)见
[`vendor-side/TREE/README.md`](vendor-side/TREE/README.md)。

## 版本管理

本仓库的 tag 与固件发布一一对应。`BASE_SDK` 为每个 tag 钉死构建所用的**两个**
SDK 快照。Rockchip 发布新 SDK 时,overlay 会 rebase 到新快照并重新发布;旧 tag
继续指向旧 SDK。

## 卸载

```bash
./setup.sh --uninstall [--vendor-only | --system-only]
```

从 SDK 树中移除 overlay 目录与从 `TREE/` 安装的文件(清单记录在 SDK 根目录
的 `.seeed-tree-files`)。已应用到 SDK git 仓库的补丁**不会**被回退(补丁
步骤工作在其自有的 `restore_<日期>` 分支上);要得到干净状态请重新同步 SDK。
