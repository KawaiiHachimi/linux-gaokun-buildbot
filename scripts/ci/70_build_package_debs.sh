#!/usr/bin/env bash
set -euo pipefail

: "${GAOKUN_DIR:?missing GAOKUN_DIR}"
: "${WORKDIR:?missing WORKDIR}"
: "${KERN_SRC:?missing KERN_SRC}"
: "${KERN_OUT:?missing KERN_OUT}"
: "${ARTIFACT_DIR:?missing ARTIFACT_DIR}"
: "${KERNEL_TAG:?missing KERNEL_TAG}"
: "${PACKAGE_RELEASE_TAG:?missing PACKAGE_RELEASE_TAG}"

KREL="$(cat "$WORKDIR/kernel-release.txt")"
DEB_TOPDIR="$WORKDIR/debbuild"
BUILDROOT_DIR="$WORKDIR/package-buildroots"
IMAGE_STAGE="$BUILDROOT_DIR/linux-image-gaokun3"
MODULES_STAGE="$BUILDROOT_DIR/linux-modules-gaokun3"
MODULES_RAW_STAGE="$BUILDROOT_DIR/linux-modules-raw"
HEADERS_STAGE="$BUILDROOT_DIR/linux-headers-gaokun3"
HEADERS_TREE="$HEADERS_STAGE/usr/src/linux-headers-$KREL"
FIRMWARE_STAGE="$BUILDROOT_DIR/linux-firmware-gaokun3"
DEB_VERSION="${KREL//-/\~}-1"
DEB_ARCH="arm64"

mkdir -p "$ARTIFACT_DIR" "$DEB_TOPDIR"

# ---------------------------------------------------------------------------
# Stage helpers
# ---------------------------------------------------------------------------

prepare_image_package() {
  rm -rf "$IMAGE_STAGE"
  # Ubuntu style: vmlinuz in /boot, dtb in /usr/lib/linux-image-$KREL
  mkdir -p "$IMAGE_STAGE/boot"
  mkdir -p "$IMAGE_STAGE/usr/lib/linux-image-$KREL/qcom"

  install -Dm644 "$KERN_OUT/arch/arm64/boot/Image" \
    "$IMAGE_STAGE/boot/vmlinuz-$KREL"
  install -Dm644 "$KERN_OUT/System.map" \
    "$IMAGE_STAGE/boot/System.map-$KREL"
  install -Dm644 "$KERN_OUT/.config" \
    "$IMAGE_STAGE/boot/config-$KREL"
  install -Dm644 "$KERN_OUT/arch/arm64/boot/dts/qcom/sc8280xp-huawei-gaokun3.dtb" \
    "$IMAGE_STAGE/usr/lib/linux-image-$KREL/qcom/sc8280xp-huawei-gaokun3.dtb"
  install -Dm644 "$KERN_OUT/arch/arm64/boot/dts/qcom/sc8280xp-huawei-gaokun3-el2.dtb" \
    "$IMAGE_STAGE/usr/lib/linux-image-$KREL/qcom/sc8280xp-huawei-gaokun3-el2.dtb"
}

prepare_modules_package() {
  rm -rf "$MODULES_STAGE" "$MODULES_RAW_STAGE"
  mkdir -p "$MODULES_STAGE/lib"

  make -C "$KERN_SRC" O="$KERN_OUT" ARCH=arm64 INSTALL_MOD_PATH="$MODULES_RAW_STAGE" modules_install
  mv "$MODULES_RAW_STAGE/lib/modules" "$MODULES_STAGE/lib/"
  rm -rf "$MODULES_RAW_STAGE"
  rm -f "$MODULES_STAGE/lib/modules/$KREL/build" \
        "$MODULES_STAGE/lib/modules/$KREL/source"
  depmod -b "$MODULES_STAGE" -a "$KREL"
}

prepare_headers_package() {
  rm -rf "$HEADERS_STAGE"
  mkdir -p "$HEADERS_TREE" "$HEADERS_STAGE/lib/modules/$KREL"

  rsync -a --delete --exclude '.git' "$KERN_SRC/" "$HEADERS_TREE/"
  rsync -a "$KERN_OUT/" "$HEADERS_TREE/"

  find "$HEADERS_TREE" -type f \
    \( -name '*.o' -o -name '*.ko' -o -name '*.a' -o -name '*.cmd' -o -name '*.mod' -o -name '*.mod.c' \) \
    -delete
  find "$HEADERS_TREE" -type l \( -name build -o -name source \) -delete

  ln -s "../../../src/linux-headers-$KREL" "$HEADERS_STAGE/lib/modules/$KREL/build"
  ln -s "../../../src/linux-headers-$KREL" "$HEADERS_STAGE/lib/modules/$KREL/source"
}

prepare_firmware_package() {
  rm -rf "$FIRMWARE_STAGE"
  mkdir -p "$FIRMWARE_STAGE/lib/firmware"
  cp -a "$GAOKUN_DIR/firmware/." "$FIRMWARE_STAGE/lib/firmware/"
  rm -f "$FIRMWARE_STAGE/lib/firmware/"*.spec.in
}

# ---------------------------------------------------------------------------
# Build a simple .deb from a staged directory tree
# ---------------------------------------------------------------------------

build_deb() {
  local pkg_name="$1"
  local stage_dir="$2"
  local description="$3"
  local depends="${4:-}"
  local arch="${5:-$DEB_ARCH}"
  local postinst="${6:-}"

  local deb_dir="$stage_dir/DEBIAN"
  mkdir -p "$deb_dir"

  cat > "$deb_dir/control" <<EOF
Package: ${pkg_name}
Version: ${DEB_VERSION}
Architecture: ${arch}
Maintainer: cool <bilibili@att.net>
Description: ${description}
EOF

  if [[ -n "$depends" ]]; then
    echo "Depends: ${depends}" >> "$deb_dir/control"
  fi

  if [[ -n "$postinst" ]]; then
    cat > "$deb_dir/postinst" <<POSTEOF
#!/bin/bash
set -e
${postinst}
POSTEOF
    chmod 755 "$deb_dir/postinst"
  fi

  dpkg-deb --build --root-owner-group "$stage_dir" "$DEB_TOPDIR/${pkg_name}_${DEB_VERSION}_${arch}.deb"
}

# ---------------------------------------------------------------------------
# Stage all packages
# ---------------------------------------------------------------------------

prepare_image_package
prepare_modules_package
prepare_headers_package
prepare_firmware_package

# ---------------------------------------------------------------------------
# Build DEBs
# ---------------------------------------------------------------------------

build_deb "linux-image-gaokun3" "$IMAGE_STAGE" \
  "Linux kernel image for gaokun3 ($KREL)" \
  "" "$DEB_ARCH" \
  "update-initramfs -c -k $KREL 2>/dev/null || true"

build_deb "linux-modules-gaokun3" "$MODULES_STAGE" \
  "Linux kernel modules for gaokun3 ($KREL)" \
  "linux-image-gaokun3 (= $DEB_VERSION)" "$DEB_ARCH" \
  "depmod -a $KREL 2>/dev/null || true"

build_deb "linux-headers-gaokun3" "$HEADERS_STAGE" \
  "Linux kernel headers for gaokun3 ($KREL)" \
  "linux-modules-gaokun3 (= $DEB_VERSION)" "$DEB_ARCH"

build_deb "linux-firmware-gaokun3" "$FIRMWARE_STAGE" \
  "Firmware bundle for Huawei MateBook E Go 2023 (gaokun3)" \
  "" "all"

# ---------------------------------------------------------------------------
# Collect artifacts
# ---------------------------------------------------------------------------

image_deb="linux-image-gaokun3_${DEB_VERSION}_${DEB_ARCH}.deb"
modules_deb="linux-modules-gaokun3_${DEB_VERSION}_${DEB_ARCH}.deb"
headers_deb="linux-headers-gaokun3_${DEB_VERSION}_${DEB_ARCH}.deb"
firmware_deb="linux-firmware-gaokun3_${DEB_VERSION}_all.deb"

cp "$DEB_TOPDIR/$image_deb" "$ARTIFACT_DIR/"
cp "$DEB_TOPDIR/$modules_deb" "$ARTIFACT_DIR/"
cp "$DEB_TOPDIR/$headers_deb" "$ARTIFACT_DIR/"
cp "$DEB_TOPDIR/$firmware_deb" "$ARTIFACT_DIR/"

cat >"$ARTIFACT_DIR/package-manifest.json" <<EOF
{
  "package_release_tag": "${PACKAGE_RELEASE_TAG}",
  "kernel_tag": "${KERNEL_TAG}",
  "kernel_release": "${KREL}",
  "built_at_utc": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "packages": {
    "image": "${image_deb}",
    "modules": "${modules_deb}",
    "headers": "${headers_deb}",
    "firmware": "${firmware_deb}"
  }
}
EOF

cat >"$ARTIFACT_DIR/package-release-body.md" <<EOF
## Package Bundle

- Package Tag: \`${PACKAGE_RELEASE_TAG}\`
- Kernel Tag: \`${KERNEL_TAG}\`
- Kernel Release: \`${KREL}\`
- Architecture: \`${DEB_ARCH}\`
- Build Time (UTC): \`$(date -u +"%Y-%m-%dT%H:%M:%SZ")\`

## Included DEBs

- \`${image_deb}\`
- \`${modules_deb}\`
- \`${headers_deb}\`
- \`${firmware_deb}\`
EOF
