# 启动文件布局

Fedora 使用 `fedora`，Ubuntu 使用 `ubuntu` 作为 kernel-install 的 entry token。
例如内核版本为 `7.2.6-gaokun3` 时：

| 文件 | Fedora | Ubuntu |
| --- | --- | --- |
| `/etc/kernel/entry-token` 内容 | `fedora` | `ubuntu` |
| ESP 启动条目 | `loader/entries/fedora-7.2.6-gaokun3.conf` | `loader/entries/ubuntu-7.2.6-gaokun3.conf` |
| ESP 内核、initrd、DTB 目录 | `fedora/7.2.6-gaokun3/` | `ubuntu/7.2.6-gaokun3/` |

镜像脚本、RPM 安装/卸载和本地安装的显式调用使用 `--entry-token=os-id`。
镜像和包安装脚本同时写入 `/etc/kernel/entry-token`，让没有传入该参数的
`update-initramfs` / systemd-boot 钩子也使用同一个名称。这个文件不应作为
临时内核配置被还原或删除。系统的 `/etc/machine-id` 仍然是机器身份，不能
把它改成发行版名称。

临时 `KERNEL_INSTALL_CONF_ROOT` 会改变配置搜索目录，因此这些调用必须
继续显式传入 `--entry-token=os-id`。

## 旧安装

新镜像的 loader.conf 指向发行版名称开头的启动项。现有安装升级软件包后，
新的启动项使用短名称；旧 machine-id 启动项保留，原来的默认项不会被自动
改写。先从菜单选择新项，确认正常启动，再修改 loader.conf 的 default 并
清理已不需要的旧项。不要批量删除其他发行版的启动目录。

如果同一 ESP 上有两份 Fedora 或两份 Ubuntu，发行版名称不足以区分它们。
本项目默认面向每个发行版一份安装；多实例用户需要分别配置唯一 entry token，
并相应调整显式 kernel-install 调用。

## 验证

运行 `python3 tests/test_boot_entries.py`。测试使用临时根目录和系统自带的
kernel-install / 90-loaderentry.install，检查两个发行版的 token 解析、
机器 ID 变化后的名称稳定性，以及内核、initrd、DTB 和启动条目的生成/删除。
这不能代替真机启动、发行版包升级和回退测试。

参考 PeronGH fork 的发行版名称方案，并将持久配置覆盖到 Ubuntu 和本地安装：
<https://github.com/PeronGH/linux-gaokun-buildbot>
