[English](../README.md) | 中文

# linux-gaokun-buildbot

面向华为 MateBook E Go 2023（代号 `gaokun3`）、基于高通骁龙 8cx Gen3（`SC8280XP`）平台的 Linux 镜像构建脚本、工具和固件。内核源码、驱动、设备树及配置在独立的下游内核仓库维护。

**迁移草案，尚不可发布。** 目标为 `gaokun3/linux` 与 `gaokun3/buildbot`；内核候选提交尚待推送到目标仓库，EL2 已禁用。参见 [迁移记录与检查项](migration.md)。

`build.env` 固定内核 SHA 与发行版版本；`./build.sh kernel|debs|rpms` 是本地入口，镜像组装暂仍由 CI 执行。

## 包含内容

### 仓库结构

- `docs/`：中英文使用/构建指南与平台说明
- `firmware/`：镜像构建使用的最小固件集
- `packaging/`：各发行版内核和固件包的打包模板和元数据
- `tools/`：设备专属辅助脚本、服务文件和 EL2 EFI 载荷
- `scripts/ci/`：工作流构建、镜像创建和打包脚本
- `scripts/local/`：一些可在本地设备上运行的实用脚本

### 软件包产物

软件包流水线会构建并安装专用软件包集：

- **Fedora (RPM)**：`kernel-gaokun3`、`kernel-modules-gaokun3`、`kernel-devel-gaokun3`、`linux-firmware-gaokun3`
- **Ubuntu (DEB)**：`linux-image-gaokun3`、`linux-modules-gaokun3`、`linux-headers-gaokun3`、`linux-firmware-gaokun3`
- **EL2 暂停构建**：等待独立迁移与验证；请求 EL2 构建会提前报错。
- Ubuntu 内核镜像包在安装/升级时运行 `update-initramfs`，进而通过发行版的 `systemd-boot` 钩子刷新 BLS 条目。
- Fedora 内核 RPM 现自带匹配的 `dracut.conf.d` 片段，并在 `%posttrans` 中运行 `dracut` + `kernel-install add`，因此安装或升级软件包会自动刷新 initramfs 和 BLS 条目。

### Release 产物

- Fedora 和 Ubuntu 镜像 release 包含压缩后的可安装镜像。
- Gaokun RPM 和 DEB release 包含镜像工作流所使用的独立内核与固件软件包集合。

### 内核来源

驱动改动与原作者信息保存在下游内核 Git 提交中。旧补丁文件仍可从本仓库迁移前的 Git 历史取回，详见 [迁移记录](migration.md)。

### Tools 来源

- `tools/audio`、`tools/bluetooth`：来自 [whitelewi1-ctrl/matebook-e-go-linux](https://github.com/whitelewi1-ctrl/matebook-e-go-linux)
- `tools/el2/qebspilaa64.efi`：来自 [stephan-gh/qebspil](https://github.com/stephan-gh/qebspil)
- `tools/el2/slbounceaa64.efi`：来自 [TravMurav/slbounce](https://github.com/TravMurav/slbounce)
- `tools/touchscreen-tuner`：来自 [chiyuki0325/EGoTouchRev-Linux](https://github.com/chiyuki0325/EGoTouchRev-Linux)，本仓库对其做了 GTK4 GUI 改进

## 启动产物布局

镜像和本地安装工作流现遵循标准 `kernel-install` + BLS 流程，而非手动编写 `systemd-boot` 条目。

- BLS 条目使用发行版名称：`loader/entries/fedora-<kernel-release>.conf` 或 `loader/entries/ubuntu-<kernel-release>.conf`。`/etc/kernel/entry-token` 持久保存名称，供升级及 initramfs 钩子读取；显式调用使用 `--entry-token=os-id`。
- ESP 上的内核、initrd/initramfs 和 DTB 放在 `fedora/<kernel-release>/` 或 `ubuntu/<kernel-release>/`，与系统自身的 machine-id 分开。
- 迁移时保留旧的 machine-id 启动项供回退，确认新项可启动后再清理。同一 ESP 上安装两份同发行版系统时，需要不同标识。详见 [启动布局](boot-layout.md)。
- 在 `/boot` 中还会保留一份 DTB 的兼容副本，方便用户后续切换到 GRUB。
- Ubuntu DTB 安装在 `/usr/lib/linux-image-<kernel-release>/qcom/` 供 `kernel-install` 使用，另有 `/boot/dtb-<kernel-release>` 兼容副本。
- Fedora DTB 安装在 `/usr/lib/modules/<kernel-release>/dtb/qcom/` 供 `kernel-install` 使用，另有 `/boot/dtb-<kernel-release>/qcom/` 兼容副本。
- Gaokun3 镜像脚本提供 `/etc/kernel/cmdline` 和 `/etc/kernel/devicetree`，然后调用 `kernel-install add` 填充最终的 BLS 条目。

## 快速开始

- Release：<https://github.com/KawaiiHachimi/linux-gaokun-buildbot/releases>
- 双系统引导指南：[English](dual_boot_guide_en.md) | [中文](dual_boot_guide_zh.md)
- EL2 实现说明：[English](el2_kvm_guide_en.md) | [中文](el2_kvm_guide_zh.md)
- Awesome Gaokun3：：[English](awesome_gaokun3_en.md) | [中文](awesome_gaokun3_zh.md)
- 构建指南 – Fedora 44：[English](matebook_ego_build_guide_fedora44_en.md) | [中文](matebook_ego_build_guide_fedora44_zh.md)
- 构建指南 – Ubuntu 26.04：[English](matebook_ego_build_guide_ubuntu26.04_en.md) | [中文](matebook_ego_build_guide_ubuntu26.04_zh.md)

## 功能支持

设备硬件工作情况可参考 [right-0903/linux-gaokun 的 `## Feature Support`](https://github.com/right-0903/linux-gaokun?tab=readme-ov-file#feature-support)。

## 参考

- [right-0903/linux-gaokun](https://github.com/right-0903/linux-gaokun)：内核补丁和设备支持工作的主要来源，附有详细的提交信息和说明。
- [TheUnknownThing/linux-gaokun](https://github.com/TheUnknownThing/linux-gaokun)：内核补丁和设备支持工作的另一个分支，包含触摸屏和 EC 相关的独特提交和说明。
- [whitelewi1-ctrl/matebook-e-go-linux](https://github.com/whitelewi1-ctrl/matebook-e-go-linux)：最早修复面板背光问题的仓库，包含一些额外的 Gaokun3 Linux 支持资源和修改。
- [gaokun on AUR](https://aur.archlinux.org/packages?O=0&K=gaokun)：为 Gaokun3 构建的多个 AUR 软件包，包括内核和固件包。
- [chenxuecong2/firmware-huawei-gaokun3](https://github.com/chenxuecong2/firmware-huawei-gaokun3)：Gaokun3 固件集合仓库。
- [chiyuki0325/EGoTouchRev-Linux](https://github.com/chiyuki0325/EGoTouchRev-Linux)：内置 `himax_hx83121a_spi` 内核模块的上游触摸屏驱动和算法仓库。
- [awarson2233/EGoTouchRev](https://github.com/awarson2233/EGoTouchRev)：EGoTouchRev-Linux 参考的 Windows 侧触控算法项目，也是 Gaokun3 触摸屏调参流水线的重要上游参考。
- [TravMurav/slbounce](https://github.com/TravMurav/slbounce)：在 Gaokun3 上启用 EL2 支持和安全启动的 UEFI 应用程序。
- [TravMurav/linux](https://github.com/TravMurav/linux/tree/x13s-6.18-v1.1-cxsd)：包含一些 sc8280xp 平台 EL2 支持补丁的 Linux 内核树。
- [stephan-gh/qebspil](https://github.com/stephan-gh/qebspil)：在高通平台上预启动 DSP 固件的 UEFI 应用程序，可在引导链中用于启动 Linux 之前。
