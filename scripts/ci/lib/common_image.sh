#!/usr/bin/env bash
set -euo pipefail

install_common_image_assets() {
  local rootfs_dir="$1"
  local gaokun_dir="$2"
  local executable_assets=(
    "tools/bluetooth/patch-nvm-bdaddr.py:/usr/local/bin/patch-nvm-bdaddr.py"
    "tools/wifi/set-stable-wifi-mac.py:/usr/local/bin/set-stable-wifi-mac.py"
    "tools/monitors/gdm-monitor-sync:/usr/local/bin/gdm-monitor-sync"
    "tools/touchscreen-tuner/touchscreen-tune:/usr/local/bin/touchscreen-tune"
    "tools/touchpad/huawei-tp-activate.py:/usr/local/bin/huawei-tp-activate.py"
  )
  local service_assets=(
    "tools/bluetooth/patch-nvm-bdaddr.service:/etc/systemd/system/patch-nvm-bdaddr.service"
    "tools/wifi/gaokun-wifi-mac@.service:/etc/systemd/system/gaokun-wifi-mac@.service"
    "tools/monitors/gdm-monitor-sync.service:/etc/systemd/system/gdm-monitor-sync.service"
    "tools/touchpad/huawei-touchpad.service:/etc/systemd/system/huawei-touchpad.service"
  )
  local data_assets=(
    "tools/audio/sc8280xp.conf:/usr/share/alsa/ucm2/Qualcomm/sc8280xp/sc8280xp.conf"
    "tools/wifi/80-gaokun-wifi-mac.rules:/etc/udev/rules.d/80-gaokun-wifi-mac.rules"
    "tools/touchscreen-tuner/tune.py:/usr/local/lib/gaokun-touchscreen-tuner/tune.py"
    "tools/touchscreen-tuner/tune-icon.svg:/usr/local/lib/gaokun-touchscreen-tuner/tune-icon.svg"
    "tools/touchscreen-tuner/touchscreen-tune.desktop:/usr/share/applications/touchscreen-tune.desktop"
    "tools/image-assets/usr/local/share/gaokun/monitors.xml:/usr/local/share/gaokun/monitors.xml"
  )
  local asset src dest

  sudo mkdir -p \
    "$rootfs_dir/etc/modules-load.d" \
    "$rootfs_dir/etc/modprobe.d" \
    "$rootfs_dir/etc/udev/rules.d" \
    "$rootfs_dir/etc/systemd/system" \
    "$rootfs_dir/etc/gaokun" \
    "$rootfs_dir/usr/local/bin" \
    "$rootfs_dir/usr/local/lib/gaokun-touchscreen-tuner" \
    "$rootfs_dir/usr/share/alsa/ucm2/Qualcomm/sc8280xp" \
    "$rootfs_dir/usr/share/applications" \
    "$rootfs_dir/usr/local/share/gaokun"

  sudo cp -a "$gaokun_dir/tools/image-assets/etc/modules-load.d/." \
    "$rootfs_dir/etc/modules-load.d/"
  sudo cp -a "$gaokun_dir/tools/image-assets/etc/modprobe.d/." \
    "$rootfs_dir/etc/modprobe.d/"

  for asset in "${executable_assets[@]}"; do
    src="${asset%%:*}"
    dest="${asset#*:}"
    sudo install -Dm755 "$gaokun_dir/$src" "$rootfs_dir$dest"
  done

  for asset in "${service_assets[@]}"; do
    src="${asset%%:*}"
    dest="${asset#*:}"
    sudo install -Dm644 "$gaokun_dir/$src" "$rootfs_dir$dest"
  done

  for asset in "${data_assets[@]}"; do
    src="${asset%%:*}"
    dest="${asset#*:}"
    sudo install -Dm644 "$gaokun_dir/$src" "$rootfs_dir$dest"
  done
}

install_el2_efi_payloads() {
  local rootfs_dir="$1"
  local gaokun_dir="$2"

  sudo install -d \
    "$rootfs_dir/boot/efi/EFI/systemd/drivers" \
    "$rootfs_dir/boot/efi/firmware"

  sudo install -Dm644 "$gaokun_dir/tools/el2/slbounceaa64.efi" \
    "$rootfs_dir/boot/efi/EFI/systemd/drivers/slbounceaa64.efi"
  sudo install -Dm644 "$gaokun_dir/tools/el2/qebspilaa64.efi" \
    "$rootfs_dir/boot/efi/EFI/systemd/drivers/qebspilaa64.efi"
  sudo install -Dm644 "$gaokun_dir/tools/el2/tcblaunch.exe" \
    "$rootfs_dir/boot/efi/tcblaunch.exe"
  sudo install -Dm644 "$rootfs_dir/lib/firmware/qcom/sc8280xp/HUAWEI/gaokun3/qcadsp8280.mbn" \
    "$rootfs_dir/boot/efi/firmware/qcom/sc8280xp/HUAWEI/gaokun3/qcadsp8280.mbn"
  sudo install -Dm644 "$rootfs_dir/lib/firmware/qcom/sc8280xp/HUAWEI/gaokun3/qccdsp8280.mbn" \
    "$rootfs_dir/boot/efi/firmware/qcom/sc8280xp/HUAWEI/gaokun3/qccdsp8280.mbn"
  sudo install -Dm644 "$rootfs_dir/lib/firmware/qcom/sc8280xp/HUAWEI/gaokun3/qcslpi8280.mbn" \
    "$rootfs_dir/boot/efi/firmware/qcom/sc8280xp/HUAWEI/gaokun3/qcslpi8280.mbn"
}
