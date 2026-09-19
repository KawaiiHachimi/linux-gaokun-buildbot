#!/usr/bin/env bash

# Fetch into a new directory; never reset or patch an existing source checkout.
prepare_kernel_source() {
  local destination="$1"
  local commit="$2"
  if [[ ! "$commit" =~ ^[0-9a-f]{40}$ ]]; then
    echo "Set a reviewed 40-character kernel commit in build.env first." >&2
    return 1
  fi
  if [[ ! -d "$destination" ]]; then
    mkdir -p "$destination"
    git -C "$destination" init -q
    git -C "$destination" remote add origin "https://github.com/$KERNEL_REPOSITORY.git"
    git -C "$destination" fetch --depth=1 origin "$commit"
    git -C "$destination" checkout --detach FETCH_HEAD
  fi
  if [[ "$(git -C "$destination" rev-parse HEAD)" != "$commit" ]]; then
    echo "Kernel checkout does not match build.env: $destination" >&2
    return 1
  fi
  if [[ -n "$(git -C "$destination" status --porcelain --untracked-files=normal)" ]]; then
    echo "Kernel checkout contains local edits: $destination" >&2
    return 1
  fi
  test -f "$destination/arch/arm64/configs/gaokun3_defconfig"
}
