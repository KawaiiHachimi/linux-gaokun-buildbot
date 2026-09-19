#!/usr/bin/env bash
set -euo pipefail

: "${GAOKUN_DIR:?missing GAOKUN_DIR}"
: "${WORKDIR:?missing WORKDIR}"
: "${ARTIFACT_DIR:?missing ARTIFACT_DIR}"
: "${KERNEL_TAG:?missing KERNEL_TAG}"
: "${KERNEL_COMMIT:?missing KERNEL_COMMIT}"
: "${PACKAGE_RELEASE_TAG:?missing PACKAGE_RELEASE_TAG}"

BUILD_EL2="${BUILD_EL2:-false}"
BUILDBOT_COMMIT="${BUILDBOT_COMMIT:-$(git -C "$GAOKUN_DIR" rev-parse HEAD)}"
KERN_SRC_BASE="${KERN_SRC_BASE:-${KERN_SRC:-}}"
KERN_OUT="${KERN_OUT:-}"
KERN_SRC_EL2="${KERN_SRC_EL2:-${KERN_SRC:-}}"
KERN_OUT_EL2="${KERN_OUT_EL2:-}"

: "${KERN_SRC_BASE:?missing KERN_SRC_BASE}"
: "${KERN_OUT:?missing KERN_OUT}"

BASE_KREL="$(cat "$WORKDIR/kernel-release.txt")"
EL2_KREL=""
if [[ -f "$WORKDIR/kernel-release-el2.txt" ]]; then
  EL2_KREL="$(cat "$WORKDIR/kernel-release-el2.txt")"
fi

DEB_TOPDIR="$WORKDIR/debbuild"
BUILDROOT_DIR="$WORKDIR/package-buildroots"
DEB_ARCH="arm64"
FIRMWARE_DEB_VERSION="${FIRMWARE_DEB_VERSION:-$(date -u +%Y%m%d)-1}"
BUILD_TIME_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

mkdir -p "$ARTIFACT_DIR" "$DEB_TOPDIR"

render_template_to_string() {
  local template_path="$1"
  shift

  local sed_args=()
  while [[ $# -gt 0 ]]; do
    sed_args+=(-e "s|$1|$2|g")
    shift 2
  done

  sed "${sed_args[@]}" "$template_path"
}

build_deb() {
  local template_root="$1"
  local pkg_name="$2"
  local stage_dir="$3"
  local version="$4"
  local description="$5"
  local depends="${6:-}"
  local arch="${7:-$DEB_ARCH}"
  local postinst="${8:-}"
  local postrm="${9:-}"

  local deb_dir="$stage_dir/DEBIAN"
  mkdir -p "$deb_dir"
  local depends_line=""
  if [[ -n "$depends" ]]; then
    depends_line="Depends: ${depends}"
  fi

  render_template_to_string \
    "$template_root/DEBIAN/control.in" \
    "@PKG_NAME@" "$pkg_name" \
    "@PKGVER@" "$version" \
    "@ARCH@" "$arch" \
    "@PKG_DESC@" "$description" \
    "@DEPENDS_LINE@" "$depends_line" >"$deb_dir/control"

  if [[ -n "$postinst" ]]; then
    cat > "$deb_dir/postinst" <<EOF
#!/bin/bash
set -e
${postinst}
EOF
    chmod 755 "$deb_dir/postinst"
  fi

  if [[ -n "$postrm" ]]; then
    cat > "$deb_dir/postrm" <<EOF
#!/bin/bash
set -e
${postrm}
EOF
    chmod 755 "$deb_dir/postrm"
  fi

  dpkg-deb --build --root-owner-group "$stage_dir" "$DEB_TOPDIR/${pkg_name}_${version}_${arch}.deb"
}

build_kernel_variant() {
  local variant_key="$1"
  local pkg_suffix="$2"
  local src_dir="$3"
  local out_dir="$4"
  local krel="$5"
  local dtb_name="$6"

  local deb_version="${krel//-/\~}-1"
  local image_pkg="linux-image-gaokun3${pkg_suffix}"
  local modules_pkg="linux-modules-gaokun3${pkg_suffix}"
  local headers_pkg="linux-headers-gaokun3${pkg_suffix}"
  local image_stage="$BUILDROOT_DIR/${image_pkg}"
  local modules_stage="$BUILDROOT_DIR/${modules_pkg}"
  local modules_raw_stage="$BUILDROOT_DIR/${modules_pkg}-raw"
  local headers_stage="$BUILDROOT_DIR/${headers_pkg}"
  local headers_tree="$headers_stage/usr/src/linux-headers-$krel"
  local postinst_script

  rm -rf "$image_stage" "$modules_stage" "$modules_raw_stage" "$headers_stage"
  mkdir -p "$image_stage/boot" "$image_stage/usr/lib/linux-image-$krel/qcom"
  mkdir -p "$modules_stage/lib" "$headers_tree" "$headers_stage/lib/modules/$krel"

  install -Dm644 "$out_dir/arch/arm64/boot/Image" \
    "$image_stage/boot/vmlinuz-$krel"
  install -Dm644 "$out_dir/System.map" \
    "$image_stage/boot/System.map-$krel"
  install -Dm644 "$out_dir/.config" \
    "$image_stage/boot/config-$krel"
  install -Dm644 "$out_dir/arch/arm64/boot/dts/qcom/$dtb_name" \
    "$image_stage/boot/dtb-$krel"
  install -Dm644 "$out_dir/arch/arm64/boot/dts/qcom/$dtb_name" \
    "$image_stage/usr/lib/linux-image-$krel/qcom/$dtb_name"

  make -C "$src_dir" O="$out_dir" ARCH=arm64 INSTALL_MOD_PATH="$modules_raw_stage" modules_install
  mv "$modules_raw_stage/lib/modules" "$modules_stage/lib/"
  rm -rf "$modules_raw_stage"
  rm -f "$modules_stage/lib/modules/$krel/build" \
        "$modules_stage/lib/modules/$krel/source"
  depmod -b "$modules_stage" -a "$krel"

  rsync -a --delete --exclude '.git' "$src_dir/" "$headers_tree/"
  rsync -a "$out_dir/" "$headers_tree/"
  find "$headers_tree" -type f \
    \( -name '*.o' -o -name '*.ko' -o -name '*.a' -o -name '*.cmd' -o -name '*.mod' -o -name '*.mod.c' \) \
    -delete
  find "$headers_tree" -type l \( -name build -o -name source \) -delete
  ln -s "../../../src/linux-headers-$krel" "$headers_stage/lib/modules/$krel/build"
  ln -s "../../../src/linux-headers-$krel" "$headers_stage/lib/modules/$krel/source"

  local image_description
  image_description="$(
    render_template_to_string \
      "$GAOKUN_DIR/packaging/deb/linux-image-gaokun3/descriptions/package.in" \
      "@PACKAGE_KIND@" "image" \
      "@KREL@" "$krel"
  )"
  postinst_script="$(
    render_template_to_string \
      "$GAOKUN_DIR/packaging/deb/linux-image-gaokun3/DEBIAN/postinst.in" \
      "@DTB_NAME@" "$dtb_name" \
      "@KREL@" "$krel"
  )"

  build_deb "$GAOKUN_DIR/packaging/deb/linux-image-gaokun3" \
    "$image_pkg" "$image_stage" "$deb_version" \
    "$image_description" \
    "linux-firmware-gaokun3" "$DEB_ARCH" \
    "$postinst_script"

  local modules_postinst
  modules_postinst="$(
    render_template_to_string \
      "$GAOKUN_DIR/packaging/deb/linux-modules-gaokun3/DEBIAN/postinst.in" \
      "@KREL@" "$krel"
  )"
  local modules_postrm
  modules_postrm="$(
    render_template_to_string \
      "$GAOKUN_DIR/packaging/deb/linux-modules-gaokun3/DEBIAN/postrm.in" \
      "@KREL@" "$krel"
  )"
  local modules_description
  modules_description="$(
    render_template_to_string \
      "$GAOKUN_DIR/packaging/deb/linux-modules-gaokun3/descriptions/package.in" \
      "@PACKAGE_KIND@" "modules" \
      "@KREL@" "$krel"
  )"

  build_deb "$GAOKUN_DIR/packaging/deb/linux-modules-gaokun3" \
    "$modules_pkg" "$modules_stage" "$deb_version" \
    "$modules_description" \
    "${image_pkg} (= $deb_version)" "$DEB_ARCH" \
    "$modules_postinst" \
    "$modules_postrm"

  local headers_description
  headers_description="$(
    render_template_to_string \
      "$GAOKUN_DIR/packaging/deb/linux-headers-gaokun3/descriptions/package.in" \
      "@PACKAGE_KIND@" "headers" \
      "@KREL@" "$krel"
  )"
  build_deb "$GAOKUN_DIR/packaging/deb/linux-headers-gaokun3" \
    "$headers_pkg" "$headers_stage" "$deb_version" \
    "$headers_description" \
    "${modules_pkg} (= $deb_version)" "$DEB_ARCH"

  local image_deb="${image_pkg}_${deb_version}_${DEB_ARCH}.deb"
  local modules_deb="${modules_pkg}_${deb_version}_${DEB_ARCH}.deb"
  local headers_deb="${headers_pkg}_${deb_version}_${DEB_ARCH}.deb"

  cp "$DEB_TOPDIR/$image_deb" "$ARTIFACT_DIR/"
  cp "$DEB_TOPDIR/$modules_deb" "$ARTIFACT_DIR/"
  cp "$DEB_TOPDIR/$headers_deb" "$ARTIFACT_DIR/"

  printf -v "KREL_${variant_key^^}" '%s' "$krel"
  printf -v "IMAGE_DEB_${variant_key^^}" '%s' "$image_deb"
  printf -v "MODULES_DEB_${variant_key^^}" '%s' "$modules_deb"
  printf -v "HEADERS_DEB_${variant_key^^}" '%s' "$headers_deb"
}

build_firmware_package() {
  local firmware_stage="$BUILDROOT_DIR/linux-firmware-gaokun3"
  local firmware_deb="linux-firmware-gaokun3_${FIRMWARE_DEB_VERSION}_all.deb"

  rm -rf "$firmware_stage"
  mkdir -p "$firmware_stage/lib/firmware" "$firmware_stage/etc/initramfs-tools/hooks"
  cp -a "$GAOKUN_DIR/firmware/." "$firmware_stage/lib/firmware/"
  cp "$GAOKUN_DIR/packaging/deb/linux-firmware-gaokun3/hooks/initramfs-hook.in" \
    "$firmware_stage/etc/initramfs-tools/hooks/gaokun3-firmware"
  chmod 0755 "$firmware_stage/etc/initramfs-tools/hooks/gaokun3-firmware"

  local firmware_description
  firmware_description="$(
    render_template_to_string \
      "$GAOKUN_DIR/packaging/deb/linux-firmware-gaokun3/descriptions/package.in"
  )"
  build_deb "$GAOKUN_DIR/packaging/deb/linux-firmware-gaokun3" \
    "linux-firmware-gaokun3" "$firmware_stage" "$FIRMWARE_DEB_VERSION" \
    "$firmware_description" "" "all"

  cp "$DEB_TOPDIR/$firmware_deb" "$ARTIFACT_DIR/"
  FIRMWARE_DEB="$firmware_deb"
}

build_kernel_variant "standard" "" "$KERN_SRC_BASE" "$KERN_OUT" "$BASE_KREL" \
  "sc8280xp-huawei-gaokun3.dtb"

if [[ "$BUILD_EL2" == "true" ]]; then
  : "${KERN_OUT_EL2:?missing KERN_OUT_EL2}"
  if [[ -z "$EL2_KREL" ]]; then
    echo "BUILD_EL2=true but kernel-release-el2.txt is missing" >&2
    exit 1
  fi

  build_kernel_variant "el2" "-el2" "$KERN_SRC_EL2" "$KERN_OUT_EL2" "$EL2_KREL" \
    "sc8280xp-huawei-gaokun3-el2.dtb"
fi

build_firmware_package

EL2_MANIFEST_BLOCK=""
EL2_RELEASE_BLOCK=""
if [[ "$BUILD_EL2" == "true" ]]; then
  EL2_MANIFEST_BLOCK="$(cat <<EOF
,
    "el2": {
      "release": "${KREL_EL2}",
      "packages": {
        "image": "${IMAGE_DEB_EL2}",
        "modules": "${MODULES_DEB_EL2}",
        "headers": "${HEADERS_DEB_EL2}"
      }
    }
EOF
)"
  EL2_RELEASE_BLOCK="$(cat <<EOF
- \`${IMAGE_DEB_EL2}\`
- \`${MODULES_DEB_EL2}\`
- \`${HEADERS_DEB_EL2}\`
EOF
)"
fi

cat >"$ARTIFACT_DIR/package-manifest.json" <<EOF
{
  "package_release_tag": "${PACKAGE_RELEASE_TAG}",
  "kernel_tag": "${KERNEL_TAG}",
  "kernel_commit": "${KERNEL_COMMIT:?missing KERNEL_COMMIT}",
  "buildbot_commit": "${BUILDBOT_COMMIT}",
  "build_el2": ${BUILD_EL2},
  "built_at_utc": "${BUILD_TIME_UTC}",
  "firmware_version": "${FIRMWARE_DEB_VERSION}",
  "kernels": {
    "standard": {
      "release": "${KREL_STANDARD}",
      "packages": {
        "image": "${IMAGE_DEB_STANDARD}",
        "modules": "${MODULES_DEB_STANDARD}",
        "headers": "${HEADERS_DEB_STANDARD}"
      }
    }${EL2_MANIFEST_BLOCK}
  },
  "packages": {
    "firmware": "${FIRMWARE_DEB}"
  }
}
EOF

cat >"$ARTIFACT_DIR/package-release-body.md" <<EOF
## Package Bundle

- Package Tag: \`${PACKAGE_RELEASE_TAG}\`
- Kernel Tag: \`${KERNEL_TAG}\`
- EL2 Package Set Included: \`${BUILD_EL2}\`
- Firmware Version: \`${FIRMWARE_DEB_VERSION}\`
- Architecture: \`${DEB_ARCH}\`
- Build Time (UTC): \`${BUILD_TIME_UTC}\`

## Included DEBs

- \`${IMAGE_DEB_STANDARD}\`
- \`${MODULES_DEB_STANDARD}\`
- \`${HEADERS_DEB_STANDARD}\`
${EL2_RELEASE_BLOCK}
- \`${FIRMWARE_DEB}\`
EOF
