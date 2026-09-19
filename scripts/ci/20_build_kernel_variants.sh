#!/usr/bin/env bash
set -euo pipefail

: "${GAOKUN_DIR:?missing GAOKUN_DIR}"
: "${WORKDIR:?missing WORKDIR}"
: "${KERN_SRC:?missing KERN_SRC}"

KERN_OUT="${KERN_OUT:-$WORKDIR/kernel-out}"
KERN_SRC_BASE="${KERN_SRC_BASE:-$KERN_SRC}"
KERN_SRC_EL2="${KERN_SRC_EL2:-$WORKDIR/linux-el2}"
KERN_OUT_EL2="${KERN_OUT_EL2:-}"
BUILD_EL2="${BUILD_EL2:-false}"

if [[ "$(uname -m)" == "aarch64" ]]; then
  CROSS_COMPILE="${CROSS_COMPILE:-}"
else
  CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
fi

export ARCH=arm64
export CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache}"
export CCACHE_BASEDIR="${CCACHE_BASEDIR:-$WORKDIR}"
export CCACHE_NOHASHDIR="${CCACHE_NOHASHDIR:-true}"
export CCACHE_COMPILERCHECK="${CCACHE_COMPILERCHECK:-content}"
export PATH="/usr/lib/ccache:$PATH"

build_variant() {
  local src_dir="$1"
  local out_dir="$2"
  local localversion="${3:-}"

  mkdir -p "$out_dir"

  unset KCONFIG_CONFIG
  make -C "$src_dir" O="$out_dir" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" gaokun3_defconfig

  if [[ -n "$localversion" ]]; then
    "$src_dir"/scripts/config --file "$out_dir/.config" --set-str LOCALVERSION "$localversion"
  fi

  make -C "$src_dir" O="$out_dir" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" olddefconfig
  make -C "$src_dir" O="$out_dir" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" -j"${JOBS:-$(nproc)}" Image modules dtbs
  make -C "$src_dir" O="$out_dir" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" modules_prepare
}

mkdir -p "$WORKDIR"

# Source is already the pinned downstream tree. Builds never alter its history.
test -f "$KERN_SRC/arch/arm64/configs/gaokun3_defconfig"
if [[ "$BUILD_EL2" == true ]]; then
  : "${KERN_OUT_EL2:?missing KERN_OUT_EL2}"
  test -f "$KERN_SRC_EL2/arch/arm64/configs/gaokun3_defconfig"
  test -f "$KERN_SRC_EL2/arch/arm64/boot/dts/qcom/sc8280xp-huawei-gaokun3-el2.dts"
fi

build_variant "$KERN_SRC" "$KERN_OUT"
cat "$KERN_OUT/include/config/kernel.release" > "$WORKDIR/kernel-release.txt"
rm -f "$WORKDIR/kernel-release-el2.txt"

if [[ "$BUILD_EL2" == true ]]; then
  build_variant "$KERN_SRC_EL2" "$KERN_OUT_EL2" "-gaokun3-el2"
  cat "$KERN_OUT_EL2/include/config/kernel.release" > "$WORKDIR/kernel-release-el2.txt"
fi
