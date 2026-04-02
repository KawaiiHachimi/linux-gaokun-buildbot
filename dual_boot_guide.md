# Windows + Linux 双系统安装与引导配置（DG + systemd-boot）

本文档以 `systemd-boot` 为例，接管默认启动项，实现 Windows / Linux 二选一

## 一、准备

- 工具：DiskGenius（下文简称 DG）
- 文件：
	- 解压后的虚拟磁盘镜像如 `ubuntu-26.04-gaokun3.img`

## 二、备份虚拟磁盘 rootfs 并还原到内置硬盘

1. 在 DG 中先挂载虚拟磁盘镜像。
2. 找到镜像里的 Linux rootfs 分区，右键使用“备份分区到镜像文件”，备份类型选择“完整备份”，导出为 `rootfs.pmf`。
3. 在内置硬盘分区上右键使用“拆分分区”，分区后部建立新分区，作为 Linux rootfs 目标分区。
4. 对该新分区执行“还原分区”，选择刚才的 `rootfs.pmf`，完成 rootfs 写入。
5. 检查还原后的分区“卷UUID”是否与虚拟磁盘镜像中的 rootfs 分区“卷UUID”一致。

## 三、同步 EFI 目录

1. 从虚拟磁盘镜像中拷贝出完整的 `EFI` 目录。
2. 打开内置硬盘 EFI 分区文件浏览，先将 `\EFI\BOOT\BOOTAA64.EFI` 备份为 `\EFI\BOOT\BOOTAA64.EFI.bak`。
3. 把拷出的整个 `EFI` 目录直接拖入内置硬盘 EFI 分区根目录覆盖。

完成后，`EFI` 下通常应包含如下目录：
- `BOOT`
- `systemd`
- `Linux` 或镜像中对应的 loader entry / kernel 目录
- `Microsoft`

Windows 一般可由 `systemd-boot` 自动探测，所以无需额外修改 Windows 引导项。

## 四、修改 EFI 分区卷序列号

1. 在 DG 中查看虚拟磁盘镜像 EFI 分区卷序列号（如 `ABCD-1234`），右键可进行复制。
2. 右键内置硬盘 EFI 分区，选择“修改卷序列号”，输入复制的卷序列号，注意去除中间的 `-`。
3. 检查其卷序列号是否改成与虚拟磁盘镜像 EFI 分区相同的卷序列号。

## 五、重启验证

- 重启后应进入 `systemd-boot` 启动菜单。
- 菜单中可选择启动 Windows 或 Linux 发行版。

## 补充说明（EL2 可选）

若镜像已带好 EL2 所需文件，完成本篇后直接在 `systemd-boot` 中选择 EL2 菜单项启动即可，详见 [el2_kvm_guide.md](el2_kvm_guide.md)。

## 常见提醒

- 若启动菜单未出现，优先检查：
	- `\EFI\BOOT\BOOTAA64.EFI` 是否已经被镜像中的 `systemd-boot` 覆盖
	- EFI 目录结构是否完整（包含 `\EFI\systemd\`、`loader\entries\` 以及镜像中的内核 / initramfs / dtb 文件）
	- EFI 卷序列号是否与镜像一致
- 若误操作导致无法启动，可启动 USB 存储设备上的 Linux 或 WinPE（推荐使用 [CNBYDJ PE](https://bydjpe.winos.me)）挂载内置硬盘 EFI 分区，使用先前备份的 `BOOTAA64.EFI.bak` 回滚。
