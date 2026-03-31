#!/usr/bin/env bash
set -euo pipefail

: "${WORKDIR:?missing WORKDIR}"
: "${ROOTFS_DIR:?missing ROOTFS_DIR}"
: "${ARTIFACT_DIR:?missing ARTIFACT_DIR}"
: "${IMAGE_FILE:?missing IMAGE_FILE}"
: "${IMAGE_SIZE:?missing IMAGE_SIZE}"

KREL="$(cat "$WORKDIR/kernel-release.txt")"

truncate -s "$IMAGE_SIZE" "$IMAGE_FILE"
parted -s "$IMAGE_FILE" mklabel gpt
parted -s "$IMAGE_FILE" mkpart EFI fat32 1MiB 256MiB
parted -s "$IMAGE_FILE" set 1 esp on
parted -s "$IMAGE_FILE" mkpart rootfs ext4 256MiB 100%

LOOP="$(sudo losetup --show -fP "$IMAGE_FILE")"
sudo mkfs.vfat -F32 -n EFI "${LOOP}p1"
sudo mkfs.ext4 -L rootfs "${LOOP}p2"

EFI_UUID="$(sudo blkid -s UUID -o value "${LOOP}p1")"
ROOT_UUID="$(sudo blkid -s UUID -o value "${LOOP}p2")"

MNT=/mnt/ego-ubuntu
cleanup() {
  set +e
  sudo umount "$MNT/dev/pts" 2>/dev/null || true
  sudo umount "$MNT/boot/efi" 2>/dev/null || true
  sudo umount "$MNT/dev" 2>/dev/null || true
  sudo umount "$MNT/proc" 2>/dev/null || true
  sudo umount "$MNT/sys" 2>/dev/null || true
  sudo umount "$MNT/run" 2>/dev/null || true
  sudo umount "$MNT" 2>/dev/null || true
  sudo losetup -d "$LOOP" 2>/dev/null || true
}
trap cleanup EXIT

sudo mkdir -p "$MNT"
sudo mount "${LOOP}p2" "$MNT"
sudo mkdir -p "$MNT/boot/efi"
sudo mount "${LOOP}p1" "$MNT/boot/efi"

sudo rsync -aHAX --exclude='/proc/*' --exclude='/sys/*' --exclude='/dev/*' --exclude='/run/*' "$ROOTFS_DIR/" "$MNT/"

sudo tee "$MNT/etc/fstab" >/dev/null <<EOF
UUID=${ROOT_UUID}  /         ext4   errors=remount-ro,noatime  0  1
UUID=${EFI_UUID}   /boot/efi vfat   defaults,nofail,x-systemd.device-timeout=10s  0  2
EOF

sudo mount --bind /dev "$MNT/dev"
sudo mount --bind /dev/pts "$MNT/dev/pts"
sudo mount -t proc proc "$MNT/proc"
sudo mount -t sysfs sys "$MNT/sys"
sudo mount -t tmpfs tmpfs "$MNT/run"

sudo chroot "$MNT" /usr/bin/env KREL="$KREL" /bin/bash -euxo pipefail <<'CHROOT_EOF'
echo "ubuntu" > /etc/hostname
id -u user >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo user
echo "user:user" | chpasswd
mkdir -p /etc/sudoers.d
echo "%sudo ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/sudo-nopasswd
chmod 440 /etc/sudoers.d/sudo-nopasswd
cat > /etc/default/locale <<'EOF'
LANG=zh_CN.UTF-8
LANGUAGE=zh_CN:en_US:en
LC_MESSAGES=zh_CN.UTF-8
EOF

rm -f /etc/resolv.conf
ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

mkdir -p /var/lib/AccountsService/users
cat > /var/lib/AccountsService/users/user <<'EOF'
[User]
Language=zh_CN.UTF-8
EOF
cat > /var/lib/AccountsService/users/gdm <<'EOF'
[User]
Language=zh_CN.UTF-8
SystemAccount=true
EOF

mkdir -p /home/user/.config
cat > /home/user/.config/monitors.xml <<'EOF'
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
chown -R user:user /home/user

install -d -m 1777 -o root -g root /tmp/.X11-unix

cat > /etc/systemd/system/gaokun-fix-x11-unix.service <<'EOF'
[Unit]
Description=Fix /tmp/.X11-unix ownership for Xwayland
After=gdm.service
Wants=gdm.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'mkdir -p /tmp/.X11-unix && chown root:root /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix'

[Install]
WantedBy=graphical.target
EOF

systemctl enable gdm NetworkManager ssh huawei-touchpad.service \
  gaokun-fix-x11-unix.service gdm-monitor-sync.service || true

mkdir -p /etc/modules-load.d
echo -e "pci-pwrctrl-pwrseq\nath11k_pci" > /etc/modules-load.d/wifi.conf
echo "btqca" > /etc/modules-load.d/bluetooth.conf
echo -e "panel-himax-hx83121a\nhimax_hx83121a_spi\nmsm\nhid_multitouch" > /etc/modules-load.d/display.conf
echo -e "lpasscc_sc8280xp\nsnd-soc-sc8280xp" > /etc/modules-load.d/audio.conf
echo -e "huawei-gaokun-ec\nhuawei-gaokun-battery\nucsi_huawei_gaokun" > /etc/modules-load.d/battery.conf

mkdir -p /etc/modprobe.d
echo "softdep pinctrl_sc8280xp_lpass_lpi pre: lpasscc_sc8280xp" > /etc/modprobe.d/audio-deps.conf

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

update-initramfs -c -k "$KREL"

# Ubuntu GRUB's 10_linux looks for /boot/dtb-$KREL
cp "/usr/lib/linux-image-$KREL/qcom/sc8280xp-huawei-gaokun3.dtb" "/boot/dtb-$KREL"

# EL2 DTB is expected in build artifacts; copy it unconditionally.
cp "/usr/lib/linux-image-$KREL/qcom/sc8280xp-huawei-gaokun3-el2.dtb" "/boot/dtb-el2-$KREL"

ROOT_UUID="$(blkid -s UUID -o value /dev/disk/by-label/rootfs)"
mkdir -p /boot/efi/EFI/BOOT /boot/efi/EFI/ubuntu
cat > /etc/default/grub <<'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Ubuntu"
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX="clk_ignore_unused pd_ignore_unused arm64.nopauth iommu.passthrough=0 iommu.strict=0 pcie_aspm.policy=powersupersave modprobe.blacklist=simpledrm efi=noruntime fbcon=rotate:1 usbhid.quirks=0x12d1:0x10b8:0x20000000 consoleblank=0 loglevel=4 psi=1"
GRUB_DISABLE_OS_PROBER=true
GRUB_DISABLE_SUBMENU=false
GRUB_DISABLE_LINUX_UUID=false
GRUB_TERMINAL_OUTPUT=gfxterm
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_RECORDFAIL_TIMEOUT=5
EOF

cat > /tmp/early-grub.cfg <<EOF
search --no-floppy --fs-uuid --set=root ${ROOT_UUID}
set prefix=(\$root)/boot/grub
EOF

grub-mkimage -c /tmp/early-grub.cfg \
    -o /boot/efi/EFI/BOOT/BOOTAA64.EFI \
    -O arm64-efi -p /boot/grub \
    part_gpt ext2 fat search search_fs_uuid search_label normal linux \
    configfile reboot echo test extcmd efifwsetup

rm -f /tmp/early-grub.cfg

cat > /etc/grub.d/11_gaokun_el2 <<SCRIPTEOF
#!/bin/sh
exec tail -n +3 \$0

menuentry 'Ubuntu ${KREL} (EL2 Hypervisor)' --class ubuntu --class gnu-linux --class gnu --class os {
        search --no-floppy --fs-uuid --set=root ${ROOT_UUID}
        linux   /boot/vmlinuz-${KREL} root=UUID=${ROOT_UUID} clk_ignore_unused pd_ignore_unused arm64.nopauth iommu.passthrough=0 iommu.strict=0 pcie_aspm.policy=powersupersave modprobe.blacklist=simpledrm efi=noruntime fbcon=rotate:1 usbhid.quirks=0x12d1:0x10b8:0x20000000 consoleblank=0 loglevel=4 psi=1
        initrd  /boot/initrd.img-${KREL}
        devicetree /boot/dtb-el2-${KREL}
}
SCRIPTEOF
chmod +x /etc/grub.d/11_gaokun_el2

update-grub

mkdir -p /boot/grub/arm64-efi
cp -a /usr/lib/grub/arm64-efi/. /boot/grub/arm64-efi/
sed -i 's/^GRUB_DISABLE_OS_PROBER=true$/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub

cat > /boot/efi/EFI/BOOT/grub.cfg <<EOF
search --no-floppy --fs-uuid --set=root ${ROOT_UUID}
set prefix=(\$root)/boot/grub
configfile (\$root)/boot/grub/grub.cfg
EOF
cp /boot/efi/EFI/BOOT/BOOTAA64.EFI /boot/efi/EFI/ubuntu/grubaa64.efi
cp /boot/efi/EFI/BOOT/grub.cfg /boot/efi/EFI/ubuntu/grub.cfg

# Validate GRUB generated correctly
grep -n "devicetree\|dtb" /boot/grub/grub.cfg || true
CHROOT_EOF

sync

trap - EXIT
cleanup
