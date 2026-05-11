#!/usr/bin/env bash
set -euo pipefail

: "${GAOKUN_DIR:?missing GAOKUN_DIR}"
: "${WORKDIR:?missing WORKDIR}"
: "${KERN_SRC:?missing KERN_SRC}"

KERN_OUT="${KERN_OUT:-$WORKDIR/kernel-out}"
KERN_SRC_BASE="${KERN_SRC_BASE:-$WORKDIR/mainline-linux-base}"
KERN_SRC_EL2="${KERN_SRC_EL2:-$KERN_SRC}"
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

configure_git_identity() {
  local repo_dir="$1"
  git -C "$repo_dir" config user.name "github-actions[bot]"
  git -C "$repo_dir" config user.email "github-actions[bot]@users.noreply.github.com"
}

build_variant() {
  local src_dir="$1"
  local out_dir="$2"
  local localversion="${3:-}"

  rm -rf "$out_dir"
  mkdir -p "$out_dir"

  unset KCONFIG_CONFIG
  make -C "$src_dir" O="$out_dir" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" gaokun3_defconfig

  if [[ -n "$localversion" ]]; then
    "$src_dir"/scripts/config --file "$out_dir/.config" --set-str LOCALVERSION "$localversion"
  fi

  make -C "$src_dir" O="$out_dir" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" olddefconfig
  make -C "$src_dir" O="$out_dir" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" -j"$(nproc)"
  make -C "$src_dir" O="$out_dir" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" modules_prepare
}

snapshot_tree() {
  local src_dir="$1"
  local dst_dir="$2"

  rm -rf "$dst_dir"
  mkdir -p "$dst_dir"
  cp -a "$src_dir"/. "$dst_dir"/
}

mkdir -p "$WORKDIR"

configure_git_identity "$KERN_SRC"
git -C "$KERN_SRC" am "$GAOKUN_DIR"/patches/upstream/*.patch
git -C "$KERN_SRC" am "$GAOKUN_DIR"/patches/others/*.patch
git -C "$KERN_SRC" am "$GAOKUN_DIR"/patches/media/*.patch
git -C "$KERN_SRC" am "$GAOKUN_DIR"/patches/0099-arm64-gaokun3-import-local-dts-and-defconfig.patch

ccache -z || true
build_variant "$KERN_SRC" "$KERN_OUT"
ccache -s || true

BASE_KREL="$(cat "$KERN_OUT/include/config/kernel.release")"
echo "$BASE_KREL" > "$WORKDIR/kernel-release.txt"

snapshot_tree "$KERN_SRC" "$KERN_SRC_BASE"

if [[ "$BUILD_EL2" != "true" ]]; then
  exit 0
fi

: "${KERN_OUT_EL2:?missing KERN_OUT_EL2}"

configure_git_identity "$KERN_SRC_EL2"
rm -rf "$KERN_OUT_EL2"
make -C "$KERN_SRC_EL2" O="$KERN_OUT_EL2" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" clean
git -C "$KERN_SRC_EL2" apply "$GAOKUN_DIR"/patches/el2/*.patch
git -C "$KERN_SRC_EL2" add -A
git -C "$KERN_SRC_EL2" commit -m "Apply EL2 patches"

ccache -z || true
build_variant "$KERN_SRC_EL2" "$KERN_OUT_EL2" "-gaokun3-el2"
ccache -s || true

EL2_KREL="$(cat "$KERN_OUT_EL2/include/config/kernel.release")"
echo "$EL2_KREL" > "$WORKDIR/kernel-release-el2.txt"
