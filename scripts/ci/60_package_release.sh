#!/usr/bin/env bash
set -euo pipefail

: "${WORKDIR:?missing WORKDIR}"
: "${ARTIFACT_DIR:?missing ARTIFACT_DIR}"
: "${IMAGE_FILE:?missing IMAGE_FILE}"
: "${IMAGE_CHUNK_SIZE:?missing IMAGE_CHUNK_SIZE}"
: "${FEDORA_RELEASE:?missing FEDORA_RELEASE}"
: "${KERNEL_TAG:?missing KERNEL_TAG}"

KREL="$(cat "$WORKDIR/kernel-release.txt")"

cp "$IMAGE_FILE" "$ARTIFACT_DIR/"
zstd -T0 -19 "$ARTIFACT_DIR/$(basename "$IMAGE_FILE")" -o "$ARTIFACT_DIR/$(basename "$IMAGE_FILE").zst"
split -b "$IMAGE_CHUNK_SIZE" -d -a 3 \
  "$ARTIFACT_DIR/$(basename "$IMAGE_FILE").zst" \
  "$ARTIFACT_DIR/$(basename "$IMAGE_FILE").zst.part-"

sudo sha256sum \
  "$ARTIFACT_DIR/gaokun3_defconfig" \
  "$ARTIFACT_DIR/$(basename "$IMAGE_FILE").zst.part-"* \
  | sudo tee "$ARTIFACT_DIR/SHA256SUMS.txt" > /dev/null
sudo chown "$(id -u):$(id -g)" "$ARTIFACT_DIR/SHA256SUMS.txt"

cat > "$ARTIFACT_DIR/release-info.txt" <<EOF
Distribution: Fedora ${FEDORA_RELEASE} (Minimal GNOME)
Kernel Tag: ${KERNEL_TAG}
Kernel Release: ${KREL}
Architecture: arm64
Bootloader: GRUB2 (BLS disabled, traditional grub.cfg)
Image File: $(basename "$IMAGE_FILE")
Compressed File: $(basename "$IMAGE_FILE").zst
Build Time (UTC): $(date -u +"%Y-%m-%dT%H:%M:%SZ")

Reassemble + Decompress:
cat $(basename "$IMAGE_FILE").zst.part-* > $(basename "$IMAGE_FILE").zst
zstd -d $(basename "$IMAGE_FILE").zst -o $(basename "$IMAGE_FILE")
EOF

TAG_NAME="fedora${FEDORA_RELEASE}-${KREL}-$(date -u +%Y%m%d%H%M%S)"

echo "$TAG_NAME" > "$WORKDIR/tag-name.txt"
echo "$KREL" > "$WORKDIR/kernel-release-export.txt"
