English | [中文](docs/README_zh.md)

# linux-gaokun-buildbot

Build scripts, tools, and firmware for Linux images targeting the Huawei MateBook E Go 2023 (codename `gaokun3`) based on Qualcomm Snapdragon 8cx Gen3 (`SC8280XP`).

**Migration draft, not ready for release.** The target repositories are `gaokun3/linux` and `gaokun3/buildbot`. The candidate kernel commit still needs publication; EL2 is disabled pending migration. See the [migration checklist](docs/migration.md).

`build.env` pins the kernel SHA and distribution versions. Use `./build.sh kernel|debs|rpms` locally; image assembly currently runs through CI. Drivers, DTS and defconfig belong in the downstream kernel tree.

## What is included

### Repository layout

- `docs/`: bilingual usage/build guides and platform notes
- `firmware/`: minimal firmware bundle used by the image build
- `packaging/`: distro kernel and firmware package templates and metadata
- `tools/`: device-specific helper scripts, service files, and EL2 EFI payloads
- `scripts/ci/`: workflow build, image creation, and packaging scripts
- `scripts/local/`: some useful scripts that can be run on the local device

### Package outputs

The package pipeline builds and installs dedicated package sets:

- **Fedora (RPM)**: `kernel-gaokun3`, `kernel-modules-gaokun3`, `kernel-devel-gaokun3`, `linux-firmware-gaokun3`
- **Ubuntu (DEB)**: `linux-image-gaokun3`, `linux-modules-gaokun3`, `linux-headers-gaokun3`, `linux-firmware-gaokun3`
- **EL2 builds paused** pending a separate migration and validation; requesting EL2 fails early.
- Ubuntu kernel image packages run `update-initramfs` during install/upgrade, which in turn refreshes the BLS entry through the distro `systemd-boot` hook.
- Fedora kernel RPMs now ship a matching `dracut.conf.d` snippet and run `dracut` + `kernel-install add` in `%posttrans`, so installing or upgrading the package refreshes the initramfs and BLS entry automatically.

### Releases

- Fedora and Ubuntu image releases contain compressed installable images.
- Gaokun RPM and DEB releases contain the standalone kernel and firmware package sets used by the image workflows.

### Kernel sources

Device changes and original authors are recorded in downstream Git commits. The old patch files remain recoverable from this repository’s pre-migration history; see the [migration record](docs/migration.md).

### Tool Sources

- `tools/audio`, `tools/bluetooth`: adapted from [whitelewi1-ctrl/matebook-e-go-linux](https://github.com/whitelewi1-ctrl/matebook-e-go-linux)
- `tools/el2/qebspilaa64.efi`: sourced from [stephan-gh/qebspil](https://github.com/stephan-gh/qebspil)
- `tools/el2/slbounceaa64.efi`: sourced from [TravMurav/slbounce](https://github.com/TravMurav/slbounce)
- `tools/touchscreen-tuner`: adapted from [chiyuki0325/EGoTouchRev-Linux](https://github.com/chiyuki0325/EGoTouchRev-Linux), with GTK4 GUI improvements in this repository

## Boot artifact layout

The image and local-install workflows now follow the standard `kernel-install` + BLS flow instead of hand-writing `systemd-boot` entries.

- BLS entries use the distribution name: `loader/entries/fedora-<kernel-release>.conf` or `loader/entries/ubuntu-<kernel-release>.conf`. `/etc/kernel/entry-token` persists that name for package upgrades and initramfs hooks; explicit calls use `--entry-token=os-id`.
- Kernel, initrd/initramfs, and DTB files are placed under `fedora/<kernel-release>/` or `ubuntu/<kernel-release>/` on the ESP. The system machine ID remains separate.
- Existing machine-ID entries are retained as fallback entries during migration. After booting and verifying the new entry, old entries can be removed deliberately. Two installations of the same distribution sharing an ESP need distinct tokens. See [boot layout](docs/boot-layout.md).
- A compatibility copy of the DTB is also kept in `/boot` so users can switch to GRUB more easily later.
- Ubuntu DTBs are installed in `/usr/lib/linux-image-<kernel-release>/qcom/` for `kernel-install`, plus `/boot/dtb-<kernel-release>` as a compatibility copy.
- Fedora DTBs are installed in `/usr/lib/modules/<kernel-release>/dtb/qcom/` for `kernel-install`, plus `/boot/dtb-<kernel-release>/qcom/` as a compatibility copy.
- The Gaokun3 image scripts provide `/etc/kernel/cmdline` and `/etc/kernel/devicetree`, then call `kernel-install add` to populate the final BLS entry.

## Getting started

- Release: <https://github.com/KawaiiHachimi/linux-gaokun-buildbot/releases>
- Dual-boot guide: [English](docs/dual_boot_guide_en.md) | [中文](docs/dual_boot_guide_zh.md)
- EL2 implementation notes: [English](docs/el2_kvm_guide_en.md) | [中文](docs/el2_kvm_guide_zh.md)
- Awesome Gaokun3: [English](docs/awesome_gaokun3_en.md) | [中文](docs/awesome_gaokun3_zh.md)
- Build guide – Fedora 44: [English](docs/matebook_ego_build_guide_fedora44_en.md) | [中文](docs/matebook_ego_build_guide_fedora44_zh.md)
- Build guide – Ubuntu 26.04: [English](docs/matebook_ego_build_guide_ubuntu26.04_en.md) | [中文](docs/matebook_ego_build_guide_ubuntu26.04_zh.md)

## Feature Support

For an overview of hardware support status on the device, see [right-0903/linux-gaokun `## Feature Support`](https://github.com/right-0903/linux-gaokun?tab=readme-ov-file#feature-support).

## References

- [right-0903/linux-gaokun](https://github.com/right-0903/linux-gaokun) : The main source of the kernel patches and device support work, with detailed commit messages and explanations.
- [TheUnknownThing/linux-gaokun](https://github.com/TheUnknownThing/linux-gaokun) : Another fork of the kernel patches and device support work, with some unique commits and explanations for Touchscreen and EC.
- [whitelewi1-ctrl/matebook-e-go-linux](https://github.com/whitelewi1-ctrl/matebook-e-go-linux) : The earliest repo to fix panel backlight problem, with some additional resources and modifications for Gaokun3 Linux support.
- [gaokun on AUR](https://aur.archlinux.org/packages?O=0&K=gaokun) : Several AUR packages built for Gaokun3, including kernel and firmware packages.
- [chenxuecong2/firmware-huawei-gaokun3](https://github.com/chenxuecong2/firmware-huawei-gaokun3) : A firmware bundle repository for Gaokun3.
- [chiyuki0325/EGoTouchRev-Linux](https://github.com/chiyuki0325/EGoTouchRev-Linux) : The upstream source for the directly integrated Himax HX83121A Linux touchscreen driver and tuning algorithm in this repository.
- [awarson2233/EGoTouchRev](https://github.com/awarson2233/EGoTouchRev) : The original Windows-side touchscreen algorithm project referenced by EGoTouchRev-Linux, and an important upstream reference for the Gaokun3 touchscreen tuning pipeline.
- [TravMurav/slbounce](https://github.com/TravMurav/slbounce) : A UEFI application that enables EL2 support and Secure Launch on Gaokun3.
- [TravMurav/linux](https://github.com/TravMurav/linux/tree/x13s-6.18-v1.1-cxsd) : A Linux kernel tree with some useful patches for EL2 support on sc8280xp platforms.
- [stephan-gh/qebspil](https://github.com/stephan-gh/qebspil) : A UEFI application that pre-launches the DSP firmware on Qualcomm platforms, which can be used in the boot chain before launching Linux.
