# gaokun3 双仓库迁移记录

这是迁移候选，不能作为已验证发行版发布。当前评审入口为原仓库 PR #7；目标仓库尚未建立，工作流在目标内核提交发布前无法完成源码检出。

## 仓库边界

- `gaokun3/linux`：从 `gregkh/linux` fork，`gaokun3` 分支维护设备提交；DTS、驱动和 `gaokun3_defconfig` 都在内核树内。
- `gaokun3/buildbot`：Bash 构建入口、打包、镜像、固件及用户空间工具。GitHub Actions 负责调度。镜像组装仍包含工作流内联步骤，尚未全部抽成脚本。
- 移除 buildbot 的 `patches/`、`drivers/`、`dts/`、`defconfig/`。原件保留在迁移前提交 `315528c028843794ccd0f3d9dab373b03033150f`，不在构建时再次应用。

## 固定输入

`build.env` 是本地与 CI 共用的版本来源：

| 输入 | 当前候选 |
| --- | --- |
| 上游分支 | gregkh/linux `linux-rolling-stable` |
| 上游提交 | `d396b05e7e39b0ed6f6d5553fbaf174228e18bdf`，Merge v7.2.6 |
| 下游提交 | `716c79802092955347a41975b8f6e14020321478` |
| Fedora / Ubuntu | 44 / 26.04 |
| EL2 | 未设置提交；显式请求会报错 |

`KERNEL_TAG` 目前只是产物命名标签，并不代表 GitHub 已存在该 tag；真正检出依据为 `KERNEL_COMMIT`。发布前需在目标仓库推送精确提交，建立不可变 tag，并保留上游 base SHA。Ubuntu rootfs 下载失败直接停止，不再回退 beta。

软件包清单记录内核 SHA 与 buildbot SHA；镜像组装核对内核 SHA，防止复用不同源码生成的软件包。

## 本地构建

安装内核构建依赖（Git、make、GCC、bc、bison、flex、OpenSSL/libelf 开发包、pahole、rsync、kmod）；x86 主机还需 AArch64 交叉工具链。DEB 打包需 dpkg-dev，RPM 打包需 rpmbuild 及相应发行版工具。打包和镜像完整流程以原生 arm64 CI 为验证目标。

```bash
./build.sh kernel
./build.sh debs
./build.sh rpms
# 候选提交尚未发布时，可使用已经恢复的本地内核仓库：
KERN_SRC=/absolute/path/to/linux ./build.sh kernel
```

已有源码目录必须与固定 SHA 一致且干净；脚本不会 reset、覆盖或打补丁。`WORKDIR` 可更改输出目录，`JOBS` 可限制并发。`scripts/local/build_kernel.sh` 保留设备上的交互式构建安装入口，也使用相同固定源码。

## 迁移审查

- 导入原补丁作者信息。PDC 映射补丁通过反向应用确认已在基线中，单独移除；不以“冲突”判定补丁已上游。
- EC 设备树保留上游 GPIO 103 修正，对应 PDC 215。
- Venus 使用 PR #5 的适配系列，选中 VENUS、停用 IRIS，并启用板级固件节点；硬件解码尚未实测。
- `CONFIG_INPUT_UINPUT=m` 已在配置中；PR #2 的用户空间部分未在本轮引入。
- `9420138` 删除的旧 UCSI、q6apm 改动与新基线冲突，尚待语义审查；不能宣称已上游或功能等价。
- EL2 仅有部分移植工作：remoteproc 异步 attach 与 q6v5 running 状态变更需要继续审查，不能发布。
- systemd-boot 使用 `fedora` / `ubuntu` entry token。旧 machine-id 条目保留作回退；详见 [启动布局](boot-layout.md)。此轮参考 PeronGH 的方向，未整体引入其发行版策略。

## 已验证与发布门槛

已验证：gaokun3 defconfig 生成、内核 Kbuild 设备树编译，以及 Himax 触摸、Venus core、EC、电池驱动对象交叉编译；systemd 255 的实际 kernel-install / BLS 插件测试通过。

尚未完成：完整 Image/modules 链接、DEB/RPM 打包、Fedora/Ubuntu 镜像构建及设备启动。还需检查 Fedora SELinux 与当前 AppArmor 配置的兼容性，并实测触摸、60/120 Hz、音频、无线、蓝牙、充电、USB-C、休眠唤醒、视频解码、升级和回退。

先完成目标内核仓库发布和上述检查，再合并迁移 PR、启用 release。EL2 单独推进，不作为普通内核已完成的功能。
