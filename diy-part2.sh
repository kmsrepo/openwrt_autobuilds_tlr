#!/bin/bash
#
# diy-part2.sh - built-in OpenWrt/x-wrt customization script (runs inside the
#                source tree, after .config has been loaded).
#
# Adds the TP-Link TL-R2005KSH (TELESQUARE LTE router, MT7620A + 32 MiB SPI
# flash) as a ramips/mt7620 device.
#
# How to use with the "miwifi-r3-router" style build repo:
#   1. put this file and mt7620a_tplink_tl-r2005ksh.dts in the repo root
#   2. either replace the repo's diy-part2.sh with this file, or append its
#      contents / call it from the existing diy-part2.sh
#   3. keep  DIY_P2_SH: diy-part2.sh  in the workflow env
#   4. in ap.config, no change is strictly required - this script flips the
#      device selection to the TL-R2005KSH
#
set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
RAMIPS=target/linux/ramips
DEVICE=tplink_tl-r2005ksh
DTS=mt7620a_tplink_tl-r2005ksh.dts

echo "==> Installing device tree: $DTS"
cp "$SRC/$DTS" "$RAMIPS/dts/$DTS"

echo "==> Adding image recipe for $DEVICE"
if ! grep -q "Device/$DEVICE" "$RAMIPS/image/mt7620.mk"; then
	cat >> "$RAMIPS/image/mt7620.mk" <<'EOF'

# TP-Link TL-R2005KSH (TELESQUARE LTE router) - MT7620A, 64 MiB RAM,
# 32 MiB W25Q256 SPI-NOR, 4x LAN + 1x WAN, internal Qualcomm Gobi LTE modem.
# Flashed at 0x80000 behind Breed; the vendor's second image at 0x1000000 is
# left untouched as a way back to stock.
define Device/tplink_tl-r2005ksh
  SOC := mt7620a
  IMAGE_SIZE := 15872k
  IMAGES += factory.bin
  IMAGE/factory.bin := append-kernel | append-rootfs | pad-rootfs | check-size
  DEVICE_VENDOR := TP-Link
  DEVICE_MODEL := TL-R2005KSH
  SUPPORTED_DEVICES += tl-r2005ksh
  DEVICE_PACKAGES := kmod-usb2 kmod-usb-ohci \
	kmod-usb-serial-option kmod-usb-net-qmi-wwan uqmi
endef
TARGET_DEVICES += tplink_tl-r2005ksh
EOF
fi

echo "==> Patching board.d files (switch layout, MAC addresses, LEDs)"
python3 - <<'PY'
import re
import sys

# x-wrt uses 'case $board in', older OpenWrt trees 'case "$board" in'
CASE_RE = re.compile(r'^\s*case\s+"?\$board"?\s+in\b')
B = 'target/linux/ramips/mt7620/base-files/etc/board.d/'

# switch layout taken from the vendor firmware (config.sh has CONFIG_WAN_AT_P4=y,
# internet.sh calls "config-vlan.sh 3 LLLLW" -> WAN at ESW port 4) and from
# admin_lan.sh, which maps the UI labels to ports as
#   lan_1 -> port 3, lan_2 -> port 2, lan_3 -> port 1, lan_4 -> port 0, wan -> 4
IFACE = '''\ttplink,tl-r2005ksh)
\t\tucidef_add_switch "switch0" \\
\t\t\t"3:lan:1" "2:lan:2" "1:lan:3" "0:lan:4" "4:wan" "6@eth0"
\t\t;;
'''
# base MAC lives at factory+0x4; the stock firmware used the same MAC for
# LAN and WAN.  Use macaddr_add "$(...)" 1 for WAN if your ISP does not bind.
MACS = '''\ttplink,tl-r2005ksh)
\t\twan_mac=$(mtd_get_mac_binary factory 0x4)
\t\tlabel_mac=$(mtd_get_mac_binary factory 0x4)
\t\t;;
'''
# bmon keeps GPIO14 lit while the device runs -> status/power LED.  The three
# auxiliary LEDs (green:aux1..3) have no function documented in the firmware;
# add netdev/switch triggers once identified on hardware, e.g.
#   ucidef_set_led_netdev "4g" "4g" "green:aux2" "wwan0"
LEDS = '''\ttplink,tl-r2005ksh)
\t\tucidef_set_led_default "status" "status" "green:status" "1"
\t\t;;
'''

# (file, function in 02_network to hook into or None, case arm)
JOBS = [
    (B + '02_network', 'ramips_setup_interfaces', IFACE),
    (B + '02_network', 'ramips_setup_macs',       MACS),
    (B + '01_leds',    None,                      LEDS),
]

def patch(path, func, arm):
    s = open(path).read()
    if arm in s:
        print('   %s: already patched' % path)
        return True
    out, active, done = [], func is None, False
    for line in s.splitlines(True):
        out.append(line)
        if func is not None and line.startswith(func):
            active = True
        if active and not done and CASE_RE.match(line):
            out.append(arm)
            done, active = True, False
    if not done:
        print('   %s: ERROR - case anchor not found' % path)
        return False
    open(path, 'w').write(''.join(out))
    print('   %s: patched' % path)
    return True

sys.exit(0 if all([patch(*j) for j in JOBS]) else 1)
PY

echo "==> Selecting the device in .config"
if [ -f .config ]; then
	python3 - <<'PY'
import re

DEV = 'CONFIG_TARGET_ramips_mt7620_DEVICE_tplink_tl-r2005ksh'
p = '.config'
s = open(p).read()

s = re.sub(r'^CONFIG_TARGET_ramips_mt7620_DEVICE_xiaomi_miwifi-r3=y',
           '# CONFIG_TARGET_ramips_mt7620_DEVICE_xiaomi_miwifi-r3 is not set', s, flags=re.M)
s = re.sub(r'^# %s is not set$' % DEV, '%s=y' % DEV, s, flags=re.M)
if '%s=y' % DEV not in s:
    s = s.rstrip('\n') + '\n%s=y\n' % DEV
s = re.sub(r'^CONFIG_TARGET_PROFILE=.*$',
           'CONFIG_TARGET_PROFILE="DEVICE_tplink_tl-r2005ksh"', s, flags=re.M)
# no 5 GHz / mini-PCIe card on this board
s = re.sub(r'^(CONFIG_PACKAGE_kmod-mt76x2(?:-common|-u)?|CONFIG_PACKAGE_kmod-mt76x02-common)=y$',
           r'# \1 is not set', s, flags=re.M)
open(p, 'w').write(s)
print('   .config updated: %s=y' % DEV)
PY
else
	echo "   no .config found - select the device manually:"
	echo "   CONFIG_TARGET_ramips_mt7620_DEVICE_tplink_tl-r2005ksh=y"
fi

echo "==> Done: device tplink_tl-r2005ksh registered"
