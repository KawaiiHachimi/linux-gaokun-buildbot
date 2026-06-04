# Gaokun3 传感器配置指南

在 MateBook E Go 2023 (SC8280XP) 上启用 SLPI DSP 传感器（加速度计、陀螺仪、光照）。

## 依赖

1. **hexagonrpcd** — 须带 `\r` strip 补丁（本仓库 `patches/hexagonfs-cr-strip.patch`）
2. 本仓库构建的内核，`CONFIG_INPUT_UINPUT=m` 已启用
3. 传感器注册表和校准文件（需从 Windows 分区手动拷贝）

## hexagonrpcd \r strip 补丁

Qualcomm SLPI DSP 固件路径中包含 Windows 风格的 trailing `\r`，Linux hexagonrpcd
无法解析。补丁在 `patches/hexagonfs-cr-strip.patch`，CI 构建时自动应用。

## 传感器配置文件部署

### 1. 挂载 Windows 分区

```bash
sudo mount /dev/nvme0n1p4 /mnt/windows  # 根据实际分区调整
```

### 2. 拷贝注册表

```bash
SRC=/mnt/windows/Windows/System32/drivers/DriverData/Qualcomm/fastRPC
DST=/usr/lib/hexagonrpcd/sensors

sudo mkdir -p $DST/registry
sudo cp -r $SRC/persist/sensors/registry/registry/* $DST/registry/
sudo cp $SRC/persist/sensors/registry/sns_reg_version $DST/registry/
```

### 3. 启用加速度计和陀螺仪

```bash
sudo sed -i 's/"data":"0"/"data":"1"/' $DST/registry/default_sensors.accel.attr_0
sudo sed -i 's/"data":"0"/"data":"1"/' $DST/registry/default_sensors.gyro.attr_0
```

### 4. 验证

```bash
sudo systemctl restart hexagonrpcd

# 等待 DSP 初始化（约 30 秒），然后测试
ssccli --sensor-accel   # 应有 XYZ 读数
ssccli --sensor-gyro    # 应有角速度读数
```

## hexagonrpcd systemd 配置

`tools/hexagonrpcd/override.conf` 配置 hexagonrpcd 指向正确的 registry 路径：

```
[Service]
Environment=HEXAGON_SENSOR_REGISTRY=/usr/lib/hexagonrpcd/sensors/registry
```

## 下一步

- 安装 [libssc](https://codeberg.org/dylanvanassche/libssc) 和 ssc-bridge 进行 evdev 桥接
- 参见 `EXPERIMENTAL.md`（后续 PR 提供）

## 参考

- KawaiiHachimi/linux-gaokun-buildbot: https://github.com/KawaiiHachimi/linux-gaokun-buildbot
- libssc: https://codeberg.org/dylanvanassche/libssc
