#!/usr/bin/env python3
"""Set a stable Wi-Fi MAC address for ath11k devices.

The image can optionally pin a fixed MAC via /etc/gaokun/wifi-mac-address.
If that file is absent, derive a deterministic locally-administered address
from machine identity to avoid shipping one hard-coded MAC in every image.
"""

import hashlib
import os
import pathlib
import subprocess
import sys

FIXED_MAC_PATH = pathlib.Path("/etc/gaokun/wifi-mac-address")


def read_first_nonempty(paths):
    for path in paths:
        try:
            value = pathlib.Path(path).read_text().strip()
        except OSError:
            continue
        if value:
            return value
    return ""


def get_machine_seed():
    seed = read_first_nonempty([
        "/sys/class/dmi/id/product_serial",
        "/sys/class/dmi/id/product_uuid",
        "/sys/class/dmi/id/board_serial",
        "/etc/machine-id",
    ])
    if seed:
        return seed
    return "gaokun3"


def generate_mac(seed):
    digest = hashlib.md5((seed + ":wifi").encode("utf-8")).hexdigest()[:12]
    first = (int(digest[:2], 16) | 0x02) & 0xFE
    return ":".join([f"{first:02x}"] + [digest[i:i + 2] for i in range(2, 12, 2)])


def target_mac():
    try:
        value = FIXED_MAC_PATH.read_text(encoding="utf-8").strip().lower()
    except OSError:
        value = ""
    if value:
        return value
    return generate_mac(get_machine_seed())


def find_wifi_iface():
    for name in sorted(os.listdir("/sys/class/net")):
        if name.startswith(("wl", "wlan")):
            return name
    return ""


def resolve_iface(preferred):
    candidates = []
    if preferred:
        candidates.append(preferred)

    detected = find_wifi_iface()
    if detected and detected not in candidates:
        candidates.append(detected)

    for name in candidates:
        if pathlib.Path(f"/sys/class/net/{name}/address").exists():
            return name
    return ""


def get_addr(iface):
    return pathlib.Path(f"/sys/class/net/{iface}/address").read_text().strip().lower()


def is_up(iface):
    try:
        out = subprocess.check_output(["ip", "-o", "link", "show", "dev", iface], text=True)
    except subprocess.CalledProcessError:
        return False
    return "UP" in out.split("<", 1)[1].split(">", 1)[0]


def run(*args):
    subprocess.check_call(list(args))


def have_command(name):
    return any(
        os.access(os.path.join(path, name), os.X_OK)
        for path in os.environ.get("PATH", "").split(os.pathsep)
        if path
    )


def nmcli_state(iface):
    if not have_command("nmcli"):
        return "", ""
    try:
        out = subprocess.check_output(
            ["nmcli", "-g", "GENERAL.STATE,GENERAL.CONNECTION", "device", "show", iface],
            text=True,
        )
    except subprocess.CalledProcessError:
        return "", ""
    lines = out.strip().splitlines()
    state = lines[0] if len(lines) > 0 else ""
    connection = lines[1] if len(lines) > 1 else ""
    return state, connection


def main():
    if os.geteuid() != 0:
        print("Error: must run as root", file=sys.stderr)
        return 1

    requested_iface = sys.argv[1] if len(sys.argv) > 1 else ""
    iface = resolve_iface(requested_iface)
    if not iface:
        print("No Wi-Fi interface found, nothing to do.")
        return 0
    if requested_iface and requested_iface != iface:
        print(f"Wi-Fi interface {requested_iface} not present, using {iface} instead.")

    wanted = target_mac()
    current = get_addr(iface)

    if current == wanted:
        print("MAC already stable, nothing to do.")
        return 0

    state, connection = nmcli_state(iface)
    reconnect = state.startswith("100") or state.startswith("30")
    if reconnect:
        run("nmcli", "device", "disconnect", iface)

    was_up = is_up(iface)
    run("ip", "link", "set", "dev", iface, "down")
    run("ip", "link", "set", "dev", iface, "address", wanted)
    if was_up:
        run("ip", "link", "set", "dev", iface, "up")

    if reconnect:
        run("nmcli", "device", "connect", iface)

    print(f"Stable Wi-Fi MAC applied: {wanted}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
