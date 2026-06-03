#!/bin/bash
# 在 chroot 内编译带 \r strip patch 的 hexagonrpcd
# 替换 apt 装的 stock 二进制
set -euo pipefail

HEXAGONRPC_SRC="https://github.com/linux-msm/hexagonrpc.git"
PATCH_FILE="/tmp/gaokun/patches/hexagonfs-cr-strip.patch"

apt-get install -y meson ninja-build git libglib2.0-dev >/dev/null 2>&1

cd /tmp
git clone --depth 1 "$HEXAGONRPC_SRC" hexagonrpc
cd hexagonrpc
patch -p1 < "$PATCH_FILE"
meson setup build --wipe -Dhexagonrpcd_verbose=false
ninja -C build
cp build/hexagonrpcd/hexagonrpcd /usr/libexec/hexagonrpc/hexagonrpcd
echo "✓ hexagonrpcd patched version installed"
