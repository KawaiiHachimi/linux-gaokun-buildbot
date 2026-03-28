# Huawei MateBook E Go 2023 Ubuntu 26.04 手动构建指南

> **目标机型**：Huawei MateBook E Go 2023 (`SC8280XP` / `gaokun3`)  
> **目标系统**：Ubuntu 26.04 (Plucky Puffin) GNOME，GRUB 启动，ext4 根文件系统  
> **推荐宿主机**：Ubuntu/Debian 或其他支持 `debootstrap` 的发行版  
> **仓库假设**：本文默认你当前仓库位于 `~/gaokun/linux-gaokun-buildbot`

**WSL2 建议切换到支持 `vfat`、`ext4` 等文件系统更完整的内核，例如：<https://github.com/Nevuly/WSL2-Linux-Kernel-Rolling/releases>**

---

## 准备说明

本文使用项目内已有内容，不需要额外获取设备专属仓库：

- `patches/`
- `defconfig/`
- `dts/`
- `tools/`
- `firmware/`

如果宿主机是 arm64，可直接原生构建。  
如果宿主机是 x86_64，请自行准备可用的 aarch64 交叉工具链，并在编译内核时额外设置 `CROSS_COMPILE`。

---

## 第一步：准备工作目录

安装基础依赖（Ubuntu 宿主机示例）：

```bash
sudo apt-get update
sudo apt-get install -y \
    gcc make bison flex bc libssl-dev libelf-dev dwarves \
    git parted dosfstools e2fsprogs curl python3 rsync \
    debootstrap qemu-user-static binfmt-support zstd xz-utils kmod
```

准备源码与工作目录：

```bash
mkdir -p ~/gaokun/matebook-build-ubuntu

cd ~/gaokun
# 获取指定版本的 Linux 主线源码
if [ ! -d "mainline-linux" ]; then
    git clone --depth 1 --branch v7.0-rc5 \
        https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git \
        mainline-linux
fi
```

设置环境变量：

```bash
export GAOKUN_DIR=~/gaokun/linux-gaokun-buildbot
export WORKDIR=~/gaokun/matebook-build-ubuntu
export KERN_SRC=~/gaokun/mainline-linux
export KERN_OUT=$GAOKUN_DIR/kernel-out
export FW_REPO=$GAOKUN_DIR/firmware
export ROOTFS_DIR=$WORKDIR/rootfs
export IMAGE_FILE=$WORKDIR/ubuntu-26.04-gaokun3.img
```

---

## 第二步：编译内核

应用项目内核补丁后直接构建。
当前触摸屏方案已经统一为内核内的 Himax HX83121A SPI 驱动，不再额外安装 DKMS：

```bash
cd $KERN_SRC

# 应用项目内置补丁
git am $GAOKUN_DIR/patches/*.patch

mkdir -p $KERN_OUT

# 根据 patch 后的 gaokun3_defconfig 生成配置，再补齐新内核默认选项
make O=$KERN_OUT ARCH=arm64 gaokun3_defconfig
make O=$KERN_OUT ARCH=arm64 olddefconfig
make O=$KERN_OUT ARCH=arm64 -j$(nproc)

KREL=$(cat $KERN_OUT/include/config/kernel.release)
echo $KREL
```

---

## 第三步：构建 RootFS

使用 Ubuntu 官方 `ubuntu-base` 预构建 rootfs 作为基础，然后通过 chroot 安装桌面环境与额外软件包。

> 如果宿主机是 x86_64，需要拷贝 `qemu-aarch64-static` 到 rootfs 中以支持 chroot 执行 arm64 二进制。

```bash
mkdir -p $ROOTFS_DIR

# 下载 ubuntu-base 预构建 rootfs（自带正确的 apt 源配置，无需手动写入）
UBUNTU_BASE_URL="https://cdimages.ubuntu.com/ubuntu-base/releases/26.04/release/ubuntu-base-26.04-base-arm64.tar.gz"
UBUNTU_BASE_BETA_URL="https://cdimages.ubuntu.com/ubuntu-base/releases/26.04/beta/ubuntu-base-26.04-beta-base-arm64.tar.gz"
UBUNTU_BASE_TAR=$WORKDIR/ubuntu-base-arm64.tar.gz

if ! curl -fsSL -o "$UBUNTU_BASE_TAR" "$UBUNTU_BASE_URL"; then
    echo "Release tarball not found, trying beta..."
    curl -fsSL -o "$UBUNTU_BASE_TAR" "$UBUNTU_BASE_BETA_URL"
fi

sudo tar -xzf "$UBUNTU_BASE_TAR" -C $ROOTFS_DIR

# x86_64 宿主机：拷贝 qemu-aarch64-static 以支持 chroot
if [ "$(uname -m)" != "aarch64" ]; then
    sudo cp "$(which qemu-aarch64-static)" $ROOTFS_DIR/usr/bin/
fi
```

挂载虚拟文件系统并进入 chroot 安装软件包：

```bash
sudo mount --bind /dev $ROOTFS_DIR/dev
sudo mount --bind /dev/pts $ROOTFS_DIR/dev/pts
sudo mount -t proc proc $ROOTFS_DIR/proc
sudo mount -t sysfs sys $ROOTFS_DIR/sys
sudo mount -t tmpfs tmpfs $ROOTFS_DIR/run

# 复制 DNS 配置以便 chroot 内可以联网
sudo cp /etc/resolv.conf $ROOTFS_DIR/etc/resolv.conf

sudo chroot $ROOTFS_DIR /bin/bash
```

在 chroot 中执行：

```bash
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y locales
sed -i 's/# zh_CN.UTF-8/zh_CN.UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=zh_CN.UTF-8 LC_MESSAGES=zh_CN.UTF-8

# 先安装内核相关依赖以及 initramfs-tools
apt-get install -y \
    linux-base initramfs-tools kmod \
    grub-efi-arm64 grub-efi-arm64-bin grub-efi-arm64-signed shim-signed efibootmgr

# 安装基础网络与压缩工具（ubuntu-base 中可能缺失）
apt-get install -y \
    iputils-ping iproute2 net-tools dnsutils traceroute \
    xz-utils unzip zip bzip2 zstd p7zip-full \
    wget curl ca-certificates gnupg lsb-release \
    less file sudo

# 安装桌面环境与常用软件
apt-get install -y \
    ubuntu-desktop-minimal \
    fonts-noto-color-emoji \
    fcitx5 fcitx5-chinese-addons \
    gnome-tweaks gnome-shell-extension-manager \
    mpv v4l-utils vim git htop fastfetch screen \
    alsa-utils pipewire-alsa \
    i2c-tools ssh \
    firefox

# 安装多媒体编解码器
apt-get install -y \
    gstreamer1.0-libav gstreamer1.0-plugins-ugly \
    ubuntu-restricted-extras

apt-get clean
exit
```

回到宿主机，安装内核、模块、固件和本地工具到 rootfs：

```bash
cd $KERN_SRC

KREL=$(cat $KERN_OUT/include/config/kernel.release)
echo $KREL

sudo make O=$KERN_OUT ARCH=arm64 INSTALL_MOD_PATH=$ROOTFS_DIR modules_install
sudo rm -f $ROOTFS_DIR/lib/modules/$KREL/{build,source}

# 按 Ubuntu 风格安装 kernel image
sudo mkdir -p $ROOTFS_DIR/boot
sudo cp $KERN_OUT/arch/arm64/boot/Image \
    $ROOTFS_DIR/boot/vmlinuz-$KREL

# Ubuntu 风格：dtb 放在 /usr/lib/linux-image-$KREL/ 下
sudo mkdir -p $ROOTFS_DIR/usr/lib/linux-image-$KREL/qcom
sudo cp $KERN_OUT/arch/arm64/boot/dts/qcom/sc8280xp-huawei-gaokun3.dtb \
    $ROOTFS_DIR/usr/lib/linux-image-$KREL/qcom/

# 直接复制项目内置的最小固件集
sudo mkdir -p $ROOTFS_DIR/lib/firmware
sudo cp -r $FW_REPO/. $ROOTFS_DIR/lib/firmware/

# 安装项目内的设备专属脚本与服务
sudo mkdir -p $ROOTFS_DIR/usr/local/bin
sudo mkdir -p $ROOTFS_DIR/etc/systemd/system
sudo mkdir -p $ROOTFS_DIR/usr/share/alsa/ucm2/Qualcomm/sc8280xp

sudo cp $GAOKUN_DIR/tools/touchpad/huawei-tp-activate.py \
    $ROOTFS_DIR/usr/local/bin/
sudo cp $GAOKUN_DIR/tools/touchpad/huawei-touchpad.service \
    $ROOTFS_DIR/etc/systemd/system/
sudo chmod +x $ROOTFS_DIR/usr/local/bin/huawei-tp-activate.py

sudo cp $GAOKUN_DIR/tools/monitors/gdm-monitor-sync \
    $ROOTFS_DIR/usr/local/bin/
sudo cp $GAOKUN_DIR/tools/monitors/gdm-monitor-sync.service \
    $ROOTFS_DIR/etc/systemd/system/
sudo chmod +x $ROOTFS_DIR/usr/local/bin/gdm-monitor-sync

sudo cp $GAOKUN_DIR/tools/bluetooth/patch-nvm-bdaddr.py \
    $ROOTFS_DIR/usr/local/bin/
sudo chmod +x $ROOTFS_DIR/usr/local/bin/patch-nvm-bdaddr.py

sudo cp $GAOKUN_DIR/tools/audio/sc8280xp.conf \
    $ROOTFS_DIR/usr/share/alsa/ucm2/Qualcomm/sc8280xp/
```

卸载之前的虚拟文件系统：

```bash
sudo umount $ROOTFS_DIR/dev/pts
sudo umount $ROOTFS_DIR/dev
sudo umount $ROOTFS_DIR/proc
sudo umount $ROOTFS_DIR/sys
sudo umount $ROOTFS_DIR/run
```

---

## 第四步：制作可启动镜像

### 1. 创建镜像和分区

```bash
cd $WORKDIR
truncate -s 12G $IMAGE_FILE

parted -s $IMAGE_FILE mklabel gpt
parted -s $IMAGE_FILE mkpart EFI fat32 1MiB 256MiB
parted -s $IMAGE_FILE set 1 esp on
parted -s $IMAGE_FILE mkpart rootfs ext4 256MiB 100%

LOOP=$(sudo losetup --show -fP $IMAGE_FILE)
sudo mkfs.vfat -F32 -n EFI ${LOOP}p1
sudo mkfs.ext4 -L rootfs ${LOOP}p2

EFI_UUID=$(sudo blkid -s UUID -o value ${LOOP}p1)
ROOT_UUID=$(sudo blkid -s UUID -o value ${LOOP}p2)
```

### 2. 同步 RootFS 到镜像

```bash
MNT=/mnt/ego-ubuntu

sudo mkdir -p $MNT
sudo mount ${LOOP}p2 $MNT
sudo mkdir -p $MNT/boot/efi
sudo mount ${LOOP}p1 $MNT/boot/efi

sudo rsync -aHAX --info=progress2 --exclude='/proc/*' --exclude='/sys/*' --exclude='/dev/*' --exclude='/run/*' $ROOTFS_DIR/ $MNT/

sudo tee $MNT/etc/fstab > /dev/null <<EOF
UUID=${ROOT_UUID}  /         ext4   errors=remount-ro,noatime  0  1
UUID=${EFI_UUID}   /boot/efi vfat   defaults,nofail,x-systemd.device-timeout=10s  0  2
EOF
```

### 3. chroot 初始化并生成 GRUB

```bash
cleanup_mounts() {
    sudo umount $MNT/dev/pts 2>/dev/null || true
    sudo umount $MNT/boot/efi 2>/dev/null || true
    sudo umount $MNT/dev 2>/dev/null || true
    sudo umount $MNT/proc 2>/dev/null || true
    sudo umount $MNT/sys 2>/dev/null || true
    sudo umount $MNT/run 2>/dev/null || true
    sudo umount $MNT 2>/dev/null || true
}
trap cleanup_mounts EXIT

sudo mount --bind /dev $MNT/dev
sudo mount --bind /dev/pts $MNT/dev/pts
sudo mount -t proc proc $MNT/proc
sudo mount -t sysfs sys $MNT/sys
sudo mount -t tmpfs tmpfs $MNT/run

sudo chroot $MNT /bin/bash
```

在 chroot 中执行：

```bash
KREL="$(ls /lib/modules/ | head -n1)"

# 创建默认用户与主机名
echo "ubuntu" > /etc/hostname
useradd -m -s /bin/bash -G sudo user
echo "user:user" | chpasswd
mkdir -p /etc/sudoers.d
echo "%sudo ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/sudo-nopasswd
chmod 440 /etc/sudoers.d/sudo-nopasswd
cat > /etc/default/locale <<EOF
LANG=zh_CN.UTF-8
LC_MESSAGES=zh_CN.UTF-8
EOF

mkdir -p /var/lib/AccountsService/users
cat > /var/lib/AccountsService/users/user <<EOF
[User]
Language=zh_CN.UTF-8
EOF
cat > /var/lib/AccountsService/users/gdm <<EOF
[User]
Language=zh_CN.UTF-8
SystemAccount=true
EOF

# 预置屏幕方向与缩放，并同步给 GDM 登录界面
mkdir -p /home/user/.config
cat > /home/user/.config/monitors.xml <<EOF
<monitors version="2">
    <configuration>
        <layoutmode>logical</layoutmode>
        <logicalmonitor>
            <x>0</x>
            <y>0</y>
            <scale>1.6666666269302368</scale>
            <primary>yes</primary>
            <transform>
                <rotation>right</rotation>
                <flipped>no</flipped>
            </transform>
            <monitor>
                <monitorspec>
                    <connector>DSI-1</connector>
                    <vendor>unknown</vendor>
                    <product>unknown</product>
                    <serial>unknown</serial>
                </monitorspec>
                <mode>
                    <width>1600</width>
                    <height>2560</height>
                    <rate>60.000</rate>
                </mode>
            </monitor>
        </logicalmonitor>
    </configuration>
</monitors>
EOF
chown user:user /home/user/.config/monitors.xml

# 开启图形、网络、SSH、触控板和首启显示同步服务
systemctl enable gdm NetworkManager ssh huawei-touchpad.service \
    gdm-monitor-sync.service

# 运行时与 initramfs 都需要的关键模块
mkdir -p /etc/modules-load.d
echo -e "pci-pwrctrl-pwrseq\nath11k_pci" > /etc/modules-load.d/wifi.conf
echo "btqca" > /etc/modules-load.d/bluetooth.conf
echo -e "panel-himax-hx83121a\nhimax_hx83121a_spi\nmsm\nhid_multitouch" > /etc/modules-load.d/display.conf
echo -e "lpasscc_sc8280xp\nsnd-soc-sc8280xp" > /etc/modules-load.d/audio.conf
echo -e "huawei-gaokun-ec\nhuawei-gaokun-battery\nucsi_huawei_gaokun" > /etc/modules-load.d/battery.conf

mkdir -p /etc/modprobe.d
echo "softdep pinctrl_sc8280xp_lpass_lpi pre: lpasscc_sc8280xp" > /etc/modprobe.d/audio-deps.conf

# Ubuntu 使用 initramfs-tools 生成 initramfs
# 将关键模块写入 /etc/initramfs-tools/modules
cat >> /etc/initramfs-tools/modules <<MODEOF
# Storage and USB
nvme
phy-qcom-qmp-pcie
phy-qcom-qmp-combo
phy-qcom-qmp-usb
phy-qcom-snps-femto-v2
usb-storage
uas
typec
# WiFi
pci-pwrctrl-pwrseq
ath11k
ath11k_pci
# Input
i2c-hid-of
# Audio
lpasscc_sc8280xp
snd-soc-sc8280xp
pinctrl_sc8280xp_lpass_lpi
MODEOF

update-initramfs -c -k $KREL

# 配置 GRUB
cat > /etc/default/grub <<GRUBEOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Ubuntu"
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX="clk_ignore_unused pd_ignore_unused arm64.nopauth iommu.passthrough=0 iommu.strict=0 pcie_aspm.policy=powersupersave modprobe.blacklist=simpledrm efi=noruntime fbcon=rotate:1 usbhid.quirks=0x12d1:0x10b8:0x20000000 consoleblank=0 loglevel=4 psi=1"
GRUB_DTB="qcom/sc8280xp-huawei-gaokun3.dtb"
GRUBEOF

echo 'GRUB_DISABLE_OS_PROBER=true' >> /etc/default/grub
grub-install --target=arm64-efi --efi-directory=/boot/efi --boot-directory=/boot --removable --force
update-grub
sed -i '/^GRUB_DISABLE_OS_PROBER=true$/d' /etc/default/grub

# 给 EFI 分区写一个桥接 grub.cfg，按 rootfs UUID 找到真正菜单
ROOT_UUID="$(blkid -s UUID -o value /dev/disk/by-label/rootfs)"
mkdir -p /boot/efi/EFI/BOOT /boot/efi/EFI/ubuntu
cat > /boot/efi/EFI/BOOT/grub.cfg <<EOF
search --no-floppy --fs-uuid --set=root ${ROOT_UUID}
if [ -f (\$root)/boot/grub/grub.cfg ]; then
    set prefix=(\$root)/boot/grub
    configfile (\$root)/boot/grub/grub.cfg
else
    echo "ERROR: grub.cfg not found on rootfs UUID ${ROOT_UUID}"
    sleep 5
fi
EOF
cp /boot/efi/EFI/BOOT/grub.cfg /boot/efi/EFI/ubuntu/grub.cfg

# 可选：确认最终 grub.cfg 中已经带上 devicetree
grep -n "devicetree\|dtb" /boot/grub/grub.cfg
exit
```

回到宿主机后清理挂载：

```bash
trap - EXIT
cleanup_mounts
sudo losetup -d $LOOP
```

---

## 第五步：刷写镜像

镜像生成后位于：

```bash
$WORKDIR/ubuntu-26.04-gaokun3.img
```

推荐先刷入 USB 存储：

```bash
sudo dd if=$IMAGE_FILE of=/dev/sdX bs=4M status=progress conv=fsync
```

也可以使用 `balenaEtcher`、`Rufus`、`gnome-disks` 等图形工具。

刷入后开机按 `F12`，在 UEFI 启动菜单里选择对应的 USB 引导项启动。

如果要写入机器内置 NVMe，还需要额外分区、复制系统并调整 EFI 引导项，不建议把上面的 `dd` 目标直接替换成内置盘设备名后盲刷。

---

## 额外说明

- 编译完成后可用 `grep CONFIG_TOUCHSCREEN_HIMAX_HX83121A_SPI $KERN_OUT/.config` 确认 SPI 触摸驱动已进入当前内核配置
- 首次启动后如需扩容 ext4，可使用 `gnome-disks`，或执行 `sudo resize2fs /dev/nvme0n1p2`
- 文中所有 `tools/` 与 firmware 都来自当前仓库，不依赖外部设备专属仓库
- 如果你需要自动化构建，可直接参考 GitHub Actions workflow：`.github/workflows/ubuntu-gaokun3-release.yml`
- 如果 GDM 登录界面的方向、主屏或外接显示器布局不对，先在用户会话里调好显示设置，再把 `~/.config/monitors.xml` 复制到 `/var/lib/gdm3/.config/monitors.xml`，并执行 `chown gdm:gdm /var/lib/gdm3/.config/monitors.xml`
