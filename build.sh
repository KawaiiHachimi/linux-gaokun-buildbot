#!/usr/bin/env bash
set -euo pipefail

GAOKUN_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build.env
. "$GAOKUN_DIR/build.env"
# shellcheck source=scripts/lib/kernel_source.sh
. "$GAOKUN_DIR/scripts/lib/kernel_source.sh"

case "${1:-help}" in
  kernel|debs|rpms) action="$1" ;;
  help|--help|-h)
    echo 'Usage: ./build.sh kernel|debs|rpms'
    echo 'Inputs: build.env; optional WORKDIR, KERN_SRC, BUILD_EL2=true.'
    echo 'debs/rpms build the kernel and packages using the host toolchain.'
    echo 'Image assembly currently runs through the Fedora/Ubuntu workflows.'
    exit 0 ;;
  *) echo "Unknown action: $1" >&2; exit 2 ;;
esac
[[ $# -eq 1 ]] || { echo 'Expected one action; see --help.' >&2; exit 2; }

WORKDIR="${WORKDIR:-$GAOKUN_DIR/build}"
mkdir -p "$WORKDIR"
WORKDIR="$(cd "$WORKDIR" && pwd)"
KERN_SRC="${KERN_SRC:-$WORKDIR/linux}"
KERN_SRC_BASE="$KERN_SRC"
KERN_SRC_EL2="${KERN_SRC_EL2:-$WORKDIR/linux-el2}"
KERN_OUT="${KERN_OUT:-$WORKDIR/kernel-out}"
KERN_OUT_EL2="${KERN_OUT_EL2:-$WORKDIR/kernel-out-el2}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$WORKDIR/artifacts}"
BUILD_EL2="${BUILD_EL2:-false}"
if [[ "$BUILD_EL2" == true && -z "$KERNEL_EL2_COMMIT" ]]; then
  echo 'EL2 migration is not ready; KERNEL_EL2_COMMIT is unset.' >&2
  exit 1
fi
prepare_kernel_source "$KERN_SRC" "$KERNEL_COMMIT"
if [[ "$BUILD_EL2" == true ]]; then
  prepare_kernel_source "$KERN_SRC_EL2" "$KERNEL_EL2_COMMIT"
fi
export GAOKUN_DIR WORKDIR KERN_SRC KERN_SRC_BASE KERN_SRC_EL2 KERN_OUT KERN_OUT_EL2
export ARTIFACT_DIR BUILD_EL2 KERNEL_TAG KERNEL_REPOSITORY KERNEL_COMMIT KERNEL_EL2_COMMIT
export PACKAGE_RELEASE_TAG="${PACKAGE_RELEASE_TAG:-local-$KERNEL_TAG}"
bash "$GAOKUN_DIR/scripts/ci/20_build_kernel_variants.sh"
case "$action" in
  debs) bash "$GAOKUN_DIR/scripts/ci/70_build_package_debs.sh" ;;
  rpms) bash "$GAOKUN_DIR/scripts/ci/70_build_package_rpms.sh" ;;
esac
